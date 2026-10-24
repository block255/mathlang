// ★★ 2026-10-24（批 3 · D3）：**空格子也要有自己的框**（框 = 列带 × 行带，不是"整列并集"）。
//
// 用户复验（2026-10-24）：E4/D2 都好了，剩下的其实是**框**的问题——
//   「第一排框在这里；第二排框却在这里；点正确的位置反而不出框」。
//
// 两条根因（都在 `buildEnvGrid`）：
//   ① 格子矩形只从"有墨迹的格子"里量 ⇒ **空格子没有矩形** ⇒ 框只能退到"整列并集"
//      ⇒ 框会跑到"别的行有内容的那一列"上，而且 `math_caret` 还要 `box.contains(点击点)` 才画框
//      ⇒ 点到"本该有框的地方"反而不出框；
//   ② 整片都没墨迹的环境（刚插出来的 `cases`）⇒ `cellRect.isEmpty` ⇒ 旧代码直接 `return null`
//      ⇒ 那种块**一个框都不画**。
//
// 修法：① 空格子的矩形 = 列带 ∩ 行带（并记进 `synthetic`，**不算"点在墨迹上"**）；
//      ② 全空环境按"根盒 ÷ 行列数"均分，照样给出网格。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/env_cells.dart';
import 'package:mathlang/render/slot_marks.dart';

import '../support/math_fonts.dart';

Future<EnvGrid?> _grid(WidgetTester tester, String tex, {int caretRel = -1}) async {
  final String injected =
      renderMathTex(tex, caretRel: caretRel, showCursor: caretRel >= 0);
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

  testWidgets('★ 全空的分段函数（刚插出来）也要有网格与框', (WidgetTester tester) async {
    const String tex = r'\begin{cases}&\\&\end{cases}';
    final EnvGrid? g = await _grid(tester, tex);
    expect(g, isNotNull, reason: '改前这里返回 null ⇒ 一个框都不画');
    expect(g!.maxRow, 1);
    expect(g.maxCol, 1);
    for (var r = 0; r <= 1; r++) {
      for (var c = 0; c <= 1; c++) {
        expect(envCellBoxIn(g, r, c), isNotNull, reason: 'cell($r,$c) 要有框');
      }
    }
    // 两列各占一半
    final Rect left = envCellBoxIn(g, 1, 0)!;
    final Rect right = envCellBoxIn(g, 1, 1)!;
    expect(left.right, lessThanOrEqualTo(right.left + 0.01),
        reason: '同一行两列不许重叠：$left / $right');
    expect(left.width, closeTo(right.width, 0.01));
  });

  testWidgets('★ 第一段有字、第二段空：第二段第一格的框在**左半边**、点得中', (WidgetTester tester) async {
    const String tex = r'\begin{cases}1,&x\in Q\\&\end{cases}';
    final EnvGrid? g = await _grid(tester, tex, caretRel: 13);
    expect(g, isNotNull);
    final Rect? box = envCellBoxIn(g!, 1, 0);
    expect(box, isNotNull, reason: '改前 cell(1,0) 是 null');
    expect(box!.left, closeTo(g.colBand[0]!.left, 0.01),
        reason: '框的左边 = 第 0 列的列带左界（不是整列并集跑到右边）');
    expect(box.top, closeTo(g.rowBand[1]!.top, 0.01));

    final EnvCellHit? hit = envCellHitIn(g, box.center);
    expect(hit?.row, 1);
    expect(hit?.col, 0);
    expect(hit?.onInk, isFalse, reason: '空格子不是"点在墨迹上"（`onInk` 口径不许被补出来的格子污染）');

    // 第一段（有字）仍然算"点在墨迹上"
    final EnvCellHit? ink = envCellHitIn(g, g.cell(0, 0)!.center);
    expect(ink?.row, 0);
    expect(ink?.onInk, isTrue);
  });

  testWidgets('★ 回归：全填满的矩阵，每个格子都还"点在墨迹上"',
      (WidgetTester tester) async {
    const String tex = r'\begin{pmatrix}A&B\\C&D\end{pmatrix}';
    final EnvGrid? g = await _grid(tester, tex);
    expect(g, isNotNull);
    for (var r = 0; r <= 1; r++) {
      for (var c = 0; c <= 1; c++) {
        final EnvCellHit? hit = envCellHitIn(g!, g.cell(r, c)!.center);
        expect(hit?.row, r, reason: 'cell($r,$c)');
        expect(hit?.col, c, reason: 'cell($r,$c)');
        expect(hit?.onInk, isTrue, reason: 'cell($r,$c) 有字 ⇒ 必须算"点在墨迹上"');
      }
    }
  });
}
