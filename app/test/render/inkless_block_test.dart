// 2026-11-01（用户："如果是我主动打的，它肯定有个明确的行 / 但它属于上下哪一行都看不出来"）：
// **无墨迹的公式块 = 空壳**，三条口径。
//
// ## 什么叫"无墨迹"
// tex 里只有空白类命令（`\ ` `\,` `\;` `\:` `\!` `\quad` `\qquad`、普通空白/换行、`~`、`{}`）⇒
// 渲染出来**一个像素的墨都没有** ⇒ 那个块在版面上**没有高度** ⇒ 它不属于任何一行，
// 视觉上只能"卡"在上下两行之间的缝里。
//
// ## 它会怎么产生
// 用户的公式块习惯用 `\ \ \ …` 做缩进（T1 每个块都这样）。一旦**内容被删光/删坏**，
// 就只剩缩进 ⇒ 一个没有行的空壳。★ 它删不掉是**另一个 bug**（见下）。
//
// ## 三条口径
//   ① `isInklessTex()`：判据本身（下面有单测）；
//   ② **退格 / Delete 在内容起点 ⇒ 整块删掉**。原来 `smartBackspace` 在段内 `rel == 0` 时
//      直接返回 `none`（"左边没东西可删"）—— 它只看得到 tex 里面，看不到外面还包着一个壳
//      ⇒ 用户"点退格也删不掉"；
//   ③ **不居中、不缩放**（`doc_view`）：原来 `Center` + `FittedBox` 把 1000×0 的盒子放到页面中间
//      ⇒ "内容起点"也在页面中间 ⇒ 光标画在缝里（用户："这是什么鬼位置"）。
//      现在靠左对齐 ⇒ 光标落在**页面左边那一行该在的地方**。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/core/doc_settings.dart';
import 'package:mathlang/editor/doc_view.dart';
import 'package:mathlang/render/empty_math_mark.dart';
import 'package:mathlang/render/math_nav.dart';
import 'package:mathlang/render/smart_delete.dart';

/// 一个"只有缩进"的块夹在两段文字之间（用户文档第 33–37 行的最小化）
const String kDoc = '甲\n\n\$\$\n\\ \\ \\ \\ \\ \\ \n\$\$\n\n乙\n';

