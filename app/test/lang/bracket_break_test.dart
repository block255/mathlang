// 批 30：**中括号也当断点字符**（用户 2026-10-24 拍板：只加 `[` `]`，`(` `)` 与 `|` 保持现状）。
//
// 背景：用户实测 `[x_2,x_3]` 的两边中括号**粗细不同** —— 因为一个括号对的两半边被 `$` 边界
// 分到了两层：`[` 在公式里（KaTeX 字体）、`]` 在正文里（正文字体）。
// 按"**层的归属**定字体"（批 18「汉字 = 断点」那条）就统一了：
//   行内公式**顶层** ⇒ 断点字符落文本层；**结构子位点 / 行间块** ⇒ 接受数学字体。
// ★ 这条判据**不看配对**：打字从左往右，打 `[` 那一刻必然还没有 `]`。
//
// 本文件守三件事：① 行内顶层真的拆；② 结构槽 / 行间块真的**不**拆；③ `(` `)` `|` 不许外溢。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/lang/break_split.dart';
import 'package:mathlang/lang/math_spans.dart';

Future<DocBuffer> _pump(WidgetTester tester, String doc, int caret) async {
  final DocBuffer buf = DocBuffer(doc)..setCaret(caret);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 600,
        child: SingleChildScrollView(child: EditView(buffer: buf)),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('甲').first);
  await tester.pumpAndSettle();
  buf.setCaret(caret);
  await tester.pumpAndSettle();
  return buf;
}

Future<void> _type(WidgetTester tester, String text) async {
  tester.testTextInput.enterText(text);
  await tester.pumpAndSettle();
}

/// [idx] 这一格是不是落在某个 `$…$` 里
bool _insideMath(String doc, int idx) {
  for (final MathSpan s in scanMathSpans(doc)) {
    if (idx >= s.start && idx < s.end) return true;
  }
  return false;
}

