// 数语引擎 · **删除区间**（纯 Dart，2026-11-03「围栏不参与选区」）
//
// 口径（讨论定稿，`notes/handover/20261102-选择边界与剪贴板.md` §3.3 / §7.3）：
//   **查剩余**：删完结构成立就照删；不成立才扩到最小单位（对象 / 层）。
//   **`$` 是零宽记账**：删可见字符，`$` 留下；内容空了再回收
//   （行间块只剩空白算空；行内只剩空白**不算**空）。
//
// 产出不是一个区间，而是「一次替换」：`(from, to, replacement)`。
// 跨段删除时 `$` 夹在中间、不能删，所以不是“删一段”，而是“把这段里的可见字符抹掉、
// 其余原样留下”——最终压成一次 `replace`（**一步撤销**）。

import 'env_table.dart';
import 'math_spans.dart';
import 'tex_structure.dart';

/// 一次删除的落盘方式：把 `[from, to)` 换成 [replacement]。
class DeletePlan {
  const DeletePlan({
    required this.from,
    required this.to,
    required this.replacement,
    required this.clipboardText,
  });

  final int from;
  final int to;
  final String replacement;

  /// 真正被删掉的**可见**内容（按 §七 编码：数学 run 包 `$`，文字原样）。
  /// 剪切用它当剪贴板文本——“删什么就复制什么”。
  final String clipboardText;

  bool get isEmpty => replacement.isEmpty && clipboardText.isEmpty;
}

/// 规划一次删除：`[from, to)` 是**可见选区**（可以反着给）。
DeletePlan planDelete(String doc, int from, int to) {
  final int lo = from <= to ? from : to;
  final int hi = from <= to ? to : from;
  var s = lo.clamp(0, doc.length);
  var e = hi.clamp(s, doc.length);
  if (e <= s) {
    return DeletePlan(from: s, to: e, replacement: '', clipboardText: '');
  }
  // 切在控制词中间 ⇒ 先扩到词边界（与复制同一判据；否则会把 `\begin` 切成半截）
  s = _snapCommandStart(doc, s);
  e = _snapCommandEnd(doc, e);
  if (e <= s) {
    return DeletePlan(from: s, to: e, replacement: '', clipboardText: '');
  }

  final List<MathSpan> spans = scanMathSpans(doc);
  final List<({int start, int end})> ranges = <({int start, int end})>[];
  final StringBuffer clip = StringBuffer();
  var cursor = s;

  for (final MathSpan sp in spans) {
    if (sp.end <= s || sp.start >= e) continue;
    final int pad = sp.display ? 2 : 1;
    final int cs = sp.start + pad;
    final int ce = sp.end - pad;

    // 段前的文字（可见字符，直接删）
    final int textEnd = e < sp.start ? e : sp.start;
    if (textEnd > cursor) {
      ranges.add((start: cursor, end: textEnd));
      clip.write(doc.substring(cursor, textEnd));
      cursor = textEnd;
    }

    // 数学段：只取**内容**交集；对象补齐在内容内做
    int ms = s > cs ? s : cs;
    int me = e < ce ? e : ce;
    if (ms < me) {
      // ★★ 2026-11-03（表批）：选区落在多行环境体内 ⇒
      //   · 覆盖**全部格** ⇒ 按整表删（连壳；交给通用路径，围栏按 §七 回收）；
      //   · 只覆盖**一部分** ⇒ 清格内容、`&` / `\\` 保留（一次替换 ⇒ 一步撤销）。
      //   单格不在此列（照旧删选中的那几个字符）。
      final EnvTable? tbl = envTableForRange(sp.tex, ms - cs, me - cs);
      if (tbl != null) {
        final CellRect? rect = cellsCovering(tbl, ms - cs, me - cs);
        if (rect != null) {
          if (coversAllCells(tbl, rect)) {
            ms = cs + tbl.beginStart;
            me = cs + tbl.endEnd;
          } else if (rect.r0 != rect.r1 || rect.c0 != rect.c1) {
            final CellClear c = cellClearPlan(tbl, sp.tex, rect)!;
            return DeletePlan(
              from: cs + c.from,
              to: cs + c.to,
              replacement: c.replacement,
              clipboardText: '\$${c.payload}\$',
            );
          }
        }
      }
      final ({int start, int end}) r = _planInSpan(doc, sp, ms, me);
      if (r.end > r.start) {
        final String cut = doc.substring(r.start, r.end);
        ranges.add((start: r.start, end: r.end));
        clip.write(r'$');
        clip.write(cut);
        clip.write(r'$');
      }
      // 内容删空（行间 trim / 行内 isEmpty）⇒ 连围栏一起回收
      final String rest = sp.tex.replaceRange(
        (r.start - cs).clamp(0, sp.tex.length),
        (r.end - cs).clamp(0, sp.tex.length),
        '',
      );
      final bool emptied = sp.display ? rest.trim().isEmpty : rest.isEmpty;
      if (emptied) {
        var b = sp.end;
        if (sp.display && b < doc.length && doc[b] == '\n') b += 1;
        ranges.add((start: sp.start, end: b));
      }
      final int adv = r.end > me ? r.end : me;
      if (adv > cursor) cursor = adv;
    }

    final int next = e < sp.end ? e : sp.end;
    if (next > cursor) cursor = next;
    if (cursor >= e) break;
  }
  if (cursor < e) {
    ranges.add((start: cursor, end: e));
    clip.write(doc.substring(cursor, e));
  }

  if (ranges.isEmpty) {
    return DeletePlan(from: s, to: s, replacement: '', clipboardText: '');
  }

  // 合并区间（对象的左右补齐可能让相邻区间重叠）
  ranges.sort((A, B) => A.start.compareTo(B.start));
  final List<({int start, int end})> merged = <({int start, int end})>[];
  for (final ({int start, int end}) r in ranges) {
    if (merged.isNotEmpty && r.start <= merged.last.end) {
      merged[merged.length - 1] = (
        start: merged.last.start,
        end: r.end > merged.last.end ? r.end : merged.last.end,
      );
    } else {
      merged.add(r);
    }
  }

  final int regionStart = merged.first.start;
  final int regionEnd = merged.last.end;
  final StringBuffer kept = StringBuffer();
  var p = regionStart;
  for (final ({int start, int end}) r in merged) {
    if (r.start > p) kept.write(doc.substring(p, r.start));
    if (r.end > p) p = r.end;
  }
  if (p < regionEnd) kept.write(doc.substring(p, regionEnd));

  final String after = doc.replaceRange(regionStart, regionEnd, kept.toString());
  // 最小差分 ⇒ 一次 replace（一步撤销）
  final int prefix = _commonPrefix(doc, after);
  final int suffix = _commonSuffix(doc, after, prefix);
  return DeletePlan(
    from: prefix,
    to: doc.length - suffix,
    replacement: after.substring(prefix, after.length - suffix),
    clipboardText: clip.toString(),
  );
}