void main() {
  group('① isInklessTex 判据', () {
    test('空白类命令 ⇒ 无墨迹', () {
      for (final String tex in <String>[
        '',
        '   ',
        r'\ ',
        r'\ \ \ \ \ ',
        r'\quad',
        r'\qquad',
        r'\, \; \: \!',
        '~',
        '{}',
        '\\ \\quad \n  {}',
      ]) {
        expect(isInklessTex(tex), isTrue, reason: '「$tex」应当算无墨迹');
      }
    });

    test('有任何可见内容 ⇒ 不算', () {
      for (final String tex in <String>['x', r'\ \ x', r'\frac{a}{b}', r'\alpha', r'\left|{x}\right|']) {
        expect(isInklessTex(tex), isFalse, reason: '「$tex」有墨迹');
      }
    });
  });

  group('② 退格 / Delete 把空壳整块删掉', () {
    test('★ 在内容起点按退格 ⇒ 整个 `\$\$…\$\$`（含末尾换行）消失', () {
      final int blockStart = kDoc.indexOf(r'$$');
      final int contentStart = displayTexStartAt(kDoc, blockStart)!;
      final SmartEdit e = smartEditAt(kDoc, contentStart, forward: false);
      expect(e.isNone, isFalse, reason: '★ 原来这里返回 none ⇒ 用户"点退格也删不掉"');
      expect(e.deletes, isTrue);
      final String after = kDoc.replaceRange(e.from!, e.to!, '');
      expect(after, '甲\n\n\n乙\n',
          reason: '空壳连同它的围栏一起消失，前后两个空行还在');
      expect(after.contains(r'$$'), isFalse);
    });

    test('★ 在内容起点按 Delete ⇒ 同样整块删掉', () {
      final int blockStart = kDoc.indexOf(r'$$');
      final int contentStart = displayTexStartAt(kDoc, blockStart)!;
      final SmartEdit e = smartEditAt(kDoc, contentStart, forward: true);
      expect(e.deletes, isTrue);
      expect(kDoc.replaceRange(e.from!, e.to!, '').contains(r'$$'), isFalse);
    });

    test('★ 块里**任何位置**按退格都整块删掉（实测用户在 589/591 也按过，那里原来也是 none）', () {
      final int blockStart = kDoc.indexOf(r'$$');
      final int contentStart = displayTexStartAt(kDoc, blockStart)!;
      for (final int off in <int>[contentStart, contentStart + 1, contentStart + 3]) {
        final SmartEdit e = smartEditAt(kDoc, off, forward: false);
        expect(e.deletes, isTrue, reason: 'off=$off 应当整块删掉');
        expect(kDoc.replaceRange(e.from!, e.to!, '').contains(r'$$'), isFalse,
            reason: 'off=$off：删完不该还留着围栏');
      }
    });

    test('★ 有墨迹的块**不走空壳那条**：删完之后围栏还在（不是整块吞掉）', () {
      const String withInk = '甲\n\n\$\$\n\\ x\n\$\$\n\n乙\n';
      final int blockStart = withInk.indexOf(r'$$');
      final int contentStart = displayTexStartAt(withInk, blockStart)!;
      expect(isInklessTex(r'\ x'), isFalse, reason: r'`\ x` 有墨迹');
      final SmartEdit e = smartEditAt(withInk, contentStart, forward: false);
      if (e.deletes) {
        final String after = withInk.replaceRange(e.from!, e.to!, '');
        expect(after.contains(r'$$'), isTrue,
            reason: '★ 有内容的块不该被"整块连围栏一起删掉"（那是无墨迹空壳的专用口径）');
      }
    });
  });

  group('③ 只有间距的块 = 空块（把鬼抓出来，用户 2026-11-01 拍板「甲」）', () {
    testWidgets('★ 空块里打一个空格 ⇒ 仍然是虚线小框（不会变成隐形块）',
        (WidgetTester tester) async {
      // 用户当场复现：空行 → 点「行间公式」 → 空块 → 打一个空格 ⇒ 变鬼。
      // 下面这份文档就是"打了一个空格之后"的状态（块内容 = `\ `）。
      const String afterSpace = '甲\n\n\$\$\n\\ \n\$\$\n\n乙\n';
      tester.view.physicalSize = const Size(900, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final DocBuffer buf = DocBuffer(afterSpace);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DocView(buffer: buf, settings: DocSettings.defaults),
          ),
        ),
      ));
      for (var i = 0; i < 10; i++) {
        await tester.pump();
      }
      final int blockStart = afterSpace.indexOf(r'$$');
      final int contentStart = displayTexStartAt(afterSpace, blockStart)!;
      buf.setCaret(contentStart);
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }

      // ① 虚线小框还在（改前：`\ ` ⇒ 判不出空 ⇒ 框消失 ⇒ 0 高隐形）
      final List<Element> marks = find.byType(EmptyMathMark).evaluate().toList();
      expect(marks, isNotEmpty,
          reason: '★ 只有间距的块必须仍然画那个虚线小框 —— 否则它 0 高、隐形，'
              '光标卡在上下两行之间的缝里（用户："原地变鬼"）');
      // ② 光标在框里能画出来，且不是 NaN
      final Element withCaret = marks.firstWhere(
          (Element e) => (e.widget as EmptyMathMark).showCaret,
          orElse: () => marks.first);
      expect((withCaret.widget as EmptyMathMark).showCaret, isTrue,
          reason: '★ 空格仍然承接光标（用户："行间的空格能承接光标是正确的"）');
      final RenderBox box = withCaret.renderObject! as RenderBox;
      final Offset at = box.localToGlobal(Offset.zero);
      expect(at.dx.isNaN || at.dy.isNaN, isFalse, reason: '★ 不许是 NaN');
    });

    test('★ 抓出来的鬼要能删：⌫ 一次整块回收（与 ② 同一条实现，这里钉住"空格块"这一档）', () {
      const String afterSpace = '甲\n\n\$\$\n\\ \n\$\$\n\n乙\n';
      final int blockStart = afterSpace.indexOf(r'$$');
      final int contentStart = displayTexStartAt(afterSpace, blockStart)!;
      final SmartEdit e = smartEditAt(afterSpace, contentStart, forward: false);
      expect(e.deletes, isTrue);
      expect(afterSpace.replaceRange(e.from!, e.to!, ''), '甲\n\n\n乙\n');
    });
  });
}
