# 数语引擎 · **MSIX 打包**（2026-10-19，方案 A）
#
# 为什么做 MSIX：Windows 11（26200）对**文件级** exe 一律走 SmartScreen；
#   而**已安装的 MSIX 应用启动时不走那道检查** ⇒ 这是"不花钱、分发也不弹"的现实解。
#   （自签证书本身过不了 SmartScreen —— 2026-10-19 实测确认，见 signing\README.md）
#
# 产物：dist\数语引擎-<版本>-x64.msix（**已签名**）
# 安装：先信任证书（本机已有；别人用发布包里的 .cer + 本脚本 -Install 也可），再双击 .msix
#
# 依赖：Windows SDK 的 MakeAppx.exe / SignTool.exe（本机在
#   C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64，脚本会自动挑最高版本）

param(
    [string]$Version = '',
    [switch]$Install,          # 装到本机（Add-AppxPackage）
    [switch]$KeepStage
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot           # projects\mathlang
$app = Join-Path $root 'app'
$signing = Join-Path $root 'signing'
$identity = 'MathLang.Editor'
$publisherDisplay = '数语引擎'
$exeName = '数语引擎.exe'

# ---------- 版本 ----------
# ★★ 2026-10-28（用户拍板）：MSIX 的第 4 段 = **构建号**（`1.1.2+5` → `1.1.2.5`）。
#   原来固定 `.0` ⇒ 同一版本名重打包**装不上**（MSIX 要求版本递增），
#   而"构建号"本来就是"同版本名的修订"，正好对上第 4 段。
#   ⇒ 不抬版本名也能反复覆盖安装；「关于」页仍只显示版本名（C2 生成）。
$rawVer = $Version
if (-not $rawVer) {
    $line = Select-String -Path (Join-Path $app 'pubspec.yaml') -Pattern '^version:\s*(\S+)' | Select-Object -First 1
    $rawVer = $line.Matches[0].Groups[1].Value
}
$verParts = "$rawVer" -split '\+'
$Version = $verParts[0]
$buildNo = if ($verParts.Count -gt 1 -and $verParts[1] -match '^\d+$') { $verParts[1] } else { '0' }
$appxVersion = "$Version".Split('.')
if ($appxVersion.Count -lt 3) { throw "版本号要形如 1.0.0（实际 $Version）" }
$appxVersion = "$($appxVersion[0]).$($appxVersion[1]).$($appxVersion[2]).$buildNo"

# ---------- SDK 工具 ----------
$sdkRoot = 'C:\Program Files (x86)\Windows Kits\10\bin'
$sdkBin = Get-ChildItem $sdkRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^10\.0\.\d+\.0$' } |
    Sort-Object { [version]$_.Name } -Descending |
    ForEach-Object { Join-Path $_.FullName 'x64' } |
    Where-Object { Test-Path (Join-Path $_ 'MakeAppx.exe') } |
    Select-Object -First 1
if (-not $sdkBin) { throw "找不到 Windows SDK 的 MakeAppx.exe（应在 $sdkRoot\10.0.x.0\x64）" }
$makeappx = Join-Path $sdkBin 'MakeAppx.exe'
$signtool = Join-Path $sdkBin 'SignTool.exe'
Write-Host "   SDK: $sdkBin" -ForegroundColor DarkGray

# ---------- 证书 ----------
$cert = Get-ChildItem Cert:\CurrentUser\My -ErrorAction SilentlyContinue |
    Where-Object { $_.Subject -eq 'CN=数语引擎（自签）' -and $_.HasPrivateKey } |
    Sort-Object NotAfter -Descending | Select-Object -First 1
if (-not $cert) { throw "找不到自签证书（signing\README.md 有生成步骤）" }
$publisher = $cert.Subject       # MSIX 的 Publisher **必须**与证书 Subject 逐字一致

# ---------- 产物目录 ----------
$rel = Join-Path $app 'build\windows\x64\runner\Release'
if (-not (Test-Path (Join-Path $rel 'mathlang.exe'))) { throw "先构建：flutter build windows --release" }
$stageRoot = Join-Path $root 'dist\_msix'
$stage = Join-Path $stageRoot 'layout'
if (Test-Path $stageRoot) { Remove-Item $stageRoot -Recurse -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null

Write-Host '   [1/5] 收产物' -ForegroundColor DarkGray
Copy-Item (Join-Path $rel '*') $stage -Recurse -Force -Exclude @('*.pdb')
Move-Item (Join-Path $stage 'mathlang.exe') (Join-Path $stage $exeName) -Force

Write-Host '   [2/5] 生成图标资源' -ForegroundColor DarkGray
Add-Type -AssemblyName System.Drawing
$srcIcon = Join-Path $app 'web\icons\Icon-512.png'
if (-not (Test-Path $srcIcon)) { throw "缺图标源：$srcIcon" }
$assetsDir = Join-Path $stage 'Assets'
New-Item -ItemType Directory -Path $assetsDir -Force | Out-Null
$src = [System.Drawing.Image]::FromFile($srcIcon)
function New-Png([int]$w, [int]$h, [string]$name) {
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    # 等比缩放居中
    $scale = [Math]::Min($w / $src.Width, $h / $src.Height)
    $dw = [int]($src.Width * $scale); $dh = [int]($src.Height * $scale)
    $g.DrawImage($src, [int](($w - $dw) / 2), [int](($h - $dh) / 2), $dw, $dh)
    $g.Dispose()
    $bmp.Save((Join-Path $assetsDir $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}
New-Png 44 44 'Square44x44Logo.png'
New-Png 150 150 'Square150x150Logo.png'
New-Png 50 50 'StoreLogo.png'
New-Png 310 150 'Wide310x150Logo.png'
New-Png 256 256 'Square150x150Logo.scale-200.png'
$src.Dispose()

Write-Host '   [3/5] 写 AppxManifest.xml' -ForegroundColor DarkGray
$pubXml = [System.Security.SecurityElement]::Escape($publisher)
$manifest = @"
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
         xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
         xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
         IgnorableNamespaces="uap rescap">
  <Identity Name="$identity"
            Publisher="$pubXml"
            Version="$appxVersion"
            ProcessorArchitecture="x64" />
  <Properties>
    <DisplayName>$publisherDisplay</DisplayName>
    <PublisherDisplayName>$publisherDisplay</PublisherDisplayName>
    <Logo>Assets\StoreLogo.png</Logo>
  </Properties>
  <Resources>
    <Resource Language="zh-CN" />
    <Resource Language="en-US" />
  </Resources>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.19041.0" MaxVersionTested="10.0.26100.0" />
  </Dependencies>
  <Applications>
    <Application Id="App" Executable="$exeName" EntryPoint="Windows.FullTrustApplication">
      <uap:VisualElements DisplayName="$publisherDisplay"
                          Description="数语引擎 —— 看不见数学编码的数学文档编辑器"
                          BackgroundColor="transparent"
                          Square150x150Logo="Assets\Square150x150Logo.png"
                          Square44x44Logo="Assets\Square44x44Logo.png"
                          AppListEntry="default">
        <uap:DefaultTile Wide310x150Logo="Assets\Wide310x150Logo.png" />
      </uap:VisualElements>
    </Application>
  </Applications>
  <Capabilities>
    <rescap:Capability Name="runFullTrust" />
  </Capabilities>
</Package>
"@
$manifestPath = Join-Path $stage 'AppxManifest.xml'
[System.IO.File]::WriteAllText($manifestPath, $manifest, (New-Object System.Text.UTF8Encoding($false)))

Write-Host '   [4/5] makeappx pack' -ForegroundColor DarkGray
$msix = Join-Path $root ("dist\数语引擎-$Version-x64.msix")
if (Test-Path $msix) { Remove-Item $msix -Force }
& $makeappx pack /d $stage /p $msix /o | Out-Null
if (-not (Test-Path $msix)) { throw "打包失败（makeappx 没产出 $msix）" }

Write-Host '   [5/5] signtool sign' -ForegroundColor DarkGray
# ★★ 2026-10-25：**默认直接走证书库**（按证书主体找本机 CurrentUser\My 里带私钥的那张）
#   ⇒ 不需要 pfx、不需要口令、没有任何凭据要保管。
#   `signtool /sha1 <指纹>` 用的是当前用户证书库里的私钥（本机实测：无口令、无弹窗，签名 Valid）。
#   只有当证书库里找不到时才退回"pfx + MATHLANG_PFX_PASSWORD"这条老路（给 CI / 别的机器用）。
$pfx = Join-Path $signing 'mathlang-selfsign.pfx'
$storeCert = Get-ChildItem Cert:\CurrentUser\My -ErrorAction SilentlyContinue |
    Where-Object { $_.Subject -eq 'CN=数语引擎（自签）' -and $_.HasPrivateKey } |
    Sort-Object NotAfter -Descending | Select-Object -First 1
if ($storeCert) {
    Write-Host "        用证书库：$($storeCert.Thumbprint)" -ForegroundColor DarkGray
    & $signtool sign /fd SHA256 /sha1 $storeCert.Thumbprint /td SHA256 `
        /tr 'http://timestamp.digicert.com' $msix | Out-Null
} else {
    if (-not (Test-Path $pfx)) { throw "证书库里没有签名证书，也没有 pfx：$pfx" }
    # 口令只从环境变量取；不要写死在脚本里（见 signing\README.md）
    $pfxPassword = $env:MATHLANG_PFX_PASSWORD
    if ([string]::IsNullOrEmpty($pfxPassword)) {
        throw '证书库里没有签名证书；要走 pfx 就得设 MATHLANG_PFX_PASSWORD（见 signing\README.md），不要把口令写进脚本。'
    }
    Write-Host '        用 pfx + MATHLANG_PFX_PASSWORD' -ForegroundColor DarkGray
    & $signtool sign /fd SHA256 /f $pfx /p $pfxPassword /td SHA256 `
        /tr 'http://timestamp.digicert.com' $msix | Out-Null
}
$sig = Get-AuthenticodeSignature $msix
Write-Host "        签名：$($sig.Status) · $($sig.SignerCertificate.Subject)" -ForegroundColor DarkGray

if ($Install) {
    Write-Host '   [装机] Add-AppxPackage' -ForegroundColor DarkGray
    # 自签 MSIX 要求证书在「受信任的根」；装到「受信任人」更稳
    foreach ($storeName in @('Root', 'TrustedPeople')) {
        $st = New-Object System.Security.Cryptography.X509Certificates.X509Store $storeName, 'CurrentUser'
        $st.Open('ReadWrite'); $st.Add($cert); $st.Close()
    }
    Add-AppxPackage -Path $msix -ForceApplicationShutdown
    Write-Host "        已安装：$identity" -ForegroundColor DarkGray
}

# ★★ 2026-10-19（U6）：给 MSIX 配一个**双击即装、装完自动开**的安装器脚本。
#   MSIX 没有"安装后执行一次"的机制（微软不给），而"普通用户根本不会去找软件装在哪"
#   ⇒ 用一个 .cmd 代劳：信任证书（需要就自提权）→ 装 msix → 启动应用
#   （首次启动应用自己会在桌面建快捷方式）。
# ★★ 2026-10-19（U7，用户拍板）：
#   · GitHub 发布的**包名用 ASCII**（`mathlang-v…-setup.zip`），解压出来的文件夹叫「数语引擎」；
#   · 安装/卸载脚本名要**一眼看懂**：`双击我安装数语引擎.cmd` / `双击我卸载数语引擎.cmd`。
$stage = Join-Path $root 'dist\_setup\数语引擎'
if (Test-Path (Join-Path $root 'dist\_setup')) { Remove-Item (Join-Path $root 'dist\_setup') -Recurse -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null

Copy-Item $msix (Join-Path $stage '数语引擎.msix') -Force
Copy-Item (Join-Path $signing '数语引擎-自签证书.cer') (Join-Path $stage '证书-数语引擎.cer') -Force

$thumbStr = $cert.Thumbprint

# ★★ C1（2026-10-28，用户 2026-10-26 报「安装时先报错、然后重试、然后弹 UAC，还弹了两次」）：
#   根因三条（调查稿 handover\公测反馈-20261026-草稿.md §五 逐行对得上）：
#     ① **当前用户证书存储对 MSIX 校验无效** —— 校验发生在 AppXSVC（SYSTEM 上下文），只认本机存储；
#     ② 提升分支是**两条** Start-Process -RunAs ⇒ **两次 UAC**；
#     ③ **先装、失败后再提升** ⇒ 每个新用户必然先看到一次 0x800B0109 大段报错。
#   改法：
#     ① 先用 Test-Path 查【本机 TrustedPeople】有没有这把证书 —— 有就**跳过全部证书动作**
#        （老用户重装 / 升级 ⇒ **零 UAC**）；
#     ② 没有就弹**一次** UAC，在**同一个**提升进程里把本机 Root + TrustedPeople 都装上
#        （提升进程跑同目录的 `装证书-管理员一次.ps1`，比在 bat 里拼引号稳）；
#     ③ **只装一次包**（不再"先失败一次"），失败才打印失败信息。
$installCmd = @"
@echo off
setlocal
set "HERE=%~dp0"
set "THUMB=$thumbStr"
echo ============================================
echo    数语引擎  $Version   （Windows 64 位）
echo ============================================
echo.
rem ── 1. 本机受信任存储里已经有这把证书吗？（重装 / 升级 -> 零 UAC）──
powershell -NoProfile -Command "if (Test-Path ('Cert:\LocalMachine\TrustedPeople\' + '%THUMB%')) { exit 0 } else { exit 1 }"
if not errorlevel 1 goto install
rem ── 2. 没有就只弹一次管理员授权（同一个提升进程里把 Root + TrustedPeople 一起装上）──
echo 第一次安装需要让系统信任本软件的自签证书（只影响这台电脑、只信任这一把）。
echo 系统会弹一次管理员授权，请点 [是]。只这一次 —— 以后升级不再问。
powershell -NoProfile -Command "Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','\"%HERE%装证书-管理员一次.ps1\"'"
rem 装完再查一次：还是没有就不硬装（硬装必然 0x800B0109 大段报错）
powershell -NoProfile -Command "if (Test-Path ('Cert:\LocalMachine\TrustedPeople\' + '%THUMB%')) { exit 0 } else { exit 1 }"
if not errorlevel 1 goto install
echo.
echo   [失败] 证书没装进"本机"受信任存储（刚才可能点了 [否]）。
echo   临时办法：改用绿色版，双击「启动数语引擎.cmd」直接运行。
pause
exit /b 1
:install
echo 正在安装…
powershell -NoProfile -Command "Add-AppxPackage -Path '%HERE%数语引擎.msix' -ForceApplicationShutdown"
if errorlevel 1 (
  echo.
  echo   [失败] 没装上。请把这句话连同上面的报错一起截图。
  echo   临时办法：改用绿色版（portable 包），双击「启动数语引擎.cmd」就能直接运行。
  pause
  exit /b 1
)
echo 装好了，正在打开…
powershell -NoProfile -Command "`$p=(Get-AppxPackage MathLang.Editor).PackageFamilyName; Start-Process ('shell:AppsFolder\'+`$p+'!App')"
rem ★ 2026-10-28：开始菜单里那份**我们自己写的 .lnk 是历史遗留**（早期开发版指向 dist\v1.0.0，
rem 目标早已不存在）。MSIX 安装后开始菜单的「所有应用」由**包清单**提供（AppListEntry=default）
rem ⇒ 那个 .lnk 是多余的死链，顺手删掉；以后也不再往开始菜单写。
del /q "%APPDATA%\Microsoft\Windows\Start Menu\Programs\数语引擎.lnk" 2>nul
rem 桌面快捷方式由**应用首次启动**自己建（MSIX 不允许安装包创建桌面快捷方式）
echo.
echo 完成。桌面图标会在第一次打开后出现（开始菜单的「数语引擎」由系统提供）。
pause
"@
[System.IO.File]::WriteAllText((Join-Path $stage '双击我安装数语引擎.cmd'), ($installCmd -replace "`r?`n", "`r`n"), [System.Text.Encoding]::GetEncoding(936))

# 提升进程跑的小脚本（C1）：一次 UAC 里把 Root + TrustedPeople 都装到**本机**存储。
$certHelper = @"
`$ErrorActionPreference = 'Stop'
`$here = Split-Path -Parent `$MyInvocation.MyCommand.Path
`$cer = Join-Path `$here '证书-数语引擎.cer'
if (-not (Test-Path `$cer)) { Write-Host "找不到证书：`$cer"; exit /b 1 }
Write-Host ''
Write-Host '正在把证书装进「本机」受信任存储（Root + TrustedPeople）…'
certutil -f -addstore -machine Root "`$cer" | Out-Null
certutil -f -addstore -machine TrustedPeople "`$cer" | Out-Null
Write-Host '完成。'
Start-Sleep -Milliseconds 800
"@
[System.IO.File]::WriteAllText((Join-Path $stage '装证书-管理员一次.ps1'), ($certHelper -replace "`r?`n", "`r`n"), (New-Object System.Text.UTF8Encoding($true)))

$uninstallCmd = @"
@echo off
setlocal
echo ============================================
echo    卸载 数语引擎  $Version
echo ============================================
echo.
powershell -NoProfile -Command "Get-Process -Name '数语引擎' -ErrorAction SilentlyContinue | Stop-Process -Force"
powershell -NoProfile -Command "Get-AppxPackage MathLang.Editor | Remove-AppxPackage"
if errorlevel 1 (
  echo   [失败] 没卸掉（可能应用还开着，或它本来就没装）。
  pause
  exit /b 1
)
rem ★ 2026-10-28：**桌面快捷方式是我们自己建的**（MSIX 不允许安装包建），
rem   Remove-AppxPackage 不会动它 ⇒ 必须在这里删，否则会留一张白纸图标。
del /q "%USERPROFILE%\Desktop\数语引擎.lnk" 2>nul
del /q "%APPDATA%\Microsoft\Windows\Start Menu\Programs\数语引擎.lnk" 2>nul
echo   已卸载，桌面与开始菜单里我们建的那个图标已删掉。
echo.
set /p PURGE=要顺带删掉设置、暂存与图标（%USERPROFILE%\mathlang）吗？保留可重装接着用 [y/N]: 
if /i "%PURGE%"=="y" (
  rmdir /s /q "%USERPROFILE%\mathlang"
  if exist "%APPDATA%\mathlang" rmdir /s /q "%APPDATA%\mathlang"
  echo   已删除。
) else (
  echo   已保留：%USERPROFILE%\mathlang（重装后设置自动接着用）
)
echo.
echo 完成。你保存的 .md 文档不受影响。
pause
"@
[System.IO.File]::WriteAllText((Join-Path $stage '双击我卸载数语引擎.cmd'), ($uninstallCmd -replace "`r?`n", "`r`n"), [System.Text.Encoding]::GetEncoding(936))

$readme = @"
数语引擎 $Version · Windows 64 位

一、安装（只有一步）
  双击「双击我安装数语引擎.cmd」。
  · 会弹一次管理员授权（信任本软件的自签证书）→ 点「是」
  · 然后自动安装、自动打开，桌面上会出现「数语引擎」图标
  以后从桌面图标打开即可。

二、卸载
  双击「双击我卸载数语引擎.cmd」，按提示走即可（会问要不要顺带清掉设置与暂存）。

三、你的数据在哪
  设置与「本地暂存」在 %USERPROFILE%\mathlang\（= C:\Users\<你>\mathlang\）。
  ★ 它**不在安装包里面** ⇒ 卸载本身**不会**删它；卸载脚本会另外问你要不要删（默认保留）。
  ★ 1.2.3 及更早的版本把数据放在包内（%APPDATA%\mathlang 会被系统虚拟化进包），
    那一份**会**随卸载消失 —— 1.2.4 起已自动迁移到上面那个路径。
  你保存的 .md 文档在任何情况下都不受影响。

四、为什么需要"信任证书"（只此一次）
  本版用**自签证书**签名。MSIX 的安装由系统校验**证书是否受信**，
  所以第一次要点一次管理员授权把证书放进「受信任人」。
  ★ 完成这一步之后：双击 .msix / 从开始菜单打开，**都不会再弹 SmartScreen**
    （本机 2026-10-19 与 2026-10-21 各实测过一次，装到 WindowsApps 里正常）。
  ★ 代价只有一个：这一步要 UAC。换成公共 CA 签名（开源项目可免费申请 SignPath）后，
    连 UAC 都不需要 —— 那一步是**未来的增强**，不是当前的阻塞。

五、手工卸载（万一脚本坏了）
  设置 → 应用 → 已安装的应用 → 搜「数语引擎」→ 卸载
  或 PowerShell：Get-AppxPackage MathLang.Editor | Remove-AppxPackage
"@
[System.IO.File]::WriteAllText((Join-Path $stage '安装说明.txt'), ($readme -replace "`r?`n", "`r`n"), (New-Object System.Text.UTF8Encoding($true)))

# 打成 zip（GitHub 发布用 ASCII 名；解压得到「数语引擎」文件夹）
$setupZip = Join-Path $root ("dist\mathlang-v$Version-win64-setup.zip")
if (Test-Path $setupZip) { Remove-Item $setupZip -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory((Join-Path $root 'dist\_setup'), $setupZip, [System.IO.Compression.CompressionLevel]::Optimal, $false)
Remove-Item (Join-Path $root 'dist\_setup') -Recurse -Force

# ★★ 2026-10-28（D1 的前置）：**再留一份 ASCII 文件名的 msix**。
#   GitHub 会直接丢弃非 ASCII 附件名（全局笔记「Flutter 开发实战经验」#60：中文名会被吞成 `-v1.0.0.apk`），
#   而 D1「检查更新」要按 asset 名找安装包 ⇒ 发布用的那一份必须叫 mathlang-<ver>-x64.msix。
$msixAscii = Join-Path $root ("dist\mathlang-v" + $Version + "-x64.msix")
Copy-Item $msix $msixAscii -Force

# ★★ P3'（2026-10-21）：`dist\安装包\` 原来是我**手工**建的一次性目录，脚本从不产出
#   ⇒ 里面的 msix 会一直是旧包（分发出去的就是旧代码）。现在由脚本每次重建它。
$bundle = Join-Path $root 'dist\安装包'
if (Test-Path $bundle) { Remove-Item $bundle -Recurse -Force }
New-Item -ItemType Directory -Path $bundle -Force | Out-Null
Copy-Item $msix (Join-Path $bundle '数语引擎.msix') -Force
Copy-Item (Join-Path $signing '数语引擎-自签证书.cer') (Join-Path $bundle '证书-数语引擎.cer') -Force
Add-Type -AssemblyName System.IO.Compression.FileSystem
$tmpBundle = Join-Path $root 'dist\_bundle'
if (Test-Path $tmpBundle) { Remove-Item $tmpBundle -Recurse -Force }
[System.IO.Compression.ZipFile]::ExtractToDirectory($setupZip, $tmpBundle)
Copy-Item (Join-Path $tmpBundle '数语引擎\双击我安装数语引擎.cmd') (Join-Path $bundle '安装数语引擎.cmd') -Force
Copy-Item (Join-Path $tmpBundle '数语引擎\安装说明.txt') (Join-Path $bundle '安装说明.txt') -Force
Remove-Item $tmpBundle -Recurse -Force

if (-not $KeepStage) { Remove-Item $stageRoot -Recurse -Force }
$mb = [math]::Round((Get-Item $msix).Length / 1MB, 1)
$zipMb = [math]::Round((Get-Item $setupZip).Length / 1MB, 1)
Write-Host ''
Write-Host "√ MSIX:   $msix  (${mb} MB)" -ForegroundColor Green
Write-Host "√ 安装包: $setupZip  (${zipMb} MB)" -ForegroundColor Green
Write-Host "   Identity=$identity  Version=$appxVersion  Publisher=$publisher" -ForegroundColor DarkGray
Write-Host "   解压后：数语引擎\双击我安装数语引擎.cmd（一键装完并自动打开）" -ForegroundColor DarkGray