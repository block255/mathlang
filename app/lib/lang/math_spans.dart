// 数语引擎 · **数学段扫描**（纯 Dart，S4-b②）
//
// 为什么需要：诊断清单要说"**编辑器替你补了哪几处 `$…$`**"，而不只是"补了几处"。
// 这个扫描器只做一件事：把源码里所有**成对的定界符**找出来（行内 `$…$` / 行间 `$$…$$`），
// 用于把"刚刚写进去的那一段"切成可以点、可以高亮的区间。
//
// 三条约定：
//   ① **不解析 tex**：只认定界符，成对才产出；落单的 `$` 一律跳过（那种情况有别的守卫盯着）；
//   ② `\$`（转义）不算定界符；行间 `$$` 优先于行内 `$`（同一位置先试两个）；
//   ③ 扫描是**线性**的，长文档也没问题（不含任何递归/回溯）。

import '../core/block.dart';

/// 一段数学区间的**绝对偏移**（`[start, end)` 含定界符本体）
class MathSpan {
  const MathSpan({
    required this.start,
    required this.end,
    required this.tex,
    required this.display,
  });

  /// 开头定界符的起点
  final int start;

  /// 收尾定界符之后的位置
  final int end;

  /// 定界符**之间**的源码
  final String tex;

  /// 行间（`$$…$$`）还是行内（`$…$`）
  final bool display;

  int get length => end - start;

  /// 清单里显示用的一行摘要（太长就截断，正文里换行会被压扁）
  String summary({int max = 28}) {
    final String t = tex.replaceAll('\n', ' ').trim();
    return t.length <= max ? t : '${t.substring(0, max)}…';
  }

  @override
  String toString() =>
      'MathSpan[$start..$end)${display ? ' 行间' : ' 行内'} "$tex"';

  @override
  bool operator ==(Object other) =>
      other is MathSpan &&
      other.start == start &&
      other.end == end &&
      other.display == display &&
      other.tex == tex;

  @override
  int get hashCode => Object.hash(start, end, display, tex);
}

/// 扫描整份源码里的数学段（按出现顺序）
///
/// ★★★ 2026-10-24（批 17）：判据与**渲染投影 / 块模型统一**，只有两条：
///   1. **行间 `$$…$$`**：`$$` 必须在**行首**（前导 ≤3 空格），且收尾是"同行 `$$`"或
///      "后续某个**行首** `$$`"（与 `projection.displayFenceEnd` 逐条一致）；
///   2. **行内 `$…$`**：收尾**必须同一行**（行内公式不是跨行的东西；跨行配对必然是错位）。
///
/// 为什么必须这么改（实测事故）：以前 `$$` 只要"相邻两个 `$`"就当行间围栏 ⇒
///   文本里一处**行内 `$$`** 就能让全局配对错位，还会吐出**跨行吞掉整段正文**的段
///   ⇒ 后面每一行真实的 `$…$` 都不再被认出来（`smart_wrap` 于是把它们当裸源码再包一层
///   ⇒ `$$\to$$` ⇒ 页面上一整行 LaTeX 裸奔）。见 `test/lang/inline_double_dollar_test.dart`。
List<MathSpan> scanMathSpans(String source) {
  final List<MathSpan> out = <MathSpan>[];
  var i = 0;
  while (i < source.length) {
    if (source[i] != r'$' || _escaped(source, i)) {
      i++;
      continue;
    }
    // ① 行间块：`$$` 且**在行首**
    if (i + 1 < source.length &&
        source[i + 1] == r'$' &&
        _atLineStart(source, i)) {
      final int closeAt = _displayClose(source, i + 2);
      if (closeAt >= 0) {
        out.add(MathSpan(
          start: i,
          end: closeAt + 2,
          tex: source.substring(i + 2, closeAt),
          display: true,
        ));
        i = closeAt + 2;
        continue;
      }
      // 未闭合的 `$$`（`$$ x` 这种"空壳 + 后续内容"）⇒ 按**空的行内公式**解（§11.22）
    }
    // ② 行内段：收尾必须同一行
    final int closeAt = _inlineClose(source, i + 1);
    if (closeAt < 0) {
      // 落单的定界符：跳过这一个字符（不要整段放弃 —— 后面可能还有成对的）
      i += 1;
      continue;
    }
    out.add(MathSpan(
      start: i,
      end: closeAt + 1,
      tex: source.substring(i + 1, closeAt),
      display: false,
    ));
    i = closeAt + 1;
  }
  return out;
}

