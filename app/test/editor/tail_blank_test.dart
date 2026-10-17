// ⑥「空行是一等公民」· **甲**（2026-10-17 用户拍板）
//
// 用户原话：「添加空行有 **enter 途径** 和 **点下方空白途径**」，
// 并反问：「enter 换行难道不改文档吗？既然我想这么做，我还不想改文档，那我是要干什么」
// ⇒ **两条路都会改文档**，不存在"点空白要不要改文档"的问题。
//
// 规则（幂等）：点文末那片空白 ⇒
//   文末已是 `…\n\n` ⇒ 只移光标过去；末尾只有一个 `\n` ⇒ 补一个；没有换行 ⇒ 补两个。
//   一次插入 = 一步编辑（`Ctrl+Z` 可一步回退）。
// 版面：槽的高度 = **这一页剩下的正文高度**（填的本来就是空的地方 ⇒ 不改变分页），
//   竖条**贴顶**画在最后一行下面。
// ★ 只有**文末真的有那一行空行**时才画竖条（否则会与最后一行字尾的光标叠成两根）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/doc_view.dart';

final Finder _blankSlot = find.byWidgetPredicate(
    (Widget w) => w.runtimeType.toString() == '_BlankSlot');

Future<DocBuffer> _pump(WidgetTester tester, String doc) async {
  final DocBuffer buf = DocBuffer(doc)..setCaret(0);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: DocView(buffer: buf)),
    ),
  ));
  await tester.pumpAndSettle();
  return buf;
}

void main() {
  testWidgets('★ 点文末空白 ⇒ **文末多一行空行**、光标落在新行行首',
      (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, '甲');
    expect(buf.buf, '甲');
    expect(_blankSlot, findsOneWidget, reason: '单行文档也要有"文末空白"这个槽');
    await tester.tap(_blankSlot);
    await tester.pumpAndSettle();
    expect(buf.buf, '甲\n\n', reason: '文末补两个换行 = 起一行空行');
    expect(buf.caret, 3, reason: '光标落在新行行首（= 文末）');
  });

  testWidgets('★ 再点一次 ⇒ 文档**不再变**（幂等，不会越点越长）',
      (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, '甲');
    await tester.tap(_blankSlot);
    await tester.pumpAndSettle();
    await tester.tap(_blankSlot);
    await tester.pumpAndSettle();
    await tester.tap(_blankSlot);
    await tester.pumpAndSettle();
    expect(buf.buf, '甲\n\n', reason: '已有一行空行 ⇒ 不再插入');
    expect(buf.caret, 3);
  });

  testWidgets('★ 文末只有一个换行 ⇒ 补一个（不补成两行）', (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, '甲\n');
    await tester.tap(_blankSlot);
    await tester.pumpAndSettle();
    expect(buf.buf, '甲\n\n');
    expect(buf.caret, 3);
  });

  testWidgets('★ 点空白是**一步编辑**：Ctrl+Z 一步回到原样', (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, '甲');
    await tester.tap(_blankSlot);
    await tester.pumpAndSettle();
    expect(buf.undo(), isTrue, reason: '点空白要能一步撤销');
    expect(buf.buf, '甲', reason: '一步就该回到点之前');
  });

  testWidgets('★ 点完之后**竖条要画出来**（用户实测："能到空行，但光标显示不出来"）',
      (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, '甲');
    await tester.tap(_blankSlot);
    await tester.pumpAndSettle();
    expect(buf.buf, '甲\n\n');
    final Iterable<Container> bars = tester
        .widgetList<Container>(find.byType(Container))
        .where((Container c) => c.constraints?.maxWidth == 1.5);
    expect(bars, isNotEmpty,
        reason: '空行上必须看得见竖条：插入 `\\n\\n` 后光标在 after+1，'
            '而空行起点是 after ⇒ 判据不能写 `_caret == after`');
  });

  testWidgets('★ Enter 到底再回车（文末空行）也要画竖条', (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, '甲\n\n');
    buf.setCaret(3); // 文末空行的行首（Enter 之后就是这个位置）
    await tester.pumpAndSettle();
    final Iterable<Container> bars = tester
        .widgetList<Container>(find.byType(Container))
        .where((Container c) => c.constraints?.maxWidth == 1.5);
    expect(bars, isNotEmpty, reason: 'Enter 出来的空行上要看得见光标');
  });

  testWidgets('★ 文末已有空行时：点它只移光标，**不画第二根**竖条',
      (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, '甲\n\n');
    buf.setCaret(3);
    await tester.pumpAndSettle();
    // 竖条由槽自己画：找到那个 1.5 宽的 Container
    final Iterable<Container> bars = tester
        .widgetList<Container>(find.byType(Container))
        .where((Container c) => c.constraints?.maxWidth == 1.5);
    expect(bars.length, lessThanOrEqualTo(1),
        reason: '空白槽 + 文本层不该同时画两根（同一根像素只画一根）');
  });
}
