// ★★ 2026-10-20（T-A 实战测试 F2，用户可见的小矛盾）：**新建之后"次编辑"要归零**。
//
// 改前现场：新建（`loadDocument('')`）之后状态栏显示「0 字符 · **2 次编辑**」——
// 一个字符都没有的文档却有两次编辑，数字自相矛盾。
//
// 根因：`EditView._edits` 只在**换 buffer 实例**（`didUpdateWidget`）时归零，
// 而 `newDocument()` / `openDocument()` 是**同一个实例**整篇换掉（`DocBuffer.loadDocument`）。
// 修法：`DocBuffer.docEpoch` 在 `loadDocument` 里 +1，编辑层看到它变了就清零（连带清"自动包裹"）。
//
// 判据走**状态栏真实文字**（`status-text` 那一串，不是读私有字段）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/ui/editor_page.dart';

import '../support/fake_file_gateway.dart';
import '../support/symbol_fixture.dart';

Future<DocBuffer> _pumpPage(WidgetTester tester, String doc) async {
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
  return buf;
}

/// 状态栏那一行文字（`共 N 页 · N 字符 · 光标 N · N 次编辑`）
String _status(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('status-text'))).data ?? '';

void main() {
  testWidgets('★ F2：`loadDocument`（新建 / 打开）之后「次编辑」归零',
      (WidgetTester tester) async {
    final DocBuffer buf = await _pumpPage(tester, '甲乙');
    expect(_status(tester), contains('0 次编辑'));

    // 走**真实编辑路径**（符号面板那条）做一次编辑 ⇒ 计数 +1
    final EditViewState st = tester.state<EditViewState>(find.byType(EditView));
    st.insertSymbolTex('', template: true, display: true);
    await tester.pumpAndSettle();
    expect(buf.buf.contains(r'$$'), isTrue, reason: '先确认这次编辑真的发生了');
    expect(_status(tester), contains('1 次编辑'),
        reason: '基线：计数在工作（改前改后都该是这样）');

    // 新建 / 打开走的就是这一句（同一个 buffer 实例）
    buf.loadDocument('');
    await tester.pumpAndSettle();

    expect(_status(tester), contains('0 字符'));
    expect(_status(tester), contains('0 次编辑'),
        reason: '换了一份文档 ⇒ 编辑计数必须归零（改前会留成 `1 次编辑`）');
    expect(buf.docEpoch, 1, reason: '载入序号 +1（编辑层就靠它认"换文档了"）');
  });

  testWidgets('★ F2 反例：普通编辑不归零（别把"换文档"判据做成"每次都清"）',
      (WidgetTester tester) async {
    final DocBuffer buf = await _pumpPage(tester, '甲乙');
    final EditViewState st = tester.state<EditViewState>(find.byType(EditView));
    st.insertSymbolTex('', template: true, display: true);
    await tester.pumpAndSettle();
    st.insertSymbolTex(r'\alpha', template: false);
    await tester.pumpAndSettle();
    expect(_status(tester), contains('2 次编辑'));
    expect(buf.docEpoch, 0);
  });
}
