// 数语引擎 · **删除区间**（纯 Dart，2026-11-02「选择边界与剪贴板」批）
//
// 判据（讨论定稿，`notes/handover/20261102-选择边界与剪贴板.md` §3.3）：
//   **查剩余**——删完结构成立就照删；不成立才扩到最小单位。
//   与复制相反：复制查**片段**，删除查**剩下的**；删除**不套用**复制的右向补全。
//
// 做法：
//   1. **围栏归一**（删一半会留下半个 `$`）：端点落在段内 ⇒ 扩到段边界（与复制同一判据）；
//   2. 若接缝两侧的段**删之前就不完整**（源本来坏，如游离的 `$^{x}$`）⇒ 不替它修；
//   3. 逐次修接缝上"悬挂"的东西：右侧的 `^`/`_`、`]`、孤 `\end`；左侧未闭合的 `{`、
//      缺参数的命令。每次只扩到"刚够成立"，最多 10 轮。

import 'math_spans.dart';
import 'tex_structure.dart';

/// 删除 `[from, to)` 时**实际要删的区间**（已按"剩余成立"修过）。
({int start, int end}) planDeleteRange(String doc, int from, int to) {
  final int lo = from <= to ? from : to;
  final int hi = from <= to ? to : from;
  var s = lo.clamp(0, doc.length);
  var e = hi.clamp(s, doc.length);
  if (e <= s) return (start: s, end: e);

  final List<MathSpan> spans = scanMathSpans(doc);
  final MathSpan? sa = _inside(spans, s);
  final MathSpan? sb = _inside(spans, e);
  if (!(sa != null && identical(sa, sb))) {
    if (sa != null) s = sa.start;
    if (sb != null) e = sb.end;
  }

  // 源本来就坏 ⇒ 不替它修（否则每删一下都会把整段吃掉）
  if (!_wasComplete(doc, spans, s, e)) return (start: s, end: e);

  for (var k = 0; k < 10; k++) {
    if (_remainderComplete(doc, s, e)) break;
    final ({int start, int end})? r = _repairOnce(doc, s, e);
    if (r == null) break;
    s = r.start;
    e = r.end;
  }
  return (start: s, end: e);
}

/// 一段区间对应的剪贴板文本（**不扩**）：两端在同一段内 ⇒ 补一对 `$…$`。
///
/// 剪切用：删什么就复制什么（讨论定稿 §3.4），所以这里只做"包不包 `$`"，
/// 不再跑 [clipboardSlice] 的补全。
String clipboardTextForRange(String doc, int start, int end) {
  final int s = start.clamp(0, doc.length);
  final int e = end.clamp(s, doc.length);
  if (e <= s) return '';
  final List<MathSpan> spans = scanMathSpans(doc);
  final MathSpan? a = _inside(spans, s);
  final MathSpan? b = _inside(spans, e);
  if (a != null && identical(a, b)) {
    return '\$${doc.substring(s, e)}\$';
  }
  return doc.substring(s, e);
}

// ---------------------------------------------------------------------------
// 判据
// ---------------------------------------------------------------------------

/// 删除前：接缝两侧的段是完整的吗？（源本来坏 ⇒ 返回 false）
bool _wasComplete(String doc, List<MathSpan> spans, int s, int e) {
  final MathSpan? a = _contentSpanAt(spans, s);
  final MathSpan? b = _contentSpanAt(spans, e > 0 ? e - 1 : 0);
  if (a != null && !isCompleteFragment(a.tex)) return false;
  if (b != null && !identical(a, b) && !isCompleteFragment(b.tex)) return false;
  return true;
}

/// 删除后：接缝所在的那一段还完整吗？
bool _remainderComplete(String doc, int s, int e) {
  // 接缝左边正好是"要参数的命令名" ⇒ 参数被这次删除切掉了（`\frac{a}` 只剩一参）
  if (s > 0) {
    final int cmd = _cmdEndingAt(doc, s);
    if (cmd >= 0 && requiredArgs(_controlWordAt(doc, cmd)) > 0) return false;
  }
  final String after = doc.replaceRange(s, e, '');
  final List<MathSpan> spans = scanMathSpans(after);
  final MathSpan? sp = _contentSpanAt(spans, s.clamp(0, after.length));
  if (sp == null) return true;
  // 残留的"可选参数收尾"（`\sqrt[` 被删掉了）
  if (sp.tex.trimLeft().startsWith(']')) return false;
  return isCompleteFragment(sp.tex);
}

