// 批 24：**两块内容相同时，单元 widget 池不许把 A 的 widget 交给 B**。
//
// 用户 2026-10-24 稳定复现：文档里两块 `\begin{cases}4\\\end{cases}` 内容完全相同，
// 光标先进第一块、再点对齐推导的第二个等号右边 ⇒ **第一块整体闪一帧**（不是花括号，是整块）。
//
// 根因（探针 v27 坐实）：`_poolKeyFor` **只按内容**寻址，而池里的 widget 内嵌着这一单元自己的
// `GlobalKey`（`MathWithCaret.mathKey`）⇒ 键相同时后一块会拿到**前一块的 widget 实例**，
// 里面装的是前一块的 GlobalKey ⇒ 同一帧同一个 GlobalKey 出现在两处
// ⇒ 框架把元素搬走：整块消失一帧 + 21 处框架断言
// （`childRenderObject.parent != null` / `_debugRelayoutBoundaryAlreadyMarkedNeedsLayout`）。
//
// 守卫（都不依赖像素，只看身份与树）：
//   ① 内容相同的 k 块 ⇒ **k 个互不相同的 mathKey**（改前：两块共用一个）；
//   ② 光标进第一块 / 再移走，**每一帧**：可见块数恒为 4、每块尺寸恒 > 0、`takeException()` 为空；
//   ③ 反例（防过度收紧）：内容**不同**的块照旧各归各的 key。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/math_caret.dart';

/// 用户那份文档（两块 `cases` 内容完全相同 —— 这就是病灶）。
const String kDoc = r'''aaa啊啊啊

你好哇

$$
\begin{cases}4\\\end{cases}
$$

$$
\begin{aligned}&=\\&=\end{aligned}
$$

$$
\begin{cases}4\\\end{cases}
$$

$$
\begin{cases}\\\end{cases}
''';

Future<void> _mount(WidgetTester tester, DocBuffer buf) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
  ));
  tester.state<EditViewState>(find.byType(EditView)).focusInput();
  await tester.pumpAndSettle();
}

Finder get _blocks => find.byType(MathWithCaret, skipOffstage: true);

List<MathWithCaret> _widgets(WidgetTester tester) =>
    tester.widgetList<MathWithCaret>(_blocks).toList();

/// 每帧都要成立的三条（块数 / 尺寸 / 无异常）
void _expectFrameSane(WidgetTester tester, int expectCount, String when) {
  final List<MathWithCaret> ws = _widgets(tester);
  expect(ws.length, expectCount,
      reason: '$when：可见公式块数应当恒为 $expectCount（少了一个 = 整块从树上消失 = 用户看到的"闪"）');
  final Set<int> keys = <int>{};
  for (final MathWithCaret w in ws) {
    expect(keys.add(identityHashCode(w.mathKey)), isTrue,
        reason: '$when：同一个 mathKey（GlobalKey）不许同时出现在两块上 —— '
            '那会让框架把元素搬走（整块闪一帧）');
  }
  for (var i = 0; i < ws.length; i++) {
    final Size sz = tester.getSize(_blocks.at(i));
    expect(sz.width, greaterThan(0.1), reason: '$when：第 $i 块的宽被压成 0 ⇒ 闪');
    expect(sz.height, greaterThan(0.1), reason: '$when：第 $i 块的高被压成 0 ⇒ 闪');
  }
  expect(tester.takeException(), isNull,
      reason: '$when：这一帧抛了框架断言（GlobalKey 被搬移的直接证据）');
}

void main() {
  group('批 24 · 单元 widget 池的键必须带身份', () {
    testWidgets('① 初始帧：4 块都在、每块尺寸正常、无框架断言（内容相同的两块也在内）',
        (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer(kDoc);
      await _mount(tester, buf);
      _expectFrameSane(tester, 4, '初始');
    });

    testWidgets('② 光标进第一块 → 再移到 aligned：每一帧都不许闪', (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer(kDoc);
      await _mount(tester, buf);

      // 第一块 `cases` 的空格子（`\\` 之后、`\end{cases}` 之前）
      final int firstCase = kDoc.indexOf(r'\begin{cases}');
      final int rowBreak = kDoc.indexOf(r'\\', firstCase);
      buf.setCaret(rowBreak + 2);
      await tester.pump();
      _expectFrameSane(tester, 4, '光标刚进第一块（第 1 帧）');
      await tester.pump();
      _expectFrameSane(tester, 4, '光标在第一块（第 2 帧）');
      await tester.pumpAndSettle();
      _expectFrameSane(tester, 4, '光标在第一块（settle）');

      // 再移到 aligned 第二个 `=` 右边（用户的稳定复现路径）
      final int alignedStart = kDoc.indexOf(r'\begin{aligned}');
      final int eq2 = kDoc.indexOf('&=', alignedStart + 2);
      buf.setCaret(eq2 + 2);
      for (var i = 0; i < 6; i++) {
        await tester.pump();
        _expectFrameSane(tester, 4, '移走后第 ${i + 1} 帧');
      }
      await tester.pumpAndSettle();
      _expectFrameSane(tester, 4, 'settle');
    });

    testWidgets('③ 反例：内容不同的块照旧各归各的 key（防过度收紧）',
        (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer(kDoc);
      await _mount(tester, buf);
      // 第 3 块（`cases 4`）与第 4 块（空 `cases`）内容不同 —— 它们的 key 也应当不同
      final List<MathWithCaret> ws = _widgets(tester);
      expect(ws[2].mathKey, isNot(same(ws[3].mathKey)));
      expect(ws[0].mathKey, isNot(same(ws[2].mathKey)),
          reason: '内容**相同**的两块也必须各归各的 key（身份进键）');
    });
  });
}
