// 数语引擎 · **应用身份与版本**（2026-10-19，U1）
//
// ★ 为什么单独一个文件：设置页「关于」与「诊断信息」都要显示版本，
//   而 Dart **读不到 pubspec 的 version**（没有运行时 API）。
//   ⇒ 这里是**唯一来源**：改版本时两边一起改（`pubspec.yaml` 的 `version:` 与本文件）。
//   （以后若让构建脚本生成它，签名不变 —— 仍是这份 const。）

/// ★★ 2026-10-19（U2，用户问"这个 +1 是什么意思"）：
/// **版本名**与**构建号**分开放 —— 「关于」只显示版本名（1.0.0），
/// 「诊断信息」里才拼成 `1.0.0+1`（我定位问题时要看构建号）。
const String kAppVersionName = '1.0.0';

/// 构建号（Flutter 的 `version: 1.0.0+1` 里 `+` 后面那个）
const String kAppBuildNumber = '1';

/// 拼好的完整版本（与 `pubspec.yaml` 的 `version:` 逐字一致）
const String kAppVersion = '$kAppVersionName+$kAppBuildNumber';

/// 产品名（窗口标题也用它）
const String kAppName = '数语引擎';

/// 数学渲染引擎（排查问题时要知道是哪一版 KaTeX 移植）
const String kMathEngine = 'flutter_math_fork 0.7.4';
