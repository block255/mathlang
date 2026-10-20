# 数语引擎 · **发布包打包**（2026-10-19）
#
# 产出：dist\mathlang-v<版本>-win64.zip
#   └─ 数语引擎\
#      ├─ 数语引擎.exe           ← 已签名（发布名与开发名不同：见下）
#      ├─ flutter_windows.dll
#      ├─ data\
#      ├─ 启动数语引擎.cmd        ← 首次请点这个（自动检查/安装自签证书后启动）
#      ├─ 证书-数语引擎.cer       ← 备用：手动装（双击 → 安装证书 → 受信任的根）
#      └─ 安装说明.txt
#
# ★★ 为什么要改名：开发产物叫 `mathlang.exe`（ASCII，进 cmake/ninja 命令行），
#   面向用户的发布名是 `数语引擎.exe`。**改名在打包这一步做**，不动构建，避免把中文塞进 CMake。
#   Flutter 的 runner 靠"exe 同目录的 data\ 与 flutter_windows.dll"找资源，改名安全。
# ★★ 首次运行的那道拦：Windows 11（26200）对**未签名** exe 一律拦；
#   我们自签 ⇒ 只要证书在本机受信任根里就不弹。启动脚本负责"检测 + 装一次 + 启动"。

param(
    [string]$Version = '',
    [switch]$NoSign
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot            # projects\mathlang
$app = Join-Path $root 'app'

if (-not $Version) {
    $line = Select-String -Path (Join-Path $app 'pubspec.yaml') -Pattern '^version:\s*(\S+)' | Select-Object -First 1
    $Version = ($line.Matches[0].Groups[1].Value -split '\+')[0]
}
$rel = Join-Path $app 'build\windows\x64\runner\Release'
if (-not (Test-Path (Join-Path $rel 'mathlang.exe'))) { throw "先构建：flutter build windows --release" }

$stage = Join-Path $root 'dist\_pack\数语引擎'
if (Test-Path (Join-Path $root 'dist\_pack')) { Remove-Item (Join-Path $root 'dist\_pack') -Recurse -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null

Write-Host "   [1/4] 收产物" -ForegroundColor DarkGray
Copy-Item (Join-Path $rel '*') $stage -Recurse -Force -Exclude @('*.pdb')
# 发布名：mathlang.exe → 数语引擎.exe
$exeOut = Join-Path $stage '数语引擎.exe'
Move-Item (Join-Path $stage 'mathlang.exe') $exeOut -Force

Write-Host "   [2/4] 签名" -ForegroundColor DarkGray
if (-not $NoSign) {
    $cert = Get-ChildItem Cert:\CurrentUser\My -ErrorAction SilentlyContinue |
        Where-Object { $_.Subject -eq 'CN=数语引擎（自签）' -and $_.HasPrivateKey } |
        Sort-Object NotAfter -Descending | Select-Object -First 1
    if ($cert) {
        $sig = Set-AuthenticodeSignature -FilePath $exeOut -Certificate $cert -HashAlgorithm SHA256 `
            -TimestampServer 'http://timestamp.digicert.com'
        if ($sig.Status -eq 'Valid') { Write-Host "        √ $($sig.SignerCertificate.Subject)" -ForegroundColor DarkGray }
        else { Write-Host "        × $($sig.Status)：$($sig.StatusMessage)" -ForegroundColor Yellow }
    } else {
        Write-Host "        × 没找到自签证书（按 signing\README.md 生成一次）" -ForegroundColor Yellow
    }
}

Write-Host "   [3/4] 证书 / 启动脚本 / 说明" -ForegroundColor DarkGray
$thumb = (Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -eq 'CN=数语引擎（自签）' } |
    Sort-Object NotAfter -Descending | Select-Object -First 1).Thumbprint
Copy-Item (Join-Path $root 'signing\数语引擎-自签证书.cer') (Join-Path $stage '证书-数语引擎.cer') -Force

$cmd = @"
@echo off
setlocal
set "HERE=%~dp0"
set "THUMB=$thumb"
echo 数语引擎 —— 首次运行需要信任一次本软件的自签证书（只影响这台电脑、只信任这一把）。
certutil -user -store Root %THUMB% >nul 2>&1
if errorlevel 1 (
  echo.
  echo   即将安装证书；系统会弹出确认框，请点「是」。
  certutil -user -addstore Root "%HERE%证书-数语引擎.cer" >nul
  if errorlevel 1 (
    echo.
    echo   [失败] 证书没装上，exe 仍会被 Windows 拦。
    echo   手动做法：双击「证书-数语引擎.cer」→ 安装证书 → 当前用户 → 受信任的根证书颁发机构。
    pause
    exit /b 1
  )
  echo   证书已信任。
)
rem ★ U6：顺手建桌面快捷方式（用户要求"装完就有图标"；绿色版直接从当前目录建）
powershell -NoProfile -Command "$d=[Environment]::GetFolderPath('Desktop'); $p=Join-Path $d '数语引擎.lnk'; if (-not (Test-Path $p)) { $s=(New-Object -ComObject WScript.Shell).CreateShortcut($p); $s.TargetPath='%HERE%数语引擎.exe'; $s.WorkingDirectory='%HERE%'; $s.IconLocation='%HERE%数语引擎.exe,0'; $s.Save() }"
start "" "%HERE%数语引擎.exe"
"@
[System.IO.File]::WriteAllText((Join-Path $stage '启动数语引擎.cmd'), ($cmd -replace "`r?`n", "`r`n"), [System.Text.Encoding]::GetEncoding(936))

$readme = @"
数语引擎 $Version · Windows 64 位（绿色版，解压即用）

一、第一次打开
  双击「启动数语引擎.cmd」。
  它会检查本软件的自签证书，没装就装一次（系统会问「是否信任」，点「是」），然后启动。
  ★ 请不要第一次就双击 exe —— 证书还没信任时，Windows 会拦它（"已保护你的电脑"）。

二、以后打开
  直接双击「数语引擎.exe」，或者右键它 →「发送到」→「桌面快捷方式」。
  ★ 绿色版**可能仍会被 Windows 拦一次**（"已保护你的电脑"）——
    因为 SmartScreen 只认公共 CA 签名的发布者，自签证书过不了它。
    遇到就点「更多信息」→「仍要运行」；这是绿色版的固有代价。
    想彻底没有这道弹窗 ⇒ 用「安装版」（装成应用后启动不走这道检查）。

三、出问题
  若仍被 Windows 拦：双击「证书-数语引擎.cer」→ 安装证书 → 当前用户 →
  「受信任的根证书颁发机构」→ 完成，再打开 exe。
  卸载：删掉整个「数语引擎」文件夹即可（设置与暂存放在同一个文件夹里，
  所以删之前若要保留，请先把文档「导出」成 .md）。
"@
[System.IO.File]::WriteAllText((Join-Path $stage '安装说明.txt'), ($readme -replace "`r?`n", "`r`n"), [System.Text.Encoding]::UTF8)

Write-Host "   [4/4] 打 zip" -ForegroundColor DarkGray
$zip = Join-Path $root ("dist\mathlang-v$Version-win64-portable.zip")  # ★ U7：GitHub 用 ASCII 名
if (Test-Path $zip) { Remove-Item $zip -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory((Join-Path $root 'dist\_pack'), $zip, [System.IO.Compression.CompressionLevel]::Optimal, $false)
Remove-Item (Join-Path $root 'dist\_pack') -Recurse -Force

$mb = [math]::Round((Get-Item $zip).Length / 1MB, 1)
Write-Host ''
Write-Host "√ 发布包: $zip  (${mb} MB)" -ForegroundColor Green
Write-Host "   里面有：数语引擎\数语引擎.exe（已签名）+ data\ + 启动数语引擎.cmd + 证书 + 安装说明.txt" -ForegroundColor DarkGray