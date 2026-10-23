// 数语引擎 · **剪贴板切片**（纯 Dart，2026-10-23 公测反馈 A1/A2）
//
// 一个选区要进剪贴板之前，先把它变成「**自洽片段**」—— 也就是"能单独渲染的完整源码"。
//
// 三条边界规则（顺序执行，见 `notes\design\剪贴板与跨语境粘贴.md` §二）：
//   ① **段级配平**：两端都在**同一个**数学段内部 ⇒ 补一对 `$…$`；
//      只有一端在段内 ⇒ 把那一端**扩到段边界**（`$` / `$$`）。
//   ② **括号配平**：片段里 `{}` 不平衡（拖选常切在 `\frac{` 中间）⇒ 向外扩到平衡。
//   ③ **控制词吸附**：边界落在 `\frac` / `\text` 这类**控制词中间** ⇒ 扩到词首 / 词尾。
//
// 为什么（平权口径）：`$` 是**渲染提示**，不是语义墙（《编辑地基与手感》§7.1）。
// 片段离开公式时**补**、进入公式时**剥**（粘贴侧见 `paste_context.dart`）——
// 于是剪贴板里永远是"完整源码"，贴到别处（含记事本 / DeepSeek）也永远能用。
//
// ★ 实测背景（2026-10-21 用户报）：复制行内公式里的一个分式，得到的是
//   `\frac{x^3}{\lvert\sin x\rvert^3}$` —— **缺开头 `$`、多结尾 `$`**（裸 substring 的必然结果）。

import 'math_spans.dart';

/// 一次复制/剪切要用的结果。
///
/// `[start, end)` 是**源区间**（剪切就删它）；[text] 是真正进剪贴板的文本。
/// 两者可能不一致：when [wrapped] 为真，[text] 是"片段 + 一对补出来的 `$`"，而源区间不变。
class ClipboardSlice {
  const ClipboardSlice({
    required this.start,
    required this.end,
    required this.text,
    this.wrapped = false,
  });

  /// 源区间起点（**剪切**要删的范围从这里算）
  final int start;

  /// 源区间终点（开区间）
  final int end;

  /// 进剪贴板的文本（自洽片段）
  final String text;

  /// 是不是替用户补了一对 `$…$`（状态栏 / 测试用）
  final bool wrapped;

  bool get isEmpty => text.isEmpty;

  @override
  String toString() =>
      'ClipboardSlice[$start,$end)${wrapped ? ' 补定界符' : ''} "$text"';
}

/// 把选区 `[selStart, selEnd)` 变成自洽片段。区间可以反着给（`selStart > selEnd` 也行）。
ClipboardSlice clipboardSlice(String doc, int selStart, int selEnd) {
  final int lo = selStart <= selEnd ? selStart : selEnd;
  final int hi = selStart <= selEnd ? selEnd : selStart;
  var s = lo.clamp(0, doc.length);
  var e = hi.clamp(0, doc.length);
  if (e <= s) {
    return ClipboardSlice(start: s, end: e, text: '');
  }

  // ③ 先做控制词吸附（吸附可能把区间吃进别的地方，所以要**在下判断之前**做）
  s = _snapCommandStart(doc, s);
  e = _snapCommandEnd(doc, e);
  if (e <= s) {
    return ClipboardSlice(start: s, end: e, text: '');
  }

  final List<MathSpan> spans = scanMathSpans(doc);
  final MathSpan? a = _spanStrictlyInside(spans, s);
  final MathSpan? b = _spanStrictlyInside(spans, e);

  // ① 两端都在**同一个**数学段内部 ⇒ 片段自己包一对定界符
  //    ★ 片段不是"一段排版"⇒ 一律按**行内** `$…$`（《剪贴板与跨语境粘贴》§五 决定 1）
  if (a != null && identical(a, b)) {
    // 选区把定界符自己切进来了（拖选起点/终点落在 `$` 上）⇒ 只能扩到整段，
    // 否则会包出 `$$$` 这种无意义的东西。
    if (doc.substring(s, e).contains(r'$')) {
      return ClipboardSlice(start: a.start, end: a.end, text: doc.substring(a.start, a.end));
    }
    final ({int start, int end}) fix = _completeWithin(doc, s, e, a);
    s = fix.start;
    e = fix.end;
    final String frag = doc.substring(s, e);
    return ClipboardSlice(
      start: s,
      end: e,
      text: '\$$frag\$',
      wrapped: true,
    );
  }

  // ① 只有一端在段内 ⇒ 那一端扩到段边界（这样 `$` 才成对）
  final MathSpan? sa = _spanStrictlyInside(spans, s);
  if (sa != null) s = sa.start;
  final MathSpan? sb = _spanStrictlyInside(spans, e);
  if (sb != null) e = sb.end;

  // ② 扩完再兜一次括号配平（真实文档里 `{}` 也可能本来就不平衡，那就原样交出去）
  if (_braceDepth(doc.substring(s, e)) != 0) {
    final MathSpan? cover = _spanContaining(spans, s) ?? _spanContaining(spans, e);
    if (cover != null) {
      final ({int start, int end}) fix = _balanceWithin(doc, s, e, cover);
      s = fix.start;
      e = fix.end;
    }
  }

  return ClipboardSlice(start: s, end: e, text: doc.substring(s, e));
}

