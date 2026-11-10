# 数语引擎 · 把桌面/开始菜单上"指向 dist 里 mathlang.exe"的快捷方式**自动重定向**到最新产物
#
# 为什么单独一个脚本（2026-11-10 用户提出）：
#   每次开发版抬版本，产物目录从 dist\v1.3.1 变成 dist\v1.3.2 ⇒ 桌面上那个快捷方式就指向旧目录，
#   用户得手动重新拖一个。本脚本在 build_exe.ps1 收尾时自动跑一次：**找到所有指向 dist\*\mathlang.exe
#   的快捷方式，就地改 TargetPath / WorkingDirectory / IconLocation**（名字、位置都不动）。
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File scripts\refresh_shortcuts.ps1            # 有就改，没有就跳过
#   powershell -ExecutionPolicy Bypass -File scripts\refresh_shortcuts.ps1 -Create    # 没有就建一个（桌面 + 开始菜单）
#   powershell -ExecutionPolicy Bypass -File scripts\refresh_shortcuts.ps1 -Quiet     # build 里调用时用

param(
    [switch]$Create,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$name = '数语引擎'

function Say([string]$msg, [string]$color = 'Gray') {
    if (-not $Quiet) { Write-Host $msg -ForegroundColor $color }
}

# 最新产物
$exe = Get-ChildItem (Join-Path $repo 'dist') -Recurse -File -Filter 'mathlang.exe' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $exe) {
    Say '  跳过：dist 里还没有 mathlang.exe'
    exit 0
}
$exePath = $exe.FullName
$workdir = $exe.Directory.FullName
$icon = "$exePath,0"

$shell = New-Object -ComObject WScript.Shell
$dirs = @(
    [Environment]::GetFolderPath('Desktop'),
    [Environment]::GetFolderPath('Programs')
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

$fixed = 0
$found = 0
foreach ($dir in $dirs) {
    Get-ChildItem $dir -Filter '*.lnk' -File -ErrorAction SilentlyContinue | ForEach-Object {
        $lnk = $_.FullName
        $sc = $shell.CreateShortcut($lnk)
        $target = $sc.TargetPath
        if (-not $target) { return }
        # 只认"指向 dist 里 mathlang.exe"的那种（别人自己建的、指向别处的都不动）
        $isDistExe = ($target -like '*\dist\v*\mathlang.exe')
        if (-not $isDistExe) { return }
        $found++
        if ($target -eq $exePath) { return }   # 已经最新
        $sc.TargetPath = $exePath
        $sc.WorkingDirectory = $workdir
        $sc.IconLocation = $icon
        $sc.Save()
        $fixed++
        Say ("  √ 重定向: " + (Split-Path -Leaf $lnk))
    }
}

if ($found -eq 0 -and $Create) {
    foreach ($dir in $dirs) {
        $lnk = Join-Path $dir ($name + '.lnk')
        $sc = $shell.CreateShortcut($lnk)
        $sc.TargetPath = $exePath
        $sc.WorkingDirectory = $workdir
        $sc.IconLocation = $icon
        $sc.Description = $name
        $sc.Save()
        $fixed++
        Say ("  √ 新建: " + $lnk)
    }
}

if ($fixed -gt 0) {
    Say "  快捷方式：重定向 $fixed 个 → $exePath" 'DarkGray'
} else {
    Say "  快捷方式：无需改动（已指向 $exePath）" 'DarkGray'
}
exit 0
