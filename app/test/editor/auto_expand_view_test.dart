// 数语引擎 · **打字即渲染**（S4-c 的自动展开）在真实编辑面上的守卫
//
// 三条入口都走同一条链：平台文本通道 → `_commitText` → `planAutoExpand` → 一次写入。
// 判据：文档变成什么、光标在哪、**撤销是一步**（这三个才是用户能感觉到的东西）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';

TextEditingValue _v(String text) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );

Future<(EditViewState, DocBuffer)> _mount(
  WidgetTester tester,
  String doc, {
  bool slash = true,
  bool words = true,
  bool shorthand = true,
}) async {
  final DocBuffer buf = DocBuffer(doc)..setCaret(doc.length);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 600,
        child: SingleChildScrollView(
          child: EditView(
            buffer: buf,
            autoSlashFraction: slash,
            autoWordTriggers: words,
            autoShorthand: shorthand,
          ),
        ),
      ),
    ),
  ));
  final EditViewState st = tester.state<EditViewState>(find.byType(EditView));
  st.focusInput();
  await tester.pump();
  return (st, buf);
}

/// 逐字符打字（走**真实的平台文本通道**，与用户敲键盘同一条路）
Future<void> _type(WidgetTester tester, String s) async {
  for (final String ch in s.split('')) {
    tester.testTextInput.updateEditingValue(_v(ch));
    await tester.pump();
  }
}

void main() {
  group('① 词触发：打字即模板', () {
    testWidgets('★ sqrt + 空格 ⇒ 变成根号模板（光标进空槽，空格不留下）',
        (WidgetTester tester) async {
      final (_, DocBuffer buf) = await _mount(tester, '');
      await _type(tester, 'sqrt');
      expect(buf.buf, 'sqrt', reason: '没有终止符之前不许展开');
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();

      expect(buf.buf, r'$\sqrt{}$');
      // `$ \ s q r t { } $` ⇒ 光标在 `{` 与 `}` 之间 = 7
      expect(buf.caret, 7);
    });

    testWidgets('★ `Tab` 也是终止符（并且不留下字符）', (WidgetTester tester) async {
      final (_, DocBuffer buf) = await _mount(tester, '');
      await _type(tester, 'sqrt');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(buf.buf, r'$\sqrt{}$');
    });

    testWidgets('★ 一步撤销就回到 `sqrt`（展开 ≠ 两次编辑）',
        (WidgetTester tester) async {
      final (EditViewState st, DocBuffer buf) = await _mount(tester, '');
      await _type(tester, 'sqrt');
      final int before = st.edits;
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(st.edits, before + 1,
          reason: '删词 + 插模板必须合成一次写入（否则 Ctrl+Z 要按两下）');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(buf.buf, 'sqrt');
    });

    testWidgets('`summer` + 空格 ⇒ 原样，不触发', (WidgetTester tester) async {
      final (_, DocBuffer buf) = await _mount(tester, '');
      await _type(tester, 'summer');
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(buf.buf, 'summer ');
    });

    testWidgets('关掉词触发 ⇒ 只打字母 + 空格', (WidgetTester tester) async {
      final (_, DocBuffer buf) = await _mount(tester, '', words: false);
      await _type(tester, 'sqrt');
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(buf.buf, 'sqrt ');
    });
  });

  group('② `/` → 分式', () {
    testWidgets('★ 正文里 a + / ⇒ 变成分式（光标进分母）',
        (WidgetTester tester) async {
      final (_, DocBuffer buf) = await _mount(tester, '');
      await _type(tester, 'a');
      tester.testTextInput.updateEditingValue(_v('/'));
      await tester.pump();
      expect(buf.buf, r'a$\frac{}{}$');
      // 2026-10-18 用户改口径：`/` 独立插入分数线，**不吃**前面的 a；光标进分子空槽
      expect(buf.caret, buf.buf.indexOf('{}') + 1);
    });

    testWidgets('关掉 ⇒ `/` 是普通斜杠', (WidgetTester tester) async {
      final (_, DocBuffer buf) = await _mount(tester, '', slash: false);
      await _type(tester, 'a');
      tester.testTextInput.updateEditingValue(_v('/'));
      await tester.pump();
      expect(buf.buf, 'a/');
    });
  });

  group('③ 缩写', () {
    testWidgets('★ a > = ⇒ 变成大于等于号', (WidgetTester tester) async {
      final (_, DocBuffer buf) = await _mount(tester, '');
      await _type(tester, 'a');
      tester.testTextInput.updateEditingValue(_v('>'));
      await tester.pump();
      tester.testTextInput.updateEditingValue(_v('='));
      await tester.pump();
      // ★ 只吞掉 `>` 与 `=` 两格；前面的 `a` 仍是正文 ⇒ `≥` 自成一个行内公式
      expect(buf.buf, r'a$\ge$');
    });

    testWidgets('关掉 ⇒ `>=` 原样留着', (WidgetTester tester) async {
      final (_, DocBuffer buf) = await _mount(tester, '', shorthand: false);
      await _type(tester, 'a');
      tester.testTextInput.updateEditingValue(_v('>'));
      await tester.pump();
      tester.testTextInput.updateEditingValue(_v('='));
      await tester.pump();
      expect(buf.buf, 'a>=');
    });
  });

  group('④ 中文输入法组合中不触发', () {
    testWidgets('组合串里出现字母也不展开', (WidgetTester tester) async {
      final (_, DocBuffer buf) = await _mount(tester, '');
      // 打拼音（组合中）
      tester.testTextInput.updateEditingValue(TextEditingValue(
        text: 'sqrt',
        selection: const TextSelection.collapsed(offset: 4),
        composing: const TextRange(start: 0, end: 4),
      ));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      // 组合中按空格 = 选字，不该变成模板
      expect(buf.buf.contains(r'\sqrt'), isFalse, reason: buf.buf);
    });
  });
}
