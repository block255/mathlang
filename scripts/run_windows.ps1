# 数语引擎 · 在 Windows 上跑起来（开发用，2026-10-17）
#
# 为什么需要这个脚本：
#   ① 构建要把缓存重定向到工作区内的 `_cache\`（DSH 沙箱只给工作区授权，见 AGENTS.md 第六节）；
#   ② `flutter build/run windows` 需要**符号链接**支持（`file_picker` 等插件）——
#      DSH 的沙箱令牌没有 `SeCreateSymbolicLinkPrivilege`，所以**必须在你自己的 PowerShell 里跑**。
#
# 用法：右键「用 PowerShell 运行」，或在普通 PowerShell 窗口里
#   powershell -ExecutionPolicy Bypass -File D:\Flutter_APP_Develop\projects\mathlang\scripts\run_windows.ps1

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot                 # projects\mathlang
$workspace = Split-Path (Split-Path $repo -Parent) -Parent   # D:\Flutter_APP_Develop

Write-Host "== 数语引擎 · Windows 开发运行 ==" -ForegroundColor Cyan
Write-Host "  项目: $repo\app"

# 缓存重定向（工作区内，避免沙箱/权限问题）
$env:PUB_CACHE           = Join-Path $workspace '_cache\pub'
$env:TEMP                = Join-Path $workspace '_cache\tmp'
$env:TMP                 = $env:TEMP
$env:LOCALAPPDATA        = Join-Path $workspace '_cache\localappdata'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:PUB_HOSTED_URL      = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'

foreach ($d in @($env:PUB_CACHE, $env:TEMP, $env:LOCALAPPDATA)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

$flutter = Join-Path $workspace 'Flutter_SDK\flutter\bin\flutter.bat'
if (-not (Test-Path $flutter)) { throw "找不到 flutter: $flutter" }

Set-Location (Join-Path $repo 'app')
Write-Host "  键盘: 保存 Ctrl+S / 打开 Ctrl+O / 新建 Ctrl+N / 另存为 Ctrl+Shift+S" -ForegroundColor DarkGray
Write-Host "  （窗口关掉 = 结束；改代码后按 r 热重载）" -ForegroundColor DarkGray

& $flutter run -d windows

Write-Host ""
Write-Host "已退出。按任意键关闭这个窗口…" -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