/// 在一个数学段的**内容**里规划删除（对象补齐 / 结构修复都不得越出内容）。
({int start, int end}) _planInSpan(String doc, MathSpan sp, int s, int e) {
  if (!isCompleteFragment(sp.tex)) return (start: s, end: e); // 源本来就坏：不修
  final int pad = sp.display ? 2 : 1;
  final int cs = sp.start + pad;
  final int ce = sp.end - pad;
  for (var k = 0; k < 10; k++) {
    if (_spanRemainderComplete(doc, sp, s, e)) break;
    ({int start, int end})? r = _repairOnce(doc, s, e);
    if (r == null) {
      // 选区切掉了某个 `\begin{X}`（或切进它的名字）⇒ 环境不能留半截 ⇒ 扩到 `\end{X}`
      final int? endTok = _envEndForCutBegin(doc, sp, s, e);
      if (endTok == null) break;
      r = (start: s, end: endTok);
    }
    if (r.start < cs || r.end > ce) break; // 不许出内容（围栏不参与）
    s = r.start;
    e = r.end;
  }
  return (start: s, end: e);
}

/// 段内容删掉 `[s, e)` 后还完整吗？
bool _spanRemainderComplete(String doc, MathSpan sp, int s, int e) {
  final int pad = sp.display ? 2 : 1;
  final int cs = sp.start + pad;
  final String rest = sp.tex.replaceRange(
    (s - cs).clamp(0, sp.tex.length),
    (e - cs).clamp(0, sp.tex.length),
    '',
  );
  // 孤立的可选参数收尾（`\sqrt[` 被删掉）
  if (rest.trimLeft().startsWith(']')) return false;
  // 剩下内容的**开头**是一个缺参数的命令（`\frac{b}`）⇒ 也不成立
  if (_missingLeadingArgs(rest)) return false;
  return isCompleteFragment(rest);
}

