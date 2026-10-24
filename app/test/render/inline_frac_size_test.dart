// ★★ 2026-10-24（批 4 · C1）：**行内分式加大**（`\frac` → `\dfrac`）
//
// 用户口径（原话）：
//   「C1 我觉得可以适当把分式的尺寸弄大一点，虽然不一定非要全尺寸，但是至少可以大一点；
//     可以允许行高变高，因为我们正常手写时有分式也是会考虑加大行距的」
//
// 探针（字号 16，inline）：
//   · 行内 `\frac`：分子/分母盒高 **15 px = 0.71 档**，整行高 19.6
//   · 行内 `\dfrac`：**21 px = 1.0 档**，整行高 32.9（+68%）
//   · 中间档（0.81，行高只 +18%）只能靠 `{\large\frac…}`，而 `\large` 不在结构命令表里
//     ⇒ 多出幻影原子 ⇒ 「叶盒数 == 原子数」的命中判据判死（本仓踩过四次）⇒ 不做
//   ⇒ 结论：走 `\dfrac`（全尺寸），行高变高已被用户预先批准。
//
// 三条不能破的约束（本文件的守卫就是钉它们）：
//   ① **源码一个字符都不动** —— 只在渲染 tex 上换；
//   ② **行间块不换** —— 它本来就走 display 尺寸；
//   ③ **偏移要同步** —— 换出来的 `\dfrac` 比 `\frac` 多一个 `d`，光标/命中都靠 tex 偏移。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/injection_map.dart';
import 'package:mathlang/render/leaf_boxes.dart';
import 'package:mathlang/render/slot_marks.dart';
import 'package:mathlang/render/tex_fixups.dart';

import '../support/math_fonts.dart';

/// 渲染一段 tex 并量出"分子"那个字的盒高
Future<double> _numerHeight(WidgetTester tester, String tex,
    {required bool inlineFractions}) async {
  final String injected = renderMathTex(
    tex,
    caretRel: -1,
    showCursor: false,
    inlineFractions: inlineFractions,
  );
  await tester.pumpWidget(MaterialApp(
    home: Center(
      child: Math.tex(injected,
          mathStyle: MathStyle.text, textStyle: const TextStyle(fontSize: 16)),
    ),
  ));
  await tester.pumpAndSettle();
  final RenderObject root = tester.renderObject(find.byType(Math));
  final List<LeafBox> boxes = scanLeafBoxes(root).eligible;
  final LeafBox b = boxes.firstWhere((LeafBox x) => x.text == 'b');
  return b.rect.height;
}

void main() {
  setUpAll(() async => loadMathFonts());

  group('① 换档本身', () {
    test(r'`\frac` ⇒ `\dfrac`，且只多插一个 `d`', () {
      final FixedTex f = withBigFractions(r'a+\frac{b}{c}+d');
      expect(f.tex, r'a+\dfrac{b}{c}+d');
      // 偏移映射：`\` 之前不动；`f` 及之后 +1
      final int slash = r'a+\frac{b}{c}+d'.indexOf(r'\frac');
      expect(f.mapOffset(slash), slash, reason: '反斜杠本身没动');
      expect(f.mapOffset(slash + 1), slash + 2, reason: 'd 插在反斜杠之后');
    });

    test(r'已经是 `\dfrac` / `\tfrac` 的不重复加', () {
      expect(withBigFractions(r'\dfrac{a}{b}').tex, r'\dfrac{a}{b}');
      expect(withBigFractions(r'\tfrac{a}{b}').tex, r'\tfrac{a}{b}');
    });

    test('没有 frac 就原样返回（同一个串、不产生插入点）', () {
      const String t = r'a+b+c';
      final FixedTex f = withBigFractions(t);
      expect(f.tex, t);
      expect(f.mapOffset(3), 3);
    });
  });

  group('② 尺寸：这才用户能看见的那一条', () {
    testWidgets(r'★ 行内开关打开 ⇒ 分子从 0.71 档（15px）变成 1.0 档（21px）',
        (WidgetTester tester) async {
      final double off =
          await _numerHeight(tester, r'a+\frac{b}{c}+d', inlineFractions: false);
      final double on =
          await _numerHeight(tester, r'a+\frac{b}{c}+d', inlineFractions: true);
      expect(off, closeTo(15.0, 0.6), reason: '改前就是 0.71 档');
      expect(on, closeTo(21.0, 0.6), reason: '改后应是全尺寸（用户要的"大一点"）');
      expect(on, greaterThan(off + 4), reason: '肉眼能分辨的差距');
    });
  });

  group('③ 不许破的三条', () {
    testWidgets(r'★ 行间块（不传开关）仍然是 `\frac`、尺寸不变',
        (WidgetTester tester) async {
      final String injected = renderMathTex(r'a+\frac{b}{c}+d', caretRel: -1);
      expect(injected.contains(r'\dfrac'), isFalse,
          reason: '行间本来就全尺寸，不该被换：$injected');
    });

    testWidgets('★ 偏移：渲染串里 frac 之后的字仍能换算回源码下标',
        (WidgetTester tester) async {
      const String src = r'a+\frac{b}{c}+d';
      final String injected = renderMathTex(src,
          caretRel: -1, showCursor: false, inlineFractions: true);
      // 源码里最后一个 `d` 的下标
      final int srcD = src.lastIndexOf('d');
      // 渲染串里找到最后一个 `d` 的位置，换算回源码
      final int renderD = injected.lastIndexOf('d');
      expect(renderToSourceOffset(injected, renderD), srcD,
          reason: '渲染串=`$injected`（多了一个 d ⇒ 不映射就会差 1）');
    });

    testWidgets(r'★ 光标偏移：在 frac 之后的 `d` 之前放光标，注入链不会把光标放到别处',
        (WidgetTester tester) async {
      const String src = r'a+\frac{b}{c}+';
      // 光标在源码末尾（frac 之后）⇒ 渲染串里应仍在末尾
      final String injected = renderMathTex(src,
          caretRel: src.length, showCursor: true, inlineFractions: true);
      // 注入链会在末尾补一个光标锚点；只要锚点在串尾就说明偏移换算对
      final int anchor = injected.indexOf(r'\textcolor{#1E88E5}');
      expect(anchor, greaterThan(0), reason: '应当有光标锚点：$injected');
      expect(injected.substring(anchor).contains(r'\frac'), isFalse,
          reason: '锚点不该落在 frac 里面：$injected');
    });
  });
}
