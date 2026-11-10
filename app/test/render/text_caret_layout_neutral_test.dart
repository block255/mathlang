// 2026-11-10 · 反馈 ④：**光标不许影响排版（文本侧）**
//
// 现场（用户 4-1/4-2 两张图）：点 `different(s)` 的 `d` 与 `i` 之间 ⇒ 排版闪；
//   `d` 一会儿在这一行末尾、一会儿跳到下一行开头。用户原话："这里光标竟然也影响了排版"。
//
// 根因（实测）：文本侧光标原来是一个 **0 宽 `WidgetSpan`**。0 宽只保证"不占宽度"，但
//   WidgetSpan 往段落字符流里塞了一个 **U+FFFC**（行内断行类别 ID）——**本身就是断行机会**：
//   · 纯 `TextSpan` 一切为二：0/181 个宽度会改断行（不是"切段"的锅）
//   · 切成两段 + **0×0** 的 WidgetSpan：**54/181** 个宽度会改（与宽度、高度都无关）
//   · 真字体 Segoe UI + 正文栏宽 657.7 + 字号 20/22：同一段 **2 行 ⇄ 3 行**
// ⇒ 光标一亮一灭，排版就上下跳一行。
//
// 本守卫钉的是**不变量**（与实现无关、与字体无关）：
//   **同一个位点，`caretOffset` 有 / 无（即闪烁亮 / 灭），段落尺寸与断行位置必须完全相同。**
//   改前必红：本文件在 Ahem（测试内置字体）下 424 宽就是"会劈开"的宽度之一（实测 59/181）。

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/inline_math_text.dart';

const String kPara =
    'It is unlikely that such gender differences are the result of gender differences in working';
const double kFontSize = 16;
const double kLineHeight = 1.7;

/// 旧实现在这些宽度上会改断行（Ahem + 本例文实测：**342–356** 每 2px 都中，
/// 灭=162.0 高 / 亮=135.0 高 = 5 行 ⇄ 6 行）
const double kWidth = 348;

int _secondDifferences() {
  final int first = kPara.indexOf('differences');
  return kPara.indexOf('differences', first + 1);
}

Future<({Size size, int lineEnd, bool hasBar})> _measure(
  WidgetTester tester, {
  required int? caret,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: kWidth,
          child: InlineMathText(
            source: kPara,
            baseOffset: 0,
            caretOffset: caret,
            mathFontSize: kFontSize,
            textStyle: const TextStyle(fontSize: kFontSize, height: kLineHeight),
            showEditingAids: true,
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  final RenderParagraph p =
      tester.renderObject<RenderParagraph>(find.byType(RichText));
  final int lineEnd =
      p.getPositionForOffset(Offset(kWidth - 1, kFontSize * kLineHeight / 2)).offset;
  bool hasBar = false;
  for (final Element e in find.byType(Container).evaluate()) {
    final Widget w = e.widget;
    if (w is! Container) continue;
    final BoxConstraints? c = w.constraints;
    if (c != null && c.minWidth == 1.5 && c.maxWidth == 1.5) hasBar = true;
  }
  return (size: p.size, lineEnd: lineEnd, hasBar: hasBar);
}

void main() {
  testWidgets('★ 光标亮 / 灭：段落尺寸与断行必须完全相同（文本侧排版中性）',
      (WidgetTester tester) async {
    final int caret = _secondDifferences() + 1; // d 与 i 之间
    final ({Size size, int lineEnd, bool hasBar}) off =
        await _measure(tester, caret: null);
    final ({Size size, int lineEnd, bool hasBar}) on =
        await _measure(tester, caret: caret);

    expect(on.size, off.size,
        reason: '光标不许改变段落尺寸：灭=${off.size} 亮=${on.size}'
            '（改前：两种相位行数不同 —— 0 宽 WidgetSpan 的 U+FFFC 造了一个断行点）');
    expect(on.lineEnd, off.lineEnd,
        reason: '光标不许改变断行位置：灭=第 ${off.lineEnd} 字 亮=第 ${on.lineEnd} 字');
  });

  testWidgets('竖条该画的时候还得画（别为了换实现把光标弄没了）',
      (WidgetTester tester) async {
    final int caret = _secondDifferences() + 1;
    expect((await _measure(tester, caret: caret)).hasBar, isTrue);
    expect((await _measure(tester, caret: null)).hasBar, isFalse);
  });

  testWidgets('竖条位置与"段落自己算出来的位置"一致（不许飘）',
      (WidgetTester tester) async {
    final int caret = _secondDifferences() + 1;
    await _measure(tester, caret: caret);
    Rect? bar;
    for (final Element e in find.byType(Container).evaluate()) {
      final Widget w = e.widget;
      if (w is! Container) continue;
      final BoxConstraints? c = w.constraints;
      if (c == null || c.minWidth != 1.5 || c.maxWidth != 1.5) continue;
      final RenderObject? ro = e.renderObject;
      if (ro is RenderBox && ro.hasSize) {
        bar = ro.localToGlobal(Offset.zero) & ro.size;
      }
    }
    expect(bar, isNotNull);
    final RenderParagraph p =
        tester.renderObject<RenderParagraph>(find.byType(RichText));
    final Rect para = p.localToGlobal(Offset.zero) & p.size;
    final Offset at = p.getOffsetForCaret(TextPosition(offset: caret), Rect.zero);
    expect(bar!.left - para.left, closeTo(at.dx, 0.6),
        reason: '竖条的 x 必须落在段落自己的光标位上');
    expect((bar.height), closeTo(kFontSize * 1.25, 0.6),
        reason: '文本层竖条高度 = 字号 × 1.25');
  });
}
