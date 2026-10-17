// ④-1（空槽占位框**自绘**）＋ ④-2（空槽**加宽**）的守卫
//
// **改前必红的两条**（旧版：一个**看得见**的灰方块、行内槽宽只有 11.2）：
//   ① 行内空分式的**总宽** ≥ 一个正文汉字 ＋ 分式内边距
//   ② 渲染树里**认得出"垫子"**（`scanSlotPads`：字形 `M` ＋ 紧邻的**零高填色盒**）
// 另守三条不变量（新机制自己必须成立的账）：
//   ③ **宽度垫只补宽**：高度 / 基线与"同字形但不加垫"**逐像素相同**（版面中性 —— 这是选它的理由）
//   ④ **配对账**：`叶盒数 == 原子数`（垫子那个零高盒由词法补 1 个合成原子）
//   ⑤ **点空槽 ⇒ 落进该槽**（垫子盒中心点一下 ⇒ 源偏移 == 空槽起点）
// ★★ 2026-10-17 新增一组「**槽带**」（用户实测"分母的框上沿跑到分子区"）：
//   ⑥ 垫子盒 ⊆ 它所在的**结构节点**盒；⑦ 不越过**分数线**（像素扫线，独立验证）；
//   ⑧ 垫子字形的 ¶ 盒必须来自**数学字体**（≈1.05em，不是 □ 的 1.55em）；⑨ 行内仍 ≥ 一个正文汉字。
//
// 数据来源：`_cache\probe_slot_pad{,2,3}.log`（2026-10-16）· `probe_font{,2}.log`（2026-10-17）。
// ★ **本文件在 `setUpAll` 里装真实数学字体** —— 回退字体下量到的是另一个世界（见 support/math_fonts.dart）。

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/hit_map.dart';
import 'package:mathlang/render/injection_map.dart';
import 'package:mathlang/render/leaf_boxes.dart';
import 'package:mathlang/render/math_caret.dart';
import 'package:mathlang/render/slot_marks.dart';
import 'package:mathlang/render/structure_geometry.dart';

import '../support/math_fonts.dart';

/// 给"像素扫线"用的重绘边界（`_pump` 里包着 Math）
final GlobalKey _padBoundary = GlobalKey();

const double kFont = 16;

/// 一个正文汉字的宽度（字号 16）
const double kHanziWidth = 16.0;

/// 分式的内边距（`_FracPos` 的 2 × 1.9，实测）
const double kFracPadding = 2 * 1.9;