/// `[` / `]` 是否都在**所有** `$…$` 之外
bool _bracketOutsideMath(String doc, String ch) {
  for (var i = 0; i < doc.length; i++) {
    if (doc[i] != ch) continue;
    // `\left[` 这种"命令自带的分隔符"不算（它以 `\` 开头）
    if (i > 0 && doc[i - 1] == r'\') continue;
    if (_insideMath(doc, i)) return false;
  }
  return true;
}

void main() {
  group('批 30 · 中括号 = 断点字符', () {
    test('判据：`[` `]` 是断点字符；**半角** `(` `)` `|` 不是（用户拍板保持现状）', () {
      expect(isBreakChar('['), isTrue);
      expect(isBreakChar(']'), isTrue);
      expect(isBreakChar('('), isFalse, reason: '用户拍板：小括号保持现状');
      expect(isBreakChar(')'), isFalse, reason: '用户拍板：小括号保持现状');
      expect(isBreakChar('|'), isFalse, reason: '用户拍板：绝对值竖线保持现状');
      // 全角括号本来就在全角区（批 18 就已是断点）—— 这条只是钉住"没被改动"
      expect(isBreakChar('（'), isTrue);
      expect(isBreakChar('）'), isTrue);
    });

    test('纯函数：行内顶层打 `[` ⇒ 拆段，`[` 落在围栏外', () {
      const String doc = r'甲 $a\in b$ 乙';
      final int caret = doc.indexOf(r'\in') + 3; // `\in` 之后、空格之前
      final BreakSplit? p = planBreakSplit(
          doc: doc, caret: caret, selStart: caret, selEnd: caret, payload: '[');
      expect(p, isNotNull, reason: '行内顶层 ⇒ 应当拆段');
      final String out = doc.replaceRange(p!.from, p.to, p.text);
      expect(out, contains(r'$a\in$'), reason: out);
      // 插进去的那一格必须落在所有围栏之外
      expect(_insideMath(out, p.caret - 1), isFalse, reason: out);
    });

    test('纯函数：`\\sqrt[3]` 的**次数**里打 `[` ⇒ 不拆（结构槽接受数学字体）', () {
      const String doc = r'甲 $\sqrt[3]{x}$ 乙';
      final int caret = doc.indexOf('[', doc.indexOf(r'\sqrt'));
      final BreakSplit? p = planBreakSplit(
          doc: doc, caret: caret, selStart: caret, selEnd: caret, payload: '[');
      expect(p, isNull, reason: '在结构槽里 ⇒ 接受数学字体，不拆');
    });

    test('纯函数：行间块里打 `[` ⇒ 不拆', () {
      const String doc = '甲\n\n\$\$a[b\$\$\n';
      final int caret = doc.indexOf('[', doc.indexOf(r'$$'));
      final BreakSplit? p = planBreakSplit(
          doc: doc, caret: caret, selStart: caret, selEnd: caret, payload: '[');
      expect(p, isNull, reason: '行间块 ⇒ 接受数学字体');
    });

    test('纯函数：`(` `)` `|` 在行内顶层打 ⇔ **不拆**（不许外溢）', () {
      for (final String ch in <String>['(', ')', '|']) {
        const String doc = r'甲 $a+b$ 乙';
        final int caret = doc.indexOf('a') + 1;
        final BreakSplit? p = planBreakSplit(
            doc: doc, caret: caret, selStart: caret, selEnd: caret, payload: ch);
        expect(p, isNull, reason: '`$ch` 用户拍板保持现状（`f(x)` 里括号与字母是同一个对象）');
      }
    });

    testWidgets(r'★ 接线：真正打字「[」⇒ 拆段且 `[` 在围栏外', (WidgetTester tester) async {
      const String doc = r'甲 $\exists x_{0}\in$ 乙';
      final int caret = doc.indexOf(r'\in') + 3; // `\in` 之后
      final DocBuffer buf = await _pump(tester, doc, caret);
      await _type(tester, '[');
      final String now = buf.buf;
      expect(_bracketOutsideMath(now, '['), isTrue, reason: now);
      expect(r'$\exists x_{0}\in$'.allMatches(now).length, 1, reason: now);
    });

    testWidgets(r'★ 接线：真正打字「]」也拆（同一条规则）', (WidgetTester tester) async {
      const String doc = r'甲 $\exists x\in$ 乙';
      final int caret = doc.indexOf(r'\in') + 3;
      final DocBuffer buf = await _pump(tester, doc, caret);
      await _type(tester, ']');
      final String now = buf.buf;
      expect(_bracketOutsideMath(now, ']'), isTrue, reason: now);
    });

    testWidgets('★ 全域：一批 tex × 每个偏移打「[」⇒ 不造行内 `\$\$`、不改别的字符、`[` 必在围栏外',
        (WidgetTester tester) async {
      const List<String> texs = <String>[
        r'a\in[b]',
        r'\exists x_{0}\in[x_{2},x_{3}]',
        r'\frac{a}{b}',
        r'\sqrt[3]{x}',
        r'x^{2}',
        r'\sin x',
        r'\begin{cases}4\\\end{cases}',
      ];
      var splits = 0;
      for (final String tex in texs) {
        for (var k = 0; k <= tex.length; k++) {
          final String doc = '甲 \$$tex\$ 乙';
          final int caret = 2 + k; // `甲 ` + `$`
          final BreakSplit? p = planBreakSplit(
              doc: doc, caret: caret, selStart: caret, selEnd: caret, payload: '[');
          if (p == null) continue;
          splits++;
          final String out = doc.replaceRange(p.from, p.to, p.text);
          expect(inlineDoubleDollarLines(out), isEmpty,
              reason: '不许造出行内 `\$\$`：$out');
          expect(_insideMath(out, p.caret - 1), isFalse,
              reason: '插进去的 `[` 必须落在所有围栏之外：$out');
        }
      }
      expect(splits, greaterThan(8), reason: '断言不许空转（实际切了 $splits 处）');
    });
  });
}
