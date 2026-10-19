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

import 'hit_map.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import 'caret_ownership.dart';
import 'caret_sites.dart';
import 'env_cells.dart';
import 'leaf_boxes.dart';
import 'leaf_pairing.dart';
import 'slot_pad.dart';
import 'visible_atoms.dart';

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
    this.selFrom,
    this.selTo,
  });

  /// **选区**（⑤ 高亮）：tex 相对区间 `[selFrom, selTo)`；`null` = 这段没被选中
  final int? selFrom;
  final int? selTo;

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
  /// 竖条的矩形（相对本盒；帧末量出来；`null` = 还没量到 / 光标不在这段里）
  Rect? _bar;

  /// ★ 空槽占位垫（④-1）—— **与光标在不在无关，恒要量**（§6.1：空槽就该一直看得见）
  List<SlotPad> _pads = const <SlotPad>[];

  /// ★ ④-4「甲」瞬时边界刻度（只在"公式之前 / 之后"那两格出现）
  Rect? _tick;

  /// 选区底色块（⑤）：按原子铺，纯绘制
  List<Rect> _bands = const <Rect>[];

  /// ★★ 2026-10-18 晚（性能）：**按渲染顺序排好的原子表，按 tex 缓存**。
  ///   `renderOrderAtoms` 每次要建位点表（实测 90 原子 **≈137 µs**），而拖选时
  ///   `_measure` 会被反复调用 ⇒ 不缓存的话"大面积拖选"每帧都在重建同一张表。
  List<VisibleAtom>? _selAtoms;
  String? _selAtomsKey;

  List<VisibleAtom> _atomsForSelection() {
    final String key = '${widget.mathStyle.name}\u0000${widget.tex}';
    if (_selAtomsKey == key && _selAtoms != null) return _selAtoms!;
    _selAtoms = renderOrderAtoms(widget.tex,
        displayStyle: widget.mathStyle == MathStyle.display);
    _selAtomsKey = key;
    return _selAtoms!;
  }

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

  /// ★★ 无论光标在不在这一段里都要量 —— 空槽垫子（④-1）**恒可见**。
  ///    （原先这里是 `if (!widget.showCaret) return;`：只有光标在时才量。）
  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measure();
    });
  }

  void _measure() {
    final BuildContext? mc = widget.mathKey.currentContext;
    if (mc == null) return;
    final RenderObject? root = mc.findRenderObject();
    if (root == null) return;
    final RenderBox? anchor = widget.showCaret ? findCaretAnchor(root) : null;
    final Offset? at = anchor?.localToGlobal(Offset.zero, ancestor: root);

    // ★★ ⑤ 选区底色：按**原子**铺（纯绘制，不改尺寸 ⇒ 不影响排版与分页）
    final int? sf = widget.selFrom;
    final int? st = widget.selTo;
    final List<Rect> bands = (sf == null || st == null || st <= sf)
        ? const <Rect>[]
        : selectionBands(
            root: root,
            tex: widget.tex,
            from: sf,
            to: st,
            atoms: _atomsForSelection(),
            displayStyle: widget.mathStyle == MathStyle.display,
          );

    Rect? bar;
    Rect? tick;
    if (at != null) {
      // ★★ **层级决定行**（2026-10-16 用户提出，§11.27）：
      //   · 公式内部（含主行 / 分子 / 分母 / 上下限 / 次数）⇒ 那一层的 ¶ 盒；
      //   · 公式两端"多认领"的那两格 ⇒ **文本层**：与"文字后面的光标"地位等同，
      //     按文本层标准画（字号 × 1.25、贴基线），**不去公式内部找最近的行**
      //     （否则"分式后面"会被分母抢走 —— 用户实测）。
      if (widget.caretEdge == CaretEdge.none) {
        bar = caretBarRect(
          at: at,
          // ★ 把**锚点**一起给它：选行以"锚点所在的那一行"为准（见 findLocalRowBox）
          localRowBox: _clampRowHeight(
              findLocalRowBox(root, at, anchor: anchor), widget.fontSize),
          width: widget.caretWidth,
          fontSize: widget.fontSize,
        );
      } else {
        // ★★ 2026-10-18：**行间块**的"公式之前 / 之后"那两格，光标要贴在**块的边界**上
        //   （之后 ⇒ 块底、之前 ⇒ 块顶），不能用块内锚点的 y ——
        //   `aligned` / `cases` 的锚点在竖直**中心** ⇒ 竖条会浮在**两行之间**
        //   （用户实测：从第 2 行右式末尾按 Tab 退出公式，光标落在两行中间靠右）。
        final bool isDisplay =
            widget.mathStyle == MathStyle.display && root is RenderBox && root.hasSize;
        final Offset baseline = isDisplay
            ? Offset(at.dx,
                widget.caretEdge == CaretEdge.before ? 0.0 : root.size.height)
            : at;
        bar = textLayerCaretRect(
          baseline: baseline,
          width: widget.caretWidth,
          fontSize: widget.textFontSize ?? widget.fontSize,
        );
        // ★★ ④-4「甲」**瞬时边界刻度**（§6.5，2026-10-16 用户拍板"甲＋丙"）：
        //   光标落在"公式之前 / 之后"那两格时，在**公式外侧**画一根 1px × 行高的灰刻度
        //   ⇒ 用户看得见"公式的边界在哪"（竖条是插入点，刻度是边界）。
        //   ★ 只在这两格出现、离开即消失（**不常驻、不包围**）—— 过闸表 §7.2 的允许形态。
        //   ★ 画在外侧（`caretWidth + 1.5`）⇒ 不与竖条重叠。
        final double w =
            (root is RenderBox && root.hasSize) ? root.size.width : 0.0;
        final double x = widget.caretEdge == CaretEdge.before
            ? -(widget.caretWidth + 1.5)
            : w + 1.5;
        tick = Rect.fromLTWH(x, bar.top, 1.0, bar.height);
      }
    }

    // ★ 空槽垫子：**当前槽**靠"锚点落在哪个垫子盒里"认出来（实测：空槽里锚点正好在垫子右缘）
    final List<SlotPad> pads = <SlotPad>[...scanSlotPads(root, caretAt: at)];
    // ★★ 2026-10-19 **重写这段**（用户三张图：框画在"有内容的格子"上、还画到公式外面去了）。
    //   新判据：**只认环境空格子专用的"填充垫"**（`kEnvCellFillTex`，零高、宽 1em）。
    //   它只会被注入到**空格子**里 ⇒ 有内容的格子、公式外面都不可能出现框。
    if (at != null && hasEnv(widget.tex)) {
      LeafBox? fillPad;
      for (final LeafBox b in scanLeafBoxes(root).eligible) {
        if (b.kind != LeafBoxKind.pad) continue;
        if (b.rect.height > 2) continue; // 填充垫是零高
        if (b.rect.width < widget.fontSize * 0.5) continue; // 结构尾垫只有 3pt，排除
        if ((b.rect.left - at.dx).abs() > widget.fontSize * 0.9) continue;
        fillPad = b;
        break;
      }
      if (fillPad != null) {
        final double h = bar?.height ?? widget.fontSize;
        pads.add(SlotPad(
            Rect.fromLTWH(fillPad.rect.left, bar?.top ?? at.dy,
                fillPad.rect.width, h),
            current: true));
      }
    }

    if (!_samePads(pads, _pads) ||
        _bar != bar ||
        _tick != tick ||
        !MathCaretPainter.sameRects(bands, _bands)) {
      setState(() {
        _bar = bar;
        _pads = pads;
        _tick = tick;
        _bands = bands;
      });
    }
  }

  static bool _samePads(List<SlotPad> a, List<SlotPad> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].rect != b[i].rect || a[i].current != b[i].current) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final bool caretVisible = widget.showCaret && _bar != null;
    // ★ 只要"有竖条 / 有垫子 / 有刻度"就要挂 painter（垫子与光标在不在无关）
    final bool any = caretVisible ||
      _pads.isNotEmpty ||
      _tick != null ||
      _bands.isNotEmpty; // ★ ⑤ 有选区底块也要挂 painter
    return CustomPaint(
      foregroundPainter: any
          ? MathCaretPainter(
              rect: _bar ?? Rect.zero,
              color: const Color(kCaretColorValue),
              caretVisible: caretVisible,
              pads: _pads,
              bands: _bands,
              tick: _tick,
              // 虚线的"一格"跟随本段字号（不写死像素，§6.4）
              dashUnit: widget.fontSize / 16.0,
            )
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
/// 选区底色（**纯绘制**，不参与布局）：淡蓝、半透明 —— 盖在字形后面
const int kSelectionColorValue = 0x3D1E88E5;
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

/// 一个渲染对象**最近的 `RenderLine` 祖先**（= 它坐在哪一行上）。
///
/// ★ 一直走到顶（**含** [root] 自己那一层）—— 实测锚点常常直接坐在**根行**上，
/// 若在 root 处停下就会返回 null，"层优先"整条判据被跳过（踩过）。
/// ★ 这是"**行**"的权威判据：嵌套结构里分子 / 分母的 ¶ 盒虽然几何上落在外层行的范围内，
/// 但它们**最近的**行祖先是**内层**那一行（配合 [sameLayer] 的"不跨结构节点"就分得开）。
RenderObject? rowOf(RenderObject o, RenderObject root) {
  RenderObject? cur = o;
  while (cur != null) {
    if (cur.runtimeType.toString().contains('RenderLine')) return cur;
    cur = cur.parent;
  }
  return null;
}

/// [row] 与 [anchorRow] 是不是**同一层**？
///
/// ★★ 定义（2026-10-16，第三次迭代后收敛）：从 [row] 往上走到 [anchorRow] 的途中
/// **不许穿过结构节点**（`RenderCustomLayout<_FracPos>` / `_SqrtPos` / `_ScriptPos` …）。
/// · `x` 的行 → 主行：途中没有结构节点 ⇒ 同一层 ✓
/// · 分母的行 → 主行：途中要穿过 `_FracPos` ⇒ **不同层** ✓（这正是"分式后面的光标不许
///   被分母抢走"的判据；`\sum` 的上下限、`\sqrt[n]` 的次数槽同理）
/// · 光标在分母里时，锚点行就是分母那一行 ⇒ 分母的字形与它同层 ✓
///
/// ⚠️ 一度用过"同一个 `RenderLine` 实例"（太严：引擎给单个原子还裹一层内层行）和
/// "锚点行的后代行"（太宽：分母的行也是主行的后代）—— 都不对。
bool sameLayer(RenderObject? row, RenderObject? anchorRow) {
  if (row == null || anchorRow == null) return false;
  RenderObject? cur = row;
  while (cur != null) {
    if (identical(cur, anchorRow)) return true;
    if (cur.runtimeType.toString().contains('CustomLayout')) return false;
    cur = cur.parent;
  }
  return false;
}

/// ★★ 找**光标所在那一行的字形盒**。
///
/// **判据（2026-10-16，两轮用户实测驱动）**：
/// 1. **层优先**：给 [anchor] 时，候选 = "**最近的 `RenderLine` 祖先是锚点那一行、或是它的后代行**"
///    的 ¶ 盒 —— 而且**竖直上要含这条基线**（先严格、再 ±2 px）。
///    ★ 为什么不能只靠几何：显示式分式里 **分子盒下沿 ≈ 分数线 ≈ 分母盒上沿 ≈ 主行基线**，
///    "谁的盒含基线"会有两三个盒同时成立，再按"水平最近"就选到分式那一列（分子 / 分母）
///    —— 用户实测"分式后面的光标像分母的"。
/// 2. 拿不到 [anchor]（或那一行里量不到字形）⇒ 退回纯几何两趟判据。
///
/// 为什么用 ¶ 盒（字形盒）而不是引擎的行盒：**行盒太紧**（16 px 字号下行盒只有 10–11 px），
/// 拿它当光标会明显偏矮；而 ¶ 盒 = 字形的**行高盒**（主行 16、上标 / 下标 11.2 —— 正好 0.7 倍）。
/// ★★ 2026-10-18（用户实测：矩阵空格子里"竖条有两行高"）：
/// 环境里的**空格子**没有任何字形 ⇒ `findLocalRowBox` 会退到"锚点那一行"的行盒，
/// 而那一行的行盒可能是**整个环境行**（矩阵里一行含多列、且高度被拉伸）⇒ 竖条过长。
/// 这里按"当地一行的合理高度"（字号 × 1.35）把它夹住，居中裁剪。
Rect? _clampRowHeight(Rect? r, double fontSize) {
  if (r == null) return null;
  final double maxH = fontSize * 1.35;
  if (r.height <= maxH || maxH <= 1) return r;
  return Rect.fromCenter(center: r.center, width: r.width, height: maxH);
}
Rect? findLocalRowBox(RenderObject root, Offset at, {RenderObject? anchor}) {
  final List<({Rect rect, double dx, RenderObject? row})> hits =
      <({Rect rect, double dx, RenderObject? row})>[];
  void walk(RenderObject o) {
    var hasChild = false;
    o.visitChildren((RenderObject c) {
      hasChild = true;
      walk(c);
    });
    if (hasChild || o is! RenderBox || !o.hasSize || o.size == Size.zero) return;
    if (!o.runtimeType.toString().contains('Paragraph')) return; // 只认字形盒
    final Rect r = o.localToGlobal(Offset.zero, ancestor: root) & o.size;
    hits.add((rect: r, dx: (r.center.dx - at.dx).abs(), row: rowOf(o, root)));
  }

  walk(root);

  // ★★ 2026-10-17：**被拉伸的行盒要按行高裁**（与 `hit_map` 同一条判据）。
  //   `\sum` 的字形盒是引擎给的行盒（实测高 **46** = 整个带上下限的算子节点）；
  //   把它当"当地那一行"⇒ 竖条高 38.6（用户："直接点末尾是**长蓝光标**"），
  //   而同一格按行高应该是 17.6 或 11.8。⇒ 高度超过**本段中位数 × 1.6** 的盒，
  //   竖直裁到中位数高（中心不变）后再参与选行。
  final double rowH = _medianHeight(hits);
  Rect clip(Rect r) => (rowH <= 0 || r.height <= rowH * 1.6)
      ? r
      : Rect.fromCenter(center: r.center, width: r.width, height: rowH);

  // ① 层优先：锚点那一行（及其后代行）里、且竖直含基线的字形盒
  final RenderObject? anchorRow = anchor == null ? null : rowOf(anchor, root);
  if (anchorRow != null) {
    ({Rect rect, double dx, RenderObject? row})? pick(double slack) {
      ({Rect rect, double dx, RenderObject? row})? best;
      for (final ({Rect rect, double dx, RenderObject? row}) h in hits) {
        if (!sameLayer(h.row, anchorRow)) continue;
        final Rect r = clip(h.rect);
        if (at.dy < r.top - slack || at.dy > r.bottom + slack) continue;
        if (best == null || h.dx < best.dx) best = (rect: r, dx: h.dx, row: h.row);
      }
      return best;
    }

    final ({Rect rect, double dx, RenderObject? row})? inRow = pick(0) ?? pick(2);
    if (inRow != null) return inRow.rect;

    // ★★ 2026-10-18：锚点那一行**一个字形都没有**（多行环境里的空格子：`aligned` / `cases` 的格子）
    //   ⇒ 直接用**那一行自己的行盒**当光标行。
    //   不补这一条会怎样（用户实测）：几何退路也找不到"含基线"的字形盒
    //   ⇒ 返回 null ⇒ 上层按"整个公式盒居中"画 ⇒ 竖条落在**两行之间**。
    if (anchorRow is RenderBox && anchorRow.hasSize && anchorRow.size.height > 0) {
      final Rect rowRect =
          anchorRow.localToGlobal(Offset.zero, ancestor: root) & anchorRow.size;
      return clip(rowRect);
    }
  }

  // ② 退路：纯几何（严格含基线 → ±2 px）
  ({Rect rect, double dx, RenderObject? row})? best;
  for (final ({Rect rect, double dx, RenderObject? row}) h in hits) {
    final Rect r = clip(h.rect);
    if (at.dy < r.top || at.dy > r.bottom) continue;
    if (best == null || h.dx < best.dx) best = (rect: r, dx: h.dx, row: h.row);
  }
  if (best == null) {
    for (final ({Rect rect, double dx, RenderObject? row}) h in hits) {
      final Rect r = clip(h.rect);
      if (at.dy < r.top - 2 || at.dy > r.bottom + 2) continue;
      if (best == null || h.dx < best.dx) best = (rect: r, dx: h.dx, row: h.row);
    }
  }
  return best?.rect;
}

/// 本段字形盒高度的**中位数**（用来认"被拉伸的行盒"，见 [findLocalRowBox]）
double _medianHeight(List<({Rect rect, double dx, RenderObject? row})> hits) {
  if (hits.isEmpty) return 0;
  final List<double> hs = <double>[for (final ({Rect rect, double dx, RenderObject? row}) h in hits) h.rect.height]
    ..sort();
  return hs[hs.length ~/ 2];
}

/// 一个**空槽占位垫**的矩形（Math 盒局部坐标）＋ 它是不是**当前槽**
class SlotPad {
  const SlotPad(this.rect, {required this.current});

  final Rect rect;
  final bool current;

  @override
  String toString() => 'SlotPad($rect${current ? ' · 当前槽' : ''})';
}

/// 空槽虚线 / 边界刻度的灰（§6.1 `#B0BEC5`）
const int kSlotDashColorValue = 0xFFB0BEC5;

/// 当前槽的淡蓝底（§6.1 `#E3F2FD`）
const int kSlotCurrentFillColorValue = 0xFFE3F2FD;

/// ★★ 在渲染子树里认出**我们注入的空槽垫子**，给出它们的矩形（④-1）。
///
/// **判据（两条都要满足 —— 都是"认渲染事实"，与 `leaf_boxes` 那四条同一层）**：
///   ① **宽度垫**：`_RenderColoredBox`、**高 ≈ 0**、宽 ≥ [kMinLeafWidth]；
///   ② 它**左边紧邻**的那个叶盒是 `RenderParagraph`，¶ 文本**恰好是** [kSlotPadGlyph]，
///      且两者 x 相接（≤ 0.75 px）。
/// ① 把"光标锚点"（0×0）滤掉；② 把"结构尾垫"（左边是内容字形，如 `2`）滤掉。
///
/// ★★ **矩形要夹进"槽带"**（2026-10-17 用户实测："分母的虚线框上边跑到分子区去了"）：
/// 字形盒是**字体行高盒**，比槽带高得多 —— 实测（真实 KaTeX 字体、字号 20）行间分式里
/// 分母的垫子盒 24.5..55.5（**31 px 高**，而分母那格只有 ~19 px）⇒ 上沿直接压到分数线上。
/// 所以盒 = `字形盒 ∪ 宽度垫盒`，再按下面三条**夹**（全部来自渲染树实测，不猜）：
///   ① **父结构节点**的盒（`_FracPos` / `_SqrtPos` / `_ScriptPos` / `RelativeWidthColumn`…）
///      ⇒ 框不许比它所在的结构还大；
///   ② **同结构里别的槽的内容盒**：垫子在它上方 ⇒ 下沿 ≤ 它上沿 − margin；
///      在下方 ⇒ 上沿 ≥ 它下沿 + margin ⇒ "别的槽占着的地方不画"；
///   ③ margin = 盒高的 12%（≈0.13em）⇒ 给那条**装饰线**（分数线 / 根号横线）让位。
/// ②③ 就是"不同结构、不同位置各不一样"的**自适应**：它跟着**邻居的实际内容**走。
///
/// [caretAt] 给了就顺便判"当前槽"：锚点落在哪个垫子盒里，哪个就是当前槽
/// （空槽里锚点正好落在垫子右缘 ⇒ 用 `inflate(1)`；实测分母的垫子**不**含这个锚点）。
List<SlotPad> scanSlotPads(RenderObject root, {Offset? caretAt}) {
  final List<({Rect rect, String type, String? glyph, RenderObject obj})> leaves =
      <({Rect rect, String type, String? glyph, RenderObject obj})>[];

  void walk(RenderObject o) {
    var hasChild = false;
    o.visitChildren((RenderObject c) {
      hasChild = true;
      walk(c);
    });
    if (hasChild || o is! RenderBox || !o.hasSize) return;
    final Rect r = o.localToGlobal(Offset.zero, ancestor: root) & o.size;
    leaves.add((
      rect: r,
      type: o.runtimeType.toString(),
      glyph: o is RenderParagraph ? o.text.toPlainText() : null,
      obj: o,
    ));
  }

  walk(root);

  // ── 先认出全部垫子（字形盒 ∪ 宽度垫盒）────────────────────────────
  final List<({Rect rect, RenderObject glyph})> pads =
      <({Rect rect, RenderObject glyph})>[];
  for (var i = 1; i < leaves.length; i++) {
    final ({Rect rect, String type, String? glyph, RenderObject obj}) filler =
        leaves[i];
    if (filler.rect.height.abs() > 0.5) continue; // ① 零高
    if (filler.rect.width < kMinLeafWidth) continue; // ① 不是锚点（0 宽）
    if (!filler.type.contains('ColoredBox')) continue; // ① 是"填色盒"（`\rule` 的画法）
    final ({Rect rect, String type, String? glyph, RenderObject obj}) glyph =
        leaves[i - 1];
    if (glyph.glyph != kSlotPadGlyph) continue; // ② 左边是我们垫的字形
    // ★ ②"紧邻"要留余量：**斜体字形盒与宽度垫之间天然有 1–2px 空隙**
    //   （实测真实字体：`M` 盒右缘 12.8 / 垫左缘 14.0；字号 20 时 21.8 / 24.0）
    if (glyph.rect.right - filler.rect.left > math.max(3.0, glyph.rect.height * 0.2)) {
      continue;
    }
    if (filler.rect.left - glyph.rect.right > math.max(3.0, glyph.rect.height * 0.2)) {
      continue; // 垫子在字形**左边** ⇒ 不是我们的写法
    }
    pads.add((rect: glyph.rect.expandToInclude(filler.rect), glyph: glyph.obj));
  }

  // ── 再逐个夹进"槽带" ──────────────────────────────────────────
  final List<Rect> allPadRects = <Rect>[for (final p in pads) p.rect];
  final List<SlotPad> out = <SlotPad>[];
  for (var i = 0; i < pads.length; i++) {
    final ({Rect rect, RenderObject glyph}) p = pads[i];
    final Rect r = _clipToSlotBand(
      root: root,
      glyph: p.glyph,
      box: p.rect,
      leaves: leaves,
      padRects: allPadRects.toSet(),
      otherPads: <Rect>[
        for (var k = 0; k < allPadRects.length; k++)
          if (k != i) allPadRects[k],
      ],
    );
    out.add(SlotPad(r, current: caretAt != null && r.inflate(1.0).contains(caretAt)));
  }
  return out;
}

/// 结构承载节点的类型判据（与 `structure_geometry.collectStructureNodes` 同一张名单，
/// 但这里**不能**调那个函数：它返回节点表，而我们要的是"**最近的祖先**"）
bool _isStructureNode(String type) =>
    type.contains('CustomLayout') ||
    type.contains('RelativeWidthColumn') ||
    type.contains('EqnArray');

/// 把垫子的盒**夹进它所在的那个槽带**（见 [scanSlotPads] 的说明）。
///
/// 拿不到父结构节点（例如**空公式**，它上面没有任何结构）⇒ 原样返回 `box`。
Rect _clipToSlotBand({
  required RenderObject root,
  required RenderObject glyph,
  required Rect box,
  required List<({Rect rect, String type, String? glyph, RenderObject obj})> leaves,
  required Set<Rect> padRects,
  required List<Rect> otherPads,
}) {
  RenderObject? n = glyph.parent;
  while (n != null && !_isStructureNode(n.runtimeType.toString())) {
    n = n.parent;
  }
  if (n is! RenderBox || !n.hasSize) return box;
  final Rect nodeRect = n.localToGlobal(Offset.zero, ancestor: root) & n.size;

  Rect band = box;
  // ① 父结构节点的盒
  final Rect clamped = box.intersect(nodeRect);
  if (clamped.width > 0.5 && clamped.height > 0.5) band = clamped;

  // ② 同结构里**别的槽的内容**（同结构子树内的叶盒，去掉所有垫子自己）
  Rect? others;
  void collect(RenderObject o) {
    var hasChild = false;
    o.visitChildren((RenderObject c) {
      hasChild = true;
      collect(c);
    });
    if (hasChild || o is! RenderBox || !o.hasSize) return;
    final Rect r = o.localToGlobal(Offset.zero, ancestor: root) & o.size;
    if (padRects.contains(r)) return; // 是垫子（我们注入的）⇒ 不算"别的内容"
    others = others == null ? r : others!.expandToInclude(r);
  }

  collect(n);
  final double margin = box.height * 0.12;
  if (others != null) {
    final Rect u = others!;
    if (box.center.dy <= u.center.dy) {
      // 垫子在上方 ⇒ 下沿不许越到"下面的内容"上边
      final double bottom = math.min(band.bottom, u.top - margin);
      if (bottom > band.top + 1) {
        band = Rect.fromLTRB(band.left, band.top, band.right, bottom);
      }
    } else {
      final double top = math.max(band.top, u.bottom + margin);
      if (top < band.bottom - 1) {
        band = Rect.fromLTRB(band.left, top, band.right, band.bottom);
      }
    }
  }

  // ③ ★★ **空槽对空槽**：同一结构里两个槽都空时，上面的判据没有任何"内容"可依
  //   —— 实测（真实字体）`\int_{}^{}` 的两个上限框重叠 1px、`\frac{\frac{}{}}{b}` 里
  //   内层的两个框把**中间的分数线盖住**。⇒ 与**另一个垫子**之间也留同样的余量。
  for (final Rect q in otherPads) {
    if (q.left >= band.right || q.right <= band.left) continue; // 水平不相交 ⇒ 各管各的
    if (q.center.dy > box.center.dy) {
      final double bottom = math.min(band.bottom, q.top - margin);
      if (bottom > band.top + 1) {
        band = Rect.fromLTRB(band.left, band.top, band.right, bottom);
      }
    } else {
      final double top = math.max(band.top, q.bottom + margin);
      if (top < band.bottom - 1) {
        band = Rect.fromLTRB(band.left, top, band.right, band.bottom);
      }
    }
  }
  return band;
}

/// 画**竖条 ＋ 空槽占位框 ＋ 瞬时边界刻度**（三者同一支画笔，一次 `CustomPaint`）
class MathCaretPainter extends CustomPainter {
  const MathCaretPainter({
    required this.rect,
    required this.color,
    this.caretVisible = true,
    this.pads = const <SlotPad>[],
    this.tick,
    this.dashUnit = 1.0,
    this.bands = const <Rect>[],
  });

  /// 竖条的矩形（[caretVisible] 为 `false` 时无意义）
  final Rect rect;
  final Color color;

  /// 竖条在不在（`false` = 光标不在这段里 ⇒ 只画垫子 / 刻度）
  final bool caretVisible;

  /// 空槽占位垫（④-1）：空槽 ⇒ 虚线灰框；当前槽 ⇒ 实线蓝框 ＋ 淡蓝底
  final List<SlotPad> pads;

  /// ★ ④-4「甲」**瞬时边界刻度**（只出现在"公式之前 / 之后"那两格；离开即消失）
  final Rect? tick;

  /// 虚线的尺度（= 本段字号 / 16 ⇒ 跟随字号，不写死像素）
  final double dashUnit;

  /// **选区高亮的底色块**（⑤）：按原子铺，交给 `hit_map.selectionBands` 算好
  final List<Rect> bands;

  @override
  void paint(Canvas canvas, Size size) {
    // ★ 选区底色先铺（在垫子与竖条**之下**）
    if (bands.isNotEmpty) {
      final Paint sel = Paint()..color = const Color(kSelectionColorValue);
      for (final Rect r in bands) {
        canvas.drawRect(r, sel);
      }
    }
    for (final SlotPad p in pads) {
      final Rect r = p.rect.deflate(0.5);
      final Paint stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = Color(p.current ? kCaretColorValue : kSlotDashColorValue);
      if (p.current) {
        // 当前槽：实线 + 淡蓝底（§6.1）。底色先铺，再描边
        canvas.drawRect(
          p.rect,
          Paint()..color = const Color(kSlotCurrentFillColorValue),
        );
        canvas.drawRect(r, stroke);
      } else {
        // 空槽：1px 虚线（引擎画不出来 ⇒ 自己走线）
        _dashRect(canvas, r, stroke, 3.0 * dashUnit, 2.0 * dashUnit);
      }
    }
    if (caretVisible) canvas.drawRect(rect, Paint()..color = color);
    final Rect? t = tick;
    if (t != null) {
      canvas.drawRect(t, Paint()..color = const Color(kSlotDashColorValue));
    }
  }

  @override
  bool shouldRepaint(MathCaretPainter old) =>
      old.rect != rect ||
      old.color != color ||
      old.caretVisible != caretVisible ||
      old.tick != tick ||
      old.dashUnit != dashUnit ||
      !sameRects(old.bands, bands) ||
      !_samePads(old.pads, pads);

  /// 选区底块比较（`_measure` 也要用，所以 public）
  static bool sameRects(List<Rect> a, List<Rect> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _samePads(List<SlotPad> a, List<SlotPad> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].rect != b[i].rect || a[i].current != b[i].current) return false;
    }
    return true;
  }
}

/// 一个矩形的**1px 虚线**（Flutter 的 `Canvas` 没有 dash ⇒ 自己沿四条边走线）
void _dashRect(Canvas canvas, Rect r, Paint p, double dash, double gap) {
  if (r.width <= 0 || r.height <= 0) return;
  _dashLine(canvas, r.topLeft, r.topRight, p, dash, gap);
  _dashLine(canvas, r.topRight, r.bottomRight, p, dash, gap);
  _dashLine(canvas, r.bottomRight, r.bottomLeft, p, dash, gap);
  _dashLine(canvas, r.bottomLeft, r.topLeft, p, dash, gap);
}

void _dashLine(Canvas canvas, Offset a, Offset b, Paint p, double dash, double gap) {
  final double total = (b - a).distance;
  if (total <= 0 || dash <= 0) return;
  final Offset dir = (b - a) / total;
  var t = 0.0;
  while (t < total) {
    final double end = math.min(t + dash, total);
    canvas.drawLine(a + dir * t, a + dir * end, p);
    t = end + gap;
  }
}
