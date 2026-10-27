// 插入侧的两条手感规则（2026-10-17 用户拍板）
//
// ① **数学段里按空格 = "我要一个空隙"** ⇒ 插 `\ `（TeX 控制空格）；文本段里是普通空格。
// ② **命令词的分隔由我们保证**：`\sin` + `x` 会被读成 `\sinx` ⇒ 插字母时自动补分隔。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';

/// 每个文档都以 `甲` 打头：**点它取焦点**（没有真 IME，必须有人持有焦点键才会进来）
Future<DocBuffer> _pump(WidgetTester tester, String doc, int caret) async {
  final DocBuffer buf = DocBuffer(doc)..setCaret(caret);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 500,
        child: SingleChildScrollView(child: EditView(buffer: buf)),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('甲').first);
  await tester.pumpAndSettle();
  buf.setCaret(caret); // 点击会挪光标，放回目标位置
  await tester.pumpAndSettle();
  return buf;
}

void main() {
  testWidgets(r'① 文本段按空格 ⇒ 普通空格', (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, '甲乙丙', 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(buf.buf, '甲 乙丙\n', reason: '文本段里是普通空格：${buf.buf}');
  });

  testWidgets(r'① 数学段里按空格 ⇒ `\ `（控制空格），不是裸空格', (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, r'甲$x+y$', 4);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(buf.buf, '${r'甲$x+\ y$'}\n',
        reason: '数学段里按空格要变成控制空格（插在光标处 = + 之后）：${buf.buf}');
  });

  testWidgets(r'② 控制词末尾插字母 ⇒ 自动补分隔符', (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, r'甲$\sin$', 6);
    tester.testTextInput.enterText('x');
    await tester.pumpAndSettle();
    expect(buf.buf, '${r'甲$\sin x$'}\n', reason: '控制词与字母之间必须自动补分隔：${buf.buf}');
  });

  testWidgets('② 普通字母后面插字母 ⇒ 不加分隔符（不能滥加）', (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, r'甲$ab$', 4); // b 与 $ 之间
    tester.testTextInput.enterText('c');
    await tester.pumpAndSettle();
    expect(buf.buf, '${r'甲$abc$'}\n', reason: '普通连写不该被插空格：${buf.buf}');
  });
}