/// [i] 处的 `$` 是不是**行首**（允许最多 3 个前导空格，与块模型 `BlockMarkers.isMathFence`、
/// 投影 `displayFenceEnd` 完全一致）。
///
/// ★★ 2026-10-24（批 17）：`$$` **只有行首才算行间围栏**。这条判据以前只有
///   `projectInline` 与块模型在用，`scanMathSpans` **没看行首** ⇒ 行内 `$$` 被当行间段，
///   配对从此错位、还会吐出跨行吞正文的段（实测：导入 `20261021作业编辑` 的第一组乱码）。
bool _atLineStart(String s, int i) {
  var k = i - 1;
  var spaces = 0;
  while (k >= 0 && s[k] == ' ') {
    k--;
    spaces++;
    if (spaces > 3) return false;
  }
  return k < 0 || s[k] == '\n';
}

/// **不能被围栏模型 / 段模型解释的 `$$`** 落在哪些行（1-based，行号升序、不重复）。
///
/// 为什么要单列一条：真正的"行内 `$$`"**没有任何合法含义**（`$$` 只在其**行首**才是行间围栏），
/// 可它会被渲染成"一个**空的行内公式** + 后面的 tex 全掉到文字层" ⇒ 用户看到**源码裸奔**；
/// 若这段正好吞掉一个 `{`，KaTeX 还会报 `[公式不完整]`。
/// ⇒ 导入时的智能包裹一旦造出它，必须**可见**（《整体设计》原则 5：静默失败必须可见）。
///
/// ★★★ 2026-11-04 重写判据（P2 剩余部分）：旧的只有一句"这个 `$$` 不在行首就报"，
///   它量的是**位置**，不是**合法围栏** ⇒ 实测两头都错（扫盘里 53 份真实 md 得出）：
///   · **误报** —— `$$x=1$$`（R5 单行块；报的是**闭合**那一对）· `$a$$b$`（相邻两段，合法）
///     · `    $$…`（缩进 ≥4 格：块模型 `trimLeft()` 认它是围栏，span 扫描限 ≤3 空格不认）；
///   · **漏报** —— `$$(x)` / `$$ x` / `$$ $\hat{x}$…`（行首但**不是**围栏 ⇒ §11.22 的空行内公式）
///     · `$$\text{纹波}…`（内容写在开头行 ⇒ 整行不是围栏 ⇒ 整段 LaTeX 裸奔，真实文档撞过）。
///
/// 现行判据 = "**围栏模型 / 段模型解释得了它吗**"：
///   1. 它是某个**行间段**（display）的**开**或**闭**定界符 ⇒ 合法；
///   2. 它是**相邻两个行内段的接缝**（前段收尾 + 后段开头，`$a$$b$`）⇒ 合法；
///   3. 该行按块模型 [BlockMarkers.isMathFence] **是围栏**，且它是行首那对或行尾那对 ⇒ 合法
///      （只为兜"缩进 ≥4 格"这一处判据分歧：块模型不限缩进，span 扫描限 3）；
///   4. 其余 ⇒ **报**。
List<int> inlineDoubleDollarLines(String source) {
  final List<MathSpan> spans = scanMathSpans(source);
  final List<int> lines = <int>[];
  var lineNo = 1;
  for (var i = 0; i + 1 < source.length; i++) {
    if (source[i] == '\n') {
      lineNo++;
      continue;
    }
    if (source[i] != r'$' || source[i + 1] != r'$' || _escaped(source, i)) continue;
    if (_ddExplainedByModel(source, spans, i)) continue;
    if (lines.isEmpty || lines.last != lineNo) lines.add(lineNo);
  }
  return lines;
}

