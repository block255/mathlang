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

/// 这个 `^` / `_` 脚本是不是**它所在容器的最后一项**（= 容器内容末尾）—— 批 6 · H4。
///
/// 判据（文本级，只认"**容器结束**"，**不认段末**）：
///   · 后面紧跟 `}` —— 关闭结构槽（`\frac{x^{3}}{…}` 的分子 / `\sqrt{x^{2}}` / `\frac{a}{x^{2}}`）
///   · 后面是 `\right` —— 透明定界符组结束（`\left(x^{2}\right)` / `\left|{x^{2}}\right|`）
///   · 后面是 `\\` / `&` / `\end{` —— 多行环境的一格结束
///
/// ★ 为什么段末不算：`$a=b^2$` 这种"整段以上标收尾"到处都有，而且段末的"对象之后"
///   落在**公式外**（`closeEnd`，文字层），与"指数尾"本来就是两个不同位置、
///   `→` 也不会把它们并成一格（"甲"方案会跳过 tex 末位点）⇒ 没有合并问题。
bool _isContainerTailScript(String tex, SlotSpan s) {
  var i = s.end;
  if (s.start > 0 && tex[s.start - 1] == '{') i++; // 跳过自己的 `}`
  if (i >= tex.length) return false;
  if (tex[i] == '}') return true; // 关结构槽
  final String rest = tex.substring(i);
  return rest.startsWith(r'\right') ||
      rest.startsWith(r'\\') ||
      rest.startsWith('&') ||
      rest.startsWith(r'\end{');
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
    //   ★★ 2026-10-18 例外：**多行环境**（`\begin{aligned}…\end{aligned}` / `cases` …）不回收。
    //      它的"空格子"是**模板本身的骨架**（用户从面板刚插进来时必然全空），
    //      按"全空结构"删掉就等于：**一失焦（提交点）就把刚插入的对齐推导吞成空壳**。
    //      实测（探针）：`normalizeTex(r'\begin{aligned}&=\\&=\end{aligned}')` 修复前返回 `""`。
    //   ★★★ 2026-10-20（T-A 实测 F8，用户拍板"乙"）：**光标还落在里面的空结构也不回收**。
    //      实测现场：空文档点面板「分式」⇒ `$\frac{}{}$`（11 字符，光标在第一个空槽里）⇒
    //      点一下搜索框（编辑器失焦 = 提交点）⇒ 只剩 `$$`（2 字符）——用户看到的是
    //      "**我刚插进去的模板凭空没了**"。
    //      口径：**只保住"光标所在的那一个"空结构**；别处的空壳照样回收（免得空壳越堆越多）。
    //      ★ 判据用**闭区间**（`u.start <= caret <= u.end`）：光标贴在结构末尾（按过 `→` 出槽）
    //        也算"还在它身上"，否则一按右箭头再点开别处还是会被吞掉。
    for (final StructureUnit u in structureUnits(t)) {
      if (!u.allEmpty) continue;
      if (caret >= u.start && caret <= u.end) continue;
      final String slice = tex.substring(
        u.start.clamp(0, tex.length),
        u.end.clamp(0, tex.length),
      );
      if (slice.contains(r'\begin{')) continue;
      edits.add((from: u.start, to: u.end, repl: '', lead: 0));
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
      // ★★★ 2026-10-24（批 6 · H4 真凶）：(d) **脚本是"结构槽的最后一项" ⇒ 绝不拆**。
      //
      // 用户给的目标序列（2026-10-24）：「依次按右箭头：3 左边 → 3 右边 → x³ 的右边（分子尾）→ 分母首」
      // —— 这四步在 `\frac{x^{3}}{…}` 里**本来就是**四个位点（9 / 10 / 11 / 13）。
      // 但失焦 normalize 把 `x^{3}` 拆成 `x^3`（下面 ②）⇒ **"指数尾"与"分子尾"并成同一个字节**
      // （`\frac{x^3}{…}` 的位点：8 / 9 / 11）⇒ 用户看到的就是"3 右边按一下就掉到分母"。
      // 判据与既有 (a)(b)(c) 同源：**拆了会合并位点 ⇒ 不拆**；这里限定在最要紧的一处 ——
      // 脚本后面紧跟 `}`（关外层槽）或 `\\` / `&` / `\end{`（环境格结束）。
      if (_isContainerTailScript(cur, s)) continue; // (d)
      final String inner = cur.substring(s.start, s.end);
      if (lexVisibleAtoms(inner).length != 1) continue; // ★ 多原子绝不去括号
      edits.add((from: s.start - 1, to: s.end + 1, repl: inner, lead: 1));
    }

    // ③ ★★★ 2026-10-24（批 6）：**结构槽尾的裸脚本参数补回花括号**（② 的反向）。
    //
    // 为什么需要它：② 在历史上已经把大量文档写成了 `\frac{x^3}{y}` 这种形态
    // （花括号一旦被拆，位点就永久并成一个字节）。只加 (d) 只能"不再继续拆"，
    // 老文档仍然缺"分子尾"这一站 ⇒ 只补最要紧的那一处（结构槽尾），其余形态一律不动。
    for (final SlotSpan s in t.slots) {
      if (s.path.isEmpty) continue;
      final String cmd = s.path.last.command;
      if (cmd != '^' && cmd != '_') continue;
      if (s.start <= 0 || s.end >= cur.length) continue;
      if (cur[s.start - 1] == '{') continue; // 已经带花括号（交给 (d) 保住）
      if (!_isContainerTailScript(cur, s)) continue;
      final String inner = cur.substring(s.start, s.end);
      if (inner.isEmpty) continue;
      if (lexVisibleAtoms(inner).length != 1) continue; // 只补单原子
      if (_hasAnotherScriptAfter(cur, s.end)) continue; // 连写脚本不动（`x^2_1`）
      edits.add((from: s.start, to: s.end, repl: '{$inner}', lead: 0));
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
