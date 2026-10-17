// ★★ 行内宽容（2026-10-17 用户实测）：**小字形旁边的那几像素也要能点中**。
//
// 用户原话：「这个 n，我必须点在它后面离它很近的地方光标才会落在它身后，
//            稍微远一点光标就直接跑到 An 前面去了」。
//
// 改前实测（`A_n = \sum_{k=2}^n |a_k|`，**行内** text 样式、字号 20）：
//   上标 `n` 的字形盒 = (68.9, −3.6) – (80.1, 7.4)   ← 只有 11.2 × 11
//   n 右边缘 **0px** ⇒ 21 = `n` 之后 ✓
//   n 右边缘 **+2px 起** ⇒ 9 = `\sum` **之前** ✗（只有 2px 的外扩）
//
// 根因：字形盒精确、外扩只有 2px ⇒ 偏过 2px 就从"精确到某个字"掉成 `glyphlessLanding`
//   的"整个结构之前/之后"。修法：`hit_map` 新增一档 **行内宽容**（同一行带内、水平 ≤ 8px
//   ⇒ 落该行最近的字形），常量 `kHitRowSlackPx`。
//
// ★ 这一条**只**放宽"小字形旁边"，不许影响 ③-B：
//   · 点分式**右侧装饰区**（竖直在分数线那一带）⇒ 那里没有任何字形带 ⇒ 仍走结构层；
//   · 点公式**外侧留白**（超出 8px）⇒ 仍走结构层。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/hit_map.dart';
import 'package:mathlang/render/leaf_boxes.dart';
import 'package:mathlang/render/leaf_pairing.dart';
import 'package:mathlang/render/slot_marks.dart';

import '../support/math_fonts.dart';

typedef _Rig = ({RenderBox root, LeafBoxScan scan, String renderTex, bool display});

Future<_Rig> _pump(WidgetTester tester, String tex, {bool display = false}) async {
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
  return (
    root: root,
    scan: scanLeafBoxes(root),
    renderTex: rt,
    display: display
  );
}

MathHit _hit(_Rig r, Offset p) => hitTestMathTex(
      root: r.root,
      localPos: p,
      tex: r.renderTex,
      atoms: renderOrderAtoms(r.renderTex, displayStyle: r.display),
      displayStyle: r.display,
    );

/// 取"最高的那个 n"的字形盒（行内侧置上限 = 上标带里的 n）
Rect _supNBox(_Rig r) {
  final List<LeafBox> ns = r.scan.eligible
      .where((LeafBox b) =>
          b.kind == LeafBoxKind.glyph && (b.text ?? '') == 'n')
      .toList()
    ..sort((LeafBox a, LeafBox b) => a.rect.top.compareTo(b.rect.top));
  return ns.first.rect;
}

