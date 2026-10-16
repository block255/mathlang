// 数语引擎 · 数学段里的**光标**：零尺寸锚点 + 自绘竖条（高度**随当地那一行自适应**）
//
// ★★ 为什么不用引擎自带的 `\cursor{}`（2026-10-15 晚用户实测后定）：
//   引擎的 `CursorNode` 是一根 **1.5 × (0.875 × 字号)** 的实心竖条，它**真的参与排版**。
//   实测（`\hat{x}`，字号 16）：
//
//   | 注入物 | Math 盒 | 内容 `x` 的 y |
//   |---|---|---|
//   | 什么都不注 | 16.00 × **11.11** | -0.9..15.1 |
//   | 引擎 `\cursor{}`（14 px 高） | 17.50 × **18.22** | **4.5..20.5**（下移 5.4 px！） |
//   | **零尺寸锚点** | 16.00 × **11.11** | -0.9..15.1 ✓ **一模一样** |
//
//   ⇒ 光标一进公式，公式盒子就被撑高/撑宽，而 accent 这类**装饰不跟着走**
//     ⇒ 视觉上"帽子跟字脱开、跳了一下"（用户原话：「跟上标跳起来了一样」）。
//
// ★★ 高度为什么要**自适应**（用户第二轮实测抓出）：
//   「不管点哪光标都一样高 ⇒ **分母的光标会顶穿分数线、根号里的会顶穿根号**」。
//   按经验值看一眼就明白：数学段里那些行的**自然高度**只有 10–11 px（引擎自己的行盒），
//   而固定高是 `16 × 1.25 = 20 px` —— 在任何**比主行矮**的格里都必然捅出去。
//   ⇒ 做法：**量出光标所在那一行的"当地字形盒"**（¶ 盒），竖条就画在它里面（上下各留 8%）：
//     · 主行字号 16 ⇒ 竖条 ≈ 14.7 px（与文本侧 20 px 的量级一致，但**不会越界**）
//     · 上标/下标（0.7 倍字号）⇒ ¶ 盒 11.2 px ⇒ 竖条 ≈ 9.3 px ✓ 自动变小
//     · 分式的分母 ⇒ 竖条**待在分母自己的盒子里** ⇒ 顶不到分数线 ✓
//     · 根号里 ⇒ 待在内容盒里 ⇒ 顶不到横线 ✓
//   ⇒ 这一条是**可证的**：竖条的矩形被夹在"当地那一行的字形盒"之内，而分数线/根号横线
//     本来就画在那一行的盒子**之外** ⇒ 结构上不可能相交。
//
// ★ `CustomPaint` 是 `RenderProxyBox` ⇒ **基线照旧透传**（`MathAlignMode.baseline` 不受影响），
//   尺寸 = 子节点 ⇒ 行内排版**完全不变**。
//
// **纯 Dart + Flutter（无第三方依赖）。**

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import 'caret_ownership.dart';
import 'caret_sites.dart';

/// 包一层：给 `Math` 画上我们自己的光标条（**不影响布局**）。
class MathWithCaret extends StatefulWidget {
  const MathWithCaret({
    super.key,
    required this.tex,
    required this.showCaret,
    required this.mathKey,
    required this.fontSize,
    this.mathStyle = MathStyle.text,
    this.caretWidth = 1.5,
    this.caretEdge = CaretEdge.none,
    this.textFontSize,
    this.onErrorFallback = Math.defaultOnErrorFallback,
  });

  /// **渲染 tex**（已经过注入链：空槽占位 + 锚点）
  final String tex;

  /// 光标在不在这段数学里（不在 ⇒ 连竖条也不画）
  final bool showCaret;

  /// 给内层 `Math` 的 key（命中测试/探针都要用它取 RenderObject）
  final GlobalKey mathKey;

  final double fontSize;
  final MathStyle mathStyle;
  final double caretWidth;

  /// ★★ 光标是不是落在**公式两端多认领的那两格**上（[CaretEdge]）。
  /// 是 ⇒ 这一格**视觉上属于文本层** ⇒ 按**文本层标准**画竖条（不拿公式内部那一行）。
  final CaretEdge caretEdge;

  /// **文本层的字号**（用于 [caretEdge] 那两格）；不给就退回 [fontSize]
  final double? textFontSize;

  final OnErrorFallback onErrorFallback;

  @override
  State<MathWithCaret> createState() => _MathWithCaretState();
}

class _MathWithCaretState extends State<MathWithCaret> {
  /// 竖条的矩形（相对本盒；帧末量出来；`null` = 还没量到）
  Rect? _bar;

