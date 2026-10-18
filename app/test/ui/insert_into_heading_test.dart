// ★ 插入进「行首语法行」（`# 标题`）时的守卫
//
// 背景：用户 2026-10-17 在浏览器里点「分式」插进标题行，**渲染出来的标题样式消失了**
//       （屏幕上 `# 例 1 · 一元二次方程` 变成小字正文）。
// 这条测试就是回答"到底是插入把块打坏了，还是渲染的错觉"：
//   · 断言**缓冲区里那一行仍然以 `# ` 开头**（块语法没被劈开）；
//   · 断言插入后 `\frac` 落进去且**没有多出来的空行**；
//   · 顺便守"一次编辑 = 一步撤销"。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/ui/editor_page.dart';

import '../support/symbol_fixture.dart';

Future<(EditorPageState, DocBuffer)> _pump(
  WidgetTester tester, {
  required String doc,
  required int caret,
}) async {
  tester.view.physicalSize = const Size(1500, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer(doc)..setCaret(caret);
  await tester.pumpWidget(MaterialApp(
    home: EditorPage(library: testSymbolLibrary(), buffer: buf),
  ));
  await tester.pumpAndSettle();
  final EditorPageState st = tester.state<EditorPageState>(find.byType(EditorPage));
  st.togglePanel(open: true);
  await tester.pumpAndSettle();
  return (st, buf);
}

void main() {
  testWidgets('★ 在 `# 标题` 里插分式：行首语法不许被打坏', (WidgetTester tester) async {
    const String doc = '# 例 1 一元二次方程\n\n正文。';
    final (EditorPageState _, DocBuffer buf) =
        await _pump(tester, doc: doc, caret: 6); // "例 1" 之后

    await tester.tap(find.byKey(const Key('symbol-frac')));
    await tester.pumpAndSettle();

    final String line1 = buf.buf.split('\n').first;
    expect(line1.startsWith('# '), isTrue,
        reason: '★ 标题行的 `# ` 必须还在（否则整行退化成正文）——实测现状：$line1');
    expect(line1, contains(r'\frac'));
    expect(buf.buf.split('\n').where((String l) => l.isEmpty).length,
        greaterThanOrEqualTo(1),
        reason: '原本的空行不该被吞掉');
    final EditViewState v = tester.state<EditViewState>(find.byType(EditView));
    expect(v.edits, 1);
  });

  testWidgets('★ 在 `# 标题` 的**最开头**（caret 0）插分式：行首语法也不许坏',
      (WidgetTester tester) async {
    // 这是浏览器里最容易撞到的情况：文档刚打开、光标还在 0。
    const String doc = '# 例 1 一元二次方程\n\n正文。';
    final (EditorPageState _, DocBuffer buf) =
        await _pump(tester, doc: doc, caret: 0);
    await tester.tap(find.byKey(const Key('symbol-frac')));
    await tester.pumpAndSettle();

    final List<String> lines = buf.buf.split('\n');
    // 允许两种正确结果：`$…$` 在标题**之前**自成一段，或插进标题里但 `# ` 仍是行首
    final int headingLine =
        lines.indexWhere((String l) => l.startsWith('# '));
    expect(headingLine, greaterThanOrEqualTo(0),
        reason: '★ `# ` 必须仍然是某一行的行首 —— 实测：${buf.buf}');
    expect(lines[headingLine], contains('例 1'));
    expect(buf.buf, contains(r'\frac'));
  });

  testWidgets('普通段落里插：只多出数学段，不多换行', (WidgetTester tester) async {
    const String doc = '甲乙丙丁\n\n正文。';
    final (EditorPageState _, DocBuffer buf) =
        await _pump(tester, doc: doc, caret: 2);
    await tester.tap(find.byKey(const Key('symbol-frac')));
    await tester.pumpAndSettle();
    expect(buf.buf.split('\n').length, doc.split('\n').length,
        reason: '普通段落里插入不该加换行');
    expect(buf.buf.startsWith(r'甲乙$\frac{}{}$'), isTrue, reason: buf.buf);
  });
}
