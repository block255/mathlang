// **字号矩阵**守卫（2026-11-04）：几何/手感判据必须在**多档字号**下都成立。
//
// 为什么需要它（当天的真事）：`_lineBoxCenterLocal` 用 `段盒高 > 1.6em` 判"单行段"，
// 而"行内放一个分式"的段盒 ≈ 2.05em —— 16px 下 32.0 正好**等于**阈值 32.0（擦边过），
// 18px 下 37.0 > 36.0 就翻了 ⇒ 竖条去画分母。全量 2099 条测试全绿，用户却一眼看得见。
// 根因不是"没适配字号"（阈值本来就随字号缩放），而是：
//   ① 判据用**几何高度猜语义**（是不是单行）；② **守卫只在一个配置下跑**。
// 本文件只治 ②：同一批**不变式**在 [14, 16, 18, 20, 24] 五档各跑一遍。
//
// ★ 纪律：矩阵里**不写死数字**，只写不变式（"落在带内 / 差 ≤N / 高 ≈ 1.25em"），
//   否则每加一档就要维护一组新基准。
//
// 注：`caret_layer_test` 那条全域扫描（10 类结构 × 67 位点）太慢，不在矩阵里重复；
//   这里用**代表性结构**（行内短式 / 行内分式 / 行间分式 / 根号 / overline）覆盖同一批判据。

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/core/doc_settings.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/math_caret.dart';

import '../support/math_fonts.dart';

const List<double> kFontSizes = <double>[14, 16, 18, 20, 24];

Future<DocBuffer> mount(WidgetTester t, String doc, int caret,
    {required double fontSize}) async {
  await t.pumpWidget(const SizedBox.shrink());
  final DocBuffer buf = DocBuffer(doc)..setCaret(caret);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 900,
        child: SingleChildScrollView(
          child: SizedBox(
            width: 793.7,
            child: EditView(
              buffer: buf,
              settings: DocSettings(bodyFontSize: fontSize),
            ),
          ),
        ),
      ),
    ),
  ));
  t.state<EditViewState>(find.byType(EditView)).focusInput();
  await t.pumpAndSettle();
  return buf;
}

/// 数学侧竖条（全局坐标）+ 它所在的 Math 盒 + 盒内的内层行（按 top 排序）
({Rect bar, Rect math, List<Rect> rows})? probe(WidgetTester t) {
  final Iterable<Element> ps = find
      .byWidgetPredicate((Widget w) =>
          w is CustomPaint && w.foregroundPainter is MathCaretPainter)
      .evaluate();
  for (final Element e in ps) {
    final RenderObject? ro = e.renderObject;
    if (ro is! RenderCustomPaint) continue;
    final MathCaretPainter p = ro.foregroundPainter! as MathCaretPainter;
    if (!p.caretVisible) continue;
    final Rect math = ro.localToGlobal(Offset.zero) & ro.size;
    final Rect bar = p.rect.shift(ro.localToGlobal(Offset.zero));
    final List<Rect> rows = <Rect>[];
    void walk(RenderObject o) {
      if (o.runtimeType.toString().contains('RenderLine') && o is RenderBox) {
        final Rect r = o.localToGlobal(Offset.zero) & o.size;
        if (r.height < ro.size.height - 0.5) rows.add(r);
      }
      o.visitChildren(walk);
    }

    walk(ro);
    rows.sort((Rect a, Rect b) => a.top.compareTo(b.top));
    return (bar: bar, math: math, rows: rows);
  }
  return null;
}

double _barCenter(Rect bar) => bar.top + bar.height / 2;