  @override
  void initState() {
    super.initState();
    _scheduleMeasure();
  }

  @override
  void didUpdateWidget(covariant MathWithCaret old) {
    super.didUpdateWidget(old);
    _scheduleMeasure();
  }

  void _scheduleMeasure() {
    if (!widget.showCaret) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measure();
    });
  }

  void _measure() {
    final BuildContext? mc = widget.mathKey.currentContext;
    if (mc == null) return;
    final RenderObject? root = mc.findRenderObject();
    if (root == null) return;
    final RenderBox? anchor = findCaretAnchor(root);
    if (anchor == null) return;
    final Offset at = anchor.localToGlobal(Offset.zero, ancestor: root);
    // ★★ **层级决定行**（2026-10-16 用户提出，§11.27）：
    //   · 公式内部（含主行 / 分子 / 分母 / 上下限 / 次数）⇒ 那一层的 ¶ 盒；
    //   · 公式两端"多认领"的那两格 ⇒ **文本层**：与"文字后面的光标"地位等同，
    //     按文本层标准画（字号 × 1.25、贴基线），**不去公式内部找最近的行**
    //     （否则"分式后面"会被分母抢走 —— 用户实测）。
    final Rect bar;
    if (widget.caretEdge == CaretEdge.none) {
      bar = caretBarRect(
        at: at,
        localRowBox: findLocalRowBox(root, at),
        width: widget.caretWidth,
        fontSize: widget.fontSize,
      );
    } else {
      bar = textLayerCaretRect(
        baseline: at,
        width: widget.caretWidth,
        fontSize: widget.textFontSize ?? widget.fontSize,
      );
    }
    if (_bar == null || _bar != bar) setState(() => _bar = bar);
  }

  @override
  Widget build(BuildContext context) {
    final Rect? bar = _bar;
    return CustomPaint(
      foregroundPainter: (widget.showCaret && bar != null)
          ? MathCaretPainter(rect: bar, color: const Color(kCaretColorValue))
          : null,
      child: Math.tex(
        widget.tex,
        key: widget.mathKey,
        mathStyle: widget.mathStyle,
        textStyle: TextStyle(fontSize: widget.fontSize),
        onErrorFallback: widget.onErrorFallback,
      ),
    );
  }
}

/// ★★ 算竖条的矩形：**夹在"光标所在那一行的字形盒"里面**。
///
/// [localRowBox] 是那一行的字形盒（§ [findLocalRowBox]）；拿不到就退回经验值
/// （`字号 × 1.25`，以锚点给出的**基线**为基准）—— 那种情形只出现在"空挂件"等少数格里。
///
/// 上下各留 [kCaretInset]（8%）：竖条不贴边，看起来像光标而不是一个色块。
const double kCaretInset = 0.08;

/// ★★ **文本层光标高度**（= "文字后面的光标"的标准，也是旧值）：
/// `字号 × 1.25`。文本侧与"公式前后那两格"**共用**这一条 —— 它们的地位等同
/// （§7.1 顶层无墙、内部有层）。字号取**本行文本 style 的字号**（标题 28、正文 16），
/// 所以改文档字号 / 标题级别时会自动跟着变。
double textCaretHeight(double fontSize) => fontSize * 1.25;

/// ★★ **结构层光标高度**：当地那一行的字形盒，上下各内缩 [kCaretInset]。
/// 自适应：上标 / 下标（0.7 倍字号）⇒ 9.3、主行 / 分子 / 分母 ⇒ 13.4。
double mathCaretHeight(double localRowBoxHeight) =>
    localRowBoxHeight * (1 - 2 * kCaretInset);

/// **文本层**竖条矩形：以**基线**为基准（拿不到文本行的行盒时用它）——
/// 与文本侧"零宽条"同一个视觉标准（同高、同一个基线）。
Rect textLayerCaretRect({
  required Offset baseline,
  required double width,
  required double fontSize,
}) {
  final double h = textCaretHeight(fontSize);
  return Rect.fromLTRB(
      baseline.dx, baseline.dy + h * 0.15 - h, baseline.dx + width, baseline.dy + h * 0.15);
}

Rect caretBarRect({
  required Offset at,
  required Rect? localRowBox,
  required double width,
  required double fontSize,
}) {
  if (localRowBox != null && localRowBox.height > 1) {
    final double top = localRowBox.top + localRowBox.height * kCaretInset;
    final double bottom = localRowBox.bottom - localRowBox.height * kCaretInset;
    return Rect.fromLTRB(at.dx, top, at.dx + width, bottom);
  }
  final double h = fontSize * 1.25; // 兜底：与文本侧光标同高的经验值
  return Rect.fromLTRB(at.dx, at.dy + h * 0.15 - h, at.dx + width, at.dy + h * 0.15);
}

