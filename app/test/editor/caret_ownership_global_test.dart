// 批 40 · **光标归属的全域守卫**（先红后绿）
//
// 不变量（2026-10-28 修订 —— 用户拍板"段间距不承接字符"）：
//   ① 每个偏移**要么**有一根光标（它是某个视觉行的行首/行尾），
//      **要么**它是**段落分隔符**（两段之间那个零高度的空行）⇒ 那时**一根都不许有**；
//   ② 有光标时，同一个偏移的所有竖条必须落在**同一行**（`top` 相同）—— 分处两地就是"双光标"。
//      ★ 允许"同一像素上叠两根"（块边界条 + 光标条的重叠是历史行为，不是这次的病）。
//
// ★★ 为什么改了命题（2026-10-28）：2026-10-26 那版写的是「每个偏移**至少**有一根」——
//   **那条命题本身是错的**。分隔符那一格在版面上**没有行盒**（高度 0），它不该有位置；
//   而"每个偏移都必须有"逼着渲染层给它编一个 y ⇒ 只能画进段距 ⇒ 用户看到的
//   「段间距能当一个容器行把光标放进去」。**用实现迁就一条错的断言**，这就是那次返工的根。
//
// 这份文档是**判据本身**的守卫：批 38/38-回归/39 三次都是在"谁画光标"上加条件，
// 每次补一头漏一头。有了它，任何一处判据改坏都会在这里红。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/blank_runs.dart';
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

/// 文档里**所有"不是位置"的偏移** = 段落分隔符那一格（`blankRowStart` 给出的前缀）。
Set<int> _separators(String s) {
  final Set<int> out = <int>{};
  final List<int> heads = <int>[0];
  for (var i = 0; i < s.length; i++) {
    if (s[i] == '\n') heads.add(i + 1);
  }
  var prevBlank = false;
  for (final int h in heads) {
    if (h >= s.length) break; // 文末 EOF 不是数据行
    final int nl = s.indexOf('\n', h);
    final int end = nl < 0 ? s.length : nl;
    final bool blank = s.substring(h, end).trim().isEmpty;
    if (blank && !prevBlank) {
      final List<int> run = blankRunFrom(s, h);
      final int start = blankRowStart(
        atDocStart: h == 0,
        atDocEnd: run.isNotEmpty && run.last + 1 >= s.length,
      );
      for (var k = 0; k < start && k < run.length; k++) {
        out.add(run[k]);
      }
    }
    prevBlank = blank;
  }
  return out;
}

const Map<String, String> kDocs = <String, String>{
  '① 单行': '甲\n',
  '② 两段': '甲\n\n乙\n',
  '③ 文末空行': '甲\n\n乙\n\n',
  '④ 分页符夹中间': '甲\n<!-- pagebreak -->\n乙\n',
  '⑤ 页尾空行 + 分页符': '甲\n\n乙\n\n\n\n\n<!-- pagebreak -->\n丙\n',
  '⑥ 分页符在文末': '甲\n<!-- pagebreak -->\n\n\n',
  '⑦ 用户那份单页': 'aa\n\nbb\n\ncc\n\n啊啊\n\n你好\n',
  // ★★ 2026-10-26 用户手测：「每一次打完字符都有双光标」——
  //   **打字之后的缓冲区没有尾换行**（`aa` / `aa⏎⏎bb`），这是这批文档里缺的形态。
  '⑨ 打字中（无尾换行）': 'aa\n\nbb\n\ncc',
  '⑩ 单字无尾换行': '甲',
  // ★ 2026-10-28：**文首空行**（`leadingBlankHeight = n × 行高`，每个都占一行、都没有分隔符）。
  '⑪ 文首两个空行': '\n\n甲\n',
  '⑫ 段间两行空行': '甲\n\n\n\n乙\n',
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
      final Set<int> seps = _separators(d.value);
      final List<String> dead = <String>[];
      final List<String> split = <String>[];
      final List<String> onSep = <String>[];
      for (var off = 0; off <= d.value.length; off++) {
        final ({int count, Set<double> tops}) r = await _at(tester, buf, off);
        if (seps.contains(off)) {
          if (r.count != 0) onSep.add('$off→${r.count} 根');
          continue;
        }
        if (r.count == 0) dead.add('$off');
        if (r.tops.length > 1) {
          split.add('$off→${r.tops.map((double y) => y.toStringAsFixed(0)).join('/')}');
        }
      }
      expect(onSep, isEmpty,
          reason: '⚠️ 段落分隔符那一格画了光标（它零高度、不是位置）：${onSep.join('、')}');
      expect(dead, isEmpty, reason: '⚠️ 死区（一根光标条都没有）：${dead.join('、')}');
      expect(split, isEmpty,
          reason: '⚠️ 一根光标画在两处（双光标）：${split.take(20).join(' , ')}');
    });
  }
}
