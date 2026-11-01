// ③-C：**行间公式块的前后那一格也必须有人画光标**（修掉"走出公式 ⇒ 光标消失"）。
//
// 用户实测 ②：「在分式内用右箭头把光标切到分式后面，光标会消失，但删除仍能删掉整个分式」。
// 实测根因（§11.25）：行内公式靠 `caretPlacement` 的「两端各多认领一格」解决了"公式前后各一格"；
// 而行间**块**的接收区间只有 `[renderBase, renderEnd]`（= 公式本身），
// 于是光标走到"块之后那一格"时**没有任何单元认领它** ⇒ `showCaret = false`、竖条 0。
//
// ★★★ 2026-11-01 修正（台账 F13）：③-C 当年顺手把 `sliceStart - 1`（块**前**一格）也认领了，
//   理由是"与行内公式两端对称"。那一格在真实文档里只有三种身份，**没有一种该归块**：
//     · 上一行文字的末尾 ⇒ 归那一行；
//     · 段落分隔符（`\n\n` 的第二个、零高度）⇒ **不是位置**，谁都不该画；
//     · 前一块自己最后一行的行尾 ⇒ 归前一块。
//   ⇒ 现在块的认领是 **[自己的行首 `$$`, 自己的行尾]**。
//   所以本文件拆成三条：
//     ① 块**之后**那一格（`acceptTo` = 块自己最后一行的行尾）⇒ 块画（③-C 的本意，保留）；
//     ② 块**自己的行首**（`$$` 那一格 = `acceptFrom`）⇒ 块画（同上）；
//     ③ 块的行首**再往前一格**（那段空白）⇒ 若它是段落分隔符 ⇒ **一根都不许有**。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/core/paragraph_break.dart';
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

/// 文本层那根竖条（`Container(width:1.5)`）的个数
int _textBars(WidgetTester tester) {
  var n = 0;
  for (final Element e in find.byType(Container).evaluate()) {
    final Widget w = e.widget;
    if (w is! Container) continue;
    final BoxConstraints? c = w.constraints;
    if (c == null || c.minWidth != 1.5 || c.maxWidth != 1.5) continue;
    n++;
  }
  return n;
}

/// ★ 本文件只验"块前/块后那两格**别丢**"，所以文档里只有**一个**公式块 —— `any` 在这里够用。
/// ★★ 但"**由哪一块**画"这件事（多块时不许每块都声称光标在自己这儿）
/// 由 `test/editor/block_caret_ownership_test.dart` 按块断言（批 25）。
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

    testWidgets(r'★ 块**自己的行首**（开围栏那一格）⇒ 块画', (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer(kDoc);
      await _mount(tester, buf);

      final int open = kDoc.indexOf(r'$$');
      buf.setCaret(open);
      await tester.pump();
      await tester.pump();
      expect(_blockShowsCaret(tester), isTrue,
          reason: '块的行首是 `\$\$` 那一格（acceptFrom = sliceStart）⇒ 由块自己画');
      expect(_bars(tester), greaterThan(0));
    });

    testWidgets(r'★★ 块行首**再往前一格**（段落分隔符）⇒ 一根都不许有（F13 新口径）',
        (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer(kDoc);
      await _mount(tester, buf);

      final int open = kDoc.indexOf(r'$$');
      final int before = open - 1; // `$$` 前那个换行
      expect(isParagraphSeparator(kDoc, before), isTrue,
          reason: '前置：`前⏎⏎\$\$` 里第二个换行就是段落分隔符（零高度、不是位置）');

      buf.setCaret(before);
      await tester.pump();
      await tester.pump();
      expect(_blockShowsCaret(tester), isFalse,
          reason: '★ 块**不该**认领分隔符那一格（改前认了 ⇒ 在块边缘画一根"块之前"光标 ＋ 刻度）');
      expect(_textBars(tester), 0,
          reason: '★ 分隔符不是位置 ⇒ 文本层也不该画（它没有行盒）');
      expect(_bars(tester), 0,
          reason: '★ 所以这一格**一根竖条都没有**才是对的（改前：块画了一根）');
    });
  });
}
