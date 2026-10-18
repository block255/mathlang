# 数语引擎 · 建桌面 / 开始菜单快捷方式（双击即启动，不经过终端）
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File scripts\make_shortcut.ps1                # 用 dist 里最新的 release
#   powershell -ExecutionPolicy Bypass -File scripts\make_shortcut.ps1 -Dev           # 额外建一个「开发（热重载）」
#   powershell -ExecutionPolicy Bypass -File scripts\make_shortcut.ps1 -Remove        # 删掉快捷方式

param(
    [switch]$Dev,
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$name = '数语引擎'

$desktop = [Environment]::GetFolderPath('Desktop')
$programs = [Environment]::GetFolderPath('Programs')
$targets = @(
    (Join-Path $desktop ($name + '.lnk')),
    (Join-Path $programs ($name + '.lnk')),
    (Join-Path $desktop ($name + '（开发）.lnk')),
    (Join-Path $programs ($name + '（开发）.lnk'))
)

if ($Remove) {
    foreach ($t in $targets) { if (Test-Path $t) { Remove-Item $t -Force; Write-Host "  已删除: $t" } }
    exit 0
}

# 找 dist\v* 里最新的 exe
$distRoot = Join-Path $repo 'dist'
$exe = $null
if (Test-Path $distRoot) {
    $exe = Get-ChildItem $distRoot -Recurse -File -Filter 'mathlang.exe' |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
}
if (-not $exe) {
    throw "dist 里还没有 release 产物 —— 先跑 scripts\build_exe.ps1"
}
$exePath = $exe.FullName

$shell = New-Object -ComObject WScript.Shell

function New-Lnk([string]$path, [string]$target, [string]$icon, [string]$workdir, [string]$desc) {
    $sc = $shell.CreateShortcut($path)
    $sc.TargetPath = $target
    $sc.WorkingDirectory = $workdir
    $sc.IconLocation = $icon
    $sc.Description = $desc
    $sc.Save()
    Write-Host "  √ $path"
}

$iconRef = "$exePath,0"
New-Lnk (Join-Path $desktop ($name + '.lnk')) $exePath $iconRef $exe.Directory.FullName '数语引擎'
New-Lnk (Join-Path $programs ($name + '.lnk')) $exePath $iconRef $exe.Directory.FullName '数语引擎'

if ($Dev) {
    $cmd = Join-Path $PSScriptRoot 'dev.cmd'
    $devIcon = 'C:\Windows\System32\imageres.dll,3'
    foreach ($dir in @($desktop, $programs)) {
        $p = Join-Path $dir ($name + '（开发）.lnk')
        $sc = $shell.CreateShortcut($p)
        $sc.TargetPath = $cmd
        $sc.WorkingDirectory = $PSScriptRoot
        $sc.IconLocation = $devIcon
        $sc.Description = '数语引擎 · 开发实例（热重载，日志在 scripts\run.log）'
        $sc.Save()
        Write-Host "  √ $p"
    }
}

Write-Host ''
Write-Host '完成。双击桌面/开始菜单里的「数语引擎」即可启动。' -ForegroundColor Cyan
