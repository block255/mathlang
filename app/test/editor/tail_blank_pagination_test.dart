// **自动分页守卫**（2026-10-27）：**尾部空行也要参与分页**。
//
// 现象（用户实测 + 探针）：页面写满后，在文末连按 Enter —— 页数一直不变，光标不停往下画，
//   第 42 次起 y=3489.8 超过末页底 3488 ⇒ **光标画到纸外消失**。
// 根因：空行高度只作为"下一个单元的 `leadingGap`"结算；文末后面没有下一个单元
//   ⇒ 分页器不知道那里还有高度。
// 修法：`_itemsFrom` 末尾追加一个"占位 item"（有高度、无单元），像正文一样被 flush 到下一页；
//   末页槽改用"全文最后一个单元"兜底，这样"只有空行的一页"上也有人画光标。
//
// 判据：连按 Enter 到页面放不下时，**页数必须增长**，而且**光标始终在最后一页里**。

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
  testWidgets('★ 文末连按 Enter 到页面放不下 ⇒ 页数增长、光标始终在最后一页内',
      (WidgetTester tester) async {
    final String doc = '${List<String>.filled(56, '一行文字').join('\n\n')}\n';
    await _mount(tester, doc, doc.length);
    final int pagesBefore = _pages(tester).length;
    expect(pagesBefore, greaterThan(1), reason: '前置：这份文档本来就占多页');
    var pagesAfter = pagesBefore;
    for (var i = 0; i < 45; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      final List<Rect> ps = _pages(tester);
      pagesAfter = ps.length;
      final double y = _caretY(tester);
      expect(y <= ps.last.bottom, isTrue,
          reason: '第 ${i + 1} 次 Enter 之后光标 y=$y 掉到末页底 ${ps.last.bottom} 外面（改前就会这样）');
    }
    // ignore: avoid_print
    print('[tail-pagination] 页数 $pagesBefore → $pagesAfter');
    expect(pagesAfter, greaterThan(pagesBefore),
        reason: '高度吃满一页后必须开新页（改前页数一直不变，光标画到纸外）');
  });
}
