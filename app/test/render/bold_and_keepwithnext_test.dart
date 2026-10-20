// ★★ 2026-10-20 守卫：N4 行内强调（**方案 B：投影层独立段**）+ N5 标题不落单页底
//
// 用户实测的 bug（方案 A 的副作用）：「点标题左右两侧，`**` 编码被显示出来、还随光标闪动排版」
// 根因：渲染层把文字段按光标**切成两半**，一对 `**` 被劈开 ⇒ 两半都不成对 ⇒ 回落成字面星号。
// 方案 B：`**…**` 升级成**投影段**（`ProjectionSegment.emphasis`），两个标记由段自己隐藏，
//   光标只能在**正文**里切 ⇒ **结构上**劈不到星号。
//
// 判据：
//   ① 树里**一个 `*` 都不许出现**（不管光标在哪）；
//   ② 正文是粗体；
//   ③ 光标停在段内/段两端时也不许把星号露出来。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/layout/paginator.dart';
import 'package:mathlang/render/inline_math_text.dart';
import 'package:mathlang/render/projection.dart';

import '../support/math_fonts.dart';

List<TextSpan> _allSpans(WidgetTester tester) {
  final List<TextSpan> out = <TextSpan>[];
  void walk(InlineSpan s) {
    if (s is TextSpan) {
      out.add(s);
      for (final InlineSpan c in s.children ?? const <InlineSpan>[]) {
        walk(c);
      }
    }
  }

  for (final Text t in tester.widgetList<Text>(find.byType(Text))) {
    final InlineSpan? s = t.textSpan;
    if (s != null) walk(s);
  }
  return out;
}

Future<void> _pump(WidgetTester tester, String doc, int caret) async {
  await loadMathFonts();
  final DocBuffer buf = DocBuffer(doc)..setCaret(caret);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 800,
        child: SingleChildScrollView(child: EditView(buffer: buf)),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  tester.state<EditViewState>(find.byType(EditView)).focusInput();
  await tester.pumpAndSettle();
}

void main() {
  group('㉞ 行内强调 `**…**`（方案 B）', () {
    test('★★ 投影：成对才算，落单的星号当文字', () {
      final List<ProjectionSegment> segs = projectInline('甲**乙**丙');
      expect(segs.length, 3);
      expect(segs[1].isEmphasis, isTrue);
      expect(segs[1].text, '乙');
      expect(segs[1].start, 3, reason: 'start 指向正文第一个字（开标记之后）');
      expect(segs[1].end, 4);

      final List<ProjectionSegment> unpaired = projectInline('甲**乙');
      expect(unpaired.any((ProjectionSegment s) => s.isEmphasis), isFalse,
          reason: '没闭合 ⇒ 全当文字');
    });

    testWidgets('★★ 正文是粗体，且树里一个 `*` 都没有', (WidgetTester tester) async {
      await _pump(tester, '甲**乙**丙', 0);
      final List<TextSpan> spans = _allSpans(tester);
      expect(spans.any((TextSpan s) => s.text == '乙' && s.style?.fontWeight == FontWeight.bold),
          isTrue, reason: '正文要粗体');
      for (final TextSpan s in spans) {
        expect((s.text ?? '').contains('*'), isFalse,
            reason: '星号不许出现在渲染树里（实际: "${s.text}"）');
      }
    });

    testWidgets('★★ 用户实测场景：光标停在段内/段两端，星号都不许露出来',
        (WidgetTester tester) async {
      // '甲**乙**丙'：0=甲前 1=甲后(开标记前) 2/3=标记里 4=乙后 5=闭标记里
      for (final int caret in <int>[1, 2, 3, 4, 5, 6]) {
        await _pump(tester, '甲**乙**丙', caret);
        final List<TextSpan> spans = _allSpans(tester);
        for (final TextSpan s in spans) {
          expect((s.text ?? '').contains('*'), isFalse,
              reason: 'caret=$caret 时星号露出来了："${s.text}"');
        }
      }
    });
  });

  group('㉞b 强调段的选区（用户实测「不成立。」没高亮）', () {
    testWidgets('★★ 整段选中时，粗体那几个字也必须被高亮', (WidgetTester tester) async {
      await loadMathFonts();
      const String src = '甲**不成立。**当乙';
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: InlineMathText(
            source: src,
            baseOffset: 0,
            selStart: 0,
            selEnd: src.length,
            mathFontSize: 16,
            onMathTap: null,
            onMathRightClick: null,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final List<String> hl = <String>[];
      void walk(InlineSpan s) {
        if (s is TextSpan) {
          if (s.style?.backgroundColor != null && (s.text ?? '').isNotEmpty) {
            hl.add(s.text!);
          }
          for (final InlineSpan c in s.children ?? const <InlineSpan>[]) {
            walk(c);
          }
        }
      }

      for (final Text t in tester.widgetList<Text>(find.byType(Text))) {
        final InlineSpan? s = t.textSpan;
        if (s != null) walk(s);
      }
      final String joined = hl.join();
      expect(joined.contains('不成立。'), isTrue,
          reason: '粗体那截必须被高亮（实际：$hl）');
      expect(joined.contains('甲'), isTrue);
      expect(joined.contains('当乙'), isTrue);
    });
  });

  group('㉟ N5 标题不许落单在页底（keep-with-next）', () {
    test('★★ 页底只剩标题 + 正文放不下 ⇒ 标题一起挪到下一页', () {
      final List<FlowItem> items = <FlowItem>[
        const FlowItem(id: 'a', height: 60),
        const FlowItem(id: 'h', height: 20, keepWithNext: true),
        const FlowItem(id: 'b', height: 30),
      ];
      final PageLayout layout = paginate(items: items, bodyHeight: 100);
      expect(layout.pageCount, 2);
      expect(layout.pages[0].map((PageSlot s) => s.item.id).toList(), <String>['a']);
      expect(layout.pages[1].map((PageSlot s) => s.item.id).toList(), <String>['h', 'b']);
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