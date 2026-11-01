// 反馈 6 / 11（2026-10-30 · R8）守卫：**数学段里的 TeX 语法字符要转义成字面字符**。
//
// 用户实测：行间公式里想打中括号却打成花括号 ⇒ `{` 进 tex ⇒ 配平被破坏 ⇒ `[公式不完整]`；
//   Shift+6 误按 Shift+7 ⇒ `&` 进 tex ⇒ TeX `Misplaced alignment tab character &`。
// 口径（原则 2）：用户按的是键盘上的普通字符，不许因为它"碰巧是 TeX 语法"就把文档弄坏。
//
// 改前必红：①②（改前 `{` / `&` 原样进 tex）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/lang/math_escape.dart';

Future<void> _mount(WidgetTester t, DocBuffer buf) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
  ));
  t.state<EditViewState>(find.byType(EditView)).focusInput();
  await t.pumpAndSettle();
}

/// 直接把一段文本喂给文本输入通道（相当于用户敲了这些字 / IME 提交）
Future<void> _type(WidgetTester t, String text) async {
  t.testTextInput.updateEditingValue(TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  ));
  await t.pumpAndSettle();
}

void main() {
  group('纯函数：escapeMathSyntax', () {
    test('① 数学段里五个语法字符都转义', () {
      expect(escapeMathSyntax('{', inMath: true), r'\{');
      expect(escapeMathSyntax('}', inMath: true), r'\}');
      expect(escapeMathSyntax('&', inMath: true), r'\&');
      expect(escapeMathSyntax('%', inMath: true), r'\%');
      expect(escapeMathSyntax('#', inMath: true), r'\#');
    });

    test('② 正文里原样（`{` `&` 在正文就是普通字符）', () {
      expect(escapeMathSyntax('{', inMath: false), '{');
      expect(escapeMathSyntax('&', inMath: false), '&');
    });

    test('③ 多字符载荷（粘贴的 LaTeX）一律不动', () {
      expect(escapeMathSyntax(r'\begin{cases}', inMath: true), r'\begin{cases}');
      expect(escapeMathSyntax('{}', inMath: true), '{}');
    });

    test(r'④ `$` 与普通字母不动（`$` 是新建/续写公式的入口）', () {
      expect(escapeMathSyntax(r'$', inMath: true), r'$');
      expect(escapeMathSyntax('a', inMath: true), 'a');
      expect(escapeMathSyntax('甲', inMath: true), '甲');
    });
  });

  group('接线：真的打字', () {
    testWidgets('⑤ 行内公式里打 `{` ⇒ 缓冲区里是 `\\{`，配平不变', (WidgetTester t) async {
      final DocBuffer buf = DocBuffer(r'前 $x$ 后' '\n');
      await _mount(t, buf);
      // `$x$` 内部那一格（`x` 之后、收尾 `$` 之前）
      buf.setCaret(4);
      await t.pumpAndSettle();
      await _type(t, '{');
      expect(buf.buf.contains(r'\{'), isTrue,
          reason: '数学段里必须写成 `\\{`（改前是裸 `{` ⇒ 公式不完整）');
    });

    testWidgets('⑥ 正文里打 `{` ⇒ 原样（不转义）', (WidgetTester t) async {
      final DocBuffer buf = DocBuffer('甲乙\n');
      await _mount(t, buf);
      buf.setCaret(2);
      await t.pumpAndSettle();
      await _type(t, '{');
      expect(buf.buf.contains(r'\{'), isFalse, reason: '正文里 `{` 就是普通字符');
      expect(buf.buf.contains('{'), isTrue);
    });
  });
}
