// 2026-11-13 反馈 ③：**拖选 + 打字替换 = 替换整个对象**（改前红）。
//
// 改前：`_commitText` 的选区分支是裸 `_buf.replace(selStart, selEnd, text)`
// ⇒ 切开结构就留残片（`\frac{` ⇒ `[公式不完整]`；`}{` ⇒ 静默错位）。
// 改后：先走 `planDelete`（扩到最小完整单位），再插 —— 一步撤销。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/leaf_boxes.dart';
import 'package:mathlang/render/math_caret.dart';

import '../support/math_fonts.dart';

Future<DocBuffer> _pump(WidgetTester tester, String doc, int a, int b) async {
  tester.view.physicalSize = const Size(1200, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer(doc);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 600,
        child: SingleChildScrollView(child: EditView(buffer: buf)),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(MathWithCaret).first);
  await tester.pumpAndSettle();
  buf.setSelection(a, b);
  await tester.pumpAndSettle();
  return buf;
}

Future<void> _click(WidgetTester tester, Offset at, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

Offset _glyphCenter(WidgetTester tester, String glyph, {bool last = false}) {
  final RenderBox root =
      find.byType(MathWithCaret).last.evaluate().single.renderObject! as RenderBox;
  final Iterable<LeafBox> all = scanLeafBoxes(root)
      .eligible
      .where((LeafBox x) => x.text == glyph && x.kind == LeafBoxKind.glyph);
  final LeafBox b = last ? all.last : all.first;
  return root.localToGlobal(Offset(b.rect.center.dx, b.rect.center.dy));
}

void main() {
  setUpAll(() async => loadMathFonts());

  testWidgets(r'选 `\frac{` 打 x ⇒ 整个分式被替换（改前：$a+xb}{c}+d$）',
      (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, r'$a+\frac{b}{c}+d$', 3, 9);
    tester.testTextInput.enterText('x');
    await tester.pumpAndSettle();
    expect(buf.buf, r'$a+x+d$' '\n');
    expect(buf.undo(), isTrue);
    expect(buf.buf, r'$a+\frac{b}{c}+d$' '\n', reason: '一次撤销就得回原样');
  });

  testWidgets(r'选分数线那一带 `}{` 打 x ⇒ 同上（改前：静默 `\frac{bxc}+d`）',
      (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, r'$a+\frac{b}{c}+d$', 10, 12);
    tester.testTextInput.enterText('x');
    await tester.pumpAndSettle();
    expect(buf.buf, r'$a+x+d$' '\n');
  });

  testWidgets('选分子里的字 ⇒ 只替换那个字（不许乱扩）', (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, r'$a+\frac{b}{c}+d$', 9, 10);
    tester.testTextInput.enterText('x');
    await tester.pumpAndSettle();
    expect(buf.buf, r'$a+\frac{x}{c}+d$' '\n');
  });

  testWidgets(r'双击 `\right|` 竖线再打字 ⇒ 整对一起被替换（改前：只剩 \left|）',
      (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, r'$a+\left|f\right|+b$', 9, 9);
    await _click(tester, _glyphCenter(tester, '|', last: true), 2);
    expect(buf.buf.substring(buf.selectionStart, buf.selectionEnd),
        r'\left|f\right|',
        reason: '双击半边定界符 ⇒ 整对');
    tester.testTextInput.enterText('x');
    await tester.pumpAndSettle();
    expect(buf.buf, r'$a+x+b$' '\n');
  });
}
