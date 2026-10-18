// 守卫测试：**Enter 的三条换行语义**（2026-10-18 用户实测：行中/行末按 Enter 后"文本不变 + 光标消失"）
//
// 语义（用户定）：
//   ① 光标在**行中** ⇒ 之后的文字换到下一行（下面的块整体下移）；
//   ② 光标在**行末**且下面还有内容 ⇒ 插入一个**空行**；
//   ③ 光标在**文末** ⇒ 新空行（这条现状已对，防回归）。
// 外加一条硬的：**任何位置按完 Enter，光标都必须还在**（不能消失）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';

Future<(EditViewState, DocBuffer)> _mount(WidgetTester tester, String doc,
    {int? caret}) async {
  final DocBuffer buf = DocBuffer(doc)..setCaret(caret ?? doc.length);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 600,
        child: SingleChildScrollView(
          child: EditView(buffer: buf),
        ),
      ),
    ),
  ));
  final EditViewState st = tester.state<EditViewState>(find.byType(EditView));
  st.focusInput();
  buf.setCaret(caret ?? doc.length);
  await tester.pump();
  return (st, buf);
}

Future<void> _enter(WidgetTester tester) async {
  await tester.testTextInput.receiveAction(TextInputAction.newline);
  await tester.pump();
}

void main() {
  testWidgets('① 行中按 Enter ⇒ 之后的文字换到下一行', (WidgetTester tester) async {
    final (EditViewState _, DocBuffer buf) = await _mount(tester, 'abcde', caret: 2);
    await _enter(tester);
    expect(buf.buf, 'ab\n\ncde', reason: 'Enter = 新块（md 约定块间空一行）⇒ cde 整体下移成下一段');
    expect(buf.caret, 4, reason: '光标落在下一段的行首');
  });

  testWidgets('② 行末且下面有内容 ⇒ 插入一个空行', (WidgetTester tester) async {
    final (EditViewState _, DocBuffer buf) = await _mount(tester, 'abc\ndef', caret: 3);
    await _enter(tester);
    expect(buf.buf, 'abc\n\n\ndef', reason: '行末 Enter ⇒ 中间多一个空块，下文整体下移');
    expect(buf.caret, 5, reason: '光标落在那个空块上');
  });

  testWidgets('③ 文末 ⇒ 新空行（防回归）', (WidgetTester tester) async {
    final (EditViewState _, DocBuffer buf) = await _mount(tester, 'abc', caret: 3);
    await _enter(tester);
    expect(buf.buf, 'abc\n\n');
    expect(buf.caret, 5);
  });

  testWidgets('★ 任何位置按 Enter，光标都不能消失', (WidgetTester tester) async {
    for (final (String doc, int caret) in <(String, int)>[
      ('abcde', 0),
      ('abcde', 2),
      ('abcde', 5),
      ('abc\ndef', 3),
      ('abc\ndef', 7),
      // 数学段里按 Enter
      (r'a $x+y$ b', 5),
    ]) {
      final (EditViewState _, DocBuffer buf) = await _mount(tester, doc, caret: caret);
      await _enter(tester);
      expect(buf.caret, isNotNull,
          reason: 'doc="$doc" caret=$caret 按完 Enter 光标不该无效（buf.caret=${buf.caret}）');
      expect(buf.caret, inInclusiveRange(0, buf.buf.length),
          reason: 'doc="$doc" 光标越界：${buf.caret} / ${buf.buf.length}');
    }
  });

  testWidgets('★ Enter 走**硬件键**也要换行（Windows 上走的就是这条路）',
      (WidgetTester tester) async {
    final (EditViewState _, DocBuffer buf) = await _mount(tester, 'abcde', caret: 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(buf.buf, 'ab\n\ncde', reason: '键事件路径必须与文本通道路径同源');
    expect(buf.caret, 4);
  });
}
