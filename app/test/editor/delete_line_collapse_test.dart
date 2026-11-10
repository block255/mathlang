// 20261110 · 反馈 ③：**选区删除 / 剪切也要走"删空一段就收掉它自己的换行"**
//
// 口径（2026-11-10 用户拍板，待写进《行与段-空行基准》）：
//   **删掉一段的可见内容后，上下文距离不变** —— 被删空的位置算 1 行，两侧原来各有几行就还是几行。
//   实现 = 收掉并置出来的那一个换行（与逐字删除同一条）。
//
// 为什么必须有这批守卫（改前实测）：
//   · 逐字退格：`A⏎⏎B⏎⏎C` 删光 B ⇒ `A⏎⏎⏎C`（**有**退化）
//   · 选区删除：同一个意图 ⇒ `A⏎⏎⏎⏎C`（**没有**退化）⇒ 两段之间多出整整一行空白
//   现场：`……⏎⏎<那一行>⏎⏎尾` 拖选整行删除，版面 1.99 行 → 2.99 行（用户："两个空行"）。
//
// 本文件钉四组：
//   ① 整行删（只选可见内容）× 三种邻接 × {Delete, Ctrl+X} ⇒ 收掉一个换行
//   ② 文首 / 文末
//   ③ 只有空格的行：**删空了才收**；删完还剩空格 ⇒ 不收（2026-11-10："有空格的不算完全空行"）
//   ④ **不回归**：跨行拖选删除的字节必须与今天逐字节一致（改前绿、改后仍绿）

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';

const String kB = 'B行内容';
const String kTail = 'C行';

Future<DocBuffer> _mount(WidgetTester tester, String doc) async {
  tester.view.physicalSize = const Size(1100, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer(doc);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
  ));
  tester.state<EditViewState>(find.byType(EditView)).focusInput();
  await tester.pumpAndSettle();
  return buf;
}

Future<void> _deleteSelection(WidgetTester tester, DocBuffer buf, int from, int to) async {
  buf.setSelection(from, to);
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.delete);
  await tester.pumpAndSettle();
}

Future<void> _cutSelection(WidgetTester tester, DocBuffer buf, int from, int to) async {
  buf.setSelection(from, to);
  await tester.pump();
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

/// 只选 B 那一行的**可见内容**（不含任何换行）
int _bFrom(String doc) => doc.indexOf(kB);

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform,
            (MethodCall call) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('① 整行删（只选可见内容）⇒ 收掉一个换行', () {
    testWidgets('各隔一个 md 空行 · Delete', (WidgetTester tester) async {
      const String doc = 'A行\n\n$kB\n\n$kTail\n';
      final DocBuffer buf = await _mount(tester, doc);
      final int f = _bFrom(doc);
      await _deleteSelection(tester, buf, f, f + kB.length);
      expect(buf.buf, 'A行\n\n\n$kTail\n',
          reason: '两段之间 3 个换行 = 1 个空行（改前是 4 个 = 2 个空行）');
    });

    testWidgets('各隔一个 md 空行 · 剪切', (WidgetTester tester) async {
      const String doc = 'A行\n\n$kB\n\n$kTail\n';
      final DocBuffer buf = await _mount(tester, doc);
      final int f = _bFrom(doc);
      await _cutSelection(tester, buf, f, f + kB.length);
      expect(buf.buf, 'A行\n\n\n$kTail\n', reason: '剪切与删除必须同结果');
    });

    testWidgets('各隔两个 md 空行 · Delete', (WidgetTester tester) async {
      const String doc = 'A行\n\n\n$kB\n\n\n$kTail\n';
      final DocBuffer buf = await _mount(tester, doc);
      final int f = _bFrom(doc);
      await _deleteSelection(tester, buf, f, f + kB.length);
      expect(buf.buf, 'A行\n\n\n\n\n$kTail\n',
          reason: '两侧各 2 个空行时，删完仍是 3 个空行（5 个换行）；改前是 6 个');
    });

    testWidgets('紧邻（单换行）· Delete', (WidgetTester tester) async {
      const String doc = 'A行\n$kB\n$kTail\n';
      final DocBuffer buf = await _mount(tester, doc);
      final int f = _bFrom(doc);
      await _deleteSelection(tester, buf, f, f + kB.length);
      expect(buf.buf, 'A行\n$kTail\n',
          reason: '与逐字退格同一条（删空了一行就把它自己的换行收掉），改前是 A行⏎⏎C行');
    });
  });

  group('② 文首 / 文末', () {
    testWidgets('文首：删掉第一段 ⇒ 收一格', (WidgetTester tester) async {
      const String doc = '$kB\n\n$kTail\n';
      final DocBuffer buf = await _mount(tester, doc);
      await _deleteSelection(tester, buf, 0, kB.length);
      expect(buf.buf, '\n$kTail\n', reason: '文首每个空行都算一行 ⇒ 收完只剩 1 个换行');
    });

    testWidgets('文末：删掉最后一段 ⇒ 收一格、光标不越界', (WidgetTester tester) async {
      const String doc = 'A行\n\n$kB\n';
      final DocBuffer buf = await _mount(tester, doc);
      final int f = _bFrom(doc);
      await _deleteSelection(tester, buf, f, f + kB.length);
      expect(buf.buf, 'A行\n\n', reason: '文末收完只剩段界');
      expect(buf.caret, lessThanOrEqualTo(buf.buf.length));
    });
  });

  group('③ 只有空格的行（2026-11-10：有空格的不算完全空行）', () {
    testWidgets('删完还剩空格 ⇒ **不收**', (WidgetTester tester) async {
      const String doc = 'A行\n\n  x  \n\n$kTail\n';
      final DocBuffer buf = await _mount(tester, doc);
      final int f = doc.indexOf('x');
      await _deleteSelection(tester, buf, f, f + 1);
      expect(buf.buf, 'A行\n\n    \n\n$kTail\n',
          reason: '这一行还剩两个空格 ⇒ 它不是空行 ⇒ 不许收掉它的换行');
    });
  });

  group('④ 不回归：跨行拖选删除保持原语义', () {
    testWidgets('选区跨过换行 ⇒ 字节与今天逐字节一致', (WidgetTester tester) async {
      const String doc = 'A行\n\n$kB\n\n$kTail\n';
      final DocBuffer buf = await _mount(tester, doc);
      final int f = _bFrom(doc);
      // 从 B 的第一个字选到 C 的第一个字之后（跨过 B 的行终止符与分隔符）
      final int to = doc.indexOf(kTail) + 1;
      await _deleteSelection(tester, buf, f, to);
      // 今天的语义：删掉选中的那段字节，不做任何"收换行"
      final String expected = doc.replaceRange(f, to, '');
      expect(buf.buf, expected,
          reason: '跨行删除是"删掉若干行"，不是"删空一段" ⇒ 退化不许参与');
    });
  });
}
