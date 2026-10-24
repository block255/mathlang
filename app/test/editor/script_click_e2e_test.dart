// ★★ 2026-10-24（批 4c · G2）**端到端**：真实指针点在 `x^{3}` 上，落点必须是"对象"那一层
//
// 单测 `script_click_outer_test` 钉的是判据；这条钉的是**接线**（`doc_view._mathTapTexOffset`）。
// 用户原话：「点 `x` 与 `3` 之间只能点到 `3` 的左边」「在 `x^{3}` 后面加东西只能点到 `3` 后面」。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/leaf_boxes.dart';
import 'package:mathlang/render/math_caret.dart';

import '../support/math_fonts.dart';

Future<DocBuffer> _pump(WidgetTester tester, String tex) async {
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer('\$\$\n$tex\n\$\$')..setCaret(0);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
  ));
  tester.state<EditViewState>(find.byType(EditView)).focusInput();
  await tester.pumpAndSettle();
  return buf;
}

void main() {
  setUpAll(() async => loadMathFonts());

  const String tex = r'x^{3}+1';

  testWidgets(r'★ 点 `3` 的左半边 ⇒ 落到**底数层**（`x` 之后 = tex 1），不是指数里',
      (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, tex);
    final RenderBox root =
        find.byType(MathWithCaret).last.evaluate().single.renderObject! as RenderBox;
    final Rect three =
        scanLeafBoxes(root).eligible.firstWhere((LeafBox b) => b.text == '3').rect;
    buf.setCaret(0);
    await tester.pumpAndSettle();
    await tester.tapAt(root.localToGlobal(Offset(three.left + 1.5, three.center.dy)));
    await tester.pumpAndSettle();
    expect(buf.caret, 3 + 1,
        reason: '点 3 左半 ⇒ 对象之前（`x` 之后），实际 tex 偏移 ${buf.caret - 3}');
  });

  testWidgets(r'★ 点 `3` 的右半边 ⇒ 落到**对象之后**（tex 5，能接着打 `+`）',
      (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, tex);
    final RenderBox root =
        find.byType(MathWithCaret).last.evaluate().single.renderObject! as RenderBox;
    final Rect three =
        scanLeafBoxes(root).eligible.firstWhere((LeafBox b) => b.text == '3').rect;
    buf.setCaret(0);
    await tester.pumpAndSettle();
    await tester.tapAt(root.localToGlobal(Offset(three.right - 1.0, three.center.dy)));
    await tester.pumpAndSettle();
    expect(buf.caret, 3 + 5,
        reason: '点 3 右半 ⇒ 整个 x^{3} 之后，实际 tex 偏移 ${buf.caret - 3}');
  });

  testWidgets('★ 对照：点普通字母 `1`（不是脚本）⇒ 行为不变', (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, tex);
    final RenderBox root =
        find.byType(MathWithCaret).last.evaluate().single.renderObject! as RenderBox;
    final Rect one =
        scanLeafBoxes(root).eligible.firstWhere((LeafBox b) => b.text == '1').rect;
    buf.setCaret(0);
    await tester.pumpAndSettle();
    await tester.tapAt(root.localToGlobal(Offset(one.right - 1.0, one.center.dy)));
    await tester.pumpAndSettle();
    expect(buf.caret, 3 + 7, reason: '`1` 的右半 ⇒ 它之后（公式末尾），实际 ${buf.caret - 3}');
  });
}