void main() {
  setUpAll(() async {
    await loadMathFonts();
  });

  for (final double fs in kFontSizes) {
    group('字号 $fs', () {
      testWidgets('① 行内短式 `\$a+b\$` tex 末尾：高 = 1.25em、中心 = 段中心',
          (WidgetTester t) async {
        const String doc = r'$a+b$';
        await mount(t, doc, doc.length + 1, fontSize: fs);
        final ({Rect bar, Rect math, List<Rect> rows})? m = probe(t);
        expect(m, isNotNull);
        final double h = m!.bar.height;
        expect((h - 1.25 * fs).abs(), lessThan(1.5),
            reason: '竖条高 $h 应 ≈ 1.25×$fs');
        final double c = _barCenter(m.bar);
        final double mathCenter = m.math.top + m.math.height / 2;
        expect((c - mathCenter).abs(), lessThan(fs * 0.5),
            reason: '竖条中心 $c 偏离公式盒中心 $mathCenter 太多');
      });

      testWidgets('② 行内分式 tex 末尾：竖条中心必须落在主行带（分子底~分母顶）',
          (WidgetTester t) async {
        const String inner = r'\frac{a-x}{a+x}';
        final String doc = '\$' '$inner' '\$';
        final int texEnd = doc.indexOf(r'$') + 1 + inner.length;
        await mount(t, doc, texEnd, fontSize: fs);
        final ({Rect bar, Rect math, List<Rect> rows})? m = probe(t);
        expect(m, isNotNull);
        expect(m!.rows.length, greaterThanOrEqualTo(2),
            reason: '分式的分子/分母行没找到');
        final Rect num = m.rows.first;
        final Rect den = m.rows.last;
        final double c = _barCenter(m.bar);
        expect(c, greaterThan(num.bottom - 2),
            reason: '竖条中心 $c 跑到分子上面（num=${num.top}..${num.bottom}）');
        expect(c, lessThan(den.top + 2),
            reason: '竖条中心 $c 落在分母那一带（den=${den.top}..${den.bottom}）');
      });

      // ★ 2026-11-04（补测后改判）：这一条**不是缺陷**，是我一开始把不变式写错了。
      //
      //   实测（四档字号，行间分式）：
      //     fs   tex末尾(块内)          块后(文本层)         中心差   Δ/字号
      //     16   148.5..166.1 h17.6     145.2..165.2 h20.0   2.09    0.131em
      //     18   156.0..175.3 h19.3     152.0..174.5 h22.5   2.35    0.131em
      //     20   162.0..183.9 h21.8     157.8..182.8 h25.0   2.61    0.131em
      //     24   175.6..201.7 h26.0     170.5..200.5 h30.0   3.14    0.131em
      //
      //   ⇒ 两格的**高度定义本来就不同**：块内 = 该层行盒 × 0.84（实测 h 随行盒），
      //     块后 = 文本层标准 1.25em（`textLayerCaretRect`）。所以 **top 差**会随字号线性增长
      //     （≈0.21em），而 **中心差恒为 0.131em** —— 这是设计结果，不是漂移。
      //   ⇒ 正确的不变式是"中心差 ≤0.15em"（与字号成比例），不是"top 差 ≤4px"。
      testWidgets('③ 行间分式：tex 末尾与"块后"两格的竖条**中心差 ≤0.15em**',
          (WidgetTester t) async {
        const String inner = r'\frac{a-x}{a+x}';
        final String doc = 'a\n\n' r'$$' '\n' '$inner' '\n' r'$$' '\n';
        final int texEnd = doc.indexOf(inner) + inner.length;
        final int closeEnd = doc.indexOf(r'$$', texEnd) + 2;

        await mount(t, doc, texEnd, fontSize: fs);
        final Rect a = probe(t)!.bar;
        await mount(t, doc, closeEnd, fontSize: fs);
        final Rect b = probe(t)!.bar;
        final double d = (a.center.dy - b.center.dy).abs();
        expect(d, lessThan(fs * 0.15),
            reason: '中心差 ${d.toStringAsFixed(2)}px（'
                '${(d / fs).toStringAsFixed(3)}em）> 0.15em；'
                'tex末尾 ${a.top.toStringAsFixed(1)}h${a.height.toStringAsFixed(1)} '
                'vs 块后 ${b.top.toStringAsFixed(1)}h${b.height.toStringAsFixed(1)}');
        // 顺带把"两格高度不同"这件事也钉住（它是设计，不是意外）
        expect((a.height - b.height).abs(), greaterThan(1.0),
            reason: '块内 = 该层行盒×0.84、块后 = 文本层 1.25em，两者不该相同');
      });

      testWidgets('④ `\\overline` / `\\sqrt` 的 tex 末尾：竖条不许被压扁',
          (WidgetTester t) async {
        for (final String inner in <String>[r'\overline{AB}', r'\sqrt{x+1}']) {
          final String doc = '\$' '$inner' '\$';
          final int texEnd = doc.indexOf(r'$') + 1 + inner.length;
          await mount(t, doc, texEnd, fontSize: fs);
          final ({Rect bar, Rect math, List<Rect> rows})? m = probe(t);
          expect(m, isNotNull, reason: inner);
          expect(m!.bar.height, greaterThan(fs * 0.7),
              reason: '$inner 的竖条被压扁了：h=${m.bar.height}');
        }
      });
    });
  }
}
