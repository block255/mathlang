// ★★ 2026-10-24（批 3 · E4）：**空行也要在环境网格里**（否则"分段的第二段点不到"）。
//
// 用户原话：「分段的第二段我鼠标好像点不到」。
// 实测根因：`buildEnvGrid` 的行带只从"有墨迹的格子"（cellRect）+ 基线下标（零高垫子）里算；
//   一个**整行都没有字**的行（`cases` 的第二段、矩阵的空行）既没有墨迹、垫子也常配不上
//   ⇒ `rowBand` 里**根本没有那一行** ⇒ 点它会被"最近中心"落到别的行
//   （实测 `\begin{cases}1,&x\in Q\\&\end{cases}` 只有 1 条行带，点第二段判成第 1 段）。
//
// 修法：一个基线锚点都没有时，用引擎自己的行格 —— **根盒高 = 行数 × 行距**、
//   **首行基线 = 0.7 × 行距**（两条都是 2026-10-19 实测过的常量）。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/env_cells.dart';
import 'package:mathlang/render/slot_marks.dart';

import '../support/math_fonts.dart';

/// 渲染（走**真实注入链**，与 `doc_view` 一致）并量出网格
Future<EnvGrid?> _grid(WidgetTester tester, String tex) async {
  final String injected = renderMathTex(tex, caretRel: -1, showCursor: false);
  await tester.pumpWidget(MaterialApp(
    home: Center(
      child: Math.tex(injected,
          mathStyle: MathStyle.display,
          textStyle: const TextStyle(fontSize: 20)),
    ),
  ));
  await tester.pumpAndSettle();
  final RenderObject root = tester.renderObject(find.byType(Math));
  return buildEnvGrid(root: root, tex: tex, displayStyle: true, fontSize: 20);
}

void main() {
  setUpAll(() async => loadMathFonts());

  testWidgets(r'分段函数第二段是空的 ⇒ 仍然要有一整条行带，且点得到', (WidgetTester tester) async {
    const String tex = r'\begin{cases}1,&x\in Q\\&\end{cases}';
    final EnvGrid? g = await _grid(tester, tex);
    expect(g, isNotNull);
    expect(g!.maxRow, 1, reason: '两个段（第二段空）');
    expect(g.rowBand[0], isNotNull);
    expect(g.rowBand[1], isNotNull, reason: '改前这一格是 null ⇒ 第二段点不到');

    final Rect band1 = g.rowBand[1]!;
    final Offset p = Offset(g.colBand[0]!.left + 2, band1.center.dy);
    final EnvCellHit? hit = envCellHitIn(g, p);
    expect(hit, isNotNull);
    expect(hit!.row, 1, reason: '点第二段就该落在第二段：$hit');
  });

  testWidgets('三段（后两段空）⇒ 三条行带，逐段点得中', (WidgetTester tester) async {
    const String tex = r'\begin{cases}1,&x>0\\&-1\\&0\end{cases}';
    final EnvGrid? g = await _grid(tester, tex);
    expect(g, isNotNull);
    expect(g!.maxRow, 2);
    for (var r = 0; r <= 2; r++) {
      expect(g.rowBand[r], isNotNull, reason: 'row$r');
      final EnvCellHit? hit = envCellHitIn(
          g, Offset(g.colBand[0]!.left + 2, g.rowBand[r]!.center.dy));
      expect(hit?.row, r, reason: '点 row$r 中心 ⇒ $hit');
    }
  });

  testWidgets('★ 回归：全填满的矩阵网格不变（行带仍按基线 + 行距）', (WidgetTester tester) async {
    const String tex = r'\begin{pmatrix}A&B\\C&D\end{pmatrix}';
    final EnvGrid? g = await _grid(tester, tex);
    expect(g, isNotNull);
    expect(g!.maxRow, 1);
    expect(g.maxCol, 1);
    expect(g.rowBand[0]!.height, closeTo(g.rowBand[1]!.height, 0.01),
        reason: '等高、铺满（既有口径）');
    expect(g.rowBand[0]!.bottom, closeTo(g.rowBand[1]!.top, 0.01),
        reason: '行带首尾相接、不重叠');
    final EnvCellHit? hit = envCellHitIn(
        g, Offset(g.colBand[1]!.center.dx, g.rowBand[1]!.center.dy));
    expect(hit?.row, 1);
    expect(hit?.col, 1);
  });
}
