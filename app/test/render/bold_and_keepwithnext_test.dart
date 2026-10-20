// ★★ 2026-10-20 守卫：N4 行内粗体 + N5 标题不许落单在页底
//
// N4（用户拍板"可以支持"）：`**文字**` 渲染成粗体，**两个星号缩小到看不见但不删**——
//   偏移一个都不许变（光标/选区/点击反查全靠"渲染串长度 == 源码长度"）；落单的 `**` 原样显示。
// N5：标题若正好被挤到页底（后面紧跟正文却放不下），把标题一起挪到下一页。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/layout/paginator.dart';
import 'package:mathlang/ui/editor_page.dart';

import '../support/symbol_fixture.dart';

Future<void> _pump(WidgetTester tester, String doc) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: EditorPage(library: testSymbolLibrary(), buffer: DocBuffer(doc)),
  ));
  await tester.pumpAndSettle();
}

/// 收集页面上所有 TextSpan（含嵌套）
void _collect(InlineSpan span, List<TextSpan> out) {
  if (span is TextSpan) {
    out.add(span);
    final List<InlineSpan>? kids = span.children;
    if (kids != null) {
      for (final InlineSpan k in kids) {
        _collect(k, out);
      }
    }
  }
}

void main() {
  group('㉞ N4 行内粗体 `**…**`', () {
    testWidgets('★★ 中间那段是粗体，两个星号缩到看不见，总字符数不变',
        (WidgetTester tester) async {
      await _pump(tester, '甲**乙**丙');
      final List<TextSpan> spans = <TextSpan>[];
      for (final Text t in tester.widgetList<Text>(find.byType(Text))) {
        final InlineSpan? s = t.textSpan;
        if (s != null) _collect(s, spans);
      }
      // ① 有一段是粗体，文字正好是"乙"
      final Iterable<TextSpan> bold = spans.where((TextSpan s) =>
          s.text == '乙' && s.style?.fontWeight == FontWeight.bold);
      expect(bold, isNotEmpty, reason: '`**乙**` 必须渲染成粗体');
      // ② 星号还在树里（偏移不变），但字号被压到看不见
      final Iterable<TextSpan> markers =
          spans.where((TextSpan s) => s.text == '**' && (s.style?.fontSize ?? 99) < 1);
      expect(markers.length, 2, reason: '起止两个星号都要在（缩到 fontSize<1）');
      // ③ 渲染出来的字符总量 == 源码长度（这个不变量是光标/选区的前提）
      final int total = spans
          .where((TextSpan s) =>
              s.text != null && (s.style?.fontSize ?? 99) >= 1)
          .fold<int>(0, (int a, TextSpan s) => a + s.text!.length);
      expect(total, 3, reason: '可见文字 = 甲乙丙 三个字（星号不可见）');
    });

    testWidgets('★ 落单的 `**` 原样显示（不吃用户的字）', (WidgetTester tester) async {
      await _pump(tester, '甲**乙');
      final List<TextSpan> spans = <TextSpan>[];
      for (final Text t in tester.widgetList<Text>(find.byType(Text))) {
        final InlineSpan? s = t.textSpan;
        if (s != null) _collect(s, spans);
      }
      final String all =
          spans.map((TextSpan s) => s.text ?? '').join();
      expect(all.contains('甲**乙'), isTrue, reason: '没闭合就照原样显示');
    });
  });

  group('㉟ N5 标题不许落单在页底', () {
    test('★★ 页底只剩标题 + 正文放不下 ⇒ 标题一起挪到下一页', () {
      // 页高 100：normal(60) 标题(20) 正文(30) ⇒ 前两页塞不下第三项
      final List<FlowItem> items = <FlowItem>[
        const FlowItem(id: 'a', height: 60),
        const FlowItem(id: 'h', height: 20, keepWithNext: true),
        const FlowItem(id: 'b', height: 30),
      ];
      final PageLayout layout = paginate(items: items, bodyHeight: 100);
      expect(layout.pageCount, 2);
      final List<String> p1 = layout.pages[0].map((PageSlot s) => s.item.id).toList();
      final List<String> p2 = layout.pages[1].map((PageSlot s) => s.item.id).toList();
      expect(p1, <String>['a'], reason: '标题不留在第 1 页底');
      expect(p2, <String>['h', 'b'], reason: '标题和正文同在第 2 页');
    });

    test('★ 整页都是标题时不许死循环/产出空页', () {
      final List<FlowItem> items = <FlowItem>[
        const FlowItem(id: 'h1', height: 50, keepWithNext: true),
        const FlowItem(id: 'h2', height: 50, keepWithNext: true),
        const FlowItem(id: 'b', height: 50),
      ];
      final PageLayout layout = paginate(items: items, bodyHeight: 100);
      expect(layout.pageCount, greaterThanOrEqualTo(1));
      expect(layout.pages.any((List<PageSlot> p) => p.isEmpty), isFalse,
          reason: '不许产出空页');
    });
  });
}