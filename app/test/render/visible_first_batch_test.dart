// ④ 看得见（第一批，2026-10-15）：**可选槽占位** + **公式范围可见**
//
// §4.8 必填槽 / 可选槽（用户 2026-10-15 提出并拍板）：
//   · **必填槽**（分式分子分母 / 被开方数 / 普通上下标）⇒ 占位**恒可见**（§6.1）
//   · **可选槽**（`\sqrt[n]{…}` 的次数 · **算子的上下限 / 底数**，如 `\sum_{}^{}`、`\int_a^b`、`\log_{}`）
//     ⇒ 位点照样提供，但**空着不算问题**、占位**只在光标进入该结构时才画**（"不打扰"）
//
// §6.5 公式范围可见：光标落在某段数学里 ⇒ 给**整段**一个淡色范围（**自绘**，不改 tex）。
//   它解决"光标在公式里 / 公式外画在同一根像素上"（§3.3「甲」的由来与 W1）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/inline_math_text.dart';
import 'package:mathlang/render/slot_marks.dart';

Future<EditViewState> _mountEdit(WidgetTester tester, DocBuffer buf) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: EditView(buffer: buf)),
    ),
  ));
  final EditViewState st = tester.state<EditViewState>(find.byType(EditView));
  st.focusInput();
  await tester.pump();
  return st;
}

/// 画面上有没有"公式范围"那层淡色（§6.5）
bool _hasRangeTint(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(find.byType(DecoratedBox))
    .any((DecoratedBox d) =>
        d.decoration is BoxDecoration &&
        (d.decoration as BoxDecoration).color == kMathRangeColor);

/// 空槽占位的个数
int _marks(String renderTex) =>
    RegExp(RegExp.escape(kEmptySlotTex)).allMatches(renderTex).length +
    RegExp(RegExp.escape(kCurrentSlotTex)).allMatches(renderTex).length;

void main() {
  // ─────────────────────────────────────────────────────────────
  // 一、§4.8 可选槽：只在光标进入该结构时才画
  // ─────────────────────────────────────────────────────────────
  group('§4.8 可选槽占位：只在光标进入该结构时才画', () {
    test(r'`\sum_{}^{}` 光标**不在**这段里 ⇒ 一个占位都不画（不打扰）', () {
      expect(_marks(renderMathTex(r'\sum_{}^{}', caretRel: -1)), 0);
    });

    test(r'`\sum_{}^{}` 光标**在**这个求和对象里 ⇒ 上下限两个占位都画', () {
      // rel 0 = `\sum` 之前（在作用域 [0, limitsEnd) 之内）
      expect(_marks(renderMathTex(r'\sum_{}^{}', caretRel: 0)), 2);
      // rel 9 = 上限槽里（当前槽 + 另一个可选槽）
      expect(_marks(renderMathTex(r'\sum_{}^{}', caretRel: 9)), 2);
    });

    test(r'`\log_{}x` 的底数槽同理（光标在 `\log x` 里就画）', () {
      expect(_marks(renderMathTex(r'\log_{}x', caretRel: -1)), 0);
      expect(_marks(renderMathTex(r'\log_{}x', caretRel: 0)), 1);
    });

    test(r'`\int_a^b` 这类上下限：光标不在里面就不画（不定积分不必填）', () {
      expect(_marks(renderMathTex(r'\int_{}^{}f', caretRel: -1)), 0);
      expect(_marks(renderMathTex(r'\int_{}^{}f', caretRel: 0)), 2);
    });

    test(r'`\sqrt[]{}`：可选次数槽跟着结构走，**被开方数**（必填）恒可见', () {
      // 光标不在 → 只画被开方数那一个（必填）
      expect(_marks(renderMathTex(r'\sqrt[]{}', caretRel: -1)), 1);
      // 光标在结构里（被开方槽里）→ 两个都画
      expect(_marks(renderMathTex(r'\sqrt[]{}', caretRel: 7)), 2);
    });

    test(r'★ 必填槽**恒可见**（分式、被开方数）—— 不管光标在不在这一段里', () {
      expect(_marks(renderMathTex(r'\frac{}{}', caretRel: -1)), 2);
      expect(_marks(renderMathTex(r'\sqrt{}', caretRel: -1)), 1);
      expect(_marks(renderMathTex(r'x^{}', caretRel: -1)), 1);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 二、§6.5 公式范围可见（自绘淡色范围，不改 tex）
  // ─────────────────────────────────────────────────────────────
  group('§6.5 公式范围可见：光标在公式里 → 整段淡色范围', () {
    testWidgets('行内公式：光标进去就有范围，出去就没了', (WidgetTester tester) async {
      const String doc = r'设 $x^2+1$ 为常数';
      final DocBuffer buf = DocBuffer(doc);
      await _mountEdit(tester, buf);
      await tester.pumpAndSettle();

      buf.setCaret(0); // 光标在文字里
      await tester.pumpAndSettle();
      expect(_hasRangeTint(tester), isFalse, reason: '光标不在公式里 ⇒ 不该有范围');

      buf.setCaret(doc.indexOf(r'x^2')); // 光标进公式（tex 起点）
      await tester.pumpAndSettle();
      expect(_hasRangeTint(tester), isTrue, reason: '光标在公式里 ⇒ 整段应当有淡色范围');

      buf.setCaret(doc.length); // 回到文字
      await tester.pumpAndSettle();
      expect(_hasRangeTint(tester), isFalse, reason: '光标离开 ⇒ 范围消失');
    });

    testWidgets('行间公式：光标在块里也有范围', (WidgetTester tester) async {
      const String doc = '正文\n\n\$\$\nx^2+1\n\$\$\n\n尾段\n';
      final DocBuffer buf = DocBuffer(doc);
      await _mountEdit(tester, buf);
      await tester.pumpAndSettle();

      buf.setCaret(0);
      await tester.pumpAndSettle();
      expect(_hasRangeTint(tester), isFalse);

      buf.setCaret(doc.indexOf('x^2')); // 光标进行间公式
      await tester.pumpAndSettle();
      expect(_hasRangeTint(tester), isTrue, reason: '行间公式也要有范围（§6.5 同一条）');
    });

    testWidgets('★ 范围是**自绘**的：tex 一个字符都不变', (WidgetTester tester) async {
      const String doc = r'设 $x^2+1$ 为常数';
      final DocBuffer buf = DocBuffer(doc);
      await _mountEdit(tester, buf);
      await tester.pumpAndSettle();
      final String before = buf.buf;
      buf.setCaret(doc.indexOf(r'x^2'));
      await tester.pumpAndSettle();
      expect(buf.buf, before, reason: '范围只是画出来的，不许动缓冲区');
      expect(find.byType(Math), findsOneWidget);
    });
  });
}
