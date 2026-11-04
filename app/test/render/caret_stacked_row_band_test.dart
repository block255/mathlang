// N3c（2026-11-04）：**分式这类"上下堆叠"的结构后面，竖条要落在主行带**，
// 不能被分母抢走；而 `\overline` / `\sqrt` 这类**单内层行**的结构必须保持原样。
//
// 现场（用户截图 + 实测）：`$$\frac{a-x}{a+x}$$` 的 tex 末尾
//   · 改前：竖条 y=159.0（贴着分母 162.4）· 块后那格 y=145.2 ⇒ 差 **13.8px**
//   · 改后：148.5 ⇒ 差 3.3px
// 决策链根因：分式根行里一个字形都没有（`\frac` 不产生 ¶ 盒），而分母行的**盒底**
//   正好等于根行盒底 ⇒ "行盒底对齐"把分母认成本层。
// 修法：只有"≥2 条内层行、一条贴根行上缘、一条贴下缘"（= 上下堆叠）时，主行带才用根行盒。
//
// 改前必红：①（13.8px）。

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/math_caret.dart';

import '../support/math_fonts.dart';

Rect? mathBar(WidgetTester t) {
  for (final Element e in find
      .byWidgetPredicate((Widget w) =>
          w is CustomPaint && w.foregroundPainter is MathCaretPainter)
      .evaluate()) {
    final RenderObject? ro = e.renderObject;
    if (ro is! RenderCustomPaint) continue;
    final MathCaretPainter p = ro.foregroundPainter! as MathCaretPainter;
    if (!p.caretVisible) continue;
    return p.rect.shift(ro.localToGlobal(Offset.zero));
  }
  return null;
}

Future<DocBuffer> mount(WidgetTester t, String doc, int caret) async {
  await t.pumpWidget(const SizedBox.shrink());
  final DocBuffer buf = DocBuffer(doc)..setCaret(caret);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 900,
        child: SingleChildScrollView(
          child: SizedBox(width: 793.7, child: EditView(buffer: buf)),
        ),
      ),
    ),
  ));
  t.state<EditViewState>(find.byType(EditView)).focusInput();
  await t.pumpAndSettle();
  return buf;
}

void main() {
  setUpAll(() async {
    await loadMathFonts();
  });

  testWidgets('① 分式：tex 末尾那格与块后那格的竖条 y 必须接近（≤4px）',
      (WidgetTester t) async {
    const String inner = r'\frac{a-x}{a+x}';
    final String doc = 'a\n\n' r'$$' '\n' '$inner' '\n' r'$$' '\n';
    final int texEnd = doc.indexOf(inner) + inner.length;
    final int closeEnd = doc.indexOf(r'$$', texEnd) + 2;

    await mount(t, doc, texEnd);
    final Rect texBar = mathBar(t)!;
    await mount(t, doc, closeEnd);
    final Rect blockBar = mathBar(t)!;

    expect((texBar.top - blockBar.top).abs(), lessThan(4.0),
        reason: '改前 13.8px（tex 末尾 ${texBar.top.toStringAsFixed(1)}、'
            '块后 ${blockBar.top.toStringAsFixed(1)}）');
  });

  testWidgets('② 对照：`\\overline` / `\\sqrt` 的 tex 末尾不许被拉平到块后',
      (WidgetTester t) async {
    // 这两类是"单内层行"，主行就是它自己 ⇒ 不能被"上下堆叠"那条吃掉。
    // 判据：竖条必须与它自己那一层的字形行相交（高度不至于塌到 < 12）。
    for (final String inner in <String>[r'\overline{AB}', r'\sqrt{x+1}']) {
      final String doc = 'a\n\n' r'$$' '\n' '$inner' '\n' r'$$' '\n';
      final int texEnd = doc.indexOf(inner) + inner.length;
      await mount(t, doc, texEnd);
      final Rect? bar = mathBar(t);
      expect(bar, isNotNull, reason: inner);
      expect(bar!.height, greaterThan(12.0),
          reason: '$inner 的竖条被压扁了：h=${bar.height.toStringAsFixed(1)}');
    }
  });
}
