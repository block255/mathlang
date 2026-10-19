# 数语引擎 · 打包 Windows release 可执行文件
#
# 产物：dist\v<版本>\（mathlang.exe + flutter_windows.dll + data\ + SHA256SUMS.txt）
# 不需要管理员（插件链接用 junction 补齐）。
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File scripts\build_exe.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\build_exe.ps1 -SkipTests

param([switch]$SkipTests)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$workspace = Split-Path (Split-Path $repo -Parent) -Parent
$app = Join-Path $repo 'app'

$env:PUB_CACHE = Join-Path $workspace '_cache\pub'
$env:TEMP = Join-Path $workspace '_cache\tmp'
$env:TMP = $env:TEMP
$env:LOCALAPPDATA = Join-Path $workspace '_cache\localappdata'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'

$flutter = Join-Path $workspace 'Flutter_SDK\flutter\bin\flutter.bat'
if (-not (Test-Path $flutter)) { throw "找不到 flutter: $flutter" }

Write-Host ''
Write-Host '== 数语引擎 · 打包 Windows release ==' -ForegroundColor Cyan

# 版本号唯一来源 = pubspec.yaml
$pubspec = Get-Content (Join-Path $app 'pubspec.yaml') -Raw -Encoding UTF8
if ($pubspec -match '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)') {
    $version = $Matches[1]
} else {
    throw 'pubspec.yaml 里读不到 version'
}
Write-Host "   版本: $version"

& (Join-Path $PSScriptRoot 'ensure_plugin_links.ps1') -Quiet

Push-Location $app
try {
    if (-not $SkipTests) {
        Write-Host '   [1/4] flutter analyze' -ForegroundColor DarkGray
        & $flutter analyze
        if ($LASTEXITCODE -ne 0) { throw 'flutter analyze 未通过' }

        Write-Host '   [2/4] flutter test' -ForegroundColor DarkGray
        & $flutter test
        if ($LASTEXITCODE -ne 0) { throw 'flutter test 未通过' }
    } else {
        Write-Host '   [1-2/4] 跳过 analyze / test' -ForegroundColor Yellow
    }

    Write-Host '   [3/4] flutter build windows --release' -ForegroundColor DarkGray
    & $flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'flutter build windows 未通过' }
} finally {
    Pop-Location
}

$rel = Join-Path $app 'build\windows\x64\runner\Release'
$exePath = Join-Path $rel 'mathlang.exe'
if (-not (Test-Path $exePath)) { throw "构建产物不存在: $exePath" }

# 新旧校验：AOT 代码在 data\app.so，exe 时间戳不可靠
$appSo = Join-Path $rel 'data\app.so'
$newest = Get-ChildItem (Join-Path $app 'lib') -Recurse -File -Filter '*.dart' |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Test-Path $appSo) -and $newest -and ((Get-Item $appSo).LastWriteTime -lt $newest.LastWriteTime)) {
    throw "产物比源码旧（data\app.so 早于 $($newest.Name)），构建可能没真的重跑"
}

$distDir = Join-Path $repo ("dist\v" + $version)

