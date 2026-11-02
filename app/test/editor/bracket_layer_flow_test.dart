// 2026-11-02 · 括号对同层（端到端：真 EditView + 真按键）
//
// 用户现场是自然打字形成的：`(` 在公式里、`)` 打在公式外。
// 这一份验"打 `)` 的瞬间就落到开括号那一层"，并且随后 `^` 能挂上。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';

TextEditingValue _v(String text) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );

Future<(EditViewState, DocBuffer)> _mount(WidgetTester t, String doc) async {
  final DocBuffer buf = DocBuffer(doc);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 600,
        child: SingleChildScrollView(child: EditView(buffer: buf)),
      ),
    ),
  ));
  final EditViewState st = t.state<EditViewState>(find.byType(EditView));
  st.focusInput();
  await t.pump();
  return (st, buf);
}

Future<void> _type(WidgetTester t, String s) async {
  for (final String ch in s.split('')) {
    t.testTextInput.updateEditingValue(_v(ch));
    await t.pump();
  }
}

String _body(String s) => s.endsWith('\n') ? s.substring(0, s.length - 1) : s;

void main() {
  testWidgets('① 开在数学、`)` 打在正文 ⇒ `)` 落进公式，随后 `^` 能挂',
      (WidgetTester t) async {
    const String doc = r'$\lim(\frac{a}{b}$';
    final (_, DocBuffer buf) = await _mount(t, doc);
    buf.setCaret(doc.length);
    await t.pump();
    await _type(t, ')');
    expect(_body(buf.buf), r'$\lim(\frac{a}{b})$',
        reason: '`)` 必须落在收尾美元符之前（同一层）');
    await _type(t, '^');
    expect(_body(buf.buf), r'$\lim(\frac{a}{b})^{}$');
    expect(_body(buf.buf).contains(r'$$'), isFalse);
  });

  testWidgets('② 开在正文、`)` 打在数学里 ⇒ `)` 落到公式之后，随后 `^` 能挂',
      (WidgetTester t) async {
    const String doc = r'($\frac{a}{b}$';
    final (_, DocBuffer buf) = await _mount(t, doc);
    buf.setCaret(doc.lastIndexOf(r'$'));
    await t.pump();
    await _type(t, ')');
    expect(_body(buf.buf), r'($\frac{a}{b}$)',
        reason: '`)` 必须落在收尾美元符之后（同一层）');
    await _type(t, '^');
    expect(_body(buf.buf), r'$(\frac{a}{b})^{}$');
  });

  testWidgets('③ 中间夹着文字 ⇒ `)` 原样留在正文（不搬）', (WidgetTester t) async {
    const String doc = r'$\lim(x$ + 1';
    final (_, DocBuffer buf) = await _mount(t, doc);
    buf.setCaret(doc.length);
    await t.pump();
    await _type(t, ')');
    expect(_body(buf.buf), r'$\lim(x$ + 1)');
  });

  testWidgets('④ 搬动 + 打指数合起来仍是一次撤销回原文', (WidgetTester t) async {
    const String doc = r'$\lim(\frac{a}{b}$';
    final (_, DocBuffer buf) = await _mount(t, doc);
    buf.setCaret(doc.length);
    await t.pump();
    await _type(t, ')');
    await _type(t, '^');
    expect(_body(buf.buf), isNot(doc));
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pump();
    // `^` 自己是一步；再撤一步应回到"打完 `)`"的状态
    expect(_body(buf.buf), r'$\lim(\frac{a}{b})$');
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pump();
    expect(_body(buf.buf), doc, reason: '再撤一步回到原文');
  });
}
