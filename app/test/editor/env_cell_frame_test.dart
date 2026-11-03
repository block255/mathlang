// 2026-11-03 晚：**每个空格子都要能画出格框**（用户："只有第一列画了框"）。
//
// 判据用自绘层的 pads（与 `env_click_test` ⑪ 同一套读法）：点进某格 ⇒ 那一格有框。

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/env_cells.dart';
import 'package:mathlang/render/math_caret.dart';

import '../support/math_fonts.dart';

String _doc(String tex) => '${r'$$'}\n$tex\n${r'$$'}';

Future<DocBuffer> _pump(WidgetTester tester, String tex) async {
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer(_doc(tex))..setCaret(0);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
  ));
  tester.state<EditViewState>(find.byType(EditView)).focusInput();
  await tester.pumpAndSettle();
  return buf;
}

RenderBox _root() =>
    find.byType(MathWithCaret).last.evaluate().single.renderObject! as RenderBox;

/// 自绘层的格框（宽 > 6 的 pad）。
List<Rect> _frames(WidgetTester tester) {
  final List<Rect> out = <Rect>[];
  for (final RenderObject ro in tester.allRenderObjects) {
    if (ro is RenderCustomPaint && ro.foregroundPainter is MathCaretPainter) {
      for (final SlotPad p in (ro.foregroundPainter! as MathCaretPainter).pads) {
        if (p.rect.width > 6) out.add(p.rect);
      }
    }
  }
  return out;
}

void main() {
  setUpAll(() async => loadMathFonts());

  testWidgets('全空的 2×3：点每一格都出框（不是只有第一列）',
      (WidgetTester tester) async {
    const String tex = r'\begin{pmatrix}&&\\&&\end{pmatrix}';
    final DocBuffer buf = await _pump(tester, tex);
    final RenderBox root = _root();
    for (var r = 0; r < 2; r++) {
      for (var c = 0; c < 3; c++) {
        buf.setCaret(0);
        await tester.pumpAndSettle();
        final Rect? box = envCellBoxAt(
            root: root, tex: tex, displayStyle: true, row: r, col: c,
            fontSize: 20, envIx: 0);
        expect(box, isNotNull, reason: '($r,$c) 量不到格框');
        await tester.tapAt(root.localToGlobal(box!.center));
        await tester.pumpAndSettle();
        expect(_frames(tester), isNotEmpty,
            reason: '点 ($r,$c) 之后应当有格框（用户：只有第一列有框）');
      }
    }
  });

  testWidgets('只填第一行的 4×6：下面三行每一格点进去都要有框',
      (WidgetTester tester) async {
    const String tex =
        r'\begin{bmatrix}a&b&2&3&4&5\\&&&&&\\&&&&&\\&&&&&\end{bmatrix}';
    final DocBuffer buf = await _pump(tester, tex);
    final RenderBox root = _root();
    for (var r = 1; r < 4; r++) {
      for (var c = 0; c < 6; c++) {
        buf.setCaret(0);
        await tester.pumpAndSettle();
        final Rect? box = envCellBoxAt(
            root: root, tex: tex, displayStyle: true, row: r, col: c,
            fontSize: 20, envIx: 0);
        if (box == null || box.width < 4 || box.height < 4) continue;
        await tester.tapAt(root.localToGlobal(box.center));
        await tester.pumpAndSettle();
        expect(_frames(tester), isNotEmpty,
            reason: '点 ($r,$c) 之后应当有格框');
      }
    }
  });

  testWidgets(r'行内矩阵（`$…$`）的每一格也要有框', (WidgetTester tester) async {
    const String tex = r'\begin{pmatrix}&&\\&&\end{pmatrix}';
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final DocBuffer buf = DocBuffer('前 \$$tex\$ 后')..setCaret(0);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
    ));
    tester.state<EditViewState>(find.byType(EditView)).focusInput();
    await tester.pumpAndSettle();
    for (var r = 0; r < 2; r++) {
      for (var c = 0; c < 2; c++) {
        buf.setCaret(0);
        await tester.pumpAndSettle();
        final RenderBox root = _root();
        final Rect? box = envCellBoxAt(
            root: root, tex: tex, displayStyle: false, row: r, col: c,
            fontSize: 16, envIx: 0);
        expect(box, isNotNull, reason: '($r,$c) 量不到格框');
        await tester.tapAt(root.localToGlobal(box!.center));
        await tester.pumpAndSettle();
        expect(_frames(tester), isNotEmpty,
            reason: '行内矩阵点 ($r,$c) 之后应当有格框');
      }
    }
  });
}