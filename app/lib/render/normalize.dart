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
import 'smart_delete.dart' show structureUnits, StructureUnit;
import 'visible_atoms.dart';

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

    final List<({int from, int to, String repl})> edits =
        <({int from, int to, String repl})>[];

    // ① 全空结构：整段删
    for (final StructureUnit u in structureUnits(t)) {
      if (u.allEmpty) edits.add((from: u.start, to: u.end, repl: ''));
    }

    // ② 单原子脚本参数：去掉花括号（`x^{2}` → `x^2`）
    //    只对 `^`/`_` 的参数做 —— 与规格给的例子一致，也避开"分式参数去括号"这种会改变位点形状的情况
    for (final SlotSpan s in t.slots) {
      if (s.path.isEmpty) continue;
      final String cmd = s.path.last.command;
      if (cmd != '^' && cmd != '_') continue;
      if (s.start <= 0 || s.end >= cur.length) continue;
      if (cur[s.start - 1] != '{' || cur[s.end] != '}') continue;
      final String inner = cur.substring(s.start, s.end);
      if (lexVisibleAtoms(inner).length != 1) continue; // ★ 多原子绝不去括号
      edits.add((from: s.start - 1, to: s.end + 1, repl: inner));
    }

    if (edits.isEmpty) break;

    // 去掉互相重叠的：**外层优先**（嵌套的空结构只删最外层就够）
    edits.sort((({int from, int to, String repl}) a,
            ({int from, int to, String repl}) b) =>
        a.from != b.from ? a.from.compareTo(b.from) : b.to.compareTo(a.to));
    final List<({int from, int to, String repl})> kept =
        <({int from, int to, String repl})>[];
    for (final ({int from, int to, String repl}) e in edits) {
      if (kept.isNotEmpty && e.from < kept.last.to) continue;
      kept.add(e);
    }

    // ★ 从右往左应用，并**精确映射光标**（不得乱跳）
    for (final ({int from, int to, String repl}) e in kept.reversed) {
      if (caret >= e.to) {
        caret += e.repl.length - (e.to - e.from);
      } else if (caret > e.from) {
        caret = e.from + (caret - e.from).clamp(0, e.repl.length);
      }
      cur = cur.substring(0, e.from) + e.repl + cur.substring(e.to);
    }
    caret = caret.clamp(0, cur.length);
    total += kept.length;
  }
  return NormalizeResult(cur, caret, total);
}
