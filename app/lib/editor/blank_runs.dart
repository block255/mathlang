// 数语引擎 · **真空段落**（连续空行）的纯函数（2026-10-18 晚，§11.46 真修）
//
// 为什么单开一个文件：它是"版面高度"的唯一判据，而**块模型看不到空行**
// （`BlockIndex.parse` 里 R1：多个连续空行 = 一个边界，**不产生空块**）——
// 所以"这里到底空了几行"只能从源码数。数错了就表现为：
//   · 连按 Enter 不长高（全被当成"段距"压成 11 px）；
//   · 光标落错行（一个槽覆盖多行时永远落第一行）。
// 纯 Dart，可单测（`test/editor/blank_run_test.dart`）。

/// 从 [from] 起（**必须是行首**）的连续**空行**，返回每个空行的**行首偏移**。
///
/// 空行 = 该行内容 `trim()` 后为空（一个只有空格的行也算空行）。
List<int> blankRunFrom(String buf, int from) {
  final List<int> out = <int>[];
  var o = from.clamp(0, buf.length);
  while (o <= buf.length) {
    final int nl = buf.indexOf('\n', o);
    final int end = nl < 0 ? buf.length : nl;
    if (buf.substring(o, end).trim().isNotEmpty) break;
    out.add(o);
    if (nl < 0) break;
    o = nl + 1;
  }
  return out;
}

/// 某个单元（它认领到 [acceptTo] 为止）**之后**那串空行的行首偏移。
///
/// [acceptTo] 一般是"单元最后一个可见字符之后那一格"；紧跟其后的 `\n` 是**这一行的换行**，
/// 跳过它才是第一个空行的行首。
List<int> blankRunAfter(String buf, int acceptTo) {
  var o = acceptTo.clamp(0, buf.length);
  if (o >= buf.length || buf[o] != '\n') return const <int>[];
  o++;
  if (o > buf.length) return const <int>[];
  return blankRunFrom(buf, o);
}

/// **块之间**的真空段落要多高：`n` 个连续空行里，第一个只是**段距**，其余每个占一整行。
///
/// `n <= 1 ⇒ 0`（一个空行就是 md 的段落边界，视觉上只是那点 `gap`）。
double extraBlankHeight(int n, {required double lineHeight}) =>
    n <= 1 ? 0.0 : (n - 1) * lineHeight;

/// **文首**空行要多高：前面没有"上一段"要分隔 ⇒ 每一个空行都占一整行。
double leadingBlankHeight(int n, {required double lineHeight}) =>
    n <= 0 ? 0.0 : n * lineHeight;
