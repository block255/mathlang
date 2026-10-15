// 数语引擎 · 数学段里的**光标**：零尺寸锚点 + 自绘竖条
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
// ★ 现在的做法（用户拍板「高度可控 + 不参与排版」）：
//   · tex 里只注入一个**零宽零高**的锚点（`kCursorTex`，见 `caret_sites.dart`）
//     —— 它只负责**给出精确坐标**，一个像素的版面都不占；
//   · 竖条由本文件**叠一层自绘**：`CustomPaint` 的 `foregroundPainter`，
//     高度、粗细、竖直位置都由我们定（与文本侧光标一致：同色、同高 `字号 × 1.25`）。
//   ★ `CustomPaint` 是 `RenderProxyBox` ⇒ **基线照旧透传**（`MathAlignMode.baseline` 不受影响），
//     尺寸 = 子节点尺寸 ⇒ 行内排版**完全不变**。
//
// **纯 Dart + Flutter（无第三方依赖）。**

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

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
    this.onErrorFallback = Math.defaultOnErrorFallback,
  });

  /// **渲染 tex**（已经过注入链：空槽占位 + 锚点）
  final String tex;

  /// 光标在不在这段数学里（不在 ⇒ 连竖条也不画）
  final bool showCaret;

  /// 给内层 `Math` 的 key（命中测试要用它取 RenderObject）
  final GlobalKey mathKey;

  final double fontSize;
  final MathStyle mathStyle;
  final double caretWidth;
  final OnErrorFallback onErrorFallback;

  @override
  State<MathWithCaret> createState() => _MathWithCaretState();
}

class _MathWithCaretState extends State<MathWithCaret> {
  /// 锚点相对本盒的位置（帧末量出来；`null` = 还没量到）
  Offset? _anchor;

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
    final Offset p = anchor.localToGlobal(Offset.zero, ancestor: root);
    if (_anchor == null || (_anchor! - p).distance > 0.01) {
      setState(() => _anchor = p);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double h = widget.fontSize * 1.25; // ★ 与文本侧光标同高（`_caretBar`）
    return CustomPaint(
      foregroundPainter: (widget.showCaret && _anchor != null)
          ? _CaretPainter(
              at: _anchor!,
              height: h,
              width: widget.caretWidth,
              color: const Color(kCaretColorValue),
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

/// 画那根竖条：**底部在基线上（稍越过一点）、往上 0.85 高**（与文本编辑器的手感一致）
class _CaretPainter extends CustomPainter {
  const _CaretPainter({
    required this.at,
    required this.height,
    required this.width,
    required this.color,
  });

  final Offset at;
  final double height;
  final double width;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // ★ 锚点的 y 就是**这一行的基线**（实测：`\hat{x}` 11.1 / 分式里在分母那一行 28.7 /
    //   求和式主行 26.4 —— 都落在它所在那一行的基线上）⇒ 竖条从基线往上画、稍微越过基线一点。
    final double bottom = at.dy + height * 0.15;
    canvas.drawRect(
      Rect.fromLTWH(at.dx, bottom - height, width, height),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_CaretPainter old) =>
      old.at != at ||
      old.height != height ||
      old.width != width ||
      old.color != color;
}
