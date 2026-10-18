// 守卫测试：**打 `^` / `_` 直接变成上下标**（PC-3，2026-10-18 用户实测：原来只插了个字符）
//
// 判据与 `/` 同源：基座 = 光标前那个可见原子（公式里）/ 一个字符（正文里）；
// 正文里整体包成 `$…$`（同权：数学由内容产生）；光标落进 `^{}` / `_{}` 的空槽。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';

TextEditingValue _v(String text) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );

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

Future<void> _type(WidgetTester tester, String ch) async {
  tester.testTextInput.updateEditingValue(_v(ch));
  await tester.pump();
}

void main() {
  testWidgets('公式里打 ^ ⇒ 前一个原子变成上标基座，光标进空槽',
      (WidgetTester tester) async {
    // $x$ 的 x 在 1..2
    final DocBuffer buf = await _mount(tester, r'$x$', 2);
    await _type(tester, '^');
    expect(buf.buf, r'$x^{}$', reason: '基座 = x，不能被抽掉');
    expect(buf.caret, 4, reason: '光标落在 { } 里');
  });

  testWidgets('公式里打 _ ⇒ 下标同源', (WidgetTester tester) async {
    final DocBuffer buf = await _mount(tester, r'$x$', 2);
    await _type(tester, '_');
    expect(buf.buf, r'$x_{}$');
    expect(buf.caret, 4);
  });

  testWidgets('正文里打 ^ ⇒ 自动包成行内公式（数学由内容产生）',
      (WidgetTester tester) async {
    final DocBuffer buf = await _mount(tester, 'a', 1);
    await _type(tester, '^');
    expect(buf.buf, r'$a^{}$', reason: '正文里的基座要被包进行内公式');
    expect(buf.caret, 4);
  });

  testWidgets('多字符原子当基座（\\alpha 整体）', (WidgetTester tester) async {
    // $\alpha$：tex 是 `\alpha`，光标在末尾
    const String doc = r'$\alpha$';
    final DocBuffer buf = await _mount(tester, doc, doc.length - 1);
    await _type(tester, '^');
    expect(buf.buf, r'$\alpha^{}$', reason: '不能切成 al/pha 两半');
  });
}
