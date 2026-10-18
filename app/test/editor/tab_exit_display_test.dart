// 守卫测试：**Tab 从行间块走出去 ⇒ 落到下一行行首**（PC-2，2026-10-18 用户实测）
//
// 旧行为：只走到收尾 `$$` 之后（`closeEnd`）⇒ 一打字就接在块后面
//   （用户："出去应该到下一个空的行，而不是接在这一块后面"）。
// 新行为：落到块后那一个 `\n` 之后（= 下一行行首）；块在文末时先补一个换行。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';

Future<DocBuffer> _mount(WidgetTester tester, String doc, int caret) async {
  final DocBuffer buf = DocBuffer(doc)..setCaret(caret);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 600,
        child: SingleChildScrollView(child: EditView(buffer: buf)),
      ),
    ),
  ));
  final EditViewState st = tester.state<EditViewState>(find.byType(EditView));
  st.focusInput();
  buf.setCaret(caret);
  await tester.pump();
  return buf;
}

Future<void> _tab(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.pump();
}

void main() {
  testWidgets('块后面还有一行 ⇒ 落到那一行的行首', (WidgetTester tester) async {
    // $$\nx\n$$\nabc
    // 0123456789...
    final DocBuffer buf = await _mount(tester, '\$\$\nx\n\$\$\nabc', 4);
    await _tab(tester);
    expect(buf.caret, 8, reason: '落到 `abc` 那一行的行首（块后的 \\n 之后）');
  });

  testWidgets('块在文末 ⇒ 先补换行，落到新的一行', (WidgetTester tester) async {
    final DocBuffer buf = await _mount(tester, '\$\$\nx\n\$\$', 4);
    await _tab(tester);
    expect(buf.buf, '\$\$\nx\n\$\$\n', reason: '文末没有下一行 ⇒ 补一个换行');
    expect(buf.caret, 8, reason: '落在新补出来的那一行上');
  });
}
