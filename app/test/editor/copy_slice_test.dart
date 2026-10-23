// ★★ 2026-10-23（批 1 · A1/A2）：**复制/剪切的接线**（走真实的 Ctrl+C / Ctrl+X）。
//
// 用户实测：复制行内公式里的一个分式，剪贴板里是
//     `\frac{x^3}{\lvert \sin x\rvert^3}$`   ← 缺开头 `$`、多结尾 `$`
// 粘回去就在公式后面挂一个裸 `$`。
//
// 改前必红：改前 `Ctrl+C` 走 `_selectedText`（裸 substring）⇒ 拿不到成对的 `$`。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/ui/editor_page.dart';

import '../support/fake_file_gateway.dart';
import '../support/symbol_fixture.dart';

const String _doc = r'设 $a^2+b^2=c^2$ 成立';

Future<DocBuffer> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer(_doc)..setCaret(0);
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

/// 拦下剪贴板写入，返回最后一次写进去的文本
String? _lastClipboard(List<MethodCall> calls) {
  final Iterable<MethodCall> sets =
      calls.where((MethodCall c) => c.method == 'Clipboard.setData');
  if (sets.isEmpty) return null;
  final Map<Object?, Object?> args =
      sets.last.arguments as Map<Object?, Object?>;
  return args['text'] as String?;
}

void main() {
  testWidgets(r'Ctrl+C 复制公式内部的片段 ⇒ 剪贴板里 `$` 成对', (WidgetTester tester) async {
    final List<MethodCall> calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (MethodCall c) async {
      calls.add(c);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final DocBuffer buf = await _pump(tester);
    buf.setSelection(_doc.indexOf('a^2'), _doc.indexOf('=c^2'));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    final String? text = _lastClipboard(calls);
    expect(text, isNotNull, reason: 'Ctrl+C 必须真的写剪贴板');
    expect(text, r'$a^2+b^2$',
        reason: r'改前是裸 `a^2+b^2`（没有定界符）或半截 `…=c^2$`');
  });

  testWidgets(r'Ctrl+X 剪切 ⇒ 文档里不留半截 `$`', (WidgetTester tester) async {
    final List<MethodCall> calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (MethodCall c) async {
      calls.add(c);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final DocBuffer buf = await _pump(tester);
    // 选区起点在公式内部、终点在文字里 ⇒ 切片会把起点扩到 `$`
    buf.setSelection(_doc.indexOf('b^2'), _doc.indexOf(' 成立'));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    final String? text = _lastClipboard(calls);
    expect(text, r'$a^2+b^2=c^2$', reason: '剪切也要给自洽片段');
    final int dollars = buf.buf.split(r'$').length - 1;
    expect(dollars.isEven, isTrue,
        reason: '剪完文档里 `\$` 必须成对（改前会留下孤零零的收尾 `\$`）：${buf.buf}');
  });
}
