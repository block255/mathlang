// TEMP PROBE v7（用完即删）：环境**外侧**点击
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/math_caret.dart';

import 'support/math_fonts.dart';

void main() {
  setUpAll(() async => loadMathFonts());

  testWidgets('probe outside', (WidgetTester tester) async {
    const String tex = r'\begin{pmatrix} A & B \\ C & D \end{pmatrix}';
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final DocBuffer buf = DocBuffer('${r'$$'}\n$tex\n${r'$$'}')..setCaret(0);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
    ));
    tester.state<EditViewState>(find.byType(EditView)).focusInput();
    await tester.pumpAndSettle();
    final RenderBox root =
        find.byType(MathWithCaret).last.evaluate().single.renderObject! as RenderBox;
    final Offset tl = root.localToGlobal(Offset.zero);
    final double midY = tl.dy + root.size.height / 2;
    final Map<String, Offset> pts = <String, Offset>{
      'inside-left-edge': Offset(tl.dx + 1, midY),
      'outside-left-8': Offset(tl.dx - 8, midY),
      'outside-left-40': Offset(tl.dx - 40, midY),
      'inside-right-edge': Offset(tl.dx + root.size.width - 1, midY),
      'outside-right-8': Offset(tl.dx + root.size.width + 8, midY),
      'above-block': Offset(tl.dx + root.size.width / 2, tl.dy - 12),
      'below-block': Offset(tl.dx + root.size.width / 2, tl.dy + root.size.height + 12),
    };
    for (final MapEntry<String, Offset> e in pts.entries) {
      buf.setCaret(0);
      await tester.tapAt(e.value);
      await tester.pumpAndSettle();
      // ignore: avoid_print
      print('PT ${e.key} caret=${buf.caret} (content=[3,${buf.buf.length - 3}) len=${buf.buf.length})');
    }
  });
}