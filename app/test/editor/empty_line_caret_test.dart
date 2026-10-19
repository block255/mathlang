// ⑥「空行是一等公民」· 丙（2026-10-17 用户拍板）
//
// 用户拍板的是 **丙**：**空行不占高度**（版面完全不变）＋ **点空白能落到空行**。
// 根因（交接快照 §十二 W3/W4）：空行被块模型当成"一个边界"（R1，不产生块）
// ⇒ 没有单元、没有渲染物 ⇒ `caret_ownership` 显式返回 null ⇒ **光标没人画**、
// 点击落到虚空（用户原话："空白行的行首"永远点不进去）。
//
// 做法（`doc_view._BlankSlot`）：把块与块之间那段空白（原来就是一个 `SizedBox(height: gap)`）
// 做成**空行槽**：
//   · 高度 = 原来那段 gap ⇒ **版面一个像素都不变**；
//   · `Listener(behavior: opaque)` 覆盖整段空隙 ⇒ 点空白 = 落在那行空行的位点上；
//   · 光标在空行上时自己画竖条（文本层 `字号×1.25`，`OverflowBox` 溢出画，不撑版面）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/doc_view.dart';

/// 文档：`甲\n\n乙`（中间那一行是空行，偏移 2）
const String kDoc = '甲\n\n乙';
const int kBlankOffset = 2;

Future<({DocBuffer buf, List<Rect?> carets, List<int> taps})> _pump(
  WidgetTester tester, {
  required int caret,
}) async {
  final DocBuffer buf = DocBuffer(kDoc)..setCaret(caret);
  final List<Rect?> carets = <Rect?>[];
  final List<int> taps = <int>[];
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: DocView(
          buffer: buf,
          onCaretRect: carets.add,
          onTapOffset: (int offset, Offset _) => taps.add(offset),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return (buf: buf, carets: carets, taps: taps);
}

void main() {
  testWidgets('★ 光标在空行上 ⇒ **有**光标矩形（不再"消失"）', (WidgetTester tester) async {
    // ★ 必须在 pump 之后**改**光标：onCaretRect 是"缓冲区变了才上报"的
    final r = await _pump(tester, caret: 0);
    r.buf.setCaret(kBlankOffset);
    await tester.pumpAndSettle();
    expect(r.carets.where((Rect? x) => x != null), isNotEmpty,
        reason: '空行必须有"人"画光标（改前：caretPlacement 对空行返回 null ⇒ 一个矩形都没有）');
    final Rect rect = r.carets.lastWhere((Rect? x) => x != null)!;
    expect(rect.height, greaterThan(10), reason: '文本层标准高度（字号×1.25）');
  });

  testWidgets('★ 空行上**看得见**竖条（不是只有矩形上报）', (WidgetTester tester) async {
    await _pump(tester, caret: kBlankOffset);
    // 空行槽里的竖条 = 1.5 宽 × textCaretHeight 的 Container
    final Iterable<Container> bars = tester
        .widgetList<Container>(find.byType(Container))
        .where((Container c) => c.constraints?.maxWidth == 1.5);
    expect(bars, isNotEmpty, reason: '空行槽要自己画那根竖条');
  });

  testWidgets('★★ **版面中性**：有没有光标，页数与单元高度都不变',
      (WidgetTester tester) async {
    final r1 = await _pump(tester, caret: 0);
    final double h1 = tester.getSize(find.byType(DocView)).height;
    final r2 = await _pump(tester, caret: kBlankOffset);
    final double h2 = tester.getSize(find.byType(DocView)).height;
    expect(h2, h1, reason: '丙 的前提：空行**不占高度**（竖条靠溢出画）');
    expect(r1.buf.length, r2.buf.length);
  });

  testWidgets('★ 点空白 ⇒ 落到那行空行（原来点这儿什么都不发生）',
      (WidgetTester tester) async {
    final r = await _pump(tester, caret: 0);
    // ★ 2026-10-17（甲）：现在**每页末尾**也有一个"文末空白"槽 ⇒ 文档里通常有两个：
    //   第一个是"块与块之间"的空行槽，最后一个是文末那个。这里点**中间那个**。
    final Finder slots = find.byWidgetPredicate((Widget w) =>
        w.runtimeType.toString() == '_BlankSlot');
    expect(slots, findsNWidgets(2), reason: '`甲`/`乙` 之间一个 + 文末一个');
    final Rect box = tester.getRect(slots.first);
    expect(box.height, greaterThan(0));
    await tester.tapAt(box.center);
    await tester.pumpAndSettle();
    expect(r.taps, contains(kBlankOffset), reason: '点空白 = 落在空行位点（$kBlankOffset）');
    // ★ DocView 只负责**算出**偏移；落光标是 EditView 的 `onTapOffset` 干的
    //   （本用例只验"空行槽接住了点击、给出的正是空行位点"）。
  });

  testWidgets('★ 相邻两块之间没有空行时**不产生**中间槽（只有文末那一个）',
      (WidgetTester tester) async {
    final DocBuffer buf = DocBuffer('# 标题\n正文')..setCaret(0);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: DocView(buffer: buf))),
    ));
    await tester.pumpAndSettle();
    final Finder slots = find.byWidgetPredicate((Widget w) =>
        w.runtimeType.toString() == '_BlankSlot');
    expect(slots, findsOneWidget, reason: '标题与正文之间是"块间距"，不是空行 ⇒ 只剩文末槽');
    // 而且那个槽的落点必须是**文末**（文档没有末尾空行 ⇒ 落在 buf.length）
    final _BlankSlotProbe probe = _BlankSlotProbe.of(tester.widget(slots));
    expect(probe.offset, buf.length, reason: '不是文末的槽就说明"凭空造了一个位点"');
  });
}

/// 只为读 `_BlankSlot` 的私有字段（测试里不去改生产代码的可见性）
class _BlankSlotProbe {
  const _BlankSlotProbe(this.offset);
  final int offset;

  static _BlankSlotProbe of(Widget w) {
    final dynamic d = w;
    return _BlankSlotProbe(d.offset as int);
  }
}
