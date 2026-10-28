# 数语引擎 · 生成 app/lib/app_info.dart（版本号唯一来源 = pubspec.yaml）
#
# 为什么要有这一条（C2，2026-10-28）：
#   Dart **读不到** pubspec 的 version（没有运行时 API）⇒ 只能有一个 Dart 常量。
#   原来是手写常量，结果「关于」页一直停在 1.0.0（三个 tag 都没跟），比包版本慢两版多。
#   ⇒ 现在改成**构建时生成**：pubspec.yaml 的 version 是唯一来源，这个脚本把它写成
#      kAppVersionName / kAppBuildNumber，再拼成 kAppVersion。
#   生成结果**仍然提交进仓库**：保证不跑脚本时 flutter analyze / flutter test 也能过。
#   守卫 test/core/version_single_source_test.dart 会比对两者 —— 改了 pubspec 忘了生成就红。
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File scripts\gen_app_info.ps1
#   （build_exe.ps1 会自己调一次）

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$app = Join-Path $repo 'app'
$pubspecPath = Join-Path $app 'pubspec.yaml'
$outPath = Join-Path $app 'lib\app_info.dart'

$pubspec = Get-Content $pubspecPath -Raw -Encoding UTF8
if ($pubspec -notmatch '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+([0-9]+))?') {
  throw 'pubspec.yaml 里读不到 version（应为 version: x.y.z+n）'
}
$name = $Matches[1]
$build = if ($Matches[2]) { $Matches[2] } else { '0' }

$lines = @(
  '// 数语引擎 · 应用身份与版本（**生成物：不要手改**）',
  '//',
  '// 由 scripts\gen_app_info.ps1 从 app\pubspec.yaml 的 version 生成。',
  '// 唯一来源 = pubspec.yaml；改版本只改那一处，然后跑一次脚本（或跑 build_exe.ps1）。',
  '// 守卫：test\core\version_single_source_test.dart（两者不一致就红）。',
  '//',
  '// ★ 为什么必须有这个文件：Dart 读不到 pubspec 的 version（没有运行时 API），',
  '//   而「关于」页与「诊断信息」都要显示版本。',
  '',
  '/// 版本名（「关于」只显示这个，例如 1.1.2）',
  "const String kAppVersionName = '$name';",
  '',
  '/// 构建号（pubspec 的 version 里 + 后面那个；只有「诊断信息」看它）',
  "const String kAppBuildNumber = '$build';",
  '',
  '/// 拼好的完整版本（与 pubspec.yaml 的 version 逐字一致）',
  "const String kAppVersion = '`$kAppVersionName+`$kAppBuildNumber';",
  '',
  '/// 产品名（窗口标题也用它）',
  "const String kAppName = '数语引擎';",
  '',
  '/// 数学渲染引擎（排查问题时要知道是哪一版 KaTeX 移植）',
  "const String kMathEngine = 'flutter_math_fork 0.7.4';",
  ''
)
$text = ($lines -join "`r`n")

# ★ 必须**不带 BOM**（Windows PowerShell 5.1 的 Set-Content -Encoding UTF8 会带 BOM，
#   而 Dart 源码带 BOM 在某些工具链里会出问题）⇒ 用 .NET 显式写 UTF-8 无 BOM。
[IO.File]::WriteAllText($outPath, $text, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "   [版本] app_info.dart = $name+$build（来自 pubspec.yaml）" -ForegroundColor DarkGray
