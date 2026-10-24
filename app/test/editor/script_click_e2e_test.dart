// ★★ 2026-10-24（批 4c · D5 / 批 8 修订）**端到端**：`x^{3}` 上"字形内"与"字形外"落点不同
//
// 用户先后提了两条**方向相反**的要求，只能靠位置分开：
//   · D5：「在 `x^{3}` 后面加东西，只能点到 `3` 后面，点不到这个指数的后面」
//   · 批 8：「`3` 后面也点不到，点后面一定是整个指数的后面」
// ⇒ 口径（批 8）：
//   · 点在 **`3` 的字形盒内** ⇒ 细粒度（左半 = `3` 之前 9、右半 = `3` 之后 10）
//   · 点在 **字形盒外**（右缘那 1px 缝起、外扩/行内宽容认领的 8px 内）⇒ 对象之前(1)/之后(11)
//
// 单测 `script_click_outer_test` 钉的是位点表判据；这条钉的是**接线**（`doc_view._mathTapTexOffset`）。

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

  testWidgets(r'★ 点 `3` 的**右半**（字形盒内）⇒ 落在指数里（`3` 之后，tex 4）',
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
    expect(buf.caret, 3 + 4,
        reason: '点 3 右半 ⇒ `3` 之后（指数内），实际 tex 偏移 ${buf.caret - 3}；'
            '改前被"对象层"规则抢成 5');
  });

  testWidgets(r'★ 点 `3` 的**左半**（字形盒内）⇒ `3` 之前（tex 3）',
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
    expect(buf.caret, 3 + 3,
        reason: '点 3 左半 ⇒ `3` 之前，实际 tex 偏移 ${buf.caret - 3}');
  });

  testWidgets(r'★★ 点 `3` 的**右缘之外**那 1px 缝 ⇒ 对象之后（tex 5，D5 要的那一格）',
      (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, tex);
    final RenderBox root =
        find.byType(MathWithCaret).last.evaluate().single.renderObject! as RenderBox;
    final Rect three =
        scanLeafBoxes(root).eligible.firstWhere((LeafBox b) => b.text == '3').rect;
    buf.setCaret(0);
    await tester.pumpAndSettle();
    await tester.tapAt(root.localToGlobal(Offset(three.right + 1.0, three.center.dy)));
    await tester.pumpAndSettle();
    expect(buf.caret, 3 + 5,
        reason: '字形盒之外 ⇒ 整个 `x^{3}` 之后，实际 tex 偏移 ${buf.caret - 3}');
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
