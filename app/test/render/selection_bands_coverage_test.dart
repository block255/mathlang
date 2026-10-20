// ★★ 2026-10-20 守卫：**整块选中数学时，底色要盖满、且同一行不许有缝**（用户实测"拖选看着漏字"）
//
// 两轮根因：
//   ① `selectionBands` 按"叶盒 → 配对组"铺色，**配不上组的盒被直接丢掉** ⇒ 结构复杂的
//      display 块（`\bigcup` + 上下限 + 下标、含 `\text{…}` 的长公式）里有几个字没有底色。
//      ⇒ 改成"没主的盒就近归属"。
//   ② 每个字形盒单独铺色 ⇒ 盒与盒之间 1px 的缝，放大看就是"字与字之间漏了"。
//      ⇒ 同一行（top/bottom 相同）相邻块**合并成一条**。
//
// 判据（不看具体字形）：
//   · 每个有墨迹的字形盒中心都必须被某条底色盖住；
//   · 同一行相邻的底色块之间**不许有 > 1.5px 的缝**。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/hit_map.dart';
import 'package:mathlang/render/leaf_boxes.dart';

import '../support/math_fonts.dart';

Future<({List<LeafBox> ink, List<Rect> bands})> _render(
    WidgetTester tester, String tex) async {
  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(MaterialApp(
    home: Center(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Math.tex(tex, key: key, mathStyle: MathStyle.display,
            textStyle: const TextStyle(fontSize: 20)),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  final RenderObject root = tester.renderObject(find.byKey(key));
  final List<LeafBox> ink = scanLeafBoxes(root)
      .eligible
      .where((LeafBox b) => b.kind != LeafBoxKind.pad && (b.text ?? '').trim().isNotEmpty)
      .toList();
  final List<Rect> bands = selectionBands(
      root: root, tex: tex, from: 0, to: tex.length, displayStyle: true);
  return (ink: ink, bands: bands);
}

void main() {
  const List<String> cases = <String>[
    r'\bigcup_{i=1}^{n} U_{x_i}',
    r'\forall x\in[a,b],\ \exists M_{\max}>0 \text{ 使 } |f(x)|\le M_{\max} \text{ 恒成立}',
    r'M_{\max}=\max\{M_{x_1},\,M_{x_2},\dots,M_{x_n}\}',
    r'\lim_{n\to\infty} a^{+}_n=|L|,\qquad \lim_{n\to\infty} a^{-}_n=-|L|',
  ];

  testWidgets('★★ 每个字形盒都被底色盖住', (WidgetTester tester) async {
    await loadMathFonts();
    for (final String tex in cases) {
      final r = await _render(tester, tex);
      expect(r.ink, isNotEmpty);
      final List<String> missing = <String>[];
      for (final LeafBox b in r.ink) {
        final Offset c = b.rect.center;
        if (!r.bands.any((Rect x) => x.inflate(1.0).contains(c))) {
          missing.add('"${b.text}"');
        }
      }
      expect(missing, isEmpty, reason: '「$tex」里这些字没被盖住：${missing.join(" ")}');
    }
  });

  testWidgets('★★ 底色之间的缝里不许有墨迹（空白间距不算问题）', (WidgetTester tester) async {
    await loadMathFonts();
    for (final String tex in cases) {
      final r = await _render(tester, tex);
      // 按 (top,bottom) 分行，行内按左边界排序，检查相邻缝
      // 缝里若有**字形盒中心** ⇒ 说明那个字漏了（真正的 bug）；
      // 若只是 `\,` / 空格那种空白 ⇒ 允许（不该把空白也涂上）。
      // ★ 行分组按**垂直重叠**判定（不能用 top/bottom 完全相等：
      //   `∈` 这种字的盒顶比邻居低 1px，会被分到另一行 ⇒ 误报"缝里有字"）。
      final Map<int, List<Rect>> rows = <int, List<Rect>>{};
      for (final Rect x in r.bands) {
        int? found;
        for (final int k in rows.keys) {
          final Rect head = rows[k]!.first;
          final double overlap = (head.bottom < x.bottom ? head.bottom : x.bottom) -
              (head.top > x.top ? head.top : x.top);
          if (overlap > 0.5 * x.height) {
            found = k;
            break;
          }
        }
        if (found == null) {
          rows[x.top.round()] = <Rect>[x];
        } else {
          rows[found]!.add(x);
        }
      }
      for (final List<Rect> row in rows.values) {
        if (row.length < 2) continue;
        row.sort((Rect a, Rect b) => a.left.compareTo(b.left));
        for (var i = 1; i < row.length; i++) {
          final double gapL = row[i - 1].right;
          final double gapR = row[i].left;
          if (gapR - gapL <= 1.5) continue;
          // 只在**同一行**里比较：不同高的字形（`[` `∈` 与邻居）会落在不同的
          // (top,bottom) 组里，跨组比较会误报。这里要求墨迹盒的垂直中心也在这条带里。
          final double rowMid = (row[i].top + row[i].bottom) / 2;
          final List<String> inGap = <String>[
            for (final LeafBox b in r.ink)
              if (b.rect.center.dx > gapL + 0.5 &&
                  b.rect.center.dx < gapR - 0.5 &&
                  (b.rect.center.dy - rowMid).abs() < (row[i].height * 0.3))
                '"${b.text}"',
          ];
          expect(inGap, isEmpty,
              reason: '「$tex」的缝里还有这些字没盖住：${inGap.join(" ")}'
                  '（缝 ${gapL.toStringAsFixed(1)}..${gapR.toStringAsFixed(1)}）');
        }
      }
    }
  });
}