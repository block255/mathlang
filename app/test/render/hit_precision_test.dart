// ★★ 命中精度：**拉伸的行盒**不许把上下限的格子吞掉（2026-10-17，用户实测）
//
// 用户原话：「我发现我很难点到 `n` 后面的位置，点这里通常会落在 ∑ 和 aᵢ 之间，
//            然后点 `i=1` 的 `i` 后面经常会落到 `i` 前面去」
//
// 探针（`\sum_{i=1}^{n}a_i`，display，字号 20，Math 盒 48.6 × 58.6）：
//   盒#0 "n"  x 10.2..18.6  y **−2.6..11.4**（上限）
//   盒#1 "∑"  x  0.0..28.9  y ** 4.9..50.9**  ← ★ 高 **46**！把上下限两格整片盖住
//   盒#2 "i"  x  3.1.. 7.9  y  45.9..59.9（下限）
//   盒#3 "="  x  7.9..18.8  y  43.4..61.4
//   盒#4 "1"  x 18.8..25.8  y  43.4..61.4
// 命中判据原来是"**第一个**包含点的盒" ⇒ 上限带/下限带上总是先撞到 `∑`
// ⇒ 点 `n` 右边 = `∑` 右半 = "∑ 之后"（4）；点下限 `i` 后面 = `∑` 左/右半。
//
// 修法：命中时把"高度 > 本段字形高度中位数 × 1.6"的盒**竖直裁到中位数高**（横向不动）。
// 实测中位数 = 18，`∑` 的 46 ⇒ 裁成 y 19.9..35.9 ⇒ 不再盖住上下限 ✓。
// 数据见《位点与结构导航》§11.33。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/hit_map.dart';
import 'package:mathlang/render/leaf_boxes.dart';
import 'package:mathlang/render/leaf_pairing.dart';
import 'package:mathlang/render/slot_marks.dart';

import '../support/math_fonts.dart';

typedef _Rig = ({RenderBox root, LeafBoxScan scan, String renderTex});

Future<_Rig> _pump(WidgetTester tester, String tex, {bool display = true}) async {
  final String rt = renderMathTex(tex, caretRel: -1);
  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: Math.tex(rt,
            key: key,
            mathStyle: display ? MathStyle.display : MathStyle.text,
            textStyle: const TextStyle(fontSize: 20)),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  final RenderBox root = key.currentContext!.findRenderObject()! as RenderBox;
  return (root: root, scan: scanLeafBoxes(root), renderTex: rt);
}

int? _tap(_Rig r, double x, double y) => hitTestMathTex(
      root: r.root,
      localPos: Offset(x, y),
      tex: r.renderTex,
      atoms: renderOrderAtoms(r.renderTex, displayStyle: true),
      displayStyle: true,
    ).offset;

void main() {
  setUpAll(() async => loadMathFonts());

  testWidgets('★ 上限 `n`：点它的右边 ⇒ **n 之后**（不是 ∑ 之后）', (WidgetTester tester) async {
    final _Rig r = await _pump(tester, r'\sum_{i=1}^{n}a_i');
    // 上限带（y≈3）里、`n` 右边那一片（x 20..28）
    expect(_tap(r, 22, 3), 13, reason: '右半 ⇒ n 的右边界');
    expect(_tap(r, 26, 4), 13);
    expect(_tap(r, 12, 3), 12, reason: 'n 的左半 ⇒ 左边界');
  });

  testWidgets('★ 下限 `i=1`：点 `i` 右边 ⇒ **i 之后**（不是 i 之前）', (WidgetTester tester) async {
    final _Rig r = await _pump(tester, r'\sum_{i=1}^{n}a_i');
    expect(_tap(r, 8.5, 50), 7, reason: '`=` 盒的左半 ⇒ 7 = i 之后');
    expect(_tap(r, 13, 50), 7, reason: '`=` 的左半');
    expect(_tap(r, 16, 50), 8, reason: '`=` 的右半 ⇒ 8');
    expect(_tap(r, 4, 50), 6, reason: '`i` 的左半 ⇒ 6');
  });

  testWidgets('★ 算子本身：点 ∑ 的墨迹 ⇒ 仍在 ∑ 上（裁剪不许把主行也栽掉）',
      (WidgetTester tester) async {
    final _Rig r = await _pump(tester, r'\sum_{i=1}^{n}a_i');
    expect(_tap(r, 14, 27), anyOf(0, 4), reason: '主行上点 ∑');
    expect(_tap(r, 2, 27), 0, reason: '∑ 左半');
    expect(_tap(r, 26, 27), 4, reason: '∑ 右半');
  });

  testWidgets('★ 主行右半（a 与 i）：各自落在自己身上', (WidgetTester tester) async {
    final _Rig r = await _pump(tester, r'\sum_{i=1}^{n}a_i');
    expect(_tap(r, 34, 28), 14, reason: '`a` 左半');
    expect(_tap(r, 41, 28), 15, reason: '`a` 右半');
    expect(_tap(r, 44, 30), 16, reason: '下标 `i` 左半');
    expect(_tap(r, 47, 30), 17, reason: '下标 `i` 右半');
  });

  testWidgets('★★ 大盒按行分带：∑ **上面那一块**不论点哪儿都落上限（不落 ∑ 侧面）',
      (WidgetTester tester) async {
    final _Rig r = await _pump(tester, r'\sum_{i=1}^{n}a_i');
    for (final double y in <double>[3, 6, 9]) {
      for (final double x in <double>[2, 8, 14, 20, 24, 28]) {
        expect(_tap(r, x, y), anyOf(12, 13),
            reason: '点 ($x, $y) 在上限那一带 ⇒ 必须落上限，不许落 ∑ 侧面');
      }
    }
  });

  testWidgets('★★ 大盒按行分带：∑ **下面那一块**同理（落 `i=1` 那一行）',
      (WidgetTester tester) async {
    final _Rig r = await _pump(tester, r'\sum_{i=1}^{n}a_i');
    for (final double y in <double>[46, 50, 55]) {
      for (final double x in <double>[2, 6, 12, 18, 24]) {
        expect(_tap(r, x, y), anyOf(6, 7, 8, 9),
            reason: '点 ($x, $y) 在下限那一带 ⇒ 必须落下限');
      }
    }
  });

  testWidgets('★ 拉伸盒的判据：中位数 ×1.6（不写死 em）', (WidgetTester tester) async {
    // 同一个公式在 **text** 样式下 `∑` 不高（26），不该被裁 ⇒ 仍能点中
    final _Rig r = await _pump(tester, r'\sum_{i=1}^{n}a_i', display: false);
    final PairGroup g = buildLeafPairing(
      tex: r.renderTex,
      boxes: r.scan.eligible,
      atoms: renderOrderAtoms(r.renderTex, displayStyle: false),
    ).groupOfBox(0)!;
    expect(g.atom.kind, r'\sum');
  });
}
