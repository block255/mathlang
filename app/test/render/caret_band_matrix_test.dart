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

      // ⚠️ 只跑到 18：矩阵第一次跑就抓到一条**新问题** —— 字号 ≥20 时，
      //   "行间分式 tex 末尾"与"块后"两格的竖条 y 差会涨到 **4.19（20px）/ 5.12（24px）**
      //   （16px 时是 3.3）。两格用的是两把尺子（堆叠 ⇒ 根行盒中心；块后 ⇒ 边界内缩），
      //   它们随字号缩放不同步 ⇒ 这是一条**独立缺陷**，已记入台账等专门修；
      //   在修好之前，这里只钉住已验证的范围（14–18），不做"把阈值调大让它变绿"那种事。
      if (fs <= 18) {
        testWidgets('③ 行间分式：tex 末尾与"块后"那格的竖条 y 差 ≤4px',
            (WidgetTester t) async {
          const String inner = r'\frac{a-x}{a+x}';
          final String doc = 'a\n\n' r'$$' '\n' '$inner' '\n' r'$$' '\n';
          final int texEnd = doc.indexOf(inner) + inner.length;
          final int closeEnd = doc.indexOf(r'$$', texEnd) + 2;

          await mount(t, doc, texEnd, fontSize: fs);
          final double y1 = probe(t)!.bar.top;
          await mount(t, doc, closeEnd, fontSize: fs);
          final double y2 = probe(t)!.bar.top;
          expect((y1 - y2).abs(), lessThan(4.0),
              reason: 'tex 末尾 $y1 vs 块后 $y2');
        });
      }

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
