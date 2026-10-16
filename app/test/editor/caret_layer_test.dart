// §11.27 **光标的层级**守卫（2026-10-16 用户提出）：
//   「行内数学语言**后面的**光标，跟文本后面的光标**地位等同**」
//   ⇒ 竖条的"行 / 高度"必须按**光标所在的那一层**定，不按"几何最近的字形"。
//
// 三条不变量（改前必须红）：
//   A. **公式之后 ≡ 文字之后**：同高（字号 × 1.25），竖直位置也基本一致
//      （改前：公式之后那格拿公式内部最近的一行 ⇒ 会被**分母**抢走、高度只有 13.4）
//   B. **竖条必须与"该位点自己那一层"的字形行相交**（全域扫描；改前分式末尾那格画到分母行）
//   C. **跟随字号**：标题（28）的光标高 = 正文（16）的 1.75 倍

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/injection_map.dart';
import 'package:mathlang/render/leaf_boxes.dart';
import 'package:mathlang/render/math_caret.dart';
import 'package:mathlang/render/site_adjacency.dart';
import 'package:mathlang/render/slot_marks.dart';
import 'package:mathlang/render/visible_atoms.dart';

Future<void> _mount(WidgetTester tester, DocBuffer buf) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
  ));
  tester.state<EditViewState>(find.byType(EditView)).focusInput();
  await tester.pumpAndSettle();
}

/// 数学侧自绘竖条 —— ★ **换算到全局坐标**（`MathCaretPainter.rect` 是 Math 盒的局部坐标），
/// 且**只认有实际尺寸的**（文档里还有一棵**测量树**，它也会渲染同一根条，
/// 但那棵树里的条是 0×0、不参与绘制 —— 不滤掉就会把两棵树混在一起）。
List<Rect> _mathBars(WidgetTester tester, {bool global = true}) {
  final List<Rect> out = <Rect>[];
  for (final Element e in find.byType(MathWithCaret).evaluate()) {
    final RenderObject? ro = e.renderObject;
    if (ro is! RenderBox) continue;
    final Offset origin = ro.localToGlobal(Offset.zero);
    // ★ 注意：`RenderCustomPaint` **有子节点**（它包着 Math）⇒ 不能套"只认叶子"的写法
    void walk(RenderObject o) {
      if (o is RenderCustomPaint && o.foregroundPainter is MathCaretPainter) {
        final Rect r = (o.foregroundPainter! as MathCaretPainter).rect;
        if (r.width > 0.5 && r.height > 1) {
          out.add(global ? r.shift(origin) : r);
        }
      }
      o.visitChildren(walk);
    }

    walk(ro);
  }
  return out;
}

/// 文本侧零宽光标条（`_caretBar` 里那个 `Container`，颜色 = 光标色）；
/// 同样**只认有实际尺寸的**（滤掉测量树里那颗 0×0 的）。
List<Rect> _textBars(WidgetTester tester) {
  final List<Rect> out = <Rect>[];
  for (final Element e in find.byType(Container).evaluate()) {
    final Container c = e.widget as Container;
    if (c.color != const Color(0xFF1E88E5)) continue;
    final Rect r = tester.getRect(find.byWidget(c));
    if (r.width > 0.5 && r.height > 1) out.add(r);
  }
  return out;
}

/// 当前**唯一**那根竖条（文本侧或数学侧），没有就 null
Rect? _caretBar(WidgetTester tester) {
  final List<Rect> all = <Rect>[..._textBars(tester), ..._mathBars(tester)];
  return all.isEmpty ? null : all.first;
}

