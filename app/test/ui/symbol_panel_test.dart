// ★★ S4-b 面板插入（widget 级，走真实外壳）：点符号 ⇒ 一次编辑写进缓冲区
//
// 守的是《界面与布局.md》§7 + §8-2：
//   · 文字里点「分式」⇒ `$\frac{}{}$` 且**光标在分子槽**；
//   · 连续点（落在**当前槽**里）⇒ 就地并进那个槽，不跳到文档末尾；
//   · 一次点击 = 一次编辑（`edits == 1`，一步撤销）；
//   · 搜索框过滤后只剩匹配项。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/ui/editor_page.dart';

import '../support/symbol_fixture.dart';

Future<(EditorPageState, DocBuffer)> _pump(
  WidgetTester tester, {
  String doc = 'abc',
  int caret = 1,
  Size window = const Size(1400, 1000),
}) async {
  tester.view.physicalSize = window;
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

int _edits(WidgetTester tester) =>
    tester.state<EditViewState>(find.byType(EditView)).edits;

void main() {
  setUpAll(() async {});

  testWidgets(r'文字里点「分式」⇒ `$\frac{}{}$`，光标在**分子槽**，只记一次编辑',
      (WidgetTester tester) async {
    final (EditorPageState st, DocBuffer buf) = await _pump(tester);
    expect(find.byKey(const Key('symbol-frac')), findsOneWidget);

    await tester.tap(find.byKey(const Key('symbol-frac')));
    await tester.pumpAndSettle();

    expect(buf.buf, '${r'a$\frac{}{}$bc'}\n', reason: '★ 自动建壳（用户不写编码）');
    // 光标在分子的空槽里：`a$\frac{` 之后
    expect(buf.caret, 1 + 1 + 6, reason: r'应为 a + $ + \frac{ ⇒ 8'); // `$\frac{` 共 7 字符
    expect(buf.buf.substring(buf.caret - 1, buf.caret), '{',
        reason: '光标应紧跟分子的 `{` 之后');
    expect(_edits(tester), 1, reason: '★ 一次点击 = 一次编辑（一步撤销）');
    // 面板保持打开（连续插入）
    expect(find.byKey(const Key('symbol-search')), findsOneWidget);
  });

  testWidgets('★ 连续插入：接着点「加号」⇒ 落在**当前槽**里（不跳到文档末尾）',
      (WidgetTester tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('symbol-frac')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('symbol-plus')));
    await tester.pumpAndSettle();

    final DocBuffer buf = tester
        .widget<EditView>(find.byType(EditView))
        .buffer;
    expect(buf.buf, '${r'a$\frac{+}{}$bc'}\n',
        reason: '第二个符号必须落进**分子的当前槽**');
    expect(_edits(tester), 2, reason: '两次点击 = 两次编辑');
  });

  testWidgets(r'`$x$` 之后点符号 ⇒ **并入**那一段（不新建第二个 `$…$`）',
      (WidgetTester tester) async {
    final (EditorPageState state, DocBuffer buf) =
        await _pump(tester, doc: r'文字$x$尾巴', caret: 5);
    await tester.tap(find.byKey(const Key('symbol-plus')));
    await tester.pumpAndSettle();
    expect(buf.buf, '${r'文字$x+$尾巴'}\n',
        reason: '★ 紧邻数学段 ⇒ 并入（同权：数学是这一行的对象）');
  });

  testWidgets('搜索框输入 ⇒ 只剩匹配项', (WidgetTester tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('symbol-alpha')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('symbol-search')), '阿尔法');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('symbol-alpha')), findsOneWidget);
    expect(find.byKey(const Key('symbol-frac')), findsNothing);
  });
}
