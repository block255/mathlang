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
