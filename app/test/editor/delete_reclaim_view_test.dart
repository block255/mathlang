// 数语引擎 · **删除要干脆**（编辑面端到端，2026-10-18）
//
// 纯函数那层在 `test/render/delete_reclaim_test.dart`（含全域扫描）；
// 这里只钉"用户按键之后屏幕上真的发生了什么"：
//   ① 行内 `$\sqrt{}$` 按一次退格 ⇒ **什么都没了**（不是留一个空框要再按一次）；
//   ② `Ctrl+Z` **一步**就回来；
//   ③ 行间块同理。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/empty_math_mark.dart';

Future<(EditViewState, DocBuffer)> _mount(
  WidgetTester tester,
  String doc,
  int caret,
) async {
  final DocBuffer buf = DocBuffer(doc)..setCaret(caret);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: EditView(buffer: buf)),
    ),
  ));
  final EditViewState st = tester.state<EditViewState>(find.byType(EditView));
  st.focusInput();
  await tester.pump();
  return (st, buf);
}

Future<void> _backspace(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
  await tester.pump();
}

void main() {
  testWidgets('★ 行内结构整段删 ⇒ 一次退格清干净，且**不留空框**',
      (WidgetTester tester) async {
    const String doc = r'前$\sqrt{}$后';
    const String math = r'$\sqrt{}$';
    final (_, DocBuffer buf) =
        await _mount(tester, doc, doc.indexOf(math) + math.length);

    await _backspace(tester);

    expect(buf.buf, '前后', reason: '改前：留下一个空框，得再按一次');
    expect(find.byType(EmptyMathMark), findsNothing, reason: '不许留占位框');
  });

  testWidgets('★ 一步撤销就回来（不是两步）', (WidgetTester tester) async {
    const String doc = r'前$\sqrt{}$后';
    const String math = r'$\sqrt{}$';
    final (_, DocBuffer buf) =
        await _mount(tester, doc, doc.indexOf(math) + math.length);

    await _backspace(tester);
    expect(buf.buf, '前后');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(buf.buf, doc, reason: '删结构与删定界符必须合成**一次**编辑');
  });

  testWidgets('★ 行间块整段删 ⇒ 连围栏一起走', (WidgetTester tester) async {
    const String doc = '\$\$\n\\sqrt{}\n\$\$\n尾段';
    final int caret = doc.indexOf('\\sqrt{}') + '\\sqrt{}'.length;
    final (_, DocBuffer buf) = await _mount(tester, doc, caret);

    await _backspace(tester);

    expect(buf.buf.contains('\\sqrt'), isFalse, reason: buf.buf);
    expect(buf.buf.contains('尾段'), isTrue, reason: '后面的内容不许被吃掉：${buf.buf}');
    expect(find.byType(EmptyMathMark), findsNothing);
  });

  testWidgets('公式里的**子位点**仍然留槽（结构不跟着走）',
      (WidgetTester tester) async {
    const String doc = r'$\sqrt{x}$';
    final (_, DocBuffer buf) = await _mount(tester, doc, doc.indexOf('x') + 1);

    await _backspace(tester);

    expect(buf.buf, r'$\sqrt{}$', reason: '子位点：删内容只留空槽，结构还在');
    // 空槽由注入的占位垫画出，不是"空公式框"
    expect(find.byType(EmptyMathMark), findsNothing);
  });
}
