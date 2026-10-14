// 数语引擎 · 空槽可视化（S3-5）
//
// 规格：notes/design/位点与结构导航.md §6.1
//   空槽 → 虚线占位框（浅灰 `#B0BEC5`，宽 ≈ 一个字符）
//   当前槽 → 换成实线 + 淡蓝底（`#E3F2FD`，与光标同色系）
//   非空槽 → 不画
//
// ★ 与规格的差别（诚实记账）：规格自己指出"虚线框要**自绘**"（WidgetSpan / 覆盖层）。
//   本版先用**注入一条短横线**（`\rule`）达到同样的**功能**：让用户看得见"这里有个空槽"，
//   当前槽用光标蓝区分。真正的"1px 虚线框 + 淡蓝底"要自绘层，留给视觉规范一起做。
//   代价：占位线会占排版宽度 —— 这正是我们要的（空槽本来就该占位，用户才会去点/Tab）。
//
// ★★ 为什么占位用 `\square`（一个正常可见字形）而不是画一条 `\rule`：
//   点击定位的真正不变量是「**我们的可见原子数 == 引擎的叶盒数**」。
//   · `\square` → **1 个原子 + 1 个叶盒** ✓ 天然对齐
//   · `\rule`  → 词法上是**结构命令（0 原子）**，但引擎很可能照样给它一个盒 ✗ 反而危险
//   所以选"原子与盒一一对应"的那个。（`\textcolor` 的颜色名曾经虚增 9 个原子，
//   那条已在 `visible_atoms.kNonRenderedArgCount` 修掉，见 injection_invariant_test。）
//
// **纯 Dart。**

import 'caret_sites.dart';
import 'site_adjacency.dart';

/// 空槽占位（浅灰小方框）
const String kEmptySlotTex = r'\textcolor{#B0BEC5}{\square}';

/// 当前槽占位（光标蓝 —— 与 §6.2 的光标同色系）
const String kCurrentSlotTex = r'\textcolor{#1E88E5}{\square}';

/// 注入结果：注入后的 tex + **光标在注入后 tex 里的相对偏移**（供继续注入光标用）
class SlotMarkResult {
  const SlotMarkResult(this.tex, this.rel);
  final String tex;
  final int rel;
}

/// 给 tex 里所有**空槽**注入可见占位；[caretRel] 落在哪个空槽里，它就用"当前槽"样式。
///
/// ★★ **[caretRel] < 0（光标不在这个单元里）→ 原样返回，什么都不注入。**
/// 为什么（2026-10-14 用户实测抓出）：点击定位 `hitTestMathTex` 用的是**原始源码**的词法原子，
/// 而叶盒来自**注入后**的渲染树 —— 只要注入让渲染多出一个盒，
/// 「叶盒数 == 原子数」就不成立 → 它**静默返回 null** → **点不回这个公式里**。
/// 所以占位只在"光标所在的那一个单元"里画（与光标注入同一条规则）：
/// 光标一走，方框消失，渲染与源码重新一致，点击立刻恢复。
/// ⚠️ 真正的根治是让点击定位**用同一份注入后的 tex 并把偏移映射回原坐标**（见交接快照 §十二）。
///
/// 注入**从右往左**做，前面的偏移不受影响；光标偏移按插入量右移补偿，
/// 所以调用方可以接着 `injectCursor(marks.tex, marks.rel)`。
SlotMarkResult injectSlotMarks(String tex, {required int caretRel}) {
  if (caretRel < 0) return SlotMarkResult(tex, caretRel); // 见上面那条 ★★
  final CaretSiteTable t = buildCaretSites(tex);
  if (t.degraded) return SlotMarkResult(tex, caretRel);

  final SlotSpan? cur = innermostSlotAt(t, caretRel);
  final List<SlotSpan> empties = <SlotSpan>[
    for (final SlotSpan s in t.slots)
      if (s.isEmpty) s,
  ]..sort((SlotSpan a, SlotSpan b) => b.start.compareTo(a.start));

  String out = tex;
  int rel = caretRel;
  for (final SlotSpan s in empties) {
    final bool isCurrent = cur != null && s.start == cur.start && s.end == cur.end;
    final String mark = isCurrent ? kCurrentSlotTex : kEmptySlotTex;
    out = out.substring(0, s.start) + mark + out.substring(s.start);
    if (rel >= s.start) rel += mark.length;
  }
  return SlotMarkResult(out, rel);
}