/// 修一次接缝；扩不动 ⇒ null。
({int start, int end})? _repairOnce(String doc, int s, int e) {
  // 右侧悬挂：脚本没有底 / 孤立的 `]` / 孤立的 `\end`
  if (e < doc.length) {
    final String c = doc[e];
    if (c == '^' || c == '_') {
      return (start: s, end: _scriptEnd(doc, e));
    }
    if (c == ']') {
      return (start: s, end: e + 1);
    }
    if (c == '}') {
      // 它的 `{` 在**被删的区间里**（或根本没有）⇒ 这个 `}` 成了孤儿 ⇒ 一起删
      final int open = _matchBraceB(doc, e);
      if (open < 0 || (open >= s && open < e)) {
        return (start: s, end: e + 1);
      }
    }
    if (_controlWordAt(doc, e) == 'end') {
      final int endTok = _endTokenEnd(doc, e);
      if (endTok > e) return (start: s, end: endTok);
    }
  }
  // 左侧悬挂：未闭合的 `{` / 缺参数的命令名
  if (s > 0) {
    var k = s - 1;
    while (k >= 0 && doc[k] == ' ') {
      k--;
    }
    if (k >= 0 && doc[k] == '{') {
      final int close = _matchBraceF(doc, k);
      if (close >= 0 && close >= s && close < e) {
        return (start: s, end: close + 1);
      }
      if (close < 0) return (start: s, end: doc.length);
    }
    // 接缝左边是 `^` / `_` ⇒ 它的参数被删掉了 ⇒ 连标记一起删（留 `a`，不留 `a^`）
    if (s > 0 && (doc[s - 1] == '^' || doc[s - 1] == '_')) {
      return (start: s - 1, end: e);
    }
    final int cmd = _cmdEndingAt(doc, s);
    if (cmd >= 0 && requiredArgs(_controlWordAt(doc, cmd)) > 0) {
      return (start: cmd, end: e);
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// 小工具
// ---------------------------------------------------------------------------

MathSpan? _inside(List<MathSpan> spans, int pos) {
  for (final MathSpan sp in spans) {
    if (pos > sp.start && pos < sp.end) return sp;
  }
  return null;
}

/// `pos` 是否落在某段的**内容**里（含两端）。
MathSpan? _contentSpanAt(List<MathSpan> spans, int pos) {
  for (final MathSpan sp in spans) {
    final int pad = sp.display ? 2 : 1;
    if (pos >= sp.start + pad && pos <= sp.end - pad) return sp;
  }
  return null;
}

int _scriptEnd(String doc, int i) {
  var j = i + 1;
  while (j < doc.length && doc[j] == ' ') {
    j++;
  }
  if (j >= doc.length) return j;
  if (doc[j] == '{') {
    final int c = _matchBraceF(doc, j);
    return c < 0 ? doc.length : c + 1;
  }
  if (doc[j] == r'\') return _skipControl(doc, j);
  return j + 1;
}

int _matchBraceF(String s, int open) {
  var d = 0;
  for (var i = open; i < s.length; i++) {
    if (s[i] == r'\') {
      i = _skipControl(s, i) - 1;
      continue;
    }
    if (s[i] == '{') d++;
    if (s[i] == '}') {
      d--;
      if (d == 0) return i;
    }
  }
  return -1;
}

/// 从 `close` 处的 `}` 往回找配对的 `{`；找不到 ⇒ -1。
int _matchBraceB(String s, int close) {
  var d = 0;
  for (var i = close; i >= 0; i--) {
    if (i > 0 && s[i - 1] == r'\') continue;
    if (s[i] == '}') d++;
    if (s[i] == '{') {
      d--;
      if (d == 0) return i;
    }
  }
  return -1;
}

int _skipControl(String s, int i) {
  if (i >= s.length || s[i] != r'\') return i + 1;
  var j = i + 1;
  if (j >= s.length) return j;
  if (!_isLetter(s[j])) return j + 1;
  while (j < s.length && _isLetter(s[j])) {
    j++;
  }
  return j;
}

String _controlWordAt(String s, int i) {
  if (i >= s.length || s[i] != r'\') return '';
  var j = i + 1;
  while (j < s.length && _isLetter(s[j])) {
    j++;
  }
  return s.substring(i + 1, j);
}

bool _isLetter(String c) {
  final int u = c.codeUnitAt(0);
  return (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A);
}

/// `end`（不含）之前紧挨着的命令的 `\` 下标；不是命令 ⇒ -1。
int _cmdEndingAt(String s, int end) {
  var j = end - 1;
  while (j >= 0 && s[j] == ' ') {
    j--;
  }
  if (j < 0 || !_isLetter(s[j])) return -1;
  while (j >= 0 && _isLetter(s[j])) {
    j--;
  }
  return (j >= 0 && s[j] == r'\') ? j : -1;
}

/// `i` 处的 `\end{…}` 之后的位置（不是 `\end` ⇒ -1）。
int _endTokenEnd(String s, int i) {
  var j = _skipControl(s, i);
  while (j < s.length && s[j] == ' ') {
    j++;
  }
  if (j >= s.length || s[j] != '{') return -1;
  final int c = _matchBraceF(s, j);
  return c < 0 ? -1 : c + 1;
}
