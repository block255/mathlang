# 数语引擎 · 发布到 GitHub Release（D1 的前置：检查更新读的就是 releases/latest）
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File scripts\publish_release.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\publish_release.ps1 -WhatIf
#
# 它做三件事：
#   ① 从 pubspec.yaml 读版本（唯一来源）；② 用 notes\release\v<ver>.md 当发布说明；
#   ③ 建 release（已存在就更新）并上传三个附件（setup / portable / ASCII 名 msix）。
#
# ★ 需要 token 有该仓库的 **Contents: Read and write**（或 classic 的 repo scope）。
#   2026-10-28 实测：global_credentials\github_token.txt 里的 token 只能读公开数据
#   （x-oauth-scopes 为空）⇒ 建 release 会 403。换/补权限后这条脚本就能一把发完。

param(
  [string]$Version = '',
  [string]$Tag = '',
  [string]$Token = '',
  [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$repoDir = Split-Path -Parent $PSScriptRoot
$app = Join-Path $repoDir 'app'
$slug = 'block255/mathlang'

if (-not $Version) {
    $line = Select-String -Path (Join-Path $app 'pubspec.yaml') -Pattern '^version:\s*(\S+)' | Select-Object -First 1
    $Version = ($line.Matches[0].Groups[1].Value -split '\+')[0]
}
if (-not $Tag) { $Tag = "v$Version" }

if (-not $Token) {
    $tokFile = 'D:\Flutter_APP_Develop\global_credentials\github_token.txt'
    if (-not (Test-Path $tokFile)) { throw "找不到 token 文件：$tokFile" }
    $Token = ([System.IO.File]::ReadAllText($tokFile)).Trim()
}

$notesPath = Join-Path $repoDir ("notes\release\v" + $Version + ".md")
if (-not (Test-Path $notesPath)) { throw "缺少发布说明：$notesPath" }
$body = [System.IO.File]::ReadAllText($notesPath, [System.Text.Encoding]::UTF8)

# 附件：名字必须是 ASCII（GitHub 会丢弃非 ASCII 附件名）
$assets = @(
    @{ file = (Join-Path $repoDir ("dist\mathlang-v" + $Version + "-win64-setup.zip")); name = "mathlang-v$Version-win64-setup.zip"; type = 'application/zip' },
    @{ file = (Join-Path $repoDir ("dist\mathlang-v" + $Version + "-win64-portable.zip")); name = "mathlang-v$Version-win64-portable.zip"; type = 'application/zip' },
    @{ file = (Join-Path $repoDir ("dist\mathlang-v" + $Version + "-x64.msix")); name = "mathlang-v$Version-x64.msix"; type = 'application/octet-stream' }
)
foreach ($a in $assets) {
    if (-not (Test-Path $a.file)) { throw "缺少附件（先跑 build_exe.ps1 + pack_msix.ps1 + pack_release.ps1）：$($a.file)" }
}

$title = "$Version · 数语引擎"
$hdr = @{
    'User-Agent'    = 'mathlang-release'
    Authorization   = "token $Token"
    Accept          = 'application/vnd.github+json'
}

Write-Host "== 发布 $slug $Tag ==" -ForegroundColor Cyan
Write-Host "   说明: $notesPath"
foreach ($a in $assets) { Write-Host ("   附件: " + $a.name) }
if ($WhatIf) { Write-Host '   (-WhatIf：只检查，不联网)'; return }

# ① 已有的 release？（用 tag 查，避免重复建）
$rel = $null
try {
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$slug/releases/tags/$Tag" -Headers $hdr -TimeoutSec 60
    Write-Host "   已有 release（id=$($rel.id)），改为更新说明" -ForegroundColor DarkGray
} catch {
    $rel = $null
}

$payload = ConvertTo-Json -Depth 3 -Compress -InputObject ([ordered]@{
    tag_name   = $Tag
    name       = $title
    body       = $body
    draft      = $false
    prerelease = $false
})

try {
    if ($rel) {
        $rel = Invoke-RestMethod -Uri ("https://api.github.com/repos/$slug/releases/" + $rel.id) `
            -Method Patch -Headers $hdr -Body ([Text.Encoding]::UTF8.GetBytes($payload)) `
            -ContentType 'application/json; charset=utf-8' -TimeoutSec 90
    } else {
        $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$slug/releases" `
            -Method Post -Headers $hdr -Body ([Text.Encoding]::UTF8.GetBytes($payload)) `
            -ContentType 'application/json; charset=utf-8' -TimeoutSec 90
    }
} catch {
    $msg = $_.Exception.Message
    if ($_.ErrorDetails.Message) { $msg = $_.ErrorDetails.Message }
    throw "建 release 失败（多半是 token 没有该仓库的 Contents: write）`n$msg"
}
Write-Host "   √ release: $($rel.html_url)" -ForegroundColor Green

# ② 上传附件（同名先删旧的，方便重发）
$existing = @($rel.assets)
foreach ($a in $assets) {
    foreach ($old in $existing) {
        if ($old.name -eq $a.name) {
            Invoke-RestMethod -Uri ("https://api.github.com/repos/$slug/releases/assets/" + $old.id) `
                -Method Delete -Headers $hdr -TimeoutSec 60 | Out-Null
            Write-Host "   - 删掉旧附件 $($a.name)" -ForegroundColor DarkGray
        }
    }
    $up = "https://uploads.github.com/repos/$slug/releases/$($rel.id)/assets?name=$($a.name)"
    $r = Invoke-RestMethod -Uri $up -Method Post -Headers $hdr -InFile $a.file -ContentType $a.type -TimeoutSec 900
    Write-Host ("   √ 上传 " + $a.name + " (" + [math]::Round($r.size / 1MB, 1) + " MB)") -ForegroundColor Green
}

Write-Host ''
Write-Host "√ 完成：https://github.com/$slug/releases/tag/$Tag" -ForegroundColor Green
Write-Host '  下一步：在已装的 1.1.x 里点「设置 → 关于 → 检查更新」测自动更新' -ForegroundColor DarkGray
