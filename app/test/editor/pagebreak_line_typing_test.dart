// 批 48（2026-10-26，用户截图实证）：**补出来的后缀换行不算用户打的** —— 光标要落在
// 用户内容末尾，否则在分页符行首/页尾空白处打字会**一行一个字**，还多出空行。
//
// 现象（用户原话 + 截图）：
//   「分页原页末尾空行，打字后光标不是跟在打出的字后面，而是挪到下面一行去了」
//   ⇒ 截图里 `w` `o` `w` `d` `a` 各占一行，每打一个字光标被送到下一行。
//
// 根因链：落点在分页符行首 ⇒ `insert_guard` 补一个后缀换行（让内容自成一行、标记不被粘坏）
//   ⇒ `DocBuffer.replace` 把光标放到插入末尾 = **那个换行之后**（下一行行首）
//   ⇒ 再打一个字又"落在行首" ⇒ 又补一个换行 ⇒ 一行一个字。
//
// 判据：这三次输入之后，缓冲区里应当是**一行** `abc`，不是三行。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';

const String kDoc = '甲\n<!-- pagebreak -->\n乙\n';

Future<DocBuffer> _mount(WidgetTester tester, int caret) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer(kDoc)..setCaret(caret);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
  ));
  tester.state<EditViewState>(find.byType(EditView)).focusInput();
  await tester.pumpAndSettle();
  return buf;
}

Future<void> _type(WidgetTester tester, String s) async {
  final EditViewState st = tester.state<EditViewState>(find.byType(EditView));
  for (final int ch in s.codeUnits) {
    st.pasteText(String.fromCharCode(ch)); // 走同一条提交链（与打字等价）
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('★ 分页符行首连打 3 个字符 ⇒ 一行 `abc`，不是一行一个', (WidgetTester tester) async {
    final int pb = kDoc.indexOf('<!--');
    final DocBuffer buf = await _mount(tester, pb);
    await _type(tester, 'abc');
    expect(buf.buf.contains('abc'), isTrue,
        reason: '三个字应当在同一行：${buf.buf.replaceAll('\n', r'\n')}');
    expect(buf.buf, '甲\nabc\n<!-- pagebreak -->\n乙\n',
        reason: '内容自成一行落在标记**之前**，且只有一行：${buf.buf.replaceAll('\n', r'\n')}');
    expect(buf.caret, pb + 3, reason: '光标应当跟在 `abc` 后面（不是下一行行首）');
  });

  testWidgets('★ 页尾空行（分页符之前那一行）连打 3 个字符 ⇒ 也只在一行里',
      (WidgetTester tester) async {
    // 分页符**之前那一行空行**的行首（= 用户点页尾空白后、"原页末尾空行"的那一格）
    const String doc = '甲\n\n<!-- pagebreak -->\n乙\n';
    final DocBuffer buf = await _mount(tester, doc.indexOf('<!--') - 1);
    await _type(tester, 'xyz');
    expect(buf.buf, '甲\nxyz\n<!-- pagebreak -->\n乙\n',
        reason: '三个字在同一行：${buf.buf.replaceAll('\n', r'\n')}');
  });
}
