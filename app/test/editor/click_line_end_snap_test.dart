// 2026-11-10 晚 · 反馈 ④ 尾巴：**点"行末右侧的空白"要落在这一行最后一个可见字符之后**
//
// 现场（用户两张截图）：软换行的断点是一个**空格**。点那一行末尾右侧的空白之后：
//   · 光标看起来和行末最后一个字隔着一格（那格是空格的宽度）；
//   · 按一下退格 ⇒ 吃掉的是那个**不可见的空格** ⇒ 两个词粘在一起
//     （实测："…boys often rate|themselves…" 退格后变成 "…often ratethemselves…"）。
//
// 口径：**点在行末右侧（点比该偏移的光标位置更靠右）⇒ 落点往回吃掉行尾空白**，
//   落在"这一行最后一个可见字符之后"。行中间的正常点击不受影响。
//
// 本守卫钉三条：① 落点 = 行末最后一个可见字符之后；② 退格删的是那个可见字符（词不粘连）；
// ③ 不回归：行中间的点击仍落在点到的位置。

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';

const String kText =
    'Harariet al., 2013) though even in the younger age group boys often rate '
    'themselves higher in mathematics than girls do (Dowker et al.,2012).';

Future<DocBuffer> _mount(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer('$kText\n');
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
  ));
  tester.state<EditViewState>(find.byType(EditView)).focusInput();
  await tester.pumpAndSettle();
  return buf;
}

Future<RenderParagraph> _para(WidgetTester tester) async {
  for (final Element e in find.byType(RichText).evaluate()) {
    final RenderParagraph p = e.renderObject! as RenderParagraph;
    if (p.text.toPlainText().contains('Harariet')) return p;
  }
  throw StateError('找不到正文段落');
}

void main() {
  testWidgets('① 点行末右侧空白 ⇒ 落在"最后一个可见字符之后"（不是换行点）',
      (WidgetTester tester) async {
    final DocBuffer buf = await _mount(tester);
    final RenderParagraph p = await _para(tester);
    final Rect pr = p.localToGlobal(Offset.zero) & p.size;
    final String plain = p.text.toPlainText();
    // 第 1 行末（段落坐标）——用"点右边缘"问出来
    final int wrap = p.getPositionForOffset(Offset(p.size.width - 2, 10)).offset;
    expect(plain[wrap - 1], ' ', reason: '前置条件：这个断点前面必须是一个空格，否则这条守卫是空测');

    await tester.tapAt(Offset(pr.right - 4, pr.top + 10));
    await tester.pumpAndSettle();
    expect(buf.caret, wrap - 1,
        reason: '落点必须越过那个行尾空格、落在可见字符之后：'
            '实际=${buf.caret} 换行点=$wrap 光标前的字="${buf.buf[buf.caret - 1]}"');
    expect(buf.buf[buf.caret - 1], isNot(' '), reason: '光标前面不该是空格');
  });

  testWidgets('② 退格删的是可见字符，两个词不许粘连', (WidgetTester tester) async {
    final DocBuffer buf = await _mount(tester);
    final RenderParagraph p = await _para(tester);
    final Rect pr = p.localToGlobal(Offset.zero) & p.size;
    await tester.tapAt(Offset(pr.right - 4, pr.top + 10));
    await tester.pumpAndSettle();
    final String before = buf.buf;
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(buf.buf.length, before.length - 1, reason: '只该删一个字符');
    expect(buf.buf.contains('ratethemselves'), isFalse,
        reason: '删掉的如果是行尾空格，两个词就会粘成一个（改前实测就是 ratethemselves）');
  });

  testWidgets('③ 不回归：行中间的点击仍落在点到的位置', (WidgetTester tester) async {
    final DocBuffer buf = await _mount(tester);
    final RenderParagraph p = await _para(tester);
    final Rect pr = p.localToGlobal(Offset.zero) & p.size;
    final Offset at = p.getOffsetForCaret(const TextPosition(offset: 10), Rect.zero);
    await tester.tapAt(Offset(pr.left + at.dx + 1, pr.top + at.dy + 10));
    await tester.pumpAndSettle();
    expect(buf.caret, 10, reason: '行中间的点击不许被"行末吸附"影响');
  });
}
