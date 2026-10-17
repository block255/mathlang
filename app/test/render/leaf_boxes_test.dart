// 叶盒过滤 + 命中映射的回归测试（S3-2 点屏幕定位的守门人）
//
// ★ 为什么必须有这条：叶盒数与可见原子数一旦不等，`hitTestMathTex` 会**静默返回 null**
//   —— 界面表现就是"点公式没反应"，没有任何报错。S3-2 实测发现：
//   S1 当年的"边界内"判据对 6 个样本里的 5 个都不成立（数学字形本来就画出根盒之外），
//   即**点屏幕定位对大多数公式静默失效**。详见 leaf_boxes.dart 的注释。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/hit_map.dart';
import 'package:mathlang/render/leaf_boxes.dart';
import 'package:mathlang/render/leaf_pairing.dart';
import 'package:mathlang/render/visible_atoms.dart';

import '../support/math_fonts.dart';

/// 覆盖各类结构：分式 / 根号 / 上下标 / 希腊字母 / 大算符上下限 / 行间公式 / 单个字母
const List<String> _texs = <String>[
  r'x',
  r'\frac{a}{b}=\sqrt{2}',
  r'\Delta = b^2-4ac',
  r'x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}',
  r'x_1+x_2 = -\frac{b}{a}',
  r'x_1 x_2 = \frac{c}{a}',
  r'\sum_{i=1}^{n} i',
  r'\sqrt[3]{x}',
  r'\alpha+\beta',
];

Future<RenderBox> _pumpMath(WidgetTester tester, String tex, GlobalKey key) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: Math.tex(
          tex,
          key: key,
          mathStyle: MathStyle.display,
          textStyle: const TextStyle(fontSize: 16),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return key.currentContext!.findRenderObject()! as RenderBox;
}

void main() {
  // ★ 量几何/量叶盒都必须用**真实数学字体**（否则量到的是回退度量的另一个世界，
  //   见 2026-10-17 的教训与 `test/support/math_fonts.dart` 头部）
  setUpAll(() async => loadMathFonts());

  testWidgets('★ 有效叶盒与可见原子**全部配对**（旧判据"两列长度相等"已作废）',
      (WidgetTester tester) async {
    for (final String tex in _texs) {
      final GlobalKey key = GlobalKey();
      final RenderBox ro = await _pumpMath(tester, tex, key);
      final LeafBoxScan scan = scanLeafBoxes(ro);
      final List<VisibleAtom> atoms =
          renderOrderAtoms(tex, displayStyle: true);
      final LeafPairing plan =
          buildLeafPairing(tex: tex, boxes: scan.eligible, atoms: atoms);
      // ★ 长度相等**不是**正确性判据：`\sin` 一族天然"一原子多盒"（见 leaf_pairing.dart）。
      //   真正的不变量是"两列**全部**对上了"。
      expect(
        plan.complete,
        isTrue,
        reason: '「$tex」叶盒 ${scan.eligible.length} / 原子 ${atoms.length}'
            '（原始叶盒 ${scan.rawCount} 个）：${plan.reason}',
      );
    }
  });

  testWidgets('★ 命中可靠、落点有效（不会再静默返回 null）', (WidgetTester tester) async {
    for (final String tex in _texs) {
      final GlobalKey key = GlobalKey();
      final RenderBox ro = await _pumpMath(tester, tex, key);
      final MathHit hit = hitTestMathTex(
        root: ro,
        localPos: ro.size.center(Offset.zero),
        tex: tex,
        // ★ 2026-10-17：配对要按**渲染顺序**（`\sum` 的上下限在 display 下会重排），
        //   而且必须告诉它这是 display 样式 —— 否则两列的次序对不上（测试自己用错了方言）。
        displayStyle: true,
      );
      expect(hit.reliable, isTrue, reason: '「$tex」$hit');
      expect(hit.offset, isNotNull, reason: '「$tex」返回了 null（= 点了没反应）');
      expect(hit.offset, inInclusiveRange(0, tex.length), reason: tex);
    }
  });

  testWidgets('点盒子的左半取原子左边界、右半取右边界（字符级精细判定）',
      (WidgetTester tester) async {
    for (final String tex in _texs) {
      final GlobalKey key = GlobalKey();
      final RenderBox ro = await _pumpMath(tester, tex, key);
      final LeafBoxScan scan = scanLeafBoxes(ro);
      final List<VisibleAtom> atoms =
          renderOrderAtoms(tex, displayStyle: true);
      final LeafPairing plan =
          buildLeafPairing(tex: tex, boxes: scan.eligible, atoms: atoms);
      expect(plan.complete, isTrue, reason: '「$tex」${plan.reason}');

      for (var i = 0; i < scan.eligible.length; i++) {
        final Rect r = scan.eligible[i].rect;
        final PairGroup g = plan.groupOfBox(i)!;

        final MathHit left = hitTestMathTex(
          root: ro,
          localPos: Offset(r.left + 1, r.center.dy),
          tex: tex,
          atoms: atoms,
          displayStyle: true,
        );
        expect(left.offset, g.srcStart, reason: '「$tex」第 $i 个盒左半应取左边界');

        final MathHit right = hitTestMathTex(
          root: ro,
          localPos: Offset(r.right - 1, r.center.dy),
          tex: tex,
          atoms: atoms,
          displayStyle: true,
        );
        expect(right.offset, g.srcEnd, reason: '「$tex」第 $i 个盒右半应取右边界');
      }
    }
  });
}
