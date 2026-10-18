# 数语引擎 · 补齐 Windows 插件的 .plugin_symlinks（用 junction，零特权）
#
# 为什么需要它：
#   flutter_tools 只在 `windows\flutter\ephemeral\.plugin_symlinks\<插件名>` **缺失时**才建符号链接
#   （源码 flutter_plugins.dart: `if (link.existsSync()) continue;`，调用处 force=false）。
#   建链接需要 SeCreateSymbolicLinkPrivilege（本机普通令牌没有，实测 errno 1314；开发者模式也不管用）。
#   而**目录联接（junction）不需要任何特权**，且 dart:io 会把它认作已存在的 Link
#   ⇒ 这里先用 junction 占位，flutter 就会跳过建链接这一步。
#
# 什么时候要跑：`flutter clean` 之后、pubspec 换了插件之后、换了 PUB_CACHE 之后。
#   `dev_windows.ps1` 与 `build_exe.ps1` 都会自动调用它。
#
# 用法：powershell -ExecutionPolicy Bypass -File scripts\ensure_plugin_links.ps1 [-Quiet]

param([switch]$Quiet)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$app = Join-Path $repo 'app'
$depsFile = Join-Path $app '.flutter-plugins-dependencies'
$linkDir = Join-Path $app 'windows\flutter\ephemeral\.plugin_symlinks'

function Say([string]$msg) {
    if (-not $Quiet) { Write-Host $msg -ForegroundColor DarkGray }
}

if (-not (Test-Path $depsFile)) {
    Say "  （跳过：还没有 $depsFile，先跑一次 flutter pub get）"
    exit 0
}

$deps = Get-Content $depsFile -Raw -Encoding UTF8 | ConvertFrom-Json
$plugins = @()
if ($deps.plugins -and $deps.plugins.windows) { $plugins = @($deps.plugins.windows) }

if ($plugins.Count -eq 0) {
    Say '  （本工程没有 Windows 插件，无需补链接）'
    exit 0
}

if (-not (Test-Path $linkDir)) {
    New-Item -ItemType Directory -Path $linkDir -Force | Out-Null
}

$created = 0
$skipped = 0
foreach ($p in $plugins) {
    $name = $p.name
    $target = $p.path
    if (-not $name -or -not $target) { continue }
    $link = Join-Path $linkDir $name

    $item = Get-Item $link -Force -ErrorAction SilentlyContinue
    if ($item) {
        # 已存在：真目录 / 有效链接 / 断链，分别处理
        if ($item.LinkType) {
            $ok = Test-Path (Join-Path $link '.')   # 穿透链接能不能到达目标
            if ($ok) { $skipped++; continue }
            Say "  修复断链: $name"
            [System.IO.Directory]::Delete($link, $false)
        } else {
            $skipped++
            continue
        }
    }

    try {
        New-Item -ItemType Junction -Path $link -Target $target | Out-Null
        $created++
        Say "  junction: $name → $target"
    } catch {
        Write-Host "  ⚠ 无法为 $name 建 junction: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Say "  插件链接：新建 $created 个、已就绪 $skipped 个（共 $($plugins.Count)）"