void main() {
  setUpAll(() async => loadMathFonts());

  group('★ 行内宽容：侧置上限 `n` 旁边（用户实测那一处）', () {
    const String tex = r'A_n = \sum_{k=2}^n |a_k|';

    testWidgets('n 右边缘 0 / 2 / 4 / 6 / 8px ⇒ 都落 **n 之后**', (WidgetTester tester) async {
      final _Rig r = await _pump(tester, tex);
      final Rect n = _supNBox(r);
      final MathHit at0 = _hit(r, Offset(n.right, n.center.dy));
      expect(at0.offset, isNotNull, reason: '贴边必须命中');
      final int want = at0.offset!;
      for (final double dx in <double>[0, 2, 4, 6, 8]) {
        final MathHit h = _hit(r, Offset(n.right + dx, n.center.dy));
        expect(h.onGlyph, isTrue,
            reason: '+$dx px 仍应算"点在这个字旁边"（实际 how=${h.how}）');
        expect(h.offset, want,
            reason: '+$dx px ⇒ 应落 n 之后（$want），实际 ${h.offset}（how=${h.how}）');
      }
    });

    testWidgets('远在公式之外（右边缘 +30px）⇒ 不算点中字形（交回结构层）',
        (WidgetTester tester) async {
      final _Rig r = await _pump(tester, tex);
      final Rect n = _supNBox(r);
      final MathHit h =
          _hit(r, Offset(r.root.size.width + 30, n.center.dy));
      expect(h.onGlyph, isFalse,
          reason: '太远就不许"抢"，否则点空白会被吸到某个字上（how=${h.how}）');
    });

    testWidgets('n 左边 4px ⇒ 落 **n 之前**（左半规则一样放宽）',
        (WidgetTester tester) async {
      final _Rig r = await _pump(tester, tex);
      final Rect n = _supNBox(r);
      final MathHit right = _hit(r, Offset(n.right, n.center.dy));
      final MathHit left = _hit(r, Offset(n.left - 4, n.center.dy));
      expect(left.onGlyph, isTrue, reason: 'how=${left.how}');
      expect(left.offset, isNot(right.offset));
      expect(left.offset, isNotNull);
    });
  });

  group('★ 上下两块取最长者：上限的可点宽度 = 下限的宽度（用户 2026-10-17 提出）', () {
    // `\sum_{k=2}^{n}`：上限 `n` 只有 11px 宽，下限 `k=2` 宽一倍多。
    // 用户的原话：「取上下两块的最长者的长度来决定它们的点击判定矩形框」。
    const String tex = r'\sum_{k=2}^{n} a_k';

    testWidgets('点"下限右端 × 上限的高度" ⇒ 仍落 **n 之后**（改前这里超出 8px 宽容度）',
        (WidgetTester tester) async {
      final _Rig r = await _pump(tester, tex);
      final Rect n = _supNBox(r);
      // 实测（真实字体、字号 20，行内 text 样式）：
      //   ∑  x 0.0..21.1   y −1.8..24.2
      //   下限 k / = / 2   x 21.1..**46.7**   y 8.9..26.9
      //   上限 n           x 21.1..29.5      y −4.6..9.4
      // ⇒ 上限只有 8.4 宽、下限 25.6 宽（左对齐）；放宽后上限的可点横向范围 = 21.1..46.7。
      const double subBandRight = 46.7;
      expect(n.right, closeTo(29.5, 1.5), reason: '上限 n 的右缘（实测 29.5）');
      expect(subBandRight - n.right, greaterThan(kHitRowSlackPx),
          reason: '★ 这个用例必须"超出 8px 宽容度"才有意义（否则测不到放宽）');
      final int want = _hit(r, Offset(n.right, n.center.dy)).offset!;
      final MathHit h = _hit(r, Offset(subBandRight - 0.5, n.center.dy));
      expect(h.onGlyph, isTrue, reason: 'how=${h.how}');
      expect(h.offset, want,
          reason: '上限的可点矩形必须放宽到"上下两块里较长的那块"（how=${h.how}）');
    });

    testWidgets('下限**逐字精度不变**：点 `=` 的右半 ⇒ 仍落 `=` 之后（不是被 `k` 抢走）',
        (WidgetTester tester) async {
      final _Rig r = await _pump(tester, tex);
      final List<LeafBox> eq = r.scan.eligible
          .where((LeafBox b) =>
              b.kind == LeafBoxKind.glyph && (b.text ?? '') == '=')
          .toList();
      final LeafBox e = eq.first;
      final MathHit right = _hit(r, Offset(e.rect.right - 1, e.rect.center.dy));
      final MathHit left = _hit(r, Offset(e.rect.left + 1, e.rect.center.dy));
      expect(right.offset, isNotNull);
      expect(left.offset, isNotNull);
      expect(right.offset, isNot(left.offset),
          reason: '左右半必须给出不同端点（逐字精度没被"放宽"毁掉）');
    });
  });

  group('★ 宽容度不许影响 ③-B 的两个既有行为', () {
    testWidgets('远在公式之外（右边缘 +30px）⇒ 不算点中字形（交回结构层）',
        (WidgetTester tester) async {
      final _Rig r = await _pump(tester, r'x', display: true);
      final MathHit h =
          _hit(r, Offset(r.root.size.width + 30, r.root.size.height / 2));
      expect(h.onGlyph, isFalse, reason: 'how=${h.how}');
    });

    // ★ 注：③-B 的端到端行为（点分式右侧留白 ⇒ 结构之后、不落进公式内部）由
    //   `test/editor/math_blank_landing_test.dart` 守着（那条走的是**真实点击**链）。
  });
}
