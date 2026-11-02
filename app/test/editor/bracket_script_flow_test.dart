// 2026-11-02 · **括号 + 挂件（^ / _ / '）的端到端守卫**（R-甲1/2/5/6）
//
// 判据是用户能感觉到的那三样：**文档变成什么、光标在哪、撤销是不是一步**。
// 旧路径（`applySymbolInsert` 把"整段公式"当裸 tex）会：
//   · 紧贴公式 ⇒ 公式掉到下一行；· 在正文里 ⇒ 再包一层成 `$$…$$` 行间块；
//   · `[` `{` 被静默改成 `(`；· 正文空格原样进数学（同像素位点 + 删不掉）。
//
// 这一份走**真实的平台文本通道**（与敲键盘同一条路），不是只测 plan 层。

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
  buf.setCaret(doc.length);
  await t.pump();
  return (st, buf);
}

Future<void> _type(WidgetTester t, String s) async {
  for (final String ch in s.split('')) {
    t.testTextInput.updateEditingValue(_v(ch));
    await t.pump();
  }
}

Future<void> _typeAt(WidgetTester t, String doc, String typed,
    {required String expected}) async {
  final (_, DocBuffer buf) = await _mount(t, doc);
  await _type(t, typed);
  // 编辑器在文末编辑后会保证一个收尾 `\n`（段落模型的正常行为），比较时剥掉它
  final String body =
      buf.buf.endsWith('\n') ? buf.buf.substring(0, buf.buf.length - 1) : buf.buf;
  expect(body, expected);
  expect(body.contains('\n'), isFalse, reason: '不许多出换行');
  expect(body.contains(r'$$'), isFalse, reason: '不许二次包成行间围栏');
}

void main() {
  testWidgets('① 极限 + 括号公式 + ^ ⇒ 合并成一段、同一行（乙）',
      (WidgetTester t) async {
    const String doc = r'$\lim_{x\to\infty}$($\frac{a}{b}$)';
    await _typeAt(t, doc, '^',
        expected: r'$\lim_{x\to\infty}(\frac{a}{b})^{}$');
  });

  testWidgets('② ln + 括号公式 + ^ ⇒ 行内，不是行间围栏', (WidgetTester t) async {
    const String doc = r'ln($\frac{1+x}{x^{2}}$)';
    await _typeAt(t, doc, '^', expected: r'ln$(\frac{1+x}{x^{2}})^{}$');
  });

  testWidgets('③ 文首括号公式 + ^ ⇒ 一段行内公式', (WidgetTester t) async {
    const String doc = r'($\alpha$)';
    await _typeAt(t, doc, '^', expected: r'$(\alpha)^{}$');
  });

  testWidgets('④ 方括号保真', (WidgetTester t) async {
    const String doc = r'[$\alpha$]';
    await _typeAt(t, doc, '^', expected: r'$[\alpha]^{}$');
  });

  testWidgets('⑤ 花括号保真（转义成 \\{ \\}）', (WidgetTester t) async {
    const String doc = r'{$\alpha$}';
    await _typeAt(t, doc, '^', expected: r'$\{\alpha\}^{}$');
  });

  testWidgets('⑥ 全角括号认', (WidgetTester t) async {
    const String doc = r'（$\alpha$）';
    await _typeAt(t, doc, '^', expected: r'$（\alpha）^{}$');
  });

  testWidgets('⑦ 纯正文括号里的空格 ⇒ 转 \\ ', (WidgetTester t) async {
    const String doc = r'(x + a)';
    await _typeAt(t, doc, '^', expected: r'$(x\ +\ a)^{}$');
  });

  testWidgets('⑧ 下标 _ 同一条路', (WidgetTester t) async {
    const String doc = r'[$\alpha$]';
    await _typeAt(t, doc, '_', expected: r'$[\alpha]_{}$');
  });

  testWidgets('⑨ 一步撤销回原文', (WidgetTester t) async {
    const String doc = r'$\lim_{x\to\infty}$($\frac{a}{b}$)';
    final (EditViewState st, DocBuffer buf) = await _mount(t, doc);
    await _type(t, '^');
    expect(buf.buf, isNot(doc));
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pump();
    final String body =
        buf.buf.endsWith('\n') ? buf.buf.substring(0, buf.buf.length - 1) : buf.buf;
    expect(body, doc, reason: '一次撤销必须逐字回到原文');
    expect(st.edits, greaterThan(0));
  });
}
