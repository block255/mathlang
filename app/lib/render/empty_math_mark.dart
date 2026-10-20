// 数语引擎 · **空公式的可见标记**（§6.1.1，2026-10-18 落地）
//
// ============================ 它解决什么 ============================
// §4.6（2026-10-15 用户拍板）：在公式**内部**把内容删光时**不删定界符**，留一个空壳
//   —— 理由很硬：删掉一个字要能接着重打，而且"不许偷偷把用户看不见的定界符收走"。
//
// 而空壳在渲染上是**零尺寸**：`$ $` 里的空格不占版面、也没有字形盒 ⇒
//   **看不见、点不到**，只能靠"再按一次退格"清掉（用户当时实测就撞到"按了没反应"）。
// ⇒ §6.1.1 要求：**空公式必须画出来**。这里就是那个"看得见"的实现：
//   一个 1px 淡虚线小框（与空槽同一支笔 `#B0BEC5`），光标在里面时再画一根蓝竖条。
//
// ★★ 2026-10-18 补一条背景（用户指出"平权不该支持打空公式壳"）：
//   「**主动造空壳**」的两个入口（`Alt+=` / `Ctrl+Alt+E`）**已撤掉** —— 数学由**内容**产生
//   （面板符号自动建壳 / `/` 成分式 / 词触发成模板 / 粘贴走智能包裹）。
//   于是空壳只剩**一个**来源：**删到空**。既然它必然存在，就必须可见、可点、可删。
//
// ★ 它是一个**内联尺寸盒**（有真实宽高）⇒ 会参与行内排版。这是有意的：
//   不可见的零宽"对象"才是不该存在的（既点不到，也不该占位置却看不见）。

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'caret_sites.dart' show kCaretColorValue;

/// 空公式的占位框（虚线小方框；可选画光标）
class EmptyMathMark extends StatelessWidget {
  const EmptyMathMark({
    super.key,
    required this.width,
    required this.height,
    this.showCaret = false,
    this.caretWidth = 1.5,
    this.color = const Color(0xFFB0BEC5),
    this.caretColor = const Color(kCaretColorValue),
    this.showEditingAids = true,
  });

  /// ★★ 2026-10-20（T-C 实测 F16）：**要不要画这个虚线小框**。
  ///
  /// 它是"空公式的可见标记"（§6.1.1：空壳必须可见、可点、可删）—— 那是**编辑态**的需要；
  /// 导出 PDF / 图片集时它是**纸面上的噪点**（实测：一个空的行间公式 ⇒ 导出的纸上
  /// 出现一个莫名其妙的虚线方框）。`DocView` 抓图时传 `false`。
  ///
  /// ★ 尺寸照旧（它是有真实宽高的内联盒，参与排版）—— 只是**不画**
  ///   ⇒ 导出不会因为"藏了它"而改变版面（版面中性）。
  final bool showEditingAids;

  /// 宽度（空公式按"一个正文汉字宽"画；见调用方）
  final double width;

  /// 高度（空公式按**当地那一行**的高度画，与光标同一标准）
  final double height;

  /// 光标是否落在这个空公式里（落进来就画竖条）
  final bool showCaret;

  final double caretWidth;
  final Color color;
  final Color caretColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        // ★ F16：导出抓图时不画笔（尺寸照旧 ⇒ 版面中性）
        painter: showEditingAids
            ? _EmptyMathPainter(
                color: color,
                showCaret: showCaret,
                caretWidth: caretWidth,
                caretColor: caretColor,
              )
            : null,
      ),
    );
  }
}

class _EmptyMathPainter extends CustomPainter {
  const _EmptyMathPainter({
    required this.color,
    required this.showCaret,
    required this.caretWidth,
    required this.caretColor,
  });

  final Color color;
  final bool showCaret;
  final double caretWidth;
  final Color caretColor;

  @override
  void paint(Canvas canvas, Size size) {
    // 虚线小框（四周内缩 0.5，免得 1px 描边被裁掉一半）
    final Rect r = Rect.fromLTWH(
      0.5,
      0.5,
      (size.width - 1).clamp(0.0, double.infinity),
      (size.height - 1).clamp(0.0, double.infinity),
    );
    if (r.width > 0 && r.height > 0) {
      final Paint p = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      _drawDashedRect(canvas, r, p);
    }
    if (showCaret) {
      final Paint c = Paint()..color = caretColor;
      final double h = size.height;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, caretWidth, h),
        c,
      );
    }
  }

  /// 虚线矩形（手画，比 `PathEffect` 好调：3 亮 3 暗）
  void _drawDashedRect(Canvas canvas, Rect r, Paint paint) {
    const double dash = 3;
    const double gap = 3;
    void line(Offset a, Offset b) {
      final double dx = b.dx - a.dx;
      final double dy = b.dy - a.dy;
      final double total = math.sqrt(dx * dx + dy * dy);
      if (total <= 0) return;
      final double ux = dx / total;
      final double uy = dy / total;
      var t = 0.0;
      while (t < total) {
        final double t2 = (t + dash) < total ? t + dash : total;
        canvas.drawLine(
          Offset(a.dx + ux * t, a.dy + uy * t),
          Offset(a.dx + ux * t2, a.dy + uy * t2),
          paint,
        );
        t = t2 + gap;
      }
    }

    line(r.topLeft, Offset(r.right, r.top));
    line(Offset(r.right, r.top), r.bottomRight);
    line(r.bottomRight, Offset(r.left, r.bottom));
    line(Offset(r.left, r.bottom), r.topLeft);
  }

  @override
  bool shouldRepaint(_EmptyMathPainter old) =>
      old.color != color ||
      old.showCaret != showCaret ||
      old.caretWidth != caretWidth ||
      old.caretColor != caretColor;
}