void main() {
  // ─────────────────────────────────────────────────────────────
  group('A 公式之后 ≡ 文字之后（同权）', () {
    testWidgets(r'`AB$\frac{c}{d}$CD`：闭合 $ 之后那一格 ≡ 正文里那一格', (WidgetTester tester) async {
      const String doc = r'AB$\frac{c}{d}$CD';
      final DocBuffer buf = DocBuffer(doc);
      await _mount(tester, buf);

      // ① 正文文字里（'D' 那一格 = 偏移 16）
      buf.setCaret(16);
      await tester.pump();
      await tester.pump();
      final Rect textBar = _caretBar(tester)!;
      debugPrint('caret=16 文本条=${_textBars(tester)}  数学条=${_mathBars(tester)}');

      // ② 闭合 `$` 之后那一格（= 公式之后，偏移 15；数据上属数学段、视觉上属文本层）
      buf.setCaret(15);
      await tester.pump();
      await tester.pump();
      final Rect afterBar = _caretBar(tester)!;
      debugPrint('caret=15 文本条=${_textBars(tester)}  数学条=${_mathBars(tester)}  '
          'showCaret=${find.byType(MathWithCaret).evaluate().map((Element e) => (e.widget as MathWithCaret).showCaret).toList()}');

      debugPrint('文字后=$textBar   公式后=$afterBar');
      expect(afterBar.height, closeTo(textBar.height, 0.5),
          reason: '★"公式之后"的光标必须与"文字之后"**同高**；'
              '实际 ${afterBar.height} vs ${textBar.height}'
              '（偏矮 = 又去拿公式内部那一行的 ¶ 盒了）');
      expect((afterBar.center.dy - textBar.center.dy).abs(), lessThan(4.0),
          reason: '★两者的竖直位置也必须基本一致（同一行、同一基线）；'
              '实际中心 ${afterBar.center.dy} vs ${textBar.center.dy} —— '
              '偏下十几像素 = 画到分母那一行去了；偏 3px 以内属"两侧约定差"'
              '（文本侧在行盒里居中、数学侧按基线摆，见 §11.27 记账）');
    });
  });

  // ─────────────────────────────────────────────────────────────
  group('B 竖条必须与"该位点自己那一层"的字形行相交', () {
    const List<String> corpus = <String>[
      r'x=\frac{a}{b}',
      r'\frac{a}{b}+\frac{c}{d}',
      r'\sqrt{2}',
      r'\sqrt{x+1}',
      r'\overline{AB}',
      r'\hat{x}+\bar{y}',
      r'x^{2}',
      r'x_{a_i}',
      r'\begin{cases}a&b\\c&d\end{cases}',
      r'\begin{aligned}a&=b\\c&=d\end{aligned}',
    ];

    testWidgets('全域扫描（${corpus.length} 类结构 × 全部位点）', (WidgetTester tester) async {
      final List<String> flags = <String>[];
      var checked = 0, skipped = 0;

      for (final String tex in corpus) {
        final String doc = '起\n\n\$\$\n$tex\n\$\$\n\n末\n';
        final DocBuffer buf = DocBuffer(doc);
        await _mount(tester, buf);
        final int texStart = doc.indexOf(tex);
        final CaretSiteTable t = buildCaretSites(tex);

        for (final int rel in t.offsets) {
          buf.setCaret(texStart + rel);
          await tester.pump();
          await tester.pump();

          // ★ 竖条取**局部**坐标（与 `scanLeafBoxes` 给的叶盒同一坐标系 —— 都以 Math 根盒为原点）
          final List<Rect> bars = _mathBars(tester, global: false);
          if (bars.isEmpty) continue; // 由文本层画（块前后那两格）—— 见 A 组
          final Rect bar = bars.first;

          RenderObject? root;
          for (final Element e in find.byType(MathWithCaret).evaluate()) {
            if ((e.widget as MathWithCaret).showCaret) root = e.renderObject;
          }
          if (root == null) continue;

          final String renderTex = renderMathTex(tex, caretRel: rel);
          final LeafBoxScan scan = scanLeafBoxes(root);
          final List<VisibleAtom> atoms = atomsForHitTest(renderTex);
          if (scan.eligible.length != atoms.length) {
            skipped++; // 一原子多盒 / 顺序错位 ⇒ 配不上一一对应（另账）
            continue;
          }
          checked++;

          final TexRegion? reg = innermostRegionAt(t, rel);
          final int rs = reg?.start ?? 0;
          final int re = reg?.end ?? tex.length;
          // ★ 层的字形盒：
          //   · 位点在某个**槽**里 ⇒ 该槽区间内的字形；
          //   · 位点在**主行**（含 tex 末尾那种"区域边界"上的位点）⇒ **不在任何槽里**的字形
          //     （这才是"主行那一行"，不会顺手把分母也算进同一层 —— 那会让判据失真）。
          final bool slotLayer = reg != null && reg.isSlot;
          bool inAnySlot(int src) => t.slots
              .any((SlotSpan sp) => src >= sp.start && src < sp.end);
          final List<Rect> layerBoxes = <Rect>[];
          for (var i = 0; i < atoms.length; i++) {
            final int src = renderToSourceOffset(renderTex, atoms[i].start);
            final bool inLayer =
                slotLayer ? (src >= rs && src < re) : (src >= 0 && src < tex.length && !inAnySlot(src));
            if (inLayer) layerBoxes.add(scan.eligible[i].rect);
          }
          if (layerBoxes.isEmpty) continue;
          final bool ok = layerBoxes
              .any((Rect r) => bar.top < r.bottom && bar.bottom > r.top);
          if (!ok) {
            flags.add('「$tex」rel=$rel：竖条 y ${bar.top.toStringAsFixed(1)}..'
                '${bar.bottom.toStringAsFixed(1)} 与该层字形行 '
                '${layerBoxes.map((Rect r) => '${r.top.toStringAsFixed(0)}..${r.bottom.toStringAsFixed(0)}').join(",")} 不相交');
          }
        }
      }

      debugPrint('扫描：检查 $checked 个位点，跳过 $skipped 个（配对不可靠）');
      expect(flags, isEmpty, reason: '竖条画到别的层去了：\n${flags.join('\n')}');
    });
  });

  // ─────────────────────────────────────────────────────────────
  group('C 跟随字号（文本层）', () {
    testWidgets('标题 28 的光标高 = 正文 16 的 1.75 倍', (WidgetTester tester) async {
      const String doc = '# 标题行\n\n正文一行\n';
      final DocBuffer buf = DocBuffer(doc);
      await _mount(tester, buf);

      buf.setCaret(3); // 标题里（`# ` 被剥掉，标题文本从 2 开始）
      await tester.pump();
      await tester.pump();
      final Rect headBar = _caretBar(tester)!;

      buf.setCaret(8); // 正文里（`# 标题行\n\n` 之后）
      await tester.pump();
      await tester.pump();
      final Rect bodyBar = _caretBar(tester)!;

      debugPrint('标题条=$headBar（字号 28）  正文条=$bodyBar（字号 16）');
      expect(bodyBar.height, closeTo(16 * 1.25, 0.5), reason: '正文：字号 × 1.25');
      expect(headBar.height, closeTo(28 * 1.25, 0.5), reason: '标题：字号 × 1.25（跟随本行字号）');
      expect(headBar.height / bodyBar.height, closeTo(28 / 16, 0.02));
    });
  });
}
