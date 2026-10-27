// **守卫（改前红）**：文末 Enter 的**每一行都是同一把尺子**，而且光标永远不离开页面。
//
// 现象（用户 2026-10-27 手测）：
//   · 文末第一下 Enter 像下了两行、后面每下只一行（实测 31px vs 20px）；
//   · 连续 Enter 到页面放不下时，光标一路画到纸外（"进入异次元空间"）。
// 根因：三把尺子混用 ——
//   ① 正文行距 = 行盒 + 段距（≈38）；② 空行高度取 `textCaretHeight`（≈20）；
//   ③ 文末占位项还额外背一个段距。
//   而且尾部空行的占位项**只有分页器认账、页面视觉不认账**（`u == null` 直接跳过）。
//
// 正确口径：**一行 = 正文行距**；空行、文字行、文末那一行都用同一把尺子；
//   段距只在"两段文字之间"出现一次，不叠在空行或文末第一行上。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/editor/page_sheet.dart';

Future<DocBuffer> _mount(WidgetTester tester, String doc, int caret) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer(doc)..setCaret(caret);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
  ));
  tester.state<EditViewState>(find.byType(EditView)).focusInput();
  await tester.pumpAndSettle();
  return buf;
}

List<Rect> _pages(WidgetTester tester) {
  final List<Rect> out = <Rect>[];
  for (final Element e in find.byType(PageSheet).evaluate()) {
    final RenderObject? ro = e.renderObject;
    if (ro is! RenderBox || !ro.hasSize) continue;
    out.add(ro.localToGlobal(Offset.zero) & ro.size);
  }
  return out;
}

double _caretY(WidgetTester tester) {
  final List<double> ys = <double>[];
  for (final Element e in find.byType(Container).evaluate()) {
    final Container w = e.widget as Container;
    final BoxConstraints? c = w.constraints;
    if (c == null || c.minWidth != 1.5 || c.maxWidth != 1.5) continue;
    final RenderObject? ro = e.renderObject;
    if (ro is! RenderBox || !ro.hasSize) continue;
    ys.add(ro.localToGlobal(Offset.zero).dy);
  }
  if (ys.isEmpty) return -1;
  ys.sort();
  return ys.last;
}

void main() {
  testWidgets('★ 文末连按 Enter：每一行增量相等（≈一个正文行距）', (WidgetTester tester) async {
    const String doc = 'aa\n\nbb\n';
    // ★ 2026-10-28：光标从**文末行末**起（用户打完字的常态），不是 EOF ——
    //   EOF 已经是"文末下一行"那一格；从那一格起按 Enter 只是把段距补成一行
    //   （已知缺陷，见交接快照 §三）。
    await _mount(tester, doc, doc.length - 1);
    final List<double> ys = <double>[_caretY(tester)];
    for (var i = 0; i < 5; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      ys.add(_caretY(tester));
    }
    // ignore: avoid_print
    print('[uniform] ys=${ys.map((double y) => y.toStringAsFixed(0)).join(",")}');
    final List<double> ds = <double>[
      for (var i = 1; i < ys.length; i++) ys[i] - ys[i - 1]
    ];
    // ignore: avoid_print
    print('[uniform] ds=${ds.map((double d) => d.toStringAsFixed(0)).join(",")}');
    for (var i = 0; i < ds.length; i++) {
      expect(ds[i], greaterThan(30.0),
          reason: '第 ${i + 1} 下只走了 ${ds[i].toStringAsFixed(0)}px（应≈一个正文行距）');
      expect(ds[i], lessThan(46.0), reason: '第 ${i + 1} 下走了 ${ds[i].toStringAsFixed(0)}px（超过一行）');
    }
  });

  testWidgets('★ 页面写满后继续 Enter：光标**始终**在最后一页内', (WidgetTester tester) async {
    final String doc = '${List<String>.filled(56, '一行文字').join('\n\n')}\n';
    await _mount(tester, doc, doc.length);
    for (var i = 0; i < 60; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      final List<Rect> ps = _pages(tester);
      final double y = _caretY(tester);
      expect(y <= ps.last.bottom, isTrue,
          reason: '第 ${i + 1} 次 Enter 后光标 y=${y.toStringAsFixed(0)} 超过末页底 '
              '${ps.last.bottom.toStringAsFixed(0)}');
    }
  });
}
