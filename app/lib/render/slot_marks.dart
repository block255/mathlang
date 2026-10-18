// 数语引擎 · 空槽可视化（S3-5）
//
// 规格：notes/design/位点与结构导航.md §6.1
//   空槽 → 虚线占位框（1 px、浅灰 `#B0BEC5`、宽 ≥ 一个正文汉字）
//   当前槽 → 换成实线 + 淡蓝底（`#E3F2FD`，与光标同色系）
//   非空槽 → 不画
//
// ★★ 2026-10-16（④-1 / ④-2）：**占位从"看得见的灰方块"改成"看不见的垫子"** ——
//   垫子只占版面（字形 + 零高宽度垫），**框由自绘层画**（引擎画不出虚线）。
//   常量、四种做法的探针数据、以及"补 1 个合成原子"的账，全部写在 **`slot_pad.dart`**。
//   本文件 `export` 它 ⇒ 旧的引用名（`kEmptySlotTex` / `kCurrentSlotTex`）照旧可用。
//
// ★ 为什么要这么改：旧的 `\textcolor{#B0BEC5}{\square}` 是一个**实心灰方块**，
//   既不像规格的虚线框（观感像"一个域"），宽度也只有 11.2 px（行内）——比一个正文汉字窄。
//
// **纯 Dart。**

import 'attachment.dart';
import 'caret_sites.dart';
import 'scope_table.dart';
import 'site_adjacency.dart';
import 'slot_pad.dart';

export 'slot_pad.dart';

/// 空槽占位（**看不见的垫子**；框由 `math_caret` 的自绘层画虚线）
const String kEmptySlotTex = kSlotPadTex;

/// 当前槽占位（垫子同形，只是墨色淡蓝 —— 自绘层还会盖一层同色底 + 实线框）
const String kCurrentSlotTex = kSlotPadCurrentTex;

// ---------------------------------------------------------------------------
// ★★ 结构尾垫（2026-10-15，设计稿 §11.18）
// ---------------------------------------------------------------------------
//
// 常量 `kStructTailTex` **住在 `slot_pad.dart`**（与空槽垫子同一处，理由见那一节）：
// 词法侧（`visible_atoms.dart`）要**在走查顺序里**认出它，而它的文档必须跟着常量走
// —— 一行常量配一整页说明时，说明不能留在另一个文件里（否则下次改宽度的人看不到它）。
//
// 本文件 `export 'slot_pad.dart'` ⇒ 旧的引用名照旧可用。

/// 需要尾垫的结构命令 —— 判据是**装饰的墨迹跟着内容变长**（这样"结构末尾"才**看得见**）。
///
/// ★★ **2026-10-15 晚实测后的名单**（探针数据见设计稿 §11.21.2 与 §11.21.3）：
///
/// | 结构 | 装饰形态 | 加尾垫后装饰的**真实宽度** | 结论 |
/// |---|---|---|---|
/// | `\sqrt{2}` | 横线（矢量图） | 29.3 → **34.1** | ✅ |
/// | `\overline{AB}` / `\underline{AB}` | 细线 `_RenderColoredBox` | 32.8 → **37.6** | ✅ |
/// | `\bar{x}` | 横杠 ¶（拉伸字形） | 16.0 → **20.8** | ✅ |
/// | `\widehat{AB}` / `\widetilde{AB}` | 可拉伸矢量图 | FittedBox 32.8 → **37.6** | ✅ |
/// | `\overrightarrow{AB}` | 可拉伸矢量图 | FittedBox 32.8 → **37.6** | ✅ |
/// | `\hat` `\tilde` `\dot` `\ddot` `\bar` `\vec` | ★ **定宽字形**（引擎 `nonStretchyAccents`） | 盒变宽、**墨迹不动** | ❌ 不加 |
/// | `\frac` | 分数线本来就超出分子分母 | — | ❌ 不需要 |
/// | `\overbrace` / `\underbrace` | 拉伸花括号（三片矢量图） | 未定（低频） | ⏳ 候选 |
///
/// ⚠️ **`\bar` 本在名单里，2026-10-15 晚拿掉了** —— 那次探针**只看盒宽**
///   （`\bar{x\rule{…}}` 的装饰 ¶ 16.0 → 20.8），把它误当成"拉伸字形"。
///   读引擎源码（`parser/tex/functions/katex_base/accent.dart`）才看清：`\bar` ∈
///   `nonStretchyAccents`，它的盒是**被强制撑到内容宽**的（原话："Non stretchy accent
///   can not contribute to overall width, thus they must fit exactly with the width
///   even if it means overflow"）⇒ **墨迹不跟着变长**。
///   ★ **盒变宽 ≠ 装饰变长** —— 这条教训写进设计稿 §11.21.3。
///   ⇒ 这 6 个定宽 accent 另按「**一个字符**」处理：`render/attachment.dart` 的
///   `kFixedShapeAccents`（删除与空槽占位的共用判据都搬到那儿了）。
///
/// ★★ **前置条件（2026-10-15 晚已就位）**：accent 的装饰盒原先**自己就是叶盒**
///   （`\overline{AB}` 的横线 32.8 × **0.6 px**）⇒ "叶盒数 ≠ 原子数" ⇒ 命中静默 null。
///   先在 `leaf_boxes.dart` 补了**高度下限**与**变音字形**两条判据（§11.21.2），
///   这里的名单才敢写上去 —— 顺序不能反（守门人测试就是为此存在的）。
const Set<String> kTailCommands = <String>{
  'sqrt',
  'overline',
  'underline',
  'widehat',
  'widetilde',
  'overrightarrow',
};

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

