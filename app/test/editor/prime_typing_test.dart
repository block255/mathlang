// ★★★ 2026-11-01（用户拍板 2/4）：撇**在输入时就写 `^{\prime}`**，并且删除行为与顺序无关。
//
// 用户报的现象：`$f_{-}'f'_{+}$` —— 两种顺序打出来的两个"左/右导数"，
//   退格删出来的残骸**完全相反**（一个剩 `'_{+}`，一个剩 `'`），
//   而且有了撇之后"f 与下标之间"那格的语义也不一致。
// 根因：裸 `'` 在模型里是普通字符，不是脚本 ⇒ `f'` 不是"一个对象"。
// 本文件钉：① 打字 ⇒ 写 `^{\prime}` ② 面板「导数撇」同一条 ③ 归一后删整块（顺序无关）

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/normalize.dart';
import 'package:mathlang/render/smart_delete.dart';

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

void main() {
  testWidgets(r"① 数学段里打 ' ⇒ 写 ^{\prime}", (WidgetTester t) async {
    final (_, DocBuffer buf) = await _mount(t, r'$f$');
    buf.setCaret(2); // f 之后
    await t.pump();
    t.testTextInput.updateEditingValue(_v("'"));
    await t.pump();
    expect(buf.buf.trimRight(), r"$f^{\prime}$");
  });

  testWidgets(r"② 面板「导数撇」同样写 ^{\prime}", (WidgetTester t) async {
    final (EditViewState st, DocBuffer buf) = await _mount(t, r'$f$');
    buf.setCaret(2);
    await t.pump();
    st.insertSymbolTex("'", template: false);
    await t.pump();
    expect(buf.buf.trimRight(), r"$f^{\prime}$");
  });

  testWidgets(r"③ 没有基座时补 {}：不写非法 tex", (WidgetTester t) async {
    final (_, DocBuffer buf) = await _mount(t, r'$$');
    buf.setCaret(1);
    await t.pump();
    t.testTextInput.updateEditingValue(_v("'"));
    await t.pump();
    expect(buf.buf.contains(r'\prime'), isTrue);
    expect(buf.buf.contains(r'{}^{\prime}'), isTrue,
        reason: '无基座 ⇒ 必须先补空组，否则 TeX 解析失败');
  });

  test(r'④ 两种打字顺序**归一后是同一份源码** ⇒ 行为必然一致', () {
    final String a = normalizeTex(r"f'_{+}", 0).tex; // 先撇后下标
    final String b = normalizeTex(r"f_{+}'", 0).tex; // 先下标后撇
    expect(a, b, reason: '脚本顺序归一（撇永远排第一）之后必须逐字节相等');
    final SmartEdit ea = smartBackspace(buildCaretSites(a), a.length);
    final SmartEdit eb = smartBackspace(buildCaretSites(b), b.length);
    expect(ea.from, eb.from);
    expect(ea.to, eb.to);
  });

  test(r'⑥ 老文档的裸撇：归一一次之后，行为与"新写的"完全一样', () {
    const String legacy = r"f'_{+}";
    final String fixed = normalizeTex(legacy, 0).tex;
    final String fresh = normalizeTex(r"f_{+}'", 0).tex;
    expect(fixed, fresh, reason: '老文档归一后应与新输入同形');
    final SmartEdit e = smartBackspace(buildCaretSites(fixed), fixed.length);
    expect(e.deletes, isTrue, reason: '末尾退格必须有东西可删');
  });

  // ★ 2026-11-01（用户实测）：正文里先打 `f`，再点面板「导数撇」——
  //   现状是插入一个**只有撇的数学段**（`f$'$`，撇无基座、f 还是正体）。
  //   与打 `^` 是同一个诉求：**把光标前那串字母一起搬进公式**，撇挂为它的上标。
  testWidgets(r"⑦ 正文里 f 后点「导数撇」⇒ 搬进公式，得到 $f^{\prime}$",
      (WidgetTester t) async {
    final (EditViewState st, DocBuffer buf) = await _mount(t, 'f');
    buf.setCaret(1);
    await t.pump();
    st.insertSymbolTex("'", template: false);
    await t.pump();
    expect(buf.buf.trimRight(), r'$f^{\prime}$',
        reason: '不许留"正体 f + 只有撇的公式段"（撇必须有基座，且 f 要进数学字体）');
  });

  // 同一诉求的第二种形态：`sin` 这种多字母也要整串搬（与打 `^` 的"搬家范围"同一条口径）。
  testWidgets(r"⑧ 正文里 sin 后点「导数撇」⇒ 整串搬进公式", (WidgetTester t) async {
    final (EditViewState st, DocBuffer buf) = await _mount(t, 'sin');
    buf.setCaret(3);
    await t.pump();
    st.insertSymbolTex("'", template: false);
    await t.pump();
    expect(buf.buf.trimRight(), r'$sin^{\prime}$');
  });
}
