// 守卫测试：**多行环境的点击按格子判落点**（P2-D，2026-10-18 用户实测）
//
// 现象：`aligned` 里想点第一行等号左侧，必须离等号非常近；点远一点就落到**第二个等号**旁边
//   （因为一行里只有 `=` 有墨迹，"最近字形"判据把它吸过去了）。
// 判据：先按**格子的矩形**认行列，再在格子内按 x 定"内容首 / 尾"。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/env_cells.dart';
import 'package:mathlang/render/leaf_boxes.dart';
import 'package:mathlang/render/slot_marks.dart';

Future<RenderBox> _pump(WidgetTester tester, String tex, GlobalKey key) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: Math.tex(tex,
            key: key,
            mathStyle: MathStyle.display,
            textStyle: const TextStyle(fontSize: 16)),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return key.currentContext!.findRenderObject()! as RenderBox;
}

void main() {
  const String base = r'\begin{aligned}a&=b\\c&=d\end{aligned}';

  testWidgets('点第二行左侧 ⇒ 落在第二行左格（不被第一行的等号吸走）',
      (WidgetTester tester) async {
    final GlobalKey key = GlobalKey();
    final RenderBox ro = await _pump(tester, renderMathTex(base, caretRel: -1), key);
    final LeafBoxScan scan = scanLeafBoxes(ro);

    // 两行各自的 `=`（col=1）与左侧字母（col=0）
    final List<LeafBox> equals =
        scan.all.where((LeafBox b) => b.text == '=').toList()
          ..sort((LeafBox a, LeafBox b) => a.rect.top.compareTo(b.rect.top));
    expect(equals.length, 2);
    final Rect row2Eq = equals.last.rect;

    // 第 2 行左侧空白：x 取该行 `=` 左边一点（第一行等号的正下方偏左）
    final Offset tap = Offset(row2Eq.left - 18, row2Eq.center.dy);
    final EnvCellHit? hit = envCellHitAt(
      root: ro,
      localPos: tap,
      tex: base,
      displayStyle: true,
    );
    expect(hit, isNotNull);
    expect(hit!.row, 1, reason: 'y 落在第二行 ⇒ 行号 1');
    expect(hit.col, 0, reason: 'x 在等号左侧 ⇒ 左格（col 0），不是等号所在列');

    // 换成源空间偏移后，应落在第二行左格里
    final int? off = envCellOffset(base, hit);
    expect(off, isNotNull);
    final CaretSiteTable t = buildCaretSites(base);
    final SlotSpan cell = t.slots.firstWhere((SlotSpan s) =>
        s.path.last.row == 1 && s.path.last.col == 0);
    expect(off, anyOf(cell.start, cell.end));
  });

  testWidgets('点第一行等号右侧 ⇒ 落在第一行右格', (WidgetTester tester) async {
    final GlobalKey key = GlobalKey();
    final RenderBox ro = await _pump(tester, renderMathTex(base, caretRel: -1), key);
    final LeafBoxScan scan = scanLeafBoxes(ro);
    final List<LeafBox> equals =
        scan.all.where((LeafBox b) => b.text == '=').toList()
          ..sort((LeafBox a, LeafBox b) => a.rect.top.compareTo(b.rect.top));
    final Rect row1Eq = equals.first.rect;
    final EnvCellHit? hit = envCellHitAt(
      root: ro,
      localPos: Offset(row1Eq.right + 4, row1Eq.center.dy),
      tex: base,
      displayStyle: true,
    );
    expect(hit, isNotNull);
    expect(hit!.row, 0);
    expect(hit.col, 1);
  });
}
