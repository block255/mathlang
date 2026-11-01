// 反馈 7（续）守卫：**打字路径**（Shift+- 打 `_` / Shift+6 打 `^` 的自动展开）也不许套娃。
//
// 用户复验 2026-11-01：「先点选再快捷键，公式不完整的情况没有了，但是套娃依然有」——
//   面板与快捷键两条已经拦住了，**打字**这条漏着：探针实测 `$f_{-}$` 在下标内容末尾
//   再打 `_` ⇒ `planAutoExpand` 给出 `tex=-_{}` ⇒ 文档变成 `f_{-_{}}`（套娃）。
//
// 判据与另外两条入口同源：`scriptInsertWouldNest`（render/script_nest.dart）。
// 改前必红：①②（改前会各多一层 `_{}` / `^{}`）。

import 'package:flutter/material.dart';
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

/// 逐字符打字（走真实平台文本通道）
Future<void> _type(WidgetTester t, String s) async {
  for (final String ch in s.split('')) {
    t.testTextInput.updateEditingValue(_v(ch));
    await t.pump();
  }
}

void main() {
  testWidgets('① 下标内容之后打 `_` ⇒ 不再套一层', (WidgetTester t) async {
    final (_, DocBuffer buf) = await _mount(t, r'$f_{-}$');
    buf.setCaret(buf.buf.indexOf('-') + 1); // `-` 之后 = 下标内容末尾
    await t.pump();
    await _type(t, '_');
    expect(buf.buf, r'$f_{-}$', reason: '改前会多套一层');
  });

  testWidgets('② 指数内容之后打 `^` ⇒ 不再套一层', (WidgetTester t) async {
    final (_, DocBuffer buf) = await _mount(t, r'$x^{2}$');
    buf.setCaret(buf.buf.indexOf('2') + 1);
    await t.pump();
    await _type(t, '^');
    expect(buf.buf, r'$x^{2}$', reason: '改前会多套一层');
  });

  testWidgets('③ 空下标槽里打 `_` ⇒ 也不再套', (WidgetTester t) async {
    final (_, DocBuffer buf) = await _mount(t, r'$f_{}$');
    buf.setCaret(buf.buf.indexOf(r'_{') + 2); // 花括号里（空槽）
    await t.pump();
    await _type(t, '_');
    expect(buf.buf, r'$f_{}$');
  });

  testWidgets('④ 正例：`f` 之后打 `_` 仍然照常展开成 `f_{}`（不许把功能做死）',
      (WidgetTester t) async {
    final (_, DocBuffer buf) = await _mount(t, r'$f$');
    buf.setCaret(2);
    await t.pump();
    await _type(t, '_');
    expect(buf.buf.trimRight(), r'$f_{}$');
    expect(buf.caret, 4, reason: '光标落进空槽（`{` 与 `}` 之间）');
  });

  testWidgets('⑤ 正例：正文里打下标也照常建壳（不在数学段里 ⇒ 不拦）',
      (WidgetTester t) async {
    final (_, DocBuffer buf) = await _mount(t, '甲');
    buf.setCaret(1);
    await t.pump();
    await _type(t, '_');
    expect(buf.buf, isNot('甲'), reason: '正文里打字必须留下东西');
  });
}
