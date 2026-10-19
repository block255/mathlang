// 数语引擎 · **应用身份与版本**（2026-10-19，U1）
//
// ★ 为什么单独一个文件：设置页「关于」与「诊断信息」都要显示版本，
//   而 Dart **读不到 pubspec 的 version**（没有运行时 API）。
//   ⇒ 这里是**唯一来源**：改版本时两边一起改（`pubspec.yaml` 的 `version:` 与本文件）。
//   （以后若让构建脚本生成它，签名不变 —— 仍是这份 const。）

/// 与 `pubspec.yaml` 的 `version:` 保持一致
const String kAppVersion = '1.0.0+1';

/// 产品名（窗口标题也用它）
const String kAppName = '数语引擎';

/// 数学渲染引擎（排查问题时要知道是哪一版 KaTeX 移植）
const String kMathEngine = 'flutter_math_fork 0.7.4';
