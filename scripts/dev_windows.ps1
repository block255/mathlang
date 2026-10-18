# 数语引擎 · 开发运行（Windows 桌面 / Web 预览）
#
# 这个脚本**不需要管理员**：插件链接用 junction 补（见 ensure_plugin_links.ps1），
# flutter_tools 只在链接缺失时才尝试建符号链接。
#
# 用法（双击 dev.cmd 等价于不带参数运行本脚本）：
#   powershell -ExecutionPolicy Bypass -File scripts\dev_windows.ps1                 # Windows 桌面
#   powershell -ExecutionPolicy Bypass -File scripts\dev_windows.ps1 -Device web     # Web 预览
#
# 起来之后：
#   改代码 → 向 scripts\cmd.txt 写入一个字符 r（热重载）/ R（热重启）/ x（完全重启）/ q（退出）
#   日志见 scripts\run.log，状态见 scripts\state.json

param(
    [ValidateSet('windows', 'web')]
    [string]$Device = 'windows',
    [int]$Port = 57134,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$workspace = Split-Path (Split-Path $repo -Parent) -Parent
$app = Join-Path $repo 'app'

# ---- 缓存重定向（工作区内，见 AGENTS.md 第六节）----
$env:PUB_CACHE = Join-Path $workspace '_cache\pub'
$env:TEMP = Join-Path $workspace '_cache\tmp'
$env:TMP = $env:TEMP
$env:LOCALAPPDATA = Join-Path $workspace '_cache\localappdata'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
foreach ($d in @($env:PUB_CACHE, $env:TEMP, $env:LOCALAPPDATA)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

if (-not $Quiet) {
    Write-Host ''
    Write-Host '== 数语引擎 · 开发运行 ==' -ForegroundColor Cyan
    Write-Host "   项目: $app"
    Write-Host "   设备: $Device"
    Write-Host '   改完代码：把字符 r 写进 scripts\cmd.txt 即热重载（R 热重启 / x 完全重启 / q 退出）' -ForegroundColor DarkGray
    Write-Host '   日志: scripts\run.log    状态: scripts\state.json' -ForegroundColor DarkGray
    Write-Host ''
}

# ---- 插件链接兜底（flutter clean 之后必须）----
& (Join-Path $PSScriptRoot 'ensure_plugin_links.ps1') -Quiet:(-not $Quiet)

# ---- 起桥（前台运行，窗口留着看日志）----
$bridge = Join-Path $PSScriptRoot 'hotreload_bridge.js'
$bridgeDevice = if ($Device -eq 'web') { 'web-server' } else { 'windows' }
Set-Location $PSScriptRoot
node $bridge --device $bridgeDevice --port $Port