/// `pos` 严格落在某个段的**内部**（不含两端边界）
MathSpan? _spanStrictlyInside(List<MathSpan> spans, int pos) {
  for (final MathSpan sp in spans) {
    if (pos > sp.start && pos < sp.end) return sp;
  }
  return null;
}

/// `pos` 落在某个段的**闭区间**里（含两个定界符）
MathSpan? _spanContaining(List<MathSpan> spans, int pos) {
  for (final MathSpan sp in spans) {
    if (pos >= sp.start && pos <= sp.end) return sp;
  }
  return null;
}

bool _isLetterCode(int c) =>
    (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

/// 切在 `\f|rac` 这种**控制词中间**时，把起点挪回 `\`
int _snapCommandStart(String doc, int i) {
  if (i <= 0 || i >= doc.length) return i;
  final int c = doc.codeUnitAt(i);
  if (!_isLetterCode(c)) return i; // 右边不是字母 ⇒ 不在词中间
  if (!_isLetterCode(doc.codeUnitAt(i - 1))) return i; // 左边不是字母 ⇒ 恰在词首
  var j = i;
  while (j > 0 && _isLetterCode(doc.codeUnitAt(j - 1))) {
    j--;
  }
  if (j > 0 && doc[j - 1] == r'\') j--;
  return j;
}

/// 切在 `\fr|ac` 这种**控制词中间**时，把终点挪到词尾之后
int _snapCommandEnd(String doc, int i) {
  if (i <= 0 || i >= doc.length) return i;
  if (!_isLetterCode(doc.codeUnitAt(i))) return i;
  if (!_isLetterCode(doc.codeUnitAt(i - 1))) return i;
  var j = i;
  while (j < doc.length && _isLetterCode(doc.codeUnitAt(j))) {
    j++;
  }
  return j;
}

/// `{}` 的净深度（跳过 `\{` / `\}` 这种转义）
int _braceDepth(String s) {
  var d = 0;
  for (var i = 0; i < s.length; i++) {
    final String ch = s[i];
    if (i > 0 && s[i - 1] == r'\') continue;
    if (ch == '{') d++;
    if (ch == '}') d--;
  }
  return d;
}

/// 在 [sp] 这个数学段内部把 `[s, e)` 修成**自洽**的片段：
/// 先补结构参数（`\frac{a}` ⇒ `\frac{a}{b}`），再补括号配平。
({int start, int end}) _completeWithin(
    String doc, int s, int e, MathSpan sp) {
  final ({int start, int end}) head = _completeArgs(doc, s, e, sp.end);
  final ({int start, int end}) tail =
      _completeTrailingCommand(doc, head.start, head.end, sp.end);
  return _balanceWithin(doc, tail.start, tail.end, sp);
}

/// 片段**末尾**正好停在一个结构命令后面（`x+\sqrt`）⇒ 把它的参数组补进来。
({int start, int end}) _completeTrailingCommand(
    String doc, int s, int e, int limit) {
  final Match? m = RegExp(r'\\([A-Za-z]+)\s*$').firstMatch(doc.substring(s, e));
  if (m == null) return (start: s, end: e);
  final int need = _requiredArgs(m.group(1)!);
  if (need == 0) return (start: s, end: e);
  var have = 0;
  var i = e;
  var end = e;
  while (have < need && i < limit) {
    if (doc[i] == ' ') {
      i++;
      continue;
    }
    if (doc[i] == '[') {
      final int j = _matchPair(doc, i, '[', ']');
      if (j < 0) break;
      i = j + 1;
      continue;
    }
    if (doc[i] != '{') break;
    final int j = _matchPair(doc, i, '{', '}');
    if (j < 0) break;
    have++;
    end = j + 1;
    i = j + 1;
  }
  return (start: s, end: end);
}

/// 片段**正好以结构命令开头**时，把它缺的参数组补进来。
///
/// 实测动因：拖选很容易停在 `\frac{a}` 这种"参数只选到一半"的地方，
/// 那样的片段单独渲染必然报错（KaTeX: expected 2 args）。
/// 只认"必须显式参数组"的结构命令；其余命令原样。
int _requiredArgs(String name) {
  switch (name) {
    case 'frac':
    case 'dfrac':
    case 'tfrac':
    case 'binom':
    case 'dbinom':
    case 'tbinom':
    case 'overset':
    case 'underset':
    case 'stackrel':
      return 2;
    case 'sqrt':
    case 'overline':
    case 'underline':
    case 'hat':
    case 'bar':
    case 'vec':
    case 'dot':
    case 'ddot':
    case 'tilde':
    case 'widehat':
    case 'widetilde':
    case 'overrightarrow':
    case 'overleftarrow':
    case 'text':
    case 'textrm':
    case 'textbf':
    case 'mathrm':
    case 'mathbf':
    case 'mathcal':
    case 'mathbb':
    case 'operatorname':
      return 1;
  }
  return 0;
}

({int start, int end}) _completeArgs(String doc, int s, int e, int limit) {
  final Match? m = RegExp(r'^\\([A-Za-z]+)').firstMatch(doc.substring(s, e));
  if (m == null) return (start: s, end: e);
  final int need = _requiredArgs(m.group(1)!);
  if (need == 0) return (start: s, end: e);
  var have = 0;
  var i = s + m.end;
  var end = e;
  // ① 先数片段里**已经完整包含**的参数组（`\sqrt[3]{x}` 的 `[…]` 不算参数）
  while (i < end) {
    if (doc[i] == ' ') {
      i++;
      continue;
    }
    if (doc[i] == '[') {
      final int j = _matchPair(doc, i, '[', ']');
      if (j < 0) break;
      i = j + 1;
      continue;
    }
    if (doc[i] == '{') {
      final int j = _matchPair(doc, i, '{', '}');
      if (j < 0) break;
      have++;
      i = j + 1;
      continue;
    }
    break;
  }
  // ② 缺的组往后补（不许越过数学段）
  while (have < need && i < limit) {
    if (doc[i] == ' ') {
      i++;
      continue;
    }
    if (doc[i] != '{') break;
    final int j = _matchPair(doc, i, '{', '}');
    if (j < 0) break;
    have++;
    end = j + 1;
    i = j + 1;
  }
  return (start: s, end: end);
}

/// 从 `open` 处的左定界符找配对的右定界符（返回下标；找不到 -1）
int _matchPair(String doc, int open, String left, String right) {
  var depth = 0;
  for (var i = open; i < doc.length; i++) {
    if (i > 0 && doc[i - 1] == r'\') continue;
    if (doc[i] == left) depth++;
    if (doc[i] == right) {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

/// 在 [sp] 这个数学段内部把 `[s, e)` 扩到**括号平衡**；
/// 怎么扩都balance不了（原文本来就坏）⇒ 退到整段。
({int start, int end}) _balanceWithin(
    String doc, int s, int e, MathSpan sp) {
  var d = _braceDepth(doc.substring(s, e));
  var a = s;
  var b = e;
  while (d > 0 && b < sp.end) {
    final String ch = doc[b];
    b++;
    if (ch == '{') d++;
    if (ch == '}') d--;
  }
  while (d < 0 && a > sp.start) {
    a--;
    final String ch = doc[a];
    if (ch == '{') d++;
    if (ch == '}') d--;
  }
  if (d == 0) return (start: a, end: b);
  return (start: sp.start, end: sp.end);
}