/// 下标 [i] 处这个 `$$` 能不能被**围栏模型 / 段模型**解释（判据见 [inlineDoubleDollarLines]）
bool _ddExplainedByModel(String source, List<MathSpan> spans, int i) {
  final int after = i + 2;
  var seamEnd = false; // 前一段在这里收尾
  var seamStart = false; // 后一段在这里开头
  for (final MathSpan s in spans) {
    if (s.display && (s.start == i || s.end == after)) return true; // 围栏的开/闭
    if (!s.display && s.end == i + 1) seamEnd = true;
    if (!s.display && s.start == i + 1) seamStart = true;
  }
  if (seamEnd && seamStart) return true; // `$a$$b$`：合法相邻
  final int ls = source.lastIndexOf('\n', i) + 1;
  final int nl = source.indexOf('\n', after);
  final String line = source.substring(ls, nl < 0 ? source.length : nl);
  if (BlockMarkers.isMathFence(line)) {
    final String t = line.trimLeft();
    final int lead = line.length - t.length;
    if (i == ls + lead + t.indexOf(r'$$') || i == ls + lead + t.lastIndexOf(r'$$')) {
      return true; // 行首/行尾那一对 + 整行是围栏（含 ≥4 格缩进）
    }
  }
  return false;
}

/// `i` 下标处的字符是不是被反斜杠转义（`\$`）
bool _escaped(String s, int i) {
  var k = i - 1;
  var n = 0;
  while (k >= 0 && s[k] == r'\') {
    n++;
    k--;
  }
  return n.isOdd;
}

/// **行内**收尾：从 [from] 起找同一行里第一个未被转义的 `$`。
///
/// ★★ 2026-10-24（批 17）：**不许跨行**（碰到 `\n` 就放弃）—— 行内公式不是跨行的东西，
///   跨行配对必然是错位（改前会吐出一个**吞掉两行正文**的段，直接把后面每行的 `$…$` 带偏）。
/// ★ 也不再"遇到 `$$` 就放弃"：`$a$$b$` 里第一个 `$` 就是 a 的收尾，第二个是 b 的开头
///   ⇒ 正常成两段（改前这里会**一个段都认不出来**）。
int _inlineClose(String s, int from) {
  for (var i = from; i < s.length; i++) {
    if (s[i] == '\n') return -1;
    if (s[i] == r'$' && !_escaped(s, i)) return i;
  }
  return -1;
}

/// **行间**收尾：从 [from] 起找 `$$` —— 要么与开关**同一行**，要么在**某个行首**。
///
/// 与 `projection.displayFenceEnd` 逐条一致（那里是渲染的唯一入口）：
///   · 同行闭合：`$$x=1$$`
///   · 跨行：首行 `$$` … 某个**行首** `$$`（`$$\n…\n$$`）
int _displayClose(String s, int from) {
  // ① 同一行内的 `$$`
  final int nl0 = s.indexOf('\n', from);
  final int sameEnd = nl0 < 0 ? s.length : nl0;
  for (var i = from; i + 1 < s.length && i < sameEnd; i++) {
    if (s[i] == r'$' && s[i + 1] == r'$' && !_escaped(s, i)) return i;
  }
  if (nl0 < 0) return -1;
  // ② 后续行首的 `$$`
  var lineFrom = nl0 + 1;
  while (lineFrom <= s.length) {
    var m = lineFrom;
    var spaces = 0;
    while (m < s.length && s[m] == ' ') {
      m++;
      spaces++;
    }
    if (spaces <= 3 &&
        m + 1 < s.length &&
        s[m] == r'$' &&
        s[m + 1] == r'$' &&
        !_escaped(s, m)) {
      return m;
    }
    final int nl = s.indexOf('\n', lineFrom);
    if (nl < 0) return -1;
    lineFrom = nl + 1;
  }
  return -1;
}
