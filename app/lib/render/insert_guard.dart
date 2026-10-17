// 数语引擎 · 插入侧守门人（2026-10-15）
//
// ============================ 为什么需要它 ============================
// 2026-10-15 用户实测：「点分式内 → 右箭头到数学区外行末 → 按 Enter → **分式被直接拆出编码**」。
// 探针把根因钉死了（`文字。$\frac{a}{b}$`，Enter 走平台真身 `performAction(newline)`）：
//
//   偏移：文0 字1 。2 $3 \4f5r6a7c8 {9a10}11{12b13}14 $15 ⏎16
//   · 14 = 分母内容末尾          Enter → 公式完好 ✓
//   · **15 = tex 末尾 = 闭合 `$` 那一格**（"还在公式里"）
//                                 Enter → `文字。$\frac{a}{b}` ⏎⏎ `$` → **劈断，退化成源码** ✗
//   · 16 = closeEnd（"在公式之后"）Enter → 公式完好 ✓
//
// ★ 关键在于 **15 与 16 在屏幕上是同一个位置**（`$` 不可见）——
//   所以"按 `→` 到行末再回车"极易停在 15，一按 Enter 就把 `$` 配成单数。
//
// ★★ 根因的**一般形式**：`EditView` 把文本**无条件**插到 `_buf.caret`，
//   而 caret 可以合法地落在数学段**内部**（槽里 / 原子之间 / tex 末尾）。
//   块级换行会破坏"行内公式不跨行、行间公式的 tex 里不出现空行"这两条结构不变量 ——
//   而**插入这一侧从来没有守门人**：设计稿 §4.0 的"永不留下半个坏公式"
//   只做在**删除**上（`smart_delete.dart`），插入侧是裸的。
//
// ============================ 规则（两条） ============================
// ① **在数学段内部插入含 `\n` 的文本 → 落点推到最后 `closeEnd`（公式之后）。**
//
// 为什么这样分：
//   · **行内**公式不能跨行（`projectInline` 是按行做的）→ 任何 `\n` 都会劈断定界符
//   · **行间**公式的 tex 里出现**空行**在 TeX 里是 `\par`（数学模式直接报错）
//   · 而**非换行**的插入**照样进公式**（在末尾打字 = 继续这段数学）——
//     这一点很重要：`$x^2$` 的光标停在 tex 末尾时打 `+1`，得到的是数学里的 `x^2+1` ✓
//
// ② ★★ **插在"语法粘合处"要挪位**（2026-10-17 加，与 `caret_sites.neutralPoint` 同一条规则）：
//    插入物与注入的光标锚点**一样**会顶掉 `^`/`_` 的结合 —— 探针实测 `\sum|^…` 打进一个字符，
//    上下限就掉到右边；`a_|i` 打进一个字符，`i` 变成普通字号（用户原话"i 被放大了"）。
//    ⇒ 落点按 `neutralPoint` 挪到**结构内部**（必要时先给裸参数补花括号，见 [InsertPlan.wrapBareArg]）。
//    ★ 这一条保证"**光标画在哪 = 打字插在哪**"。
//
// ⚠️ **已知代价（诚实记账）**：**在行间公式块内部没法再插空行** →
//    多行公式（`aligned` / `cases`）暂时写不出来。那需要先定"公式块内换行"的键位语义
//    （例如块内 `Enter` = 单个 `\n`、`Ctrl+Enter` = 断块），已记入待办（S4/S5）。
//    注意"单个 `\n`"仍然放行（`Shift+Enter` 的 `  \n` 在行间公式里是合法的），
//    被挡的只有**会产生空行**的那种。
//
// **纯 Dart，不依赖 Flutter。**

import 'caret_sites.dart';
import 'math_nav.dart';

/// 一次插入的落点计划。
class InsertPlan {
  const InsertPlan(this.offset, {required this.moved, this.why, this.wrapBareArg});

  const InsertPlan.keep(int offset)
      : this(offset, moved: false, why: null, wrapBareArg: null);

  /// 最终落点（没被调整时 = 原样）。★ 若 [wrapBareArg] 非空，这是**补完花括号之后**的偏移。
  final int offset;

  /// 落点是否被推出过（测试与探针都靠它）
  final bool moved;

  /// 为什么推（`null` = 没推）；给人读的
  final String? why;

  /// ★ 插入前要先把这段**裸参数**包上花括号（源坐标；`null` = 不用）。
  ///
  /// 为什么需要它：`a_i` 里"脚本参数"没花括号 ⇒ 往 `i` 前面插东西，插入物会**变成**那个参数
  /// （`a_xi` ⇒ `i` 掉成普通字符）。补上花括号后语义完全不变，插入物就落在参数**内部**了。
  final ({int start, int end})? wrapBareArg;

