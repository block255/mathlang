// ★★ 「新建文档点不出光标」（用户 2026-10-18 晚报）· 根因与守卫
//
// 根因（读码 + 探针）：**空文档一个流单元都没有**
//   `BlockIndex.parse('')` ⇒ 「多个连续空行 = 一个边界，不产生空块」（R1）⇒ `blocks = []`
//   ⇒ `flowUnits = []` ⇒ `DocView._units = []` ⇒ 页面里连一个命中盒都不存在
//   ⇒ 点哪儿都落不了光标（打字也就没有插入点）。这不是"光标没画"，是"没有位置"。
//
// 修法：`_units.isEmpty` 时整页铺一个**空行槽**（落点 0、高度 = 正文高），
//   与"文末那片空白"同一个组件、同一套落点逻辑。
//   ★ 这是《位点》§11.46（空块不产出单元）的**最小补丁**，只补"零单元"这一种形态。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/doc_view.dart';
import 'package:mathlang/ui/editor_page.dart';

import '../support/fake_file_gateway.dart';
import '../support/symbol_fixture.dart';

final Finder _blankSlot =
    find.byWidgetPredicate((Widget w) => w.runtimeType.toString() == '_BlankSlot');

TextEditingValue _v(String text) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );

Future<DocBuffer> _pumpDocView(WidgetTester tester, String doc) async {
  final DocBuffer buf = DocBuffer(doc)..setCaret(0);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: DocView(buffer: buf)),
    ),
  ));
  await tester.pumpAndSettle();
  return buf;
}

Future<DocBuffer> _pumpPage(WidgetTester tester, String doc) async {
  tester.view.physicalSize = const Size(1500, 1000);
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
  return buf;
}

void main() {
  testWidgets('★ 空文档也要有**可点单元**（改前：一个都没有）',
      (WidgetTester tester) async {
    await _pumpDocView(tester, '');
    // 改前的红：`_units` 为空 ⇒ 文末槽要求 `prevUnit != null` 不成立 ⇒ findsNothing
    expect(_blankSlot, findsOneWidget,
        reason: '空文档必须至少有一个能落光标的单元，否则点击/打字全无入口');
  });

  testWidgets('★ 空文档点一下 ⇒ 光标落在 0，并且**画得出来**',
      (WidgetTester tester) async {
    final DocBuffer buf = await _pumpDocView(tester, '');
    await tester.tap(_blankSlot);
    await tester.pumpAndSettle();
    expect(buf.caret, 0);
    final Iterable<Container> bars = tester
        .widgetList<Container>(find.byType(Container))
        .where((Container c) => c.constraints?.maxWidth == 1.5);
    expect(bars, isNotEmpty, reason: '点了之后要看得见那根竖条（用户报的就是"点不出光标"）');
    expect(buf.buf, '', reason: '空文档上点一下**不改文档**（与文末空白不同：这里没有行可加）');
  });

  testWidgets('★ 新建空文档：点空白 ⇒ 直接能打字（光标 0 处插入）',
      (WidgetTester tester) async {
    final DocBuffer buf = await _pumpPage(tester, '');
    await tester.tap(_blankSlot);
    await tester.pumpAndSettle();
    tester.testTextInput.updateEditingValue(_v('答'));
    await tester.pump();
    expect(buf.buf, '答', reason: '新建文档点一下就该能写第一个字');
    expect(buf.caret, 1);
  });
}
