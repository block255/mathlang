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
  // ★ 只数**真有行盒**的空行：`o == buf.length` 那个位置是"最后一个换行之后"，
  //   它没有行（`甲\n` 的第二个"行"在渲染上是文末那片空白，不是一行空行）。
  //   把它算进来会让"按一次 Enter 后的段距"被当成两行（用户实测的"高度不对"）。
  while (o < buf.length) {
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

/// 一段空行串里，**从第几个位置起才是真正的「行」**（有高度、能承接光标）。
///
/// ★★★ 2026-10-28（用户拍板：**段间距不承接字符**）：
///   · **文首 / 文末** ⇒ `0`：没有"下一段"来用掉段落分隔符 ⇒ 每个空行都是真行
///     （与 [leadingBlankHeight] / [trailingBlankHeight] 的 `n × 行高` 同一条口径）；
///   · **两段之间** ⇒ `1`：第一个空行是 **Markdown 的段落分隔符** —— 它零高度、
///     不是行、**不许落光标**（判据本体在 `core/paragraph_break.dart`）。
///
/// 为什么必须有这一条：`A⏎⏎B` 在缓冲区里是 3 行（"A" / "" / "B"），可版面上那个空行
/// 高度是 0（`extraBlankHeight(1) == 0`）—— **同一串字符，数据里是一行、版面里是零行**。
/// 之前为了让"每个偏移都有光标"成立，把它的光标硬塞进段距里（`doc_view` 的折线），
/// 于是出现了"段间距能当容器行"—— 那是**用实现迁就一条错的断言**。
int blankRowStart({required bool atDocStart, required bool atDocEnd}) =>
    (atDocStart || atDocEnd) ? 0 : 1;

/// **块之间**的真空段落要多高：`n` 个连续空行里，第一个只是**段距**，其余每个占一整行。
///
/// `n <= 1 ⇒ 0`（一个空行就是 md 的段落边界，视觉上只是那点 `gap`）。
double extraBlankHeight(int n, {required double lineHeight}) =>
    n <= 1 ? 0.0 : (n - 1) * lineHeight;

/// **文首**空行要多高：前面没有"上一段"要分隔 ⇒ 每一个空行都占一整行。
double leadingBlankHeight(int n, {required double lineHeight}) =>
    n <= 0 ? 0.0 : n * lineHeight;

/// **文末**空行要多高：**与文首同一条** —— 后面没有"下一段"要分隔，
/// 所以第一个空行也占一整行。
///
/// ★ 2026-10-27 改前用的是 `extraBlankHeight`（第一个空行只是段距、高度 0），
///   于是"文末按一次 Enter 屏幕不动、要补两个换行才看得见一行"，而退格只删一个 ⇒ 两边不 1:1。
///   文末与文首对称之后：**一个空行 = 一行 = 一个换行符**，字节与行一齐平。
double trailingBlankHeight(int n, {required double lineHeight}) =>
    n <= 0 ? 0.0 : n * lineHeight;
