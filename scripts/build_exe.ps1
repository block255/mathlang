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
if (Test-Path $distDir) { Remove-Item $distDir -Recurse -Force }
New-Item -ItemType Directory -Path $distDir -Force | Out-Null

Write-Host '   [4/4] 归档到 dist' -ForegroundColor DarkGray
Copy-Item $exePath $distDir -Force
Copy-Item (Join-Path $rel 'flutter_windows.dll') $distDir -Force -ErrorAction SilentlyContinue
Get-ChildItem $rel -Filter '*.dll' -File | ForEach-Object {
    Copy-Item $_.FullName $distDir -Force
}
Copy-Item (Join-Path $rel 'data') $distDir -Recurse -Force

# SHA256 清单
$lines = @()
Get-ChildItem $distDir -Recurse -File | Where-Object { $_.Name -ne 'SHA256SUMS.txt' } | ForEach-Object {
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
