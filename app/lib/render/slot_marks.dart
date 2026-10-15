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

// ---------------------------------------------------------------------------
// ★★ 结构尾垫（2026-10-15，设计稿 §11.18）
// ---------------------------------------------------------------------------

/// **包裹型结构**的内容末尾塞一段"看不见但占宽"的横线，让它的**装饰跟着内容一起变长**。
///
/// 解决的是用户实测的那个"点不准"：
/// `\sqrt{2}` 的横线**不超出**被开方数 ⇒ 结构右缘 **==** 内容右缘 ⇒
/// "里面式子末尾"与"根号整体末尾"**落在同一根像素上**，光标也长得一模一样
/// （分式不同：分数线两头**超出**分子分母，所以它天然有"结构专属像素"）。
///
/// 加了尾垫之后：
/// · **视觉**：横线比内容长一截 ⇒ 两根像素分开（内容末尾在 `2` 右缘、结构末尾在横线末端）
/// · **点击**：尾垫之内（横线之下）→ 内容末尾；越过横线末端（公式盒右缘之外）→ 结构末尾
///
/// ★ **宽度必须用绝对单位**（`pt`）：`em` 会随字号缩小，小字号下会被
///   `leaf_boxes.kMinLeafWidth = 2.0` **过滤掉** ⇒ 叶盒数 ≠ 原子数 ⇒
///   `hitTestMathTex` **静默返回 null**（公式内点击全废）—— 这个坑踩过四次。
/// ★ 它**会多出一个叶盒** ⇒ `injection_map.atomsForHitTest` 必须为它补一个**合成原子**。
/// ★ 宽度取 `3pt`（≈ 4 px，2026-10-15 用户看图后定的 —— `6pt` 那版"多了一点点"）。
///   ⚠️ **下限**：不能再小于 `leaf_boxes.kMinLeafWidth = 2.0`，否则叶盒被过滤 ⇒
///   叶盒数 ≠ 原子数 ⇒ 命中**静默返回 null**（上面那条坑）。
const String kStructTailTex = r'\rule{3pt}{0pt}';

/// 需要尾垫的结构命令：**包裹型**（装饰宽度跟着内容走）。
///
/// 目前只给 `\sqrt`（用户实测报的那一例）。`\frac` **不在内** ——
/// 它的分数线本来就两头超出分子分母，天然有结构专属像素。
const Set<String> kTailCommands = <String>{'sqrt'};

/// 注入结果：注入后的 tex + **光标在注入后 tex 里的相对偏移**（供继续注入光标用）
class SlotMarkResult {
  const SlotMarkResult(this.tex, this.rel);
  final String tex;
  final int rel;
}

/// 一次注入（**从右往左**统一应用，见 [injectSlotMarks]）
class _Ins {
  const _Ins(this.at, this.text, {required this.shiftAt});

  /// 注入点（**原始 tex** 里的偏移）
  final int at;

  final String text;

  /// 光标**正好**落在注入点时怎么办：
  /// `true` = 右移（光标画在注入物**之后**；空槽占位用 —— 光标落在方框右侧）；
  /// `false` = 不动（光标画在注入物**之前**；尾垫用 —— 内容末尾的光标要贴在式子右缘）。
  final bool shiftAt;
}

