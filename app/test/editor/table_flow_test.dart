// ★★ 2026-11-03（表批 A）：**表选择的端到端**——真 `EditView` + 真 Ctrl+C / Ctrl+X。
//
// 纯函数（`clipboard_slice` / `planDelete`）已经有了单元守卫；这一层钉的是**接线**：
// 拖选落在表里时，剪贴板拿到的是**整格矩形**、文档里 `&` / `\\` 还在。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/ui/editor_page.dart';

import '../support/fake_file_gateway.dart';
import '../support/symbol_fixture.dart';

const String _doc = '\$\$\n\\begin{pmatrix}a&b\\\\c&d\\end{pmatrix}\n\$\$';

Future<DocBuffer> _pump(WidgetTester tester, {String doc = _doc}) async {
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

String? _lastClipboard(List<MethodCall> calls) {
  final Iterable<MethodCall> sets =
      calls.where((MethodCall c) => c.method == 'Clipboard.setData');
  if (sets.isEmpty) return null;
  final Map<Object?, Object?> args =
      sets.last.arguments as Map<Object?, Object?>;
  return args['text'] as String?;
}

/// 格内容都是单字母：`}a` / `&b` / `\\c` 三种前缀。
int _cell(String doc, String name) {
  for (final String lead in <String>['}', '&', r'\\']) {
    final int i = doc.indexOf('$lead$name');
    if (i >= 0) return i + lead.length;
  }
  fail('找不到格「$name」');
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Ctrl+C 选一行两格 ⇒ 剪贴板是中性 bmatrix 矩形',
      (WidgetTester tester) async {
    final List<MethodCall> calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (MethodCall c) async {
      calls.add(c);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final DocBuffer buf = await _pump(tester);
    buf.setSelection(_cell(_doc, 'a'), _cell(_doc, 'b') + 1);
    await tester.pumpAndSettle();
    await _press(tester, LogicalKeyboardKey.keyC);

    expect(_lastClipboard(calls), r'$\begin{bmatrix}a&b\end{bmatrix}$');
  });

  testWidgets('Ctrl+C 选整张表 ⇒ 保留原类型（pmatrix 不变 bmatrix）',
      (WidgetTester tester) async {
    final List<MethodCall> calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (MethodCall c) async {
      calls.add(c);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final DocBuffer buf = await _pump(tester);
    buf.setSelection(_cell(_doc, 'a'), _cell(_doc, 'd') + 1);
    await tester.pumpAndSettle();
    await _press(tester, LogicalKeyboardKey.keyC);

    expect(_lastClipboard(calls), r'$\begin{pmatrix}a&b\\c&d\end{pmatrix}$');
  });

  testWidgets(r'Ctrl+X 剪切一行 ⇒ 文档里 `&` 与 `\\` 都还在（删格留空）',
      (WidgetTester tester) async {
    final List<MethodCall> calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (MethodCall c) async {
      calls.add(c);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final DocBuffer buf = await _pump(tester);
    final String before = buf.buf; // 引擎可能给文末补一个换行，别拿常量比
    buf.setSelection(_cell(_doc, 'a'), _cell(_doc, 'b') + 1);
    await tester.pumpAndSettle();
    await _press(tester, LogicalKeyboardKey.keyX);

    expect(_lastClipboard(calls), r'$\begin{bmatrix}a&b\end{bmatrix}$');
    expect(buf.buf, contains(r'\begin{pmatrix}&\\c&d\end{pmatrix}'),
        reason: '删格留空：${buf.buf}');
    // 一步撤销能回到原样（引擎会补文末换行，比内容不比那一个 `\n`）
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(buf.buf.trimRight(), before.trimRight(),
        reason: '撤销必须一步回到原样：'
            '「${buf.buf.replaceAll('\n', '⏎')}」 vs 「${before.replaceAll('\n', '⏎')}」');
  });

  testWidgets('局部片段粘到正文 ⇒ 按行落成行内公式（不再造矩阵）',
      (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, doc: '开头\n\n$_doc\n\n后文');
    buf.setCaret(buf.buf.length); // 文末 = 正文
    await tester.pumpAndSettle();
    final EditViewState state = tester.state<EditViewState>(find.byType(EditView));
    state.pasteText(r'$\begin{bmatrix}a&b\end{bmatrix}$');
    await tester.pumpAndSettle();
    expect(buf.buf, contains(r'$a\ b$'), reason: buf.buf);
    expect(buf.buf, isNot(contains(r'\begin{bmatrix}')), reason: buf.buf);
  });
}