/// `tex` 去掉前导空白后以"要参数的命令"开头、但紧跟的参数组不够 ⇒ true。
bool _missingLeadingArgs(String tex) {
  final String t = tex.trimLeft();
  final Match? m = RegExp(r'^\\([A-Za-z]+)').firstMatch(t);
  if (m == null) return false;
  final int need = requiredArgs(m.group(1)!);
  if (need == 0) return false;
  var i = m.end;
  var have = 0;
  while (i < t.length) {
    if (t[i] == ' ') {
      i++;
      continue;
    }
    if (t[i] == '[') {
      final int j = t.indexOf(']', i);
      if (j < 0) break;
      i = j + 1;
      continue;
    }
    if (t[i] == '{') {
      final int j = _matchBraceF(t, i);
      if (j < 0) break;
      have++;
      i = j + 1;
      continue;
    }
    break;
  }
  return have < need;
}

/// `brace` 处 `{` 的主人（紧挨在前的要参数命令）；没有 ⇒ null。
int? _ownerOfBrace(String doc, int brace) {
  final int cmd = _cmdEndingAt(doc, brace);
  if (cmd < 0) return null;
  return requiredArgs(_controlWordAt(doc, cmd)) > 0 ? cmd : null;
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
  // 左侧悬挂：未闭合的 `{` / `^` `_` / 缺参数的命令名
  if (s > 0) {
    var k = s - 1;
    while (k >= 0 && doc[k] == ' ') {
      k--;
    }
    if (k >= 0 && doc[k] == '{') {
      // `{` 的主人（要参数的命令）在选区左边 ⇒ 连命令一起删（整块走）
      final int? owner = _ownerOfBrace(doc, k);
      if (owner != null && owner < s) {
        return (start: owner, end: e);
      }
      final int close = _matchBraceF(doc, k);
      if (close >= 0 && close >= s && close < e) {
        return (start: s, end: close + 1);
      }
      if (close < 0) return (start: s, end: doc.length);
    }
    if (doc[s - 1] == '^' || doc[s - 1] == '_') {
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

/// 选区切掉了某个 `\begin{X}`（或切进它的名字）⇒ 找到它配对的 `\end{X}` 末尾。
///
/// 环境不能留半截：`\begin` 被删 ⇒ 必须连 `\end` 一起删（整块走）。
int? _envEndForCutBegin(String doc, MathSpan sp, int s, int e) {
  final int pad = sp.display ? 2 : 1;
  final int cs = sp.start + pad;
  final int ce = sp.end - pad;
  final RegExp rx = RegExp(r'\\(begin|end)\s*\{([A-Za-z*]+)\}');
  final List<({int at, int end, bool isBegin})> toks =
      <({int at, int end, bool isBegin})>[];
  for (final Match m in rx.allMatches(doc.substring(cs, ce))) {
    toks.add((
      at: cs + m.start,
      end: cs + m.end,
      isBegin: m.group(1) == 'begin',
    ));
  }
  for (var i = 0; i < toks.length; i++) {
    final ({int at, int end, bool isBegin}) t = toks[i];
    if (!t.isBegin || t.at < s || t.at >= e) continue;
    var depth = 0;
    for (var j = i; j < toks.length; j++) {
      if (toks[j].isBegin) {
        depth++;
      } else {
        depth--;
        if (depth == 0) return toks[j].end;
      }
    }
  }
  return null;
}

/// 切在 `\f|rac` 这种控制词中间 ⇒ 挪回词首（与复制同一判据）。
int _snapCommandStart(String doc, int i) {
  if (i <= 0 || i >= doc.length) return i;
  final int c = doc.codeUnitAt(i);
  if (!_isLetterCode(c)) return i;
  if (!_isLetterCode(doc.codeUnitAt(i - 1))) return i;
  var j = i;
  while (j > 0 && _isLetterCode(doc.codeUnitAt(j - 1))) {
    j--;
  }
  if (j > 0 && doc[j - 1] == r'\') j--;
  return j;
}

/// 切在 `\fr|ac` 这种控制词中间 ⇒ 挪到词尾之后。
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

bool _isLetterCode(int c) =>
    (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

int _commonPrefix(String a, String b) {
  final int n = a.length < b.length ? a.length : b.length;
  var i = 0;
  while (i < n && a.codeUnitAt(i) == b.codeUnitAt(i)) {
    i++;
  }
  return i;
}

int _commonSuffix(String a, String b, int prefix) {
  final int n = (a.length < b.length ? a.length : b.length) - prefix;
  var i = 0;
  while (i < n &&
      a.codeUnitAt(a.length - 1 - i) == b.codeUnitAt(b.length - 1 - i)) {
    i++;
  }
  return i;
}