/// ★★ 在渲染子树里找**锚点**：我们注入的那个零宽零高 `\rule`。
///
/// 实测形态：**`_RenderColoredBox`，`size == Size.zero`**（`\rule{0pt}{0pt}` 画出来的）。
/// · 它**不会**被 `leaf_boxes.scanLeafBoxes` 收进"有效叶盒"（宽度 0 < `kMinLeafWidth`）
///   ⇒ 命中测试的「叶盒数 == 原子数」不受影响 ✓
/// · 词法上 `\rule` 是结构命令 ⇒ **0 个可见原子** ✓ 两边都不用为它补账 ✓
///
/// ⚠️ 这是**认渲染事实**（与"宽度上限""高度下限""变音字形"同一层判据）；
///   引擎若改了 `\rule` 的画法，`math_caret_test.dart` 的守卫会当场变红。
RenderBox? findCaretAnchor(RenderObject root) {
  RenderBox? found;
  void walk(RenderObject o) {
    if (found != null) return;
    var hasChild = false;
    o.visitChildren((RenderObject c) {
      hasChild = true;
      walk(c);
    });
    if (!hasChild &&
        o is RenderBox &&
        o.hasSize &&
        o.size == Size.zero &&
        o.runtimeType.toString().contains('ColoredBox')) {
      found = o;
    }
  }

  walk(root);
  return found;
}

/// ★★ 找**光标所在那一行的字形盒**：竖直上"住着"这条基线、水平上离光标最近的 ¶ 盒。
///
/// **两趟判据**（2026-10-16 修，用户实测"分式后面的光标看着像分母的"）：
/// 1. **只认"严格含基线"**的盒（`at.dy ∈ [top, bottom]`）⇒ 同一行内的盒里取水平最近；
/// 2. ★ 一个都没有，**才**退回"±2 px 容忍"（引擎的盒与基线偶有微小偏差）。
///
/// 为什么必须分两趟：原来只有第 2 趟 —— 基线恰落在两行盒子的边界上时
/// （实测 `x=\frac{a}{b}` 的主行盒 7..20.4、分母盒 16.7..32.7），**下一行的盒也进候选**，
/// 而分母正在公式末尾正下方、水平最近 ⇒ 竖条被画到**分母那一行**。
///
/// 为什么用 ¶ 盒（字形盒）而不是引擎的行盒：**行盒太紧**（16 px 字号下行盒只有 10–11 px），
/// 拿它当光标会明显偏矮；而 ¶ 盒 = 字形的**行高盒**（主行 16、上标 / 下标 11.2 —— 正好 0.7 倍）。
Rect? findLocalRowBox(RenderObject root, Offset at) {
  final List<({Rect rect, double dx})> hits = <({Rect rect, double dx})>[];
  void walk(RenderObject o) {
    var hasChild = false;
    o.visitChildren((RenderObject c) {
      hasChild = true;
      walk(c);
    });
    if (hasChild || o is! RenderBox || !o.hasSize || o.size == Size.zero) return;
    if (!o.runtimeType.toString().contains('Paragraph')) return; // 只认字形盒
    final Rect r = o.localToGlobal(Offset.zero, ancestor: root) & o.size;
    hits.add((rect: r, dx: (r.center.dx - at.dx).abs()));
  }

  walk(root);

  ({Rect rect, double dx})? best;
  // 第 1 趟：**严格**含基线
  for (final ({Rect rect, double dx}) h in hits) {
    if (at.dy < h.rect.top || at.dy > h.rect.bottom) continue;
    if (best == null || h.dx < best.dx) best = h;
  }
  // 第 2 趟：±2 px 容忍
  if (best == null) {
    for (final ({Rect rect, double dx}) h in hits) {
      if (at.dy < h.rect.top - 2 || at.dy > h.rect.bottom + 2) continue;
      if (best == null || h.dx < best.dx) best = h;
    }
  }
  return best?.rect;
}

/// 画那根竖条（矩形已经在 [_MathWithCaretState._measure] 里算好）
class MathCaretPainter extends CustomPainter {
  const MathCaretPainter({required this.rect, required this.color});

  final Rect rect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(rect, Paint()..color = color);
  }

  @override
  bool shouldRepaint(MathCaretPainter old) =>
      old.rect != rect || old.color != color;
}
