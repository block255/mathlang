// 批 25：**"光标在不在这段公式里"必须按区间判** —— 不在这段就不许画（也不许说"在"）。
//
// 背景（批 23 探针抓到的潜在缺陷）：`blockShowsCaret` 只判 `caret != null` +
// 「共享格让给左边那块」，**不看光标是否在本块的 [acceptFrom, acceptTo] 里**
// ⇒ 只要文档里有光标，**每个**公式块的 `showCaret` 都是 `true`。
//
// 今天没画出 k 根竖条，是靠另外两道巧合挡住的：
//   ① `doc_view` 只对含光标的单元注锚点（`showCursor: caretAbs != null`）；
//   ② `MathWithCaret._measure` 的 `findCaretAnchor` 找不到那个零尺寸 `ColoredBox` 就返回 null。
// ⇒ 一旦注入链或 findCaretAnchor 变化（例如给所有块注锚点、或加"找不到用首原子"的兜底），
//   屏幕上会**同时冒出 k 根光标**，而现有守卫抓不到（`block_after_caret_test` 是"任意一块 true 就算过"）。
//
// 本守卫因此**按块断言**：光标在第 k 块 ⇒ 只有第 k 块 `showCaret == true`，其余全 false。
//
// 文档形状（两块**紧挨着**，共享一格）：
//   甲 ⏎⏎ $$ a $$ ⏎ $$ b $$ ⏎⏎ 乙 ⏎
//   A: acceptFrom=2  .. acceptTo=10      B: acceptFrom=10 .. acceptTo=18   ⇒ 10 是共享格

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/math_caret.dart';

const String kDoc = '甲\n\n\$\$\na\n\$\$\n\$\$\nb\n\$\$\n\n乙\n';

const int kAcceptFromA = 2;
const int kAcceptToA = 10;
const int kAcceptFromB = 10;
const int kAcceptToB = 18;

Future<void> _mount(WidgetTester tester, DocBuffer buf) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
  ));
  tester.state<EditViewState>(find.byType(EditView)).focusInput();
  await tester.pumpAndSettle();
}

/// 两个公式块（按文档顺序）的 `showCaret`
List<bool> _flags(WidgetTester tester) => tester
    .widgetList<MathWithCaret>(find.byType(MathWithCaret, skipOffstage: true))
    .map((MathWithCaret w) => w.showCaret)
    .toList();

Future<List<bool>> _at(WidgetTester tester, DocBuffer buf, int caret) async {
  buf.setCaret(caret);
  await tester.pump();
  await tester.pump();
  return _flags(tester);
}

void main() {
  group('批 25 · 光标只在它所在的那个公式块里', () {
    test('前置：文档偏移与两个块的认领区间对得上', () {
      final int openA = kDoc.indexOf(r'$$');
      final int closeA = kDoc.indexOf(r'$$', openA + 2);
      final int openB = kDoc.indexOf(r'$$', closeA + 2);
      final int closeB = kDoc.indexOf(r'$$', openB + 2);
      expect(openA - 1, kAcceptFromA);
      expect(closeA + 2, kAcceptToA);
      expect(openB - 1, kAcceptFromB, reason: '两块紧挨着 ⇒ 共享一格');
      expect(closeB + 2, kAcceptToB);
      expect(kAcceptToA, kAcceptFromB);
    });

    testWidgets('★ 光标在**文字段落**里 ⇒ 两个公式块都不许声称"光标在"（改前必红）',
        (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer(kDoc);
      await _mount(tester, buf);
      expect(await _at(tester, buf, 1), <bool>[false, false],
          reason: '光标在"甲"里 —— 改前两块都是 true（靠 findCaretAnchor 返回 null 才没画）');
      expect(await _at(tester, buf, kDoc.indexOf('乙')), <bool>[false, false],
          reason: '光标在"乙"里同理');
    });

    testWidgets('★ 光标在 A 里 ⇒ 只有 A 声称（B 不许）', (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer(kDoc);
      await _mount(tester, buf);
      expect(await _at(tester, buf, kDoc.indexOf('a')), <bool>[true, false]);
    });

    testWidgets('★ 光标在 B 里 ⇒ 只有 B 声称（A 不许）', (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer(kDoc);
      await _mount(tester, buf);
      expect(await _at(tester, buf, kDoc.indexOf('b')), <bool>[true, false].reversed.toList());
    });

    testWidgets('★ 共享那一格（A 的块后 = B 的块前）⇒ 只归左边那块',
        (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer(kDoc);
      await _mount(tester, buf);
      expect(await _at(tester, buf, kAcceptToA), <bool>[true, false],
          reason: '共享格让给 A（左）⇒ B 不画；A 的"块之后"照常');
    });

    testWidgets('★ B 的"块之后"那一格 ⇒ 只归 B', (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer(kDoc);
      await _mount(tester, buf);
      expect(await _at(tester, buf, kAcceptToB), <bool>[false, true]);
    });
  });
}
