// ④-1（空槽占位框**自绘**）＋ ④-2（空槽**加宽**）的守卫
//
// **改前必红的两条**（旧版：一个**看得见**的灰方块、行内槽宽只有 11.2）：
//   ① 行内空分式的**总宽** ≥ 一个正文汉字 ＋ 分式内边距
//   ② 渲染树里**认得出"垫子"**（`scanSlotPads`：字形 `□` ＋ 紧邻的**零高填色盒**）
// 另守三条不变量（新机制自己必须成立的账）：
//   ③ **宽度垫只补宽**：高度 / 基线与"同字形但不加垫"**逐像素相同**（版面中性 —— 这是选它的理由）
//   ④ **配对账**：`叶盒数 == 原子数`（垫子那个零高盒由词法补 1 个合成原子）
//   ⑤ **点空槽 ⇒ 落进该槽**（垫子盒中心点一下 ⇒ 源偏移 == 空槽起点）
//
// 数据来源：`_cache\probe_slot_pad{,2,3}.log`（2026-10-16 三批探针）。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/hit_map.dart';
import 'package:mathlang/render/injection_map.dart';
import 'package:mathlang/render/leaf_boxes.dart';
import 'package:mathlang/render/math_caret.dart';
import 'package:mathlang/render/slot_marks.dart';

const double kFont = 16;

/// 一个正文汉字的宽度（字号 16）
const double kHanziWidth = 16.0;

/// 分式的内边距（`_FracPos` 的 2 × 1.9，实测）
const double kFracPadding = 2 * 1.9;

