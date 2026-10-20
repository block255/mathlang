// ★★ 2026-10-20 守卫：行间 `\limsup` / `\liminf` 的上下限要**堆到正下方**
//
// 用户原话：「行间的上下极限会显示成这样（右侧小下标），不太符合数学书写习惯；
//   可以跟行内一样渲染成趋近在下的（点击判定也要同步）」
// 探针实测：`\limsup_{x}` 高 18.8（侧标）；`\limsup\limits_{x}` 高 31.8（堆叠）。
// 插入 `\limits` 会改长度 ⇒ 偏移必须同步映射（光标注入/选区/原子都吃 tex 偏移）。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/tex_fixups.dart';

import '../support/math_fonts.dart';

void main() {
  group('㊱ withOperandLimits（纯函数）', () {
    test(r'★★ 两个算符都补 limits', () {
      expect(withOperandLimits(r'\limsup_{n}').tex, r'\limsup\limits_{n}');
      expect(withOperandLimits(r'\liminf_{n}').tex, r'\liminf\limits_{n}');
    });

    test(r'★ 已经有 limits / nolimits 的不重复插', () {
      expect(withOperandLimits(r'\limsup\limits_{n}').tex, r'\limsup\limits_{n}');
      expect(withOperandLimits(r'\limsup\nolimits_{n}').tex, r'\limsup\nolimits_{n}');
    });

    test(r'★ 别的命令不动（lim 本来就堆叠；limsupfoo 不是命令名）', () {
      expect(withOperandLimits(r'\lim_{n}').tex, r'\lim_{n}');
      expect(withOperandLimits(r'\limsupfoo').tex, r'\limsupfoo');
    });

    test('★★ 偏移映射：插入点之前的偏移不变，之后的右移（= limits 的长度）', () {
      const String src = r'\limsup_{n}';
      final FixedTex f = withOperandLimits(src);
      expect(f.mapOffset(0), 0);
      expect(f.mapOffset(7), 7 + kLimitInsert.length,
          reason: '命令名之后（下标起点）要右移');
      expect(f.mapOffset(src.length), src.length + kLimitInsert.length);
    });

    test('★ 没东西可改时 mapOffset 恒等', () {
      final FixedTex f = withOperandLimits('x^2');
      expect(f.tex, 'x^2');
      expect(f.mapOffset(2), 2);
    });
  });

  group('㊲ 渲染高度：修正后必须真的堆叠（比侧标高）', () {
    testWidgets(r'★★ 修正后高度接近堆叠版，而不是侧标高度', (WidgetTester tester) async {
      await loadMathFonts();
      Future<double> h(String tex) async {
        await tester.pumpWidget(MaterialApp(
          home: Center(
            child: SizedBox(
              width: 600,
              child: Math.tex(
                withOperandLimits(tex).tex,
                mathStyle: MathStyle.display,
                textStyle: const TextStyle(fontSize: 20),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        return tester.getSize(find.byType(Math)).height;
      }

      final double fixedH = await h(r'\limsup_{n\to\infty}');
      final double rawH = await h(r'\limsup');
      expect(fixedH, greaterThan(rawH + 6),
          reason: '修正后应把上限堆到下面（实测 31.8 vs 18.8），实际 $fixedH vs $rawH');
    });
  });
}