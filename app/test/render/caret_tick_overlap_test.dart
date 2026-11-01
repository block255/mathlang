// 块边界刻度**不许压在光标竖条上**（2026-11-01 用户实测：光标变成一根淡色细条）。
//
// 现场：光标停在行间块的"公式之后 / 之前"那两格时，屏幕上只有一根**淡色**细条，
//   深色光标（`#1E88E5`）在整张截图里**一个像素都找不到**。
// 根因：批 10 把这两格的**竖条**挪到了块边外（`-(caretWidth+1.5)` / `w+1.5`），
//   而刻度仍按**同一个 x** 画 ⇒ 刻度（1px 淡色）后画、盖住竖条（1.5px 深色）。
// 修法：刻度再往外让 3px，两者错开。
//
// 改前必红：①②（刻度与竖条的 x 区间相交）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/math_caret.dart';

import '../support/math_fonts.dart';

Future<DocBuffer> _pump(WidgetTester t, String doc) async {
  final DocBuffer buf = DocBuffer(doc);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
  ));
  t.state<EditViewState>(find.byType(EditView)).focusInput();
  await t.pumpAndSettle();
  return buf;
}

({Rect bar, Rect tick})? _caret(WidgetTester t) {
  for (final Element e in find.byType(MathWithCaret).evaluate()) {
    final dynamic st = (e as StatefulElement).state as dynamic;
    final Rect? bar = st.debugCaretBar as Rect?;
    final Rect? tick = st.debugTick as Rect?;
    if (bar != null && tick != null) return (bar: bar, tick: tick);
  }
  return null;
}

void main() {
  setUpAll(() async => loadMathFonts());
  const String doc = '前\n\$\$\na+b\n\$\$\n后\n';

  testWidgets('① 公式**之前**那一格：刻度在竖条外侧，不许相交', (WidgetTester t) async {
    final DocBuffer buf = await _pump(t, doc);
    final int open = buf.buf.indexOf(r'$$');
    buf.setCaret(open - 1); // 块之前那一格
    await t.pumpAndSettle();
    await t.pumpAndSettle();
    final ({Rect bar, Rect tick})? c = _caret(t);
    expect(c, isNotNull, reason: '这一格必须同时有竖条与刻度（否则这条守卫没测到东西）');
    expect(c!.tick.right <= c.bar.left + 0.01, isTrue,
        reason: '刻度 ${c.tick} 不许压在竖条 ${c.bar} 上（重叠 ⇒ 光标被盖成淡色）');
  });

  testWidgets('② 公式**之后**那一格：同样不许相交', (WidgetTester t) async {
    final DocBuffer buf = await _pump(t, doc);
    final int close = buf.buf.lastIndexOf(r'$$');
    buf.setCaret(close + 2); // 块之后那一格
    await t.pumpAndSettle();
    await t.pumpAndSettle();
    final ({Rect bar, Rect tick})? c = _caret(t);
    expect(c, isNotNull, reason: '这一格必须同时有竖条与刻度');
    expect(c!.tick.left >= c.bar.right - 0.01, isTrue,
        reason: '刻度 ${c.tick} 不许压在竖条 ${c.bar} 上');
  });
}