Future<void> _pump(WidgetTester t, String tex,
    {MathStyle style = MathStyle.text}) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: Math.tex(
          tex,
          textStyle: const TextStyle(fontSize: kFont),
          mathStyle: style,
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

RenderObject _root(WidgetTester t) =>
    t.renderObject<RenderObject>(find.byType(Math));

void main() {
  group('④-2 空槽加宽：行内槽 ≥ 一个正文汉字', () {
    testWidgets('★ 行内（text 样式）空分式的总宽 ≥ 汉字宽 + 内边距', (WidgetTester tester) async {
      // 改前：旧占位（灰方块，1em 字形）→ 行内空分式只有 15.0 px（= 11.2 + 3.8）
      await _pump(tester, renderMathTex(r'\frac{}{b}', caretRel: -1));
      final double empty = tester.getSize(find.byType(Math)).width;

      await _pump(tester, r'\frac{a}{b}');
      final double filled = tester.getSize(find.byType(Math)).width;

      expect(empty, greaterThanOrEqualTo(kHanziWidth + kFracPadding - 0.5),
          reason: '★ 空槽的**触摸目标**要按正文汉字定标（§6.1）——'
              '实测：旧占位 15.0、新垫子 20.7、填满分式 $filled');
      expect(empty, greaterThan(filled),
          reason: '空槽那一格现在是"汉字宽的字形 + 0.3em 宽度垫" ⇒ 比单个 $filled 里的字母宽');
    });

    testWidgets('宽度垫只补宽：**高度逐像素相同**（版面中性）', (WidgetTester tester) async {
      // 同一个字形、同一个位置，只差一条零高宽度垫
      await _pump(tester, '\\frac{$kSlotPadTex}{b}');
      final Size withPad = tester.getSize(find.byType(Math));
      await _pump(tester, r'\frac{\textcolor{#FFFFFF}{\square}}{b}');
      final Size noPad = tester.getSize(find.byType(Math));

      debugPrint('带垫=$withPad  不带垫=$noPad');
      expect(withPad.height, closeTo(noPad.height, 0.01),
          reason: '★ 选"零高宽度垫"就是为了**不改变高度/基线** —— '
              '白 `\\rule{18mu}` 那一版会把空分式撑高 ~10px（探针实测），等于"换槽时版面跳"');
      expect(withPad.width - noPad.width, closeTo(5.6, 1.0),
          reason: '只补宽：0.3em ≈ 5.6 px（字号 16）');
    });
  });

  group('④-1 垫子认得出来（自绘框的前提）', () {
    testWidgets('★ 字形 □ + 紧邻的零高填色盒 ⇒ 合成一个"槽矩形"', (WidgetTester tester) async {
      await _pump(tester, renderMathTex(r'\frac{}{b}', caretRel: -1));
      final List<SlotPad> pads = scanSlotPads(_root(tester));
      expect(pads.length, 1, reason: '分母非空 ⇒ 只有一个空槽');
      expect(pads.single.rect.width, greaterThanOrEqualTo(kHanziWidth),
          reason: '槽矩形 = 字形盒 ∪ 宽度垫盒（实测严格相接）');
      expect(pads.single.current, isFalse, reason: '没给 caretAt ⇒ 没有"当前槽"');
    });

    testWidgets('非空槽 / 挂件槽不画（回归：`\\frac{a}{b}` 一个垫子都没有）',
        (WidgetTester tester) async {
      await _pump(tester, renderMathTex(r'\frac{a}{b}', caretRel: 6));
      expect(scanSlotPads(_root(tester)), isEmpty);
    });

    testWidgets('结构尾垫**不许**被当成槽垫（它的左边是内容字形，不是 `□`）',
        (WidgetTester tester) async {
      // `\sqrt{2}` 会注入尾垫（`\rule{3pt}{0pt}`，也是零高填色盒）
      await _pump(tester, renderMathTex(r'\sqrt{2}', caretRel: -1));
      expect(scanSlotPads(_root(tester)), isEmpty,
          reason: '判据②要求左边紧邻的字形是 $kSlotPadGlyph —— 尾垫左边是 `2`');
    });

    testWidgets('空公式也要画得出来（§6.1.1）', (WidgetTester tester) async {
      await _pump(tester, renderMathTex('', caretRel: -1));
      final List<SlotPad> pads = scanSlotPads(_root(tester));
      expect(pads.length, 1, reason: '空公式 = 一个垫子（看得见、点得到，不再是幽灵）');
      expect(tester.getSize(find.byType(Math)).width,
          greaterThanOrEqualTo(kHanziWidth));
    });
  });

  group('★ 配对账 + 点空槽（垫子多一个盒 ⇒ 必须补一个合成原子）', () {
    const List<String> corpus = <String>[
      r'\frac{}{b}',
      r'\frac{a}{}',
      r'\frac{}{}',
      r'\sqrt{}',
      r'\sqrt{2}',
      r'x=\frac{a}{}',
      r'\frac{1}{} + \sqrt{}',
      r'\sum_{i=1}^{}a_i',
      r'x^{}',
    ];

    testWidgets('全域：叶盒数 == 原子数（display 与 text 两种样式）',
        (WidgetTester tester) async {
      final List<String> bad = <String>[];
      for (final MathStyle style
          in <MathStyle>[MathStyle.display, MathStyle.text]) {
        for (final String tex in corpus) {
          final String rt = renderMathTex(tex, caretRel: -1);
          await _pump(tester, rt, style: style);
          final int boxes = scanLeafBoxes(_root(tester)).eligible.length;
          final int atoms = atomsForHitTest(rt).length;
          if (boxes != atoms) {
            bad.add('${style.name} 「$tex」：叶盒 $boxes ≠ 原子 $atoms');          }
        }
      }
      expect(bad, isEmpty,
          reason: '★ 不相等 ⇒ `hitTestMathTex` **静默返回 null** ⇒ 公式内点击全废：\n'
              '${bad.join('\n')}');
    });

    testWidgets('★ 端到端：点空槽垫子的中心 ⇒ 源偏移 == 空槽起点', (WidgetTester tester) async {
      const String tex = r'\frac{}{b}'; // 分子空槽的源偏移 = 6
      const int slotStart = 6;
      final String rt = renderMathTex(tex, caretRel: -1);
      await _pump(tester, rt);

      final RenderObject root = _root(tester);
      final SlotPad pad = scanSlotPads(root).single;
      final MathHit hit = hitTestMathTex(
        root: root,
        localPos: pad.rect.center,
        tex: rt,
        atoms: atomsForHitTest(rt),
      );
      debugPrint('点垫子中心 ${pad.rect.center} → $hit');
      expect(hit.reliable, isTrue, reason: '配对必须是好的（否则 offset 恒 null）');
      expect(hit.offset, isNotNull);
      expect(renderToSourceOffset(rt, hit.offset!), slotStart,
          reason: '★ 点空槽 ⇒ 落进**那个槽**（§5.3：空槽框内直接进槽，不做就近）');
    });
  });
}
