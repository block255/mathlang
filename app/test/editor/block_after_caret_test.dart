// ③-C：**行间公式块的前后那一格也必须有人画光标**（修掉"走出公式 ⇒ 光标消失"）。
//
// 用户实测 ②：「在分式内用右箭头把光标切到分式后面，光标会消失，但删除仍能删掉整个分式」。
// 实测根因（§11.25）：行内公式靠 `caretPlacement` 的「两端各多认领一格」解决了"公式前后各一格"；
// 而行间**块**的接收区间只有 `[renderBase, renderEnd]`（= 公式本身），
// 于是光标走到"块之后那一格"时**没有任何单元认领它** ⇒ `showCaret = false`、竖条 0。
//
// 目标：块的单元**认领自己整片源码**（围栏与行尾都算），
//       `relFor` 把两端夹进 tex ⇒ 光标画在公式的**左 / 右边缘**。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/math_caret.dart';

const String kDoc = '前\n\n\$\$\nx=\\frac{a}{b}\n\$\$\n\n后\n';

Future<void> _mount(WidgetTester tester, DocBuffer buf) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
  ));
  tester.state<EditViewState>(find.byType(EditView)).focusInput();
  await tester.pumpAndSettle();
}

/// 有谁在画自绘竖条吗（`MathCaretPainter` 是公开类）
int _bars(WidgetTester tester) {
  var n = 0;
  for (final Element e in find.byType(CustomPaint).evaluate()) {
    if ((e.widget as CustomPaint).foregroundPainter is MathCaretPainter) n++;
  }
  return n;
}

bool _blockShowsCaret(WidgetTester tester) => find
    .byType(MathWithCaret)
    .evaluate()
    .any((Element e) => (e.widget as MathWithCaret).showCaret);

void main() {
  group('③-C 行间块的块前 / 块后那一格', () {
    testWidgets(r'★ 块**之后**那一格（闭合围栏之后）⇒ 仍有人画光标', (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer(kDoc);
      await _mount(tester, buf);

      final int open = kDoc.indexOf(r'$$');
      final int close = kDoc.indexOf(r'$$', open + 2);
      final int afterBlock = close + 2; // 闭合围栏的后面那一格
      debugPrint('块围栏 = [$open, ${close + 2})  块后那一格 = $afterBlock');

      buf.setCaret(afterBlock);
      await tester.pump();
      await tester.pump();
      expect(_blockShowsCaret(tester), isTrue,
          reason: '光标在块之后那一格时，块应当**认领**它并把光标画在公式右缘；'
              '若为 false = 这一格没有任何单元认领（用户看到的"光标消失"）');
      expect(_bars(tester), greaterThan(0), reason: '自绘竖条应当画出来');
    });

    testWidgets(r'★ 块**之前**那一格（开围栏之前）⇒ 仍有人画光标', (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer(kDoc);
      await _mount(tester, buf);

      final int open = kDoc.indexOf(r'$$');
      buf.setCaret(open - 1); // 块之前那一格
      await tester.pump();
      await tester.pump();
      expect(_blockShowsCaret(tester), isTrue,
          reason: '光标在块之前那一格时也应当有人认领（画在公式左缘）');
    });
  });
}