/// 给 tex 里所有**空槽**注入可见占位；[caretRel] 落在哪个空槽里，它就用"当前槽"样式。
/// 另外给**包裹型结构**（`\sqrt`）的内容末尾注入**尾垫**（§11.18，见 [kStructTailTex]）。
///
/// ★★ **[caretRel] < 0（光标不在这一段里）→ 照样注入，只是没有"当前槽"高亮。**
///
/// 这一条 2026-10-15 改的，原因值得记下来：
/// 原先 `caretRel < 0` 是**直接原样返回、什么都不注入**，理由是
/// "注入会让叶盒数 ≠ 原子数 → `hitTestMathTex` 静默返回 null → 点不回公式里"。
/// **那个根因当天晚些时候就被根治了**（`3c2bf0c`：命中改用 `renderTex` +
/// `atomsForHitTest` + `renderToSourceOffset`，本文件自己的注释当时也写了
/// "真正的根治是让点击定位用同一份注入后的 tex"）—— **根治做完了，这条临时措施却留了下来**。
///
/// 留下的后果（用户实测抓出）：粘贴 `$\frac{}{}$` 之后光标停在
/// **闭合 `$` 之后那一格**，判定"不在这段里" → 不注入占位
/// → 空分数退化成 **3.4 × 10.3 px** 的细线（实测）→ 用户看到的是**"粘贴进去直接消失了"**。
/// 规格 §6.1 从来没有"只在光标处画占位"这条附加条件 —— 空槽**就该一直看得见**。
///
/// 注入**从右往左**做，前面的偏移不受影响；光标偏移按插入量右移补偿，
/// 所以调用方可以接着 `injectCursor(marks.tex, marks.rel)`。
SlotMarkResult injectSlotMarks(String tex, {required int caretRel}) {
  final CaretSiteTable t = buildCaretSites(tex);
  if (t.degraded) return SlotMarkResult(tex, caretRel);

  // 光标不在这一段（caretRel < 0）→ 没有"当前槽"，全部按普通空槽画
  final SlotSpan? cur = caretRel < 0 ? null : innermostSlotAt(t, caretRel);
  final List<_Ins> ins = <_Ins>[
    // ① 空槽占位
    for (final SlotSpan s in t.slots)
      if (s.isEmpty)
        _Ins(
          s.start,
          (cur != null && s.start == cur.start && s.end == cur.end)
              ? kCurrentSlotTex
              : kEmptySlotTex,
          shiftAt: true,
        ),
    // ② ★ 尾垫（§11.18）：插在**内容末尾**、花括号**之内** ⇒ 装饰跟着内容变长
    for (final SlotSpan s in t.slots)
      if (s.path.isNotEmpty &&
          s.path.last.argIndex == 0 &&
          kTailCommands.contains(s.path.last.command) &&
          !s.isEmpty)
        _Ins(s.end, kStructTailTex, shiftAt: false),
  ]..sort((_Ins a, _Ins b) => b.at.compareTo(a.at));

  String out = tex;
  int rel = caretRel;
  for (final _Ins e in ins) {
    out = out.substring(0, e.at) + e.text + out.substring(e.at);
    if (e.shiftAt ? rel >= e.at : rel > e.at) rel += e.text.length;
  }
  return SlotMarkResult(out, rel);
}

/// ★ 空公式的占位字形（2026-10-15，§6.1.1）。
///
/// `tex` 为空 / 全白时，公式本来渲染成**零尺寸** —— 既看不见也点不到。
/// 而 §4.6 决定"在公式内删到空 → **留空壳**"（有撤回、能接着重打），
/// 若空壳是零尺寸，它就成了一只**幽灵**（用户实测："按了没反应"，只能再按一次退格清掉）。
/// ⇒ **"留空壳"与"画出来"是一对，不能只做一半。** 观感上复用空槽那一套（同一个字形、同一档颜色）。
const String kEmptyFormulaTex = kEmptySlotTex;

/// ★ 一段数学的**渲染 tex** —— 注入链的**唯一入口**。
///
/// 抽成纯函数的目的（2026-10-15）：注入链原先散在两个 widget 里各写一遍
/// （`InlineMathText._mathSpan` 与 `DocView` 的行间公式分支），
/// 而"到底注了什么"只能靠猜 `Math` 内部的 ast —— 探针都难写。
/// 收成一个纯函数之后，注入结果**可以直接被单测断言**（不必真渲染）。
///
/// 顺序不能反：**先注空槽占位**（它给光标偏移做了补偿），**再注光标**。
String renderMathTex(String tex, {required int caretRel}) {
  // ★ 空公式也要画出来（§6.1.1）——它没有任何槽可注入，所以要单独兜一句
  if (tex.trim().isEmpty) {
    final String mark = caretRel < 0 ? kEmptyFormulaTex : kCurrentSlotTex;
    // 光标在里面时再补一根光标条（否则用户不知道自己停在哪儿）
    return caretRel < 0 ? mark : mark + kCursorTex;
  }
  final SlotMarkResult marks = injectSlotMarks(tex, caretRel: caretRel);
  // 光标不在这段里 → 只画空槽，不画光标（`marks.rel` 此时为负，不能喂给 injectCursor）
  if (caretRel < 0) return marks.tex;
  return injectCursor(marks.tex, marks.rel).tex;
}
