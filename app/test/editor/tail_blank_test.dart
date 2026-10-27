// ⑥「空行是一等公民」· 点"文末那片空白"的口径（**2026-10-27 变更**）
//
// ★★★ 口径变更：从 2026-10-17 的 **甲**（点空白 = 补一行空行，**改文档**）
//   改为 **点空白 = 只移光标、文档一个字都不变**。
//   用户 2026-10-27 原话：「点击下部空白让光标落到文末下一个空行，符合直觉和操作习惯，
//   但没必要和改文档冲突」——「文末下一个空行」**不是要造出来的东西**：
//   它就是这个位置（最后一行之后那一格 = `buf.length`），再按一次 Enter 也正落在那里。
//   旧口径的依据（2026-10-17 用户反问"既然我想这么做，还不想改文档，那我是要干什么"）
//   是在"Enter 曾经一次长两行"的语境下得到的；现在 Enter 一次正好一行、且光标看得见，
//   所以点击没有必要再替 Enter 干活。
//
// 版面：槽的高度 = 这一页剩下的正文高度（填的本来就是空的地方 ⇒ 不改变分页）；
//   竖条由槽自己画（贴顶画在最后一行下面）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/doc_view.dart';

final Finder _blankSlot = find.byWidgetPredicate(
    (Widget w) => w.runtimeType.toString() == '_BlankSlot');

Future<DocBuffer> _pump(WidgetTester tester, String doc) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer(doc)..setCaret(0);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: DocView(buffer: buf)),
    ),
  ));
  await tester.pumpAndSettle();
  return buf;
}

Iterable<Container> _bars(WidgetTester tester) => tester
    .widgetList<Container>(find.byType(Container))
    .where((Container c) => c.constraints?.maxWidth == 1.5);

void main() {
  testWidgets('★ 点文末空白 ⇒ 光标落到文末下一行，**文档一个字都不变**',
      (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, '甲\n');
    expect(_blankSlot, findsWidgets, reason: '单行文档也要有"文末空白"这个槽（尾部每一行各一个 + 末尾那片白）');
    await tester.tap(_blankSlot.first);
    await tester.pumpAndSettle();
    expect(buf.buf, '甲\n', reason: '点击只移光标（改前会补 `\\n` ⇒ `甲\\n\\n`）');
    expect(buf.caret, 2, reason: '光标落在最后一行之后那一格（文末下一行行首）');
  });

  testWidgets('★ 连点三次 ⇒ 文档不变、光标不动（不越点越长）', (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, '甲\n');
    for (var i = 0; i < 3; i++) {
      await tester.tap(_blankSlot.first);
      await tester.pumpAndSettle();
    }
    expect(buf.buf, '甲\n');
    expect(buf.caret, 2);
  });

  testWidgets('★ 点空白不产生编辑 ⇒ 撤销栈里没有东西可撤', (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, '甲\n');
    await tester.tap(_blankSlot.first);
    await tester.pumpAndSettle();
    expect(buf.undo(), isFalse, reason: '点击没有改文档，自然没有可撤销的编辑');
    expect(buf.buf, '甲\n');
  });

  testWidgets('★ 点完之后**竖条要画出来**（用户实测："能到空行，但光标显示不出来"）',
      (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, '甲\n');
    await tester.tap(_blankSlot.first);
    await tester.pumpAndSettle();
    expect(buf.caret, 2);
    expect(_bars(tester), isNotEmpty, reason: '文末下一行上必须看得见竖条');
  });

  testWidgets('★ Enter 到底再回车（文末空行）也要画竖条', (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, '甲\n\n');
    buf.setCaret(3); // 文末空行的行首（Enter 之后就是这个位置）
    await tester.pumpAndSettle();
    expect(_bars(tester), isNotEmpty, reason: 'Enter 出来的空行上要看得见光标');
  });

  testWidgets('★ 文末已有空行时：点它只移光标，**不画第二根**竖条',
      (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, '甲\n\n');
    buf.setCaret(3);
    await tester.pumpAndSettle();
    expect(_bars(tester).length, lessThanOrEqualTo(1),
        reason: '空白槽 + 文本层不该同时画两根（同一根像素只画一根）');
  });
}
