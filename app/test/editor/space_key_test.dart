// 空格键必须能打出空格（2026-10-17 用户实测"文本段也打不出空格"）
//
// 探针坐实的机制（Flutter Web）：按空格时 `updateEditingValue` **一次都没被调用**
// （而 `a` / `啊` 都有），同时框架的默认动作把**文本区翻了一页** ——
// 即空格在到达 DOM 输入框之前就被吃掉了。
// ⇒ 只能由 `EditView._onKey` 自己把它落进缓冲区（并且 `handled` 顺便拦掉翻页）。
//
// 本守卫验两件事：
//   ① 在**文本段**里按空格 ⇒ 缓冲区真的多了一个空格，光标后移一位；
//   ② 空格不改变块结构（不会有人偷偷把它 formatter 成 `\n\n` 之类）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';

Future<DocBuffer> _pump(WidgetTester tester, String doc) async {
  final DocBuffer buf = DocBuffer(doc)..setCaret(0);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 500,
        child: SingleChildScrollView(child: EditView(buffer: buf)),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  // 点正文 ⇒ 取焦点（并让光标落到那一行）
  await tester.tap(find.textContaining('甲').first);
  await tester.pumpAndSettle();
  return buf;
}

void main() {
  testWidgets('★ 文本段：按空格 ⇒ 缓冲区多一个空格', (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, '甲乙丙');
    final int before = buf.caret;
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    // ★ 2026-10-28：非空文档以 `\n` 收尾 ⇒ 3 个字 + 1 个空格 + 1 个行终止符 = 5
    expect(buf.buf.length, 5, reason: '空格必须真的插进缓冲区（改前：一个字符都没多）');
    expect(buf.buf.contains(' '), isTrue, reason: '插的必须是普通空格');
    expect(buf.caret, before + 1, reason: '光标要跟着走一格');
  });

  testWidgets('★ 连按三次空格 ⇒ 三个空格', (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, '甲乙丙');
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
    }
    expect(' '.allMatches(buf.buf).length, 3, reason: buf.buf);
  });

  testWidgets('★ 空格不改变块结构（不做任何换行替换）', (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, '甲乙丙');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    // ★ 缓冲区的 `\n` 只该有那个行终止符：空格没有被换成换行
    expect('\n'.allMatches(buf.buf).length, 1,
        reason: '空格不许变成换行（缓冲区里只该有行终止符那一个）：${buf.buf}');
  });
}
