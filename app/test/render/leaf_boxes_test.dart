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
import 'package:mathlang/render/visible_atoms.dart';

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
  testWidgets('★ 有效叶盒数 == 可见原子数（不等则点屏幕定位静默失效）',
      (WidgetTester tester) async {
    for (final String tex in _texs) {
      final GlobalKey key = GlobalKey();
      final RenderBox ro = await _pumpMath(tester, tex, key);
      final LeafBoxScan scan = scanLeafBoxes(ro);
      expect(
        scan.eligible.length,
        lexVisibleAtoms(tex).length,
        reason: '「$tex」叶盒 ${scan.eligible.length} vs 原子 '
            '${lexVisibleAtoms(tex).length}（原始叶盒 ${scan.rawCount} 个）',
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
      final List<VisibleAtom> atoms = lexVisibleAtoms(tex);

      for (var i = 0; i < scan.eligible.length; i++) {
        final Rect r = scan.eligible[i].rect;
        final VisibleAtom a = atoms[i];

        final MathHit left = hitTestMathTex(
          root: ro,
          localPos: Offset(r.left + 1, r.center.dy),
          tex: tex,
          atoms: atoms,
        );
        expect(left.offset, a.start, reason: '「$tex」第 $i 个盒左半应取左边界');

        final MathHit right = hitTestMathTex(
          root: ro,
          localPos: Offset(r.right - 1, r.center.dy),
          tex: tex,
          atoms: atoms,
        );
        expect(right.offset, a.end, reason: '「$tex」第 $i 个盒右半应取右边界');
      }
    }
  });
}