# ★★ 2026-10-19：**归档前先检查"应用是不是还开着"**。
#   以前直接 Remove-Item -Recurse ⇒ dist 里的 flutter_windows.dll 被占用时会**删到一半**
#   （data\ 已没了、exe 还在）—— 用户看到的就是"重打之后打不开了"。
#   ⇒ 先探测能不能独占打开；不能就**一个字节都不删**，直接告诉用户关掉应用。
foreach ($probe in @((Join-Path $distDir 'mathlang.exe'), (Join-Path $distDir 'flutter_windows.dll'))) {
    if (-not (Test-Path $probe)) { continue }
    try {
        $fs = [System.IO.File]::Open($probe, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $fs.Close()
    } catch {
        throw "请先**完全关闭**正在运行的「数语引擎」（$([System.IO.Path]::GetFileName($probe)) 被占用）。dist 没有做任何删除。"
    }
}

# ★★ 2026-10-19：**保住用户的本地暂存**（mathlang-session.json 就写在 exe 同目录）。
#   整目录重拷会把它一起删掉 ⇒ 用户下次打开是空白、设置回默认（2026-10-19 真的发生过一次）。
$sessionKeep = Join-Path $distDir 'mathlang-session.json'
$sessionTmp = $null
if (Test-Path $sessionKeep) {
    $sessionTmp = Join-Path ([System.IO.Path]::GetTempPath()) ('mathlang-session-' + [guid]::NewGuid().ToString('N') + '.json')
    Copy-Item $sessionKeep $sessionTmp -Force
}
if (Test-Path $distDir) { Remove-Item $distDir -Recurse -Force }
New-Item -ItemType Directory -Path $distDir -Force | Out-Null
if ($sessionTmp) {
    Copy-Item $sessionTmp $sessionKeep -Force
    Remove-Item $sessionTmp -Force
}

Write-Host '   [4/4] 归档到 dist' -ForegroundColor DarkGray
Copy-Item $exePath $distDir -Force
Copy-Item (Join-Path $rel 'flutter_windows.dll') $distDir -Force -ErrorAction SilentlyContinue
Get-ChildItem $rel -Filter '*.dll' -File | ForEach-Object {
    Copy-Item $_.FullName $distDir -Force
}
Copy-Item (Join-Path $rel 'data') $distDir -Recurse -Force

# ★★ 2026-10-19：**给 exe 签名**（自签证书；Windows 11 26200 对未签名 exe 一律拦）。
#   · 证书在「当前用户\个人」里（`signing\README.md` 有生成/导出/装根的步骤）；
#   · 用 `Set-AuthenticodeSignature`（不需要 Windows SDK 的 signtool）；
#   · **带公网时间戳** ⇒ 证书到期后已签的 exe 仍有效。
#   ★ 必须在生成 SHA256 之前签 —— 签完文件字节变了，校验和要对得上最终产物。
$signSubject = 'CN=数语引擎（自签）'
$signCert = Get-ChildItem Cert:\CurrentUser\My -ErrorAction SilentlyContinue |
    Where-Object { $_.Subject -eq $signSubject -and $_.HasPrivateKey } |
    Sort-Object NotAfter -Descending | Select-Object -First 1
$exeInDist = Join-Path $distDir 'mathlang.exe'
if ($signCert) {
    try {
        $sig = Set-AuthenticodeSignature -FilePath $exeInDist -Certificate $signCert `
            -HashAlgorithm SHA256 -TimestampServer 'http://timestamp.digicert.com'
        if ($sig.Status -eq 'Valid') {
            Write-Host "   [签名] √ $($signCert.Subject)  $($signCert.Thumbprint)" -ForegroundColor DarkGray
        } else {
            Write-Host "   [签名] × $($sig.Status)：$($sig.StatusMessage)" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "   [签名] × 失败：$($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host "   [签名] 跳过 —— 没找到自签证书（$signSubject）；" `
        "按 signing\README.md 生成一次即可（未签名的 exe 在 Win11 上会被 SmartScreen 拦）" -ForegroundColor Yellow
}

# SHA256 清单
$lines = @()
Get-ChildItem $distDir -Recurse -File | Where-Object { $_.Name -ne 'SHA256SUMS.txt' -and $_.Name -ne 'mathlang-session.json' } | ForEach-Object {
    $hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower()
    $relPath = $_.FullName.Substring($distDir.Length + 1) -replace '\\', '/'
    $lines += "$hash  $relPath"
}
$sumFile = Join-Path $distDir 'SHA256SUMS.txt'
[System.IO.File]::WriteAllText($sumFile, ($lines -join "`n") + "`n", (New-Object System.Text.UTF8Encoding($false)))

$sizeMb = [math]::Round(((Get-ChildItem $distDir -Recurse -File | Measure-Object Length -Sum).Sum / 1MB), 1)
Write-Host ''
Write-Host "√ 完成: $distDir  (${sizeMb} MB, $($lines.Count) 个文件)"
Write-Host "  下一步可跑：powershell -ExecutionPolicy Bypass -File scripts\make_shortcut.ps1" -ForegroundColor DarkGray