/// 给 tex 里所有**空槽**注入占位**垫子**（看不见，只占版面；框由自绘层画）；
/// [caretRel] 落在哪个空槽里，它就用"当前槽"垫子（淡蓝墨）。
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
  final List<OpScope> scopes = operatorScopes(tex); // ★ §4.8 判"可选槽"用
  final List<_Ins> ins = <_Ins>[
    // ① 空槽占位（可选槽只在光标进入该结构时才画，见 [_shouldDrawEmptySlot]）
    for (final SlotSpan s in t.slots)
      if (s.isEmpty && _shouldDrawEmptySlot(t, tex, s, caretRel, cur, scopes))
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

/// ★★ §4.8 **三类槽**（2026-10-15 用户拍板）：这个**空槽**的占位该不该画？
///
/// · **必填槽**（分式的分子分母 · 被开方数 · 函数算子的内容）⇒ **恒可见**（§6.1）
/// · **可选槽** ⇒ **只在光标进入该结构时才画**（"不打扰"）：
///     - **算子的上下限 / 底数**（`\sum_{}^{}`、`\int_a^b`、`\log_{}`）—— 不定积分、纯求和号都不必填
///     - **可选参数**（`\sqrt[n]{…}` 的次数）
///   例外：**当前槽**永远画 —— 否则光标停在一个看不见的槽里，用户不知道自己在哪。
/// · ★★ **挂件槽**（脚本 `^`/`_` ＋ 定宽 accent 的参数）⇒ **不画**（第三类，见下面第一行）
bool _shouldDrawEmptySlot(
  CaretSiteTable t,
  String tex,
  SlotSpan s,
  int caretRel,
  SlotSpan? cur,
  List<OpScope> scopes,
) {
  // ★★ 2026-10-18（用户第二版口径）：**多行环境的格子只在"光标就在该格"时画占位框**。
  //   第一版是"格子一律不画"——用户复验后否掉：矩阵/行列式的空格子**需要看得见的落点**
  //   （行列式还能省略 0），但也不该常驻（会把网格画满虚线框）。
  //   ⇒ 归到"可选槽"这一类：**仅当前格**显示。
  if (s.path.any((SlotStep st) => st.row != null || st.col != null)) {
    return cur != null && cur.start == s.start && cur.end == s.end;
  }

  // ★★ §4.8 **第三类：挂件槽不画占位框**（2026-10-15 晚用户拍板）——
  //    理由（用户的模型：**挂件挂在/套在基座上，不是结构**）：
  //    · 文本里的一个字**旁边没有格子**；给挂件画框，就是把"渲染提示"画成了"一个域"；
  //    · 空挂件**已经有可见落点** —— 基座字符本身就在那儿（accent 则那顶帽子在），不是幽灵；
  //    · 光标进去时**自己会把位置画出来**（注入的蓝色竖条）⇒ 不必再造一个方框；
  //    · 光标离开后留下的空挂件，**提交点 normalize 会回收**（§4.8 既有行为）。
  //    ★ **连"当前槽"也不画**（用户口径：挂件这儿没有"占位框"这个概念）。
  //    ⚠️ 但 `\sum_{i=1}^{n}` / `\log_{2}` / `\int_a^b` 的**上下限与底数**在源码里
  //      **就是脚本槽** —— 它们属于 §4.8 的**可选槽**（不定积分 / 纯求和号不必填），
  //      **不是挂件** ⇒ 判据必须把它们排除（与下面的可选槽分支**共用作用域表**）。
  if (isAttachmentSlot(s) && !_isOperatorLimit(s, scopes)) return false;

  if (cur != null && s.start == cur.start && s.end == cur.end) return true; // 当前槽
  // ① 算子的上下限 / 底数（**可选**）：光标在**这个算子对象**里就画
  //    —— §4.7 的作用域就是那个"结构"
  for (final OpScope sc in scopes) {
    if (s.start >= sc.opStart && s.end <= sc.limitsEnd) {
      return caretRel >= 0 && caretRel >= sc.start && caretRel <= sc.end;
    }
  }
  // ② 可选参数（`\sqrt[n]{…}`，**可选**）：光标在**拥有这个槽的那个内容项**里就画
  if (s.path.isNotEmpty && s.path.last.argIndex == -1) {
    final TexItem? owner = _innermostItemContaining(t, s);
    if (owner != null) {
      return caretRel >= 0 && caretRel >= owner.start && caretRel <= owner.end;
    }
  }
  return true; // 必填槽 ⇒ **恒可见**（§6.1，用户拍板）
}

/// 这个"脚本槽"其实是**算子的上下限 / 底数**吗？
///
/// `\sum_{i=1}^{n}`、`\log_{2}`、`\int_a^b` 的上下限在**源码里就是脚本**（`_` / `^`），
/// 但它们是 §4.8 的**可选槽**（不定积分、纯求和号本来就不必填）⇒ 不算"挂件"。
/// ★ 判据与可选槽那一条**共用作用域表**（`scope_table.dart`），不另判一遍。
bool _isOperatorLimit(SlotSpan s, List<OpScope> scopes) {
  for (final OpScope sc in scopes) {
    if (s.start >= sc.opStart && s.end <= sc.limitsEnd) return true;
  }
  return false;
}

/// 拥有槽 [s] 的**最内层内容项**（`\sqrt[3]{x}` 整段）—— 直接用解析器导出的项表，不另判一遍
TexItem? _innermostItemContaining(CaretSiteTable t, SlotSpan s) {
  TexItem? best;
  for (final TexRegion r in t.regions) {
    for (final TexItem it in r.items) {
      if (it.start > s.start || it.end < s.end) continue;
      if (best == null || (it.end - it.start) < (best.end - best.start)) {
        best = it;
      }
    }
  }
  return best;
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
/// 渲染某个数学段时用的 tex（**注入与渲染必须走同一个函数**，否则点击定位会错位）。
///
/// ★★ 2026-10-18：`caretRel` 与 `showCursor` **拆成两件事**（用户实测"虚线框随光标闪烁若隐若现 +
///   排版闪动"的根因）：
///   · `caretRel` = **光标逻辑位置**（不受闪烁/选区影响）⇒ 决定"注不注空槽垫子"（会改宽度！）
///   · `showCursor` = **视觉上画不画竖条**（闪烁灭、有选区时 false）
///   以前两者共用同一个 `caretRel`（闪烁灭 ⇒ -1），于是垫子每秒增删两次 ⇒ 整段重排两次。
String renderMathTex(String tex, {required int caretRel, bool showCursor = true}) {
  // ★ 空公式也要画出来（§6.1.1）——它没有任何槽可注入，所以要单独兜一句
  if (tex.trim().isEmpty) {
    final String mark = caretRel < 0 ? kEmptyFormulaTex : kCurrentSlotTex;
    // 光标在里面时再补一根光标条（否则用户不知道自己停在哪儿）
    return (caretRel < 0 || !showCursor) ? mark : mark + kCursorTex;
  }
  final SlotMarkResult marks = injectSlotMarks(tex, caretRel: caretRel);
  // 光标不在这段里 → 只画空槽，不画光标（`marks.rel` 此时为负，不能喂给 injectCursor）
  if (caretRel < 0 || !showCursor) return marks.tex;
  return injectCursor(marks.tex, marks.rel).tex;
}
