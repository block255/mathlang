// 批 40 · **光标归属的全域守卫**（先红后绿）
//
// 不变量（用户 2026-10-26 拍板）：
//   ① 每个偏移**至少**有一根光标竖条 —— 不然就是"按了没反应"的死区；
//   ② 同一偏移的所有竖条必须**落在同一行**（`top` 相同）—— 分处两地就是用户看到的"双光标"。
//      ★ 允许"同一像素上叠两根"（块边界条 + 光标条的重叠是历史行为，不是这次的病）。
//
// 这份文档是**判据本身**的守卫：批 38/38-回归/39 三次都是在"谁画光标"上加条件，
// 每次补一头漏一头。有了它，任何一处判据改坏都会在这里红。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';

Future<DocBuffer> _mount(WidgetTester tester, String doc) async {
  tester.view.physicalSize = const Size(900, 5200);
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

/// 光标竖条的 (left, top)（`Container(width:1.5)` 那一族）
List<Offset> _bars(WidgetTester tester) {
  final List<Offset> out = <Offset>[];
  for (final Element e in find.byType(Container).evaluate()) {
    final Widget w = e.widget;
    if (w is! Container) continue;
    final BoxConstraints? c = w.constraints;
    if (c == null || c.minWidth != 1.5 || c.maxWidth != 1.5) continue;
    final RenderObject? ro = e.renderObject;
    if (ro is RenderBox && ro.hasSize) out.add(ro.localToGlobal(Offset.zero));
  }
  out.sort((Offset a, Offset b) => a.dy.compareTo(b.dy));
  return out;
}

Future<({int count, Set<double> tops})> _at(
    WidgetTester tester, DocBuffer buf, int off) async {
  buf.setCaret(off);
  await tester.pump();
  await tester.pump();
  final List<Offset> bars = _bars(tester);
  return (
    count: bars.length,
    tops: <double>{for (final Offset o in bars) o.dy.roundToDouble()},
  );
}

const Map<String, String> kDocs = <String, String>{
  '① 单行': '甲\n',
  '② 两段': '甲\n\n乙\n',
  '③ 文末空行': '甲\n\n乙\n\n',
  '④ 分页符夹中间': '甲\n<!-- pagebreak -->\n乙\n',
  '⑤ 页尾空行 + 分页符': '甲\n\n乙\n\n\n\n\n<!-- pagebreak -->\n丙\n',
  '⑥ 分页符在文末': '甲\n<!-- pagebreak -->\n\n\n',
  '⑦ 用户那份单页': 'aa\n\nbb\n\ncc\n\n啊啊\n\n你好\n',
  '⑧ 自然溢出': '一行文字\n\n一行文字\n\n一行文字\n\n一行文字\n\n一行文字\n\n'
      '一行文字\n\n一行文字\n\n一行文字\n\n一行文字\n\n一行文字\n\n'
      '一行文字\n\n一行文字\n\n一行文字\n\n一行文字\n\n一行文字\n\n'
      '一行文字\n\n一行文字\n\n一行文字\n\n一行文字\n\n一行文字\n\n'
      '一行文字\n\n一行文字\n\n一行文字\n\n一行文字\n\n一行文字\n\n'
      '一行文字\n\n一行文字\n\n一行文字\n\n一行文字\n\n一行文字\n',
};

void main() {
  for (final MapEntry<String, String> d in kDocs.entries) {
    testWidgets('★ 光标归属：${d.key}', (WidgetTester tester) async {
      final DocBuffer buf = await _mount(tester, d.value);
      final List<String> dead = <String>[];
      final List<String> split = <String>[];
      for (var off = 0; off <= d.value.length; off++) {
        final ({int count, Set<double> tops}) r = await _at(tester, buf, off);
        if (r.count == 0) dead.add('$off');
        if (r.tops.length > 1) {
          split.add('$off→${r.tops.map((double y) => y.toStringAsFixed(0)).join('/')}');
        }
      }
      expect(dead, isEmpty, reason: '⚠️ 死区（一根光标条都没有）：${dead.join('、')}');
      expect(split, isEmpty,
          reason: '⚠️ 一根光标画在两处（双光标）：${split.take(20).join(' , ')}');
    });
  }
}
