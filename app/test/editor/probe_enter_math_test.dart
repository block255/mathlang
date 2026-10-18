// 临时探针（用完即删）：行内/行间数学里按 Enter 的产物
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';

Future<DocBuffer> _mount(WidgetTester tester, String doc, int caret) async {
  final DocBuffer buf = DocBuffer(doc)..setCaret(caret);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(height: 600, child: SingleChildScrollView(child: EditView(buffer: buf))),
    ),
  ));
  final EditViewState st = tester.state<EditViewState>(find.byType(EditView));
  st.focusInput();
  buf.setCaret(caret);
  await tester.pump();
  return buf;
}

void main() {
  testWidgets('probe enter in math', (WidgetTester tester) async {
    // (doc, caret, 说明)
    final List<(String, int, String)> cases = <(String, int, String)>[
      (r'a $x+y$ b', 5, '行内数学中间（+ 与 y 之间）'),
      (r'a $x+y$ b', 7, '行内数学末尾（y 之后）'),
      (r'a $x+y$ b', 3, '行内数学开头（x 之前）'),
      (r'$$\nx+y\n$$', 5, '行间块中间'),
    ];
    for (final (String doc, int caret, String why) in cases) {
      final DocBuffer buf = await _mount(tester, doc, caret);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      // ignore: avoid_print
      print('--- $why\n  doc=$doc caret=$caret\n  → ${buf.buf.replaceAll("\n", r"\n")}  caret=${buf.caret}');
    }
  });
}
