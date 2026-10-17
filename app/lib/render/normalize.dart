// 数语引擎 · normalize（S3-5）
//
// 规格：notes/design/位点与结构导航.md §七
//   **提交点**（**只在**这些时刻跑，绝不逐击键）：失焦 · 光标离开该数学段 · 粘贴完成 · 明确动作
//   ① **空结构回收**：全空的结构单元（`\frac{}{}`、`^{}`）→ 删掉整个单元（与 §4.3 一致）
//   ② **多余花括号**：**只在"去掉括号后仍是单原子"时**去
//        `x^{2}` → `x^2` ✅ ；`x^{2n}` **不动** ❌（★ 这条最容易写错）
//   ③ 未闭合告警 → 走「问题清单」，本文件不管（那需要 UI）
//   ★ **normalize 不得让光标乱跳**：删除后光标落到"最近的前一个位点"（这里用精确的偏移映射）
//
// **纯 Dart。**

import 'caret_sites.dart';
import 'leaf_pairing.dart' show kAlwaysStackedOps, kDisplayStackedOps;
import 'smart_delete.dart' show structureUnits, StructureUnit;
import 'visible_atoms.dart';

/// `pos` 之后（跳空格）紧跟的是不是另一个 `^` / `_` 脚本
bool _hasAnotherScriptAfter(String tex, int pos) {
  var i = pos;
  while (i < tex.length && tex[i] == ' ') {
    i++;
  }
  return i < tex.length && (tex[i] == '^' || tex[i] == '_');
}

/// `pos` 处的 `^`/`_` 的**基座**是不是"堆叠上下限的算子"（`\sum` / `\prod` / `\lim` …）
///
/// ★ 这些算子的上下限在显示时是**堆叠**的，"n 之后 / 整个上标之后"本来是两个位点；
///   一旦去花括号，两者会**合并成同一偏移**（探针实测）⇒ 所以一律不拆。
bool _baseIsStackedOp(String tex, int pos) {
  var i = pos;
  while (i >= 0 && tex[i] == ' ') {
    i--;
  }
  if (i < 0) return false;
  if (tex[i] == '}') return false; // 基座是组 ⇒ 不按算子判（相邻那种已由 (b) 挡住）
  if (!_isNameChar(tex[i])) return false; // 普通单字符基座
  var j = i;
  while (j >= 0 && _isNameChar(tex[j])) {
    j--;
  }
  if (j < 0 || tex[j] != '\\') return false;
  final String name = tex.substring(j + 1, i + 1);
  return kAlwaysStackedOps.contains(name) || kDisplayStackedOps.contains(name);
}

bool _isNameChar(String ch) {
  final int c = ch.codeUnitAt(0);
  return (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
}

/// normalize 结果：新 tex + **映射后的光标偏移**
class NormalizeResult {
  const NormalizeResult(this.tex, this.caret, this.changes);

  final String tex;
  final int caret;

  /// 做了几处回收（0 = 没变）
  final int changes;

  bool get changed => changes > 0;

  @override
  String toString() => changed
      ? 'Normalize($changes 处：$tex @$caret)'
      : 'Normalize(无变化)';
}

/// 对**一个数学段的 tex** 跑 normalize（幂等：反复调用第二次无变化）。
NormalizeResult normalizeTex(String tex, int caretRel) {
  var cur = tex;
  var caret = caretRel.clamp(0, tex.length);
  var total = 0;

  for (var round = 0; round < 8; round++) {
    final CaretSiteTable t = buildCaretSites(cur);
    if (t.degraded) break; // 结构不可靠就别动（§4.4 同样的克制）

    // `lead` = 区域开头**被丢掉**的字符数（去花括号时 = 1，因为 `{` 不属于 repl）。
    // ★ 少了它，光标落在"内容开头"时会算成 +1 —— 2026-10-17 探针实测：
    //   `x^{2}` 的位点 3（`2` 之前）失焦后变成"`2` 之后"，光标右移一格；
    //   `\sum_{i=1}^{n}` 同理（"n 之前"跳到"n 之后"）。
    final List<({int from, int to, String repl, int lead})> edits =
        <({int from, int to, String repl, int lead})>[];

    // ① 全空结构：整段删
    for (final StructureUnit u in structureUnits(t)) {
      if (u.allEmpty) edits.add((from: u.start, to: u.end, repl: '', lead: 0));
    }

    // ② 单原子脚本参数：去掉花括号（`x^{2}` → `x^2`）
    //    ★ 2026-10-17 **收窄**（用户拍板）：只在"**拆了不会合并位点**"的最简单情形下拆。
    //      去花括号会把"两个不同位点"并成同一偏移（探针实测：`\sum_{i=1}^{n}` 的
    //      "n 之后"与"整个上标之后"、`x^{2}_{1}` 的"上标之后"与"下标之前"）——
    //      合并后只能画一行，用户就会觉得"某处点不到"。三种情况**一律不拆**：
    //        (a) 后面紧跟另一个脚本（`x^{2}_{1}` 的上标）
    //        (b) 前面紧挨着一个 `}`（基座已有脚本 / 算子已带一层上下限）
    //        (c) 基座是**堆叠上下限的算子**（`\sum`/`\prod`/`\lim` …）
    for (final SlotSpan s in t.slots) {
      if (s.path.isEmpty) continue;
      final String cmd = s.path.last.command;
      if (cmd != '^' && cmd != '_') continue;
      if (s.start <= 0 || s.end >= cur.length) continue;
      if (cur[s.start - 1] != '{' || cur[s.end] != '}') continue;
      if (_hasAnotherScriptAfter(cur, s.end + 1)) continue; // (a)
      if (s.start >= 3 && cur[s.start - 3] == '}') continue; // (b)
      if (_baseIsStackedOp(cur, s.start - 2)) continue; // (c)
      final String inner = cur.substring(s.start, s.end);
      if (lexVisibleAtoms(inner).length != 1) continue; // ★ 多原子绝不去括号
      edits.add((from: s.start - 1, to: s.end + 1, repl: inner, lead: 1));
    }

    if (edits.isEmpty) break;

    // 去掉互相重叠的：**外层优先**（嵌套的空结构只删最外层就够）
    edits.sort((({int from, int to, String repl, int lead}) a,
            ({int from, int to, String repl, int lead}) b) =>
        a.from != b.from ? a.from.compareTo(b.from) : b.to.compareTo(a.to));
    final List<({int from, int to, String repl, int lead})> kept =
        <({int from, int to, String repl, int lead})>[];
    for (final ({int from, int to, String repl, int lead}) e in edits) {
      if (kept.isNotEmpty && e.from < kept.last.to) continue;
      kept.add(e);
    }

    // ★ 从右往左应用，并**精确映射光标**（不得乱跳）
    for (final ({int from, int to, String repl, int lead}) e in kept.reversed) {
      if (caret >= e.to) {
        caret += e.repl.length - (e.to - e.from);
      } else if (caret > e.from) {
        // ★ 减掉 `lead`：区域开头那些**被丢掉**的字符不该算进 repl 的偏移
        caret = e.from + (caret - e.from - e.lead).clamp(0, e.repl.length);
      }
      cur = cur.substring(0, e.from) + e.repl + cur.substring(e.to);
    }
    caret = caret.clamp(0, cur.length);
    total += kept.length;
  }
  return NormalizeResult(cur, caret, total);
}
