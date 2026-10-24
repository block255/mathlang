// ★★ 2026-10-24（批 3 · 用户实测）：**拖选删掉已有分段 ⇒ 显示「公式不完整」**。
//
// 现场：`f(x)=\begin{cases}...\end{cases}` 里拖选一段按删除 ⇒ 页面上红字 `[公式不完整]`。
// 根因：选区只删了一半的围栏 —— `\begin{cases}` 留下、`\end{cases}` 被删掉（或反过来）
//   ⇒ 整段 tex 解析失败。老实现 `_deleteRange` 直接 `remove(from, to)`，不管围栏。
//
// 修法：删之前把区间**扩到自洽边界**（与复制/剪切同一套 `clipboardSlice`）：
//   · 端点落在数学段**内部** ⇒ 扩到段边界（整个 `$…$` / 块被一起删掉）；
//   · 整段都在公式内部 ⇒ 不动（照旧删内容）。
//
// 判据：删完缓冲区里 `$$` 与 `\begin{cases}` / `\end{cases}` **必须成对**。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/ui/editor_page.dart';

import '../support/fake_file_gateway.dart';
import '../support/symbol_fixture.dart';

const String kBlock = 'f(x)=\\begin{cases}a,&x>0\\\\b,&x<0\\end{cases}';
String docOf(String block) => '前文\n\n\$\$\n$block\n\$\$\n\n后文';

Future<DocBuffer> _pump(WidgetTester tester, String doc) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer(doc)..setCaret(0);
  await tester.pumpWidget(MaterialApp(
    home: EditorPage(
      library: testSymbolLibrary(),
      buffer: buf,
      gateway: FakeFileGateway(),
    ),
  ));
  await tester.pumpAndSettle();
  tester.state<EditViewState>(find.byType(EditView)).focusInput();
  await tester.pumpAndSettle();
  return buf;
}

int _count(String h, String n) {
  var c = 0;
  var i = 0;
  while (true) {
    final int k = h.indexOf(n, i);
    if (k < 0) return c;
    c++;
    i = k + n.length;
  }
}

Future<void> _deleteSelection(
    WidgetTester tester, DocBuffer buf, int from, int to) async {
  buf.setSelection(from, to);
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
  await tester.pumpAndSettle();
}

/// 围栏 / 环境必须成对（删完不许留半截）
void _expectPaired(String buf) {
  expect(_count(buf, r'$$') % 2, 0,
      reason: '`\$\$` 必须成对：${buf.replaceAll('\n', r'\n')}');
  expect(_count(buf, r'\begin{cases}'), _count(buf, r'\end{cases}'),
      reason: '环境必须成对：${buf.replaceAll('\n', r'\n')}');
}

void main() {
  testWidgets('★ 选区从文字跨进分段块内部 ⇒ 删的是**整块**，不留半截', (WidgetTester tester) async {
    final String doc = docOf(kBlock);
    final DocBuffer buf = await _pump(tester, doc);
    // 从前文里一路选到 `\begin{cases}` 之后
    final int from = doc.indexOf('前文') + 1;
    final int to = doc.indexOf(r'\begin{cases}') + 10;
    await _deleteSelection(tester, buf, from, to);

    _expectPaired(buf.buf);
    expect(buf.buf.contains(r'\begin{cases}'), isFalse,
        reason: '整块都该被删掉（不许留 `\\begin{`）：${buf.buf.replaceAll('\n', r'\n')}');
    expect(buf.buf.contains('后文'), isTrue, reason: '块后面的文字不许被吃掉');
  });

  testWidgets('★ 选区整个落在分段块**内部** ⇒ 只删内容，围栏不动', (WidgetTester tester) async {
    final String doc = docOf(kBlock);
    final DocBuffer buf = await _pump(tester, doc);
    final int from = doc.indexOf('a,&x>0');
    final int to = from + 6;
    await _deleteSelection(tester, buf, from, to);

    _expectPaired(buf.buf);
    expect(buf.buf.contains(r'\begin{cases}'), isTrue, reason: '围栏不许被删');
    expect(buf.buf.contains(r'\end{cases}'), isTrue);
  });

  testWidgets('★★ 全域：从每个起点删到块内每个终点 ⇒ 围栏/环境永远成对',
      (WidgetTester tester) async {
    final String doc = docOf(kBlock);
    final int dl = doc.indexOf(r'$$');
    final int dr = doc.indexOf(r'$$', dl + 2) + 2;
    for (var from = dl - 3; from <= dl + 4; from++) {
      for (final int to in <int>[dl + 6, dl + 12, dr - 4, dr]) {
        if (to <= from) continue;
        final DocBuffer buf = await _pump(tester, doc);
        await _deleteSelection(tester, buf, from, to);
        _expectPaired(buf.buf);
      }
    }
  });
}
