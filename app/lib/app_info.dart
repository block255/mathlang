// 数语引擎 · 应用身份与版本（**生成物：不要手改**）
//
// 由 scripts\gen_app_info.ps1 从 app\pubspec.yaml 的 version 生成。
// 唯一来源 = pubspec.yaml；改版本只改那一处，然后跑一次脚本（或跑 build_exe.ps1）。
// 守卫：test\core\version_single_source_test.dart（两者不一致就红）。
//
// ★ 为什么必须有这个文件：Dart 读不到 pubspec 的 version（没有运行时 API），
//   而「关于」页与「诊断信息」都要显示版本。

/// 版本名（「关于」只显示这个，例如 1.1.2）
const String kAppVersionName = '1.2.5';

/// 构建号（pubspec 的 version 里 + 后面那个；只有「诊断信息」看它）
const String kAppBuildNumber = '11';

/// 拼好的完整版本（与 pubspec.yaml 的 version 逐字一致）
const String kAppVersion = '$kAppVersionName+$kAppBuildNumber';

/// 产品名（窗口标题也用它）
const String kAppName = '数语引擎';

/// 数学渲染引擎（排查问题时要知道是哪一版 KaTeX 移植）
const String kMathEngine = 'flutter_math_fork 0.7.4';
