// 数语引擎 · **手打输入的过滤与落点校正**（2026-11-01，用户两条反馈）
//
// ## 一、反斜杠不许手打
//
// 原则 2：**用户永远不需要看数学编码**。而 `\` 是 LaTeX 命令的开头 —— 手打一个孤立的 `\`
// 会让整块公式立刻变成 `[公式不完整]`（用户实测："数学区段里打 `\` 会变成公式不完整"）。
// 进编码的入口是**符号面板 / 快捷键 / 模板**，不是键盘敲反斜杠。
//
// 只挡"**一次按键提交一个字符**"那种输入（`filterTypedText`）；粘贴 / IME 的多字符载荷
// 一律放行（那是用户从外面搬进来的内容，不是"敲编码"）。
//
// ## 二、打字落点不许落在行首标记里
//
// 实测：标题 `# 20261028作业`，光标停在最前面（`#` 之前）打一个 `w`
// ⇒ 缓冲区变成 `w# 20261028作业` ⇒ `#` 不在行首、不再是标题
// ⇒ **markdown 标记漏到屏幕上**（屏上显示 `w# 20261028作业`）。
// 违反原则 3：**结构由块类型表达，用户不写 Markdown 标记**。
//
// ⇒ 插入点落在标记区之内时，挪到**标记之后** —— 语义就是"在标题开头插字"。
// ★ 只挪**插入点**，不删标记：删标记是 `Delete` 的语义（`math_nav._visibleObjectDelete` ②：
//   "整块降级、绝不留下半个标记"），两者别混。

import '../core/block.dart';

/// 手打的一段文本要不要落进缓冲区？`null` = **丢掉**。
///
/// 现在只挡一种：**单个反斜杠**（= 一次按键敲了一个 `\`）。
String? filterTypedText(String text) {
  if (text == '\\') return null;
  return text;
}

/// 插入点若落在**行首标记区**里 ⇒ 返回标记之后那个偏移（"内容起点"）；
/// `null` = 落点没问题（不在标记里 / 这一行没有标记）。
///
/// 只对"**插入**"用；删除有自己的语义（删标记 = 整块降级）。
int? shiftInsertOutOfMarker(String source, int caret) {
  if (caret < 0 || caret > source.length) return null;
  final int ls = source.lastIndexOf('\n', caret == 0 ? 0 : caret - 1) + 1;
  final int nl = source.indexOf('\n', ls);
  final String line = source.substring(ls, nl < 0 ? source.length : nl);
  final int ml = BlockMarkers.markerLength(line);
  if (ml <= 0) return null;
  final int contentStart = ls + ml;
  return caret < contentStart ? contentStart : null;
}