Future<void> _pump(WidgetTester t, String tex,
    {MathStyle style = MathStyle.text, double size = kFont}) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: RepaintBoundary(
          key: _padBoundary,
          child: Math.tex(
            tex,
            textStyle: TextStyle(fontSize: size),
            mathStyle: style,
          ),
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

RenderObject _root(WidgetTester t) =>
    t.renderObject<RenderObject>(find.byType(Math));

void main() {
  setUpAll(() async {
    // ★ 真实 KaTeX 字体：否则字形落在回退度量上，量到的是另一个世界（见 support/math_fonts.dart）
    await loadMathFonts();
  });

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
      await _pump(tester, '\\frac{\\textcolor{#FFFFFF}{$kSlotPadGlyph}}{b}');
      final Size noPad = tester.getSize(find.byType(Math));

      debugPrint('带垫=$withPad  不带垫=$noPad');
      expect(withPad.height, closeTo(noPad.height, 0.01),
          reason: '★ 选"零高宽度垫"就是为了**不改变高度/基线** —— '
              '白 `\\rule{18mu}` 那一版会把空分式撑高 ~10px（探针实测），等于"换槽时版面跳"');
      expect(withPad.width - noPad.width, closeTo(5.6, 1.5),
          reason: '只补宽：0.3em（字号 16 下 ≈5.6 px）');
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

  // ─────────────────────────────────────────────────────────────
  // ★★ 槽带（2026-10-17 用户实测："分母的虚线框上沿跑到分子区去了"）
  //
  // 根因（真实字体探针）：字形盒是**字体行高盒**，`\square` 更是落在 AMS/回退度量上
  // （字号 20 时 15.6×**31** = 1.55em），而分母那格只有 ~19px ⇒ 框必然顶穿分数线。
  // 修法两条：**换数学字体里的字形**（`M`：19.4×21 = 1.05em）+ **把框夹进槽带**。
  // ─────────────────────────────────────────────────────────────
  group('★★ 槽带：框不许比结构大、不许压到别的槽', () {
    testWidgets('★ ⑥ 垫子盒 ⊆ 它所在的**结构节点**盒', (WidgetTester tester) async {
      // 改前：`\frac{a}{}` 的分母垫子盒 y 14.9..45.9，而 `_FracPos` 节点盒只到 35.9 ⇒ 溢出 10px
      for (final String tex in <String>[r'\frac{a}{}', r'\frac{}{b}']) {
        final String rt = renderMathTex(tex, caretRel: -1);
        await _pump(tester, rt);
        final RenderObject root = _root(tester);
        final Rect pad = scanSlotPads(root).single.rect;
        final StructureNode node = collectStructureNodes(root).first;
        final Rect nr = node.rect;
        debugPrint('「$tex」pad=$pad  node=${node.type} $nr');
        expect(pad.top, greaterThanOrEqualTo(nr.top - 0.5),
            reason: '★ 框的上沿不许超出结构（pad=$pad node=$nr）');
        expect(pad.bottom, lessThanOrEqualTo(nr.bottom + 0.5),
            reason: '★ 框的下沿不许超出结构（pad=$pad node=$nr）');
      }
    });

    testWidgets('★ ⑦ 分母的框**不许越过分数线**（像素扫线，独立验证）',
        (WidgetTester tester) async {
      // 用**用户的式子**：行间、字号 20。分数线不是盒（`_FracPos` 自己画的）⇒ 扫像素找它。
      for (final String tex in <String>[
        r'x=\frac{-b\pm\sqrt{b^2-4ac}}{}',
        r'\frac{a}{}',
      ]) {
        final String rt = renderMathTex(tex, caretRel: -1);
        await _pump(tester, rt, size: 20, style: MathStyle.display);
        final RenderObject root = _root(tester);
        final Rect pad = scanSlotPads(root).single.rect;
        final double? line = await _lineY(tester, Offset.zero & (root as RenderBox).size);
        debugPrint('「$tex」pad=$pad  扫出的分数线 y=$line');
        expect(line, isNotNull, reason: '必须能扫到分数线（否则这条断言是假通过）');
        expect(pad.top, greaterThanOrEqualTo(line! + 0.5),
            reason: '★ 分母的框上沿必须在**分数线之下**（pad=$pad 线=$line）——'
                '改前实测：框顶 24.5、线 26 ⇒ 直接压在线上');
      }
    });

    testWidgets('★ ⑧ 垫子字形的 ¶ 盒必须来自**数学字体**（≈1.05em，不是 1.55em）',
        (WidgetTester tester) async {
      await _pump(tester, renderMathTex(r'\frac{}{b}', caretRel: -1),
          size: 20, style: MathStyle.display);
      final RenderObject root = _root(tester);
      Rect? glyphBox;
      void walk(RenderObject o) {
        if (o is RenderParagraph && o.text.toPlainText() == kSlotPadGlyph) {
          glyphBox = o.localToGlobal(Offset.zero, ancestor: root) & o.size;
        }
        o.visitChildren(walk);
      }

      walk(root);
      expect(glyphBox, isNotNull, reason: '垫子字形必须在（¶ 文本 = $kSlotPadGlyph）');
      final double em = glyphBox!.height / 20.0;
      debugPrint('垫子字形 ¶ 盒 = ${glyphBox!.width.toStringAsFixed(1)}×'
          '${glyphBox!.height.toStringAsFixed(1)} ⇒ ${em.toStringAsFixed(2)}em');
      expect(em, lessThan(1.2),
          reason: '★ 字形盒必须是**数学字体**的行盒（`M` = 1.05em）；'
              '用 `\\square` 这类落在 AMS/回退度量的字形会得到 1.55em ⇒ 框偏大');
      expect(glyphBox!.width, greaterThan(15.0),
          reason: '还要够宽（帮 ④-2 够到"一个正文汉字"）');
    });

    testWidgets('★ ⑨ 真实字体下：行内空分式仍 ≥ 一个正文汉字', (WidgetTester tester) async {
      await _pump(tester, renderMathTex(r'x_1x_2=\frac{c}{}', caretRel: -1));
      final double w = tester.getSize(find.byType(Math)).width;
      await _pump(tester, r'x_1x_2=\frac{c}{a}');
      final double filled = tester.getSize(find.byType(Math)).width;
      debugPrint('行内空分式（真实字体）= $w，填满 = $filled');
      expect(w, greaterThanOrEqualTo(kHanziWidth),
          reason: '★ §6.1：空槽是**触摸目标**，宽度按正文汉字定标（真实字体下也要够）');
    });
  });
}

/// 在 [region]（**Math 局部坐标** = 重绘边界局部坐标，两者同原点）里扫出
/// **最长连续深色像素**所在的行 ⇒ 分数线
/// （分数线不是盒，是 `_FracPos` 自己画的 ⇒ 只能扫像素。★ `toImage` 必须走 `runAsync`）
Future<double?> _lineY(WidgetTester tester, Rect region) async {
  final RenderRepaintBoundary b =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_padBoundary));
  double? best;
  var bestLen = 0;
  await tester.runAsync(() async {
    final ui.Image img = await b.toImage(pixelRatio: 1.0);
    final ByteData? d = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (d == null) return;
    final int w = img.width;
    // ★ 图像像素 = 边界局部坐标（pixelRatio 1.0）⇒ **不加任何全局偏移**
    final int x0 = math.max(0, region.left.floor());
    final int x1 = math.min(w - 1, region.right.ceil());
    final int y0 = math.max(0, region.top.floor());
    final int y1 = math.min(img.height - 1, region.bottom.ceil());
    for (var y = y0; y <= y1; y++) {
      var run = 0;
      for (var x = x0; x <= x1; x++) {
        final int i = (y * w + x) * 4;
        final int r = d.getUint8(i), g = d.getUint8(i + 1), bl = d.getUint8(i + 2);
        // 深色 = 三通道均值 < 200（分数线很细、抗锯齿后也就 ~50% 灰）
        if (d.getUint8(i + 3) > 8 && (r + g + bl) < 3 * 200) {
          run++;
          if (run > bestLen) {
            bestLen = run;
            best = y.toDouble();
          }
        } else {
          run = 0;
        }
      }
    }
    img.dispose();
  });
  return best;
}
