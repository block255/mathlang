// ★★ U3 守卫（2026-10-21 用户拍板"平权"）：**同一视觉行上，光标不该因为旁边是文字还是
// 数学符号而变高变矮**。
//
// 探针实测（正文 16px、行内公式 `$a+b$`）：
//   · 文字侧竖条 h **20.0**（= 字号 × 1.25），cy 109.0
//   · 数学主行竖条 h **13.4**（= 当地行盒 16.0 × 0.84），cy 108.8
//   ⇒ 中心只差 0.2px（几乎重合），**高度矮了 6.6px（1/3）** —— 光标一进一出就"跳"。
//
// 修法：行内公式**主行**（`caretDepth == 0`）的竖条改用文本层标准高度、中心不动；
//   **子层**（分子/分母/上下限/脚标）与**行间块**一律保持原样 —— 那是"适应数学符号"，
//   正是本文件第 2、3 组要钉住不许被破坏的部分。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/math_caret.dart';

import '../support/math_fonts.dart';

Future<DocBuffer> _pump(WidgetTester tester, String doc) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer(doc);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
  ));
  tester.state<EditViewState>(find.byType(EditView)).focusInput();
  await tester.pumpAndSettle();
  return buf;
}

Future<void> _caretAt(WidgetTester tester, DocBuffer buf, int at) async {
  buf.setCaret(at);
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

/// 文本侧竖条（Container：宽 ≈1.5、无 child、有 color；过滤掉池里的副本）
List<Rect> _textBars(WidgetTester tester) {
  final List<Rect> out = <Rect>[];
  for (final Element e in find.byType(Container).evaluate()) {
    final Container c = e.widget as Container;
    if (c.child != null || c.color == null) continue;
    final BoxConstraints? bc = c.constraints;
    if (bc == null || bc.maxWidth > 4 || bc.minWidth < 1) continue;
    final RenderObject? ro = e.renderObject;
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) continue;
    if (ro.size.width <= 0 || ro.size.height <= 0) continue;
    final Offset tl = ro.localToGlobal(Offset.zero);
    if (tl.dy < 40) continue;
    out.add(tl & ro.size);
  }
  return out;
}

/// 数学侧竖条：**读组件这一帧真正算出来的矩形**（`debugCaretBar`），不复制业务公式
Rect? _mathBar(WidgetTester tester) {
  for (final Element e in find.byType(MathWithCaret).evaluate()) {
    final MathWithCaret w = e.widget as MathWithCaret;
    if (!w.showCaret) continue;
    final RenderObject? ro = e.renderObject;
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) continue;
    final Offset tl = ro.localToGlobal(Offset.zero);
    if (tl.dy < 40) continue;
    final dynamic st = (e as StatefulElement).state as dynamic;
    final Rect? local = st.debugCaretBar as Rect?;
    if (local == null || local.isEmpty) continue;
    return local.shift(tl);
  }
  return null;
}

void main() {
  setUpAll(() async => loadMathFonts());

  group('① 行内公式**主行** vs 文字：高度与中心必须一致（改前：矮 6.6px）', () {
    testWidgets(r'$a+b$ 主行竖条 ≈ 文字侧竖条（高 ±0.5 / 中心 ±0.5）', (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, r'甲乙 $a+b$ 尾');
      await _caretAt(tester, buf, 2); // 文字里（乙后）
      final List<Rect> t = _textBars(tester);
      expect(t, isNotEmpty, reason: '文字侧竖条要能抓到');
      final Rect textBar = t.first;

      await _caretAt(tester, buf, 4); // 公式主行（a 前）
      final Rect? mathBar = _mathBar(tester);
      expect(mathBar, isNotNull, reason: '主行要画出竖条');

      expect(mathBar!.height, closeTo(textBar.height, 0.5),
          reason: '平权：同一行上光标高矮必须一致。文字 ${textBar.height.toStringAsFixed(1)} '
              '· 数学 ${mathBar.height.toStringAsFixed(1)}（改前 13.4 vs 20.0）');
      expect(mathBar.center.dy, closeTo(textBar.center.dy, 0.5),
          reason: '中心也不许错开。文字 ${textBar.center.dy.toStringAsFixed(1)} '
              '· 数学 ${mathBar.center.dy.toStringAsFixed(1)}');
    });

    testWidgets('主行的 3 个位点都一样（a 前 / + 后 / 公式末）',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, r'甲乙 $a+b$ 尾');
      await _caretAt(tester, buf, 2);
      final double textH = _textBars(tester).first.height;
      for (final int at in <int>[4, 6, 8]) {
        await _caretAt(tester, buf, at);
        final Rect? b = _mathBar(tester);
        expect(b, isNotNull, reason: 'caret=$at 应有竖条');
        expect(b!.height, closeTo(textH, 0.5), reason: 'caret=$at 高度应与文字一致');
      }
    });
  });

  group('② 子层必须保持"适应"：竖条只占自己那一层', () {
    testWidgets(r'\frac{a}{b}：分子与分母的竖条互不重叠、且都不等于文字高',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, r'甲乙 $\frac{a}{b}$ 尾');
      await _caretAt(tester, buf, 2);
      final double textH = _textBars(tester).first.height;

      await _caretAt(tester, buf, 10); // 分子（a 前）
      final Rect? num = _mathBar(tester);
      await _caretAt(tester, buf, 14); // 分母（b 后）
      final Rect? den = _mathBar(tester);
      expect(num, isNotNull);
      expect(den, isNotNull);

      expect(num!.height, lessThan(textH - 2),
          reason: '分子里的竖条本来就该比正文行矮（按当地行盒），不许被"统一"掉');
      expect(den!.height, lessThan(textH - 2), reason: '分母同理');
      expect(num.overlaps(den), isFalse,
          reason: '分子/分母是两层 ⇒ 竖条不许跨层（改前/改后都必须如此）');
    });

    testWidgets(r'上标 $x^{2}$：脚标层的竖条比主行矮', (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, r'甲乙 $x^{2}$ 尾');
      await _caretAt(tester, buf, 2);
      final double textH = _textBars(tester).first.height;
      // `$x^{2}$` 偏移：3 `$` · 4 `x` · 5 `^` · 6 `{` · 7 `2` · 8 `}` · 9 `$`
      // ⇒ 8 = 上标组内末尾（depth>0）；9 是"公式之后"那一格（走文本层标准，不是本组要测的）
      await _caretAt(tester, buf, 8);
      final Rect? sup = _mathBar(tester);
      expect(sup, isNotNull);
      expect(sup!.height, lessThan(textH - 2),
          reason: '上标层的竖条要跟着上标那一层（适应），不许被拉高到正文标准');
    });
  });

  group('③ 行间公式块不受影响（与改前同口径）', () {
    testWidgets(r'$$\n a+b \n$$ 里的竖条仍按行盒，不是文本层标准',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, '甲\n\n\$\$\na+b\n\$\$\n');
      // 找块内第一个可落点
      await _caretAt(tester, buf, buf.buf.indexOf('a') + 1);
      final Rect? bar = _mathBar(tester);
      expect(bar, isNotNull, reason: '行间块里要画出竖条');
      // 行间字号 20 ⇒ 文本层标准会是 25.0；按行盒应是 ~20 ⇒ 用"明显不等于 25"来钉住
      expect(bar!.height, lessThan(24.0),
          reason: '行间块不许被 U3 改动（它独占一行，没有"旁边的文字"要对齐）');
    });
  });
}
