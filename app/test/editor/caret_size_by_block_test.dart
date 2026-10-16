// 【临时探针 · 用完即删】文本侧光标高度：标题 / 正文 / 列表项 / 数学侧各是多少。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/math_caret.dart';
import 'package:mathlang/render/inline_math_text.dart';

const String kDoc = '# 标题行\n\n正文一行\n\n- 列表一行\n\n\$\$\nx=\\frac{a}{b}\n\$\$\n';

Future<void> _mount(WidgetTester tester, DocBuffer buf) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
  ));
  tester.state<EditViewState>(find.byType(EditView)).focusInput();
  await tester.pumpAndSettle();
}

String _f(double v) => v.toStringAsFixed(1);

void main() {
  testWidgets('各块类型的光标条高度', (WidgetTester tester) async {
    final DocBuffer buf = DocBuffer(kDoc);
    await _mount(tester, buf);

    for (final int caret in <int>[1, 8, 14, 23]) {
      buf.setCaret(caret);
      await tester.pump();
      await tester.pump();

      // 文本侧：`_caretBar` 里那个 Container（宽 = caretWidth 1.5）
      final List<String> textBars = <String>[];
      for (final Element e in find.byType(Container).evaluate()) {
        final Container c = e.widget as Container;
        if (c.constraints == null && c.color != null && c.child == null) {
          final Rect r = tester.getRect(find.byWidget(c));
          if (r.width <= 4) {
            textBars.add('w ${_f(r.width)} h ${_f(r.height)} y ${_f(r.top)}..${_f(r.bottom)}');
          }
        }
      }
      // 数学侧
      final List<String> mathBars = <String>[];
      for (final Element e in find.byType(CustomPaint).evaluate()) {
        final CustomPainter? p = (e.widget as CustomPaint).foregroundPainter;
        if (p is MathCaretPainter) {
          mathBars.add('w ${_f(p.rect.width)} h ${_f(p.rect.height)} '
              'y ${_f(p.rect.top)}..${_f(p.rect.bottom)}');
        }
      }
      // 这一格的字号（段落实际字号）
      final List<String> sizes = <String>[];
      for (final Element e in find.byType(InlineMathText).evaluate()) {
        final InlineMathText w = e.widget as InlineMathText;
        sizes.add('mathFont=${w.mathFontSize} textFont=${w.textStyle?.fontSize}');
      }
      debugPrint('caret=$caret  文本侧=[${textBars.join(" | ")}]  '
          '数学侧=[${mathBars.join(" | ")}]  字号=[${sizes.join(" ; ")}]');
    }
  });
}
