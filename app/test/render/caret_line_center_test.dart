// 行内主行竖条：中心 = **行盒中心**（与文字侧同一个定义），不许随邻居变（2026-11-01）。
//
// 现场（用户两张图，同一行、同一格）：
//   `$f^{\prime}_{+}f^{\prime}_{+}$`          → 竖条低 7px（下沿伸出墨迹 11px）
//   `$f^{\prime}_{+}f^{\prime}_{+}\xi\omega$` → 竖条正、包住墨迹
// 根因：中心取"挑中的**字形盒**"中心 ⇒ 换邻居就换盒 ⇒ 跳 4.2px，且无后续那档比文字侧低 4.0px。
// 修法：中心取**行盒中心**（单行段 = 段落盒中心）——与文字侧 `_caretInset` 同源：
//   文字侧 = 行顶 + (行盒 − 1.25em)/2 + 1.25em/2 = **行盒中心**。
//
// 改前必红：①（跳 4.2px）· ②（低 4.0px）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/math_caret.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../support/math_fonts.dart';

Future<DocBuffer> _pump(WidgetTester tester, String doc) async {
  tester.view.physicalSize = const Size(1400, 900);
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

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

Rect? _mathBar(WidgetTester tester) {
  for (final Element e in find.byType(MathWithCaret).evaluate()) {
    final MathWithCaret w = e.widget as MathWithCaret;
    if (!w.showCaret) continue;
    final dynamic st = (e as StatefulElement).state as dynamic;
    return st.debugCaretBar as Rect?;
  }
  return null;
}

Rect? _textBar(WidgetTester tester) {
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
    return tl & ro.size;
  }
  return null;
}

Future<({Rect bar, Rect math})> _at(
    WidgetTester tester, DocBuffer buf, int at) async {
  buf.setCaret(at);
  await _settle(tester);
  final Rect? local = _mathBar(tester);
  final Rect math = tester.getRect(find.byType(Math).first);
  expect(local, isNotNull, reason: '这个位点必须有竖条');
  return (bar: local!.shift(math.topLeft), math: math);
}

void main() {
  setUpAll(() async => loadMathFonts());
  const String u = r'f^{\prime}_{+}';

  testWidgets('① 同一格：后面加内容不许改变竖条', (WidgetTester tester) async {
    final List<({Rect bar, Rect math})> rs = <({Rect bar, Rect math})>[];
    final List<String> labels = <String>[];
    for (final (String doc, String label) in <(String, String)>[
      ('甲\$$u$u\$乙', '无后续'),
      ('甲\$$u${u}x\$乙', '+x'),
      (r'甲$' '$u' '$u' r'\xi\omega$乙', r'+ξω'),
      ('甲\$$u$u\$', '后面没正文'),
    ]) {
      final DocBuffer buf = await _pump(tester, doc);
      final int s = buf.buf.indexOf('f^{');
      rs.add(await _at(tester, buf, s + u.length));
      labels.add(label);
    }
    final String desc = <String>[
      for (int i = 0; i < rs.length; i++)
        '${labels[i]}: ${rs[i].bar.top.toStringAsFixed(1)}/${rs[i].bar.height.toStringAsFixed(1)}'
    ].join(' · ');
    final double top0 = rs[0].bar.top - rs[0].math.top;
    for (var i = 1; i < rs.length; i++) {
      final double top = rs[i].bar.top - rs[i].math.top;
      expect((top - top0).abs(), lessThan(0.6), reason: '邻居不该改变竖条位置（$desc）');
      expect((rs[i].bar.height - rs[0].bar.height).abs(), lessThan(0.6),
          reason: '邻居不该改变竖条高度（$desc）');
    }
  });

  testWidgets('② 与文字侧竖条同中心（同一把尺子：行盒中心）', (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, '甲\$$u$u\$乙');
    final int s = buf.buf.indexOf('f^{');
    final ({Rect bar, Rect math}) r = await _at(tester, buf, s + u.length);

    buf.setCaret(1);
    await _settle(tester);
    final Rect? tb = _textBar(tester);
    expect(tb, isNotNull, reason: '文字侧必须有竖条');
    expect((r.bar.center.dy - tb!.center.dy).abs(), lessThan(0.6),
        reason: '公式侧 ${r.bar.center.dy.toStringAsFixed(1)} vs 文字侧 ${tb.center.dy.toStringAsFixed(1)}');
  });
}
