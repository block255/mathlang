// ④-5 **行间公式的独立字号**守卫（2026-10-16 用户提出："行间是不是允许有自己不同于段落的独立大小"）
//
// 规格（§6.4 ＋ §7.3）：块类型**允许**有自己的**渲染**（字号/缩进/居中 —— 那是排版意图），
// 但**编辑行为**一律不许因它不同。所以这里守两件事：
//   ① `DocSettings.displayFontSize` 生效：行间块用它、**行内公式不受影响**；
//   ② 不设它时**跟随正文**（正文改 ⇒ 行间跟着改，只差一个固定比例）。
// ★ 块内光标**不另设判据** —— 它取自当地 ¶ 盒 ⇒ 自动跟随（`caret_layer_test` D 组钉着）。
// ★ 块"之前 / 之后"那两格仍按**段落文本层**标准（`textFontSize: body`），不随本项变。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/core/doc_settings.dart';
import 'package:mathlang/editor/doc_view.dart';
import 'package:mathlang/render/math_caret.dart';

/// 一段同时含**行内**与**行间**公式的文档
const String kDoc = '前 \$x^2\$ 后\n\n\$\$\nx=\\frac{a}{b}\n\$\$\n\n末段\n';

Future<void> _pump(WidgetTester tester, DocSettings s) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: DocView(
          buffer: DocBuffer(kDoc),
          settings: s,
          onStats: (DocViewStats _) {},
        ),
      ),
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump();
  }
}

/// 所有数学控件的 (mathStyle, fontSize)
List<(MathStyle, double, double?)> _maths(WidgetTester tester) {
  final List<(MathStyle, double, double?)> out = [];
  for (final Element e in find.byType(MathWithCaret).evaluate()) {
    final MathWithCaret w = e.widget as MathWithCaret;
    out.add((w.mathStyle, w.fontSize, w.textFontSize));
  }
  return out;
}

double _blockSize(WidgetTester tester) => _maths(tester)
    .where((r) => r.$1 == MathStyle.display)
    .map((r) => r.$2)
    .reduce((a, b) => a > b ? a : b);

void main() {
  group('DocSettings：行间字号（不设 ⇒ 跟随正文）', () {
    test('默认：跟随正文的 1.25 倍', () {
      expect(DocSettings.defaults.displayFontSize, isNull);
      expect(DocSettings.defaults.effectiveDisplayFontSize,
          closeTo(DocSettings.defaults.bodyFontSize * 1.25, 0.001));
    });

    test('显式设了就听它的', () {
      final DocSettings s =
          DocSettings.defaults.copyWith(displayFontSize: 30);
      expect(s.effectiveDisplayFontSize, 30);
    });

    test('★ 跟随：只改正文字号 ⇒ 行间跟着改（不会僵在原地）', () {
      final DocSettings s = DocSettings.defaults.copyWith(bodyFontSize: 20);
      expect(s.displayFontSize, isNull);
      expect(s.effectiveDisplayFontSize, closeTo(25, 0.001));
      expect(s.copyWith(bodyFontSize: 12).effectiveDisplayFontSize,
          closeTo(15, 0.001));
    });
  });

  group('渲染：行间用独立字号，行内不受影响', () {
    testWidgets('★ 行间块 = effectiveDisplayFontSize；行内 = 正文',
        (WidgetTester tester) async {
      await _pump(tester, DocSettings.defaults);
      final List<(MathStyle, double, double?)> all = _maths(tester);
      debugPrint('默认设置下的数学控件：$all');
      expect(_blockSize(tester),
          closeTo(DocSettings.defaults.effectiveDisplayFontSize, 0.001),
          reason: '★ 行间块必须用 `effectiveDisplayFontSize`（改前：它和正文一样是 16）');
      for (final (MathStyle, double, double?) r in all) {
        if (r.$1 == MathStyle.display) continue;
        expect(r.$2, DocSettings.defaults.bodyFontSize,
            reason: '行内公式仍用正文字号（行间那一项**只管行间**）');
      }
    });

    testWidgets('★ 改显式 displayFontSize ⇒ 行间变大、行内一点不变',
        (WidgetTester tester) async {
      await _pump(tester, DocSettings.defaults);
      final double before = _blockSize(tester);

      final DocSettings s = DocSettings.defaults.copyWith(displayFontSize: 32);
      await _pump(tester, s);
      expect(_blockSize(tester), 32);
      expect(_blockSize(tester), greaterThan(before));
      for (final (MathStyle, double, double?) r in _maths(tester)) {
        if (r.$1 == MathStyle.display) continue;
        expect(r.$2, DocSettings.defaults.bodyFontSize);
      }
    });

    testWidgets('★ 块前后那两格仍按**段落文本层**标准（textFontSize = 正文）',
        (WidgetTester tester) async {
      await _pump(tester, DocSettings.defaults.copyWith(displayFontSize: 32));
      final List<(MathStyle, double, double?)> blocks = _maths(tester)
          .where((r) => r.$1 == MathStyle.display)
          .toList();
      expect(blocks, isNotEmpty);
      for (final (MathStyle, double, double?) r in blocks) {
        expect(r.$3, DocSettings.defaults.bodyFontSize,
            reason: '★ 块**之前 / 之后**那两格是文本层（§11.27）⇒ 不随行间字号变，'
                '否则"同一根像素上的两个位点"会给出两种高度');
      }
    });

    testWidgets('行间字号真的进了排版：块内公式盒随之变高', (WidgetTester tester) async {
      // ★ 必须**指名**块内那个 Math（文档里第一个 Math 是行内公式 `$x^2$`，它不随本项变）
      final Finder blockMath = find.descendant(
        of: find.byWidgetPredicate(
            (Widget w) => w is MathWithCaret && w.mathStyle == MathStyle.display),
        matching: find.byType(Math),
      );
      await _pump(tester, DocSettings.defaults);
      final double small = tester.getSize(blockMath.first).height;
      await _pump(tester, DocSettings.defaults.copyWith(displayFontSize: 40));
      final double big = tester.getSize(blockMath.first).height;
      debugPrint('块内 Math 盒高：默认 $small → 40 号 $big');
      expect(big, greaterThan(small),
          reason: '行间字号必须真的进排版（否则只是设置里一个死值）');
    });
  });
}
