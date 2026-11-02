// ★★ 2026-11-02（选择边界与剪贴板批）：**删除/剪切**的端到端守卫。
//
// 单元判据在 `test/lang/delete_range_test.dart`；这里只钉"接进编辑器之后"：
//   · 拖选删 `a`（`a^2` 的底）⇒ 文档里不许剩 `^2`；一步撤销回到原样；
//   · 剪切 = **删什么就复制什么**：选区在 `a` 上，删的是 `a^2`，剪贴板就是 `$a^2$`。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/ui/editor_page.dart';

import '../support/fake_file_gateway.dart';
import '../support/symbol_fixture.dart';

const String kDoc = '前 \$a^2\$ 后';

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

Future<void> _undo(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

Future<void> _cut(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

void main() {
  final List<String> copied = <String>[];

  setUp(() {
    copied.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform,
            (MethodCall call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map<Object?, Object?>)['text'] as String);
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('★ 删底 `a` ⇒ 不许剩 `^2`；一步撤销回原样', (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, kDoc);
    final int a = kDoc.indexOf('a');
    buf.setSelection(a, a + 1);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();

    expect(buf.buf.contains('^2'), isFalse,
        reason: '删底之后剩 `^2` 就是残片：${buf.buf}');
    expect(buf.buf.contains('a'), isFalse, reason: buf.buf);

    await _undo(tester);
    // 编辑器在载入/编辑后会补一个尾换行 —— 与 kDoc 比时按 body 比（既有约定）。
    expect(buf.buf.trimRight(), kDoc, reason: '撤销必须一步回到原样');
  });

  testWidgets('★ 剪切 = 删什么就复制什么（选 `a`，删/拷 `a^2`）',
      (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, kDoc);
    final int a = kDoc.indexOf('a');
    buf.setSelection(a, a + 1);
    await tester.pumpAndSettle();
    await _cut(tester);

    expect(copied, isNotEmpty, reason: '剪切必须写剪贴板');
    expect(copied.last, r'$a^2$',
        reason: '剪贴板必须是**实际删掉**的那段（不是只选了 `a`）');
    expect(buf.buf.contains('^2'), isFalse, reason: buf.buf);
  });
}