  @override
  String toString() => moved
      ? 'InsertPlan(→$offset, $why${wrapBareArg == null ? '' : '，补括号 $wrapBareArg'})'
      : 'InsertPlan(保持 $offset)';
}

/// 把一次插入的落点调到"不会破坏结构不变量"的地方。
///
/// ★ **不要**在这里顺手拦"插入一个 `$`" —— 那正是用户**新建公式**的路径（打 `$` 开始一段数学），
///   拦了就没法用了。
InsertPlan planInsert(String source, int offset, String text) {
  final int o = offset.clamp(0, source.length);
  final MathRegion? r = mathRegionAt(source, o);

  if (r != null) {
    // ★★ 规则 ⓞ：**插入点落在定界符的字符之间 ⇒ 先挪出去**（2026-10-17，全域守卫抓出）。
    //   `$$|$` 里插任何字符都会把 `$$` 配成两个单 `$` ⇒ 公式退化成源码。
    if (o < r.contentStart) {
      final bool nl = text.contains('\n');
      return InsertPlan(
        nl ? r.closeEnd : r.contentStart,
        moved: true,
        why: '插入点落在**开头定界符**里（会把 `\$` 配成单数）⇒ 挪进公式',
      );
    }
    if (o > r.contentEnd) {
      // ★ 围栏里 / 围栏**行末**都没有"公式之外"的位置（那一行末尾塞字符就不再是围栏）
      //   ⇒ 非换行文本落进公式内部；换行落块之后。
      return InsertPlan(
        text.contains('\n') ? r.closeEnd : r.contentEnd,
        moved: true,
        why: '插入点落在**结尾定界符**（或围栏行末）上 ⇒ 非换行文本落进公式、换行落块之后',
      );
    }
  }

  if (!text.contains('\n')) {
    // ★★ 规则 ②：非换行插入也要过"结构中性"这一关（2026-10-17）
    final InsertPlan? neutral = _neutralInsert(source, o);
    if (neutral != null) return neutral;
    return InsertPlan.keep(o);
  }

  if (r == null) return InsertPlan.keep(o); // 不在数学段里 → 正常断块

  // ★★ 规则 ①：**单行闭合的 `$$…$$` 一个换行都不许收**（收了就不再是"同行闭合"⇒ 退化）
  final bool multiLineFence =
      source.substring(r.openStart, r.contentStart).contains('\n');
  // 行间公式块（多行围栏）：只有"会产生空行"的才破（单个 `\n` 在 TeX 里合法，`aligned` 要用）
  if (r.isDisplay && multiLineFence && !_introducesBlankLine(source, o, text)) {
    return InsertPlan.keep(o);
  }

  return InsertPlan(
    r.closeEnd,
    moved: true,
    why: !r.isDisplay
        ? '行内公式不能跨行'
        : (!multiLineFence
            ? '单行闭合的 `\$\$…\$\$` 不能收换行（会退化成源码）'
            : '块级换行不能落在行间公式的 tex 里（TeX 空行 = \\par）'),
  );
}

/// 插入点落在语法粘合处时，按 [neutralPoint] 给出的**中性落点**做计划；不需要调整返回 null。
InsertPlan? _neutralInsert(String source, int o) {
  final MathRegion? r = mathRegionAt(source, o);
  if (r == null) return null;
  final int rel = o - r.contentStart;
  if (rel < 0 || rel > r.tex.length) return null;
  final NeutralPoint np = neutralPoint(r.tex, rel);
  if (np.wrap == null && np.at == rel) return null;
  final ({int start, int end})? wrap = np.wrap == null
      ? null
      : (start: r.contentStart + np.wrap!.start, end: r.contentStart + np.wrap!.end);
  return InsertPlan(
    r.contentStart + np.at,
    moved: true,
    why: wrap == null
        ? '插入点紧跟 ^/_（注入物会顶掉结合关系）⇒ 挪进脚本内部'
        : '插入点在裸参数里（插入物会顶掉这个参数）⇒ 先补花括号再插进内部',
    wrapBareArg: wrap,
  );
}

/// 这次插入会不会在公式块里造出**空行**（TeX 里 = `\par`，数学模式会报错）。
bool _introducesBlankLine(String source, int o, String text) {
  if (text.contains('\n\n')) return true;
  if (!text.contains('\n')) return false;
  // 插入点紧邻已有的 `\n` → 拼起来就是一个空行
  final bool prevNl = o > 0 && source[o - 1] == '\n';
  final bool nextNl = o < source.length && source[o] == '\n';
  return prevNl || nextNl;
}
