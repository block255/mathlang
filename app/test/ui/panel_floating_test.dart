// 数语引擎 · **覆盖式面板 = 视觉覆盖，不是模态**（2026-10-18 用户拍板）
//
// 用户原话（类比）：
//   「9336 打开可以悬浮在机甲网页上面，但是不影响机甲网页其他部分的视觉；
//     我操作机甲网页也不影响它们继续悬浮。」
//
// 所以三条判据：
//   ① 面板打开时**没有遮罩**（页面不被压暗）；
//   ② 点编辑器区域 ⇒ 面板**不关**；
//   ③ 面板开着也能**继续打字进正文**（编辑器不失焦）—— 想用搜索框就点它一下。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/ui/editor_page.dart';

import '../support/fake_file_gateway.dart';
import '../support/symbol_fixture.dart';

TextEditingValue _v(String text) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );

Future<(EditorPageState, DocBuffer)> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1500, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer('甲乙丙')..setCaret(0);
  await tester.pumpWidget(MaterialApp(
    home: EditorPage(
      library: testSymbolLibrary(),
      buffer: buf,
      gateway: FakeFileGateway(),
    ),
  ));
  await tester.pumpAndSettle();
  // 点正文 ⇒ 编辑面拿到焦点（与真人操作一致）
  await tester.tap(find.textContaining('甲').first);
  await tester.pumpAndSettle();
  buf.setCaret(0);
  await tester.pump();
  return (tester.state<EditorPageState>(find.byType(EditorPage)), buf);
}

void main() {
  testWidgets('★ 默认就打开符号面板与快捷栏（2026-10-18 晚用户定）',
      (WidgetTester tester) async {
    final (EditorPageState st, _) = await _pump(tester);
    // ★ 判据：**未修改任何设置**时，两个入口都在屏幕上（各是各的开关）
    expect(st.panelOpen, isTrue,
        reason: '用户原话：「未修改时，符号面板与快捷栏默认都打开」');
    expect(st.quickOpen, isTrue);
    expect(find.byKey(const Key('symbol-panel')), findsOneWidget);
    expect(find.byKey(const Key('quick-slot-0')), findsOneWidget);
  });

  testWidgets('★ 面板打开时没有遮罩（页面不压暗）', (WidgetTester tester) async {
    final (EditorPageState st, _) = await _pump(tester);
    st.togglePanel(open: true);
    await tester.pumpAndSettle();

    expect(st.panelOpen, isTrue);
    expect(find.byKey(const Key('symbol-panel')), findsOneWidget);
    expect(find.byKey(const Key('panel-scrim')), findsNothing,
        reason: '覆盖 = 视觉覆盖，不是模态；那层 26% 黑要彻底去掉');
  });

  testWidgets('★ 点编辑器不会关掉面板（交互不被抢）',
      (WidgetTester tester) async {
    final (EditorPageState st, _) = await _pump(tester);
    st.togglePanel(open: true);
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('甲').first);
    await tester.pumpAndSettle();

    expect(st.panelOpen, isTrue, reason: '点编辑器是"编辑"，不是"点外面关闭"');
  });

  testWidgets('★ 面板开着也能继续打字（编辑器没失焦）',
      (WidgetTester tester) async {
    final (EditorPageState st, DocBuffer buf) = await _pump(tester);
    st.togglePanel(open: true);
    await tester.pumpAndSettle();

    // 打开面板**不许**把焦点抢给搜索框 ⇒ 文本通道仍属于编辑面
    // ★ 2026-10-28：`before` 是**归一前**的长度；打完字缓冲区会带上行终止符 ⇒ 基准也算归一后
    final int before = normalizeDocumentText(buf.buf).length;
    tester.testTextInput.updateEditingValue(_v('Z'));
    await tester.pump();

    expect(buf.length, before + 1, reason: '面板开着时打字要直接进正文');
    expect(buf.buf.contains('Z'), isTrue);
    expect(st.panelOpen, isTrue);
  });

  testWidgets('Esc 仍然能关掉面板（关闭方式：Esc / 顶栏开关）',
      (WidgetTester tester) async {
    final (EditorPageState st, _) = await _pump(tester);
    st.togglePanel(open: true);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(st.panelOpen, isFalse);
  });
}
