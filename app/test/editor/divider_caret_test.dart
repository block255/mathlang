// 批 27：**分界线（`---`）上下都不许有"看不见光标"的死区**。
//
// 用户 2026-10-24 22:0x 实测三张图：
//   「点分界线下面的行 ⇒ 虽然判定光标确实在下面的第一个空行（打字也打在那里），
//     但光标不显示」+「有的时候分界线下面那一行有字，后面的光标也不显示」。
//
// 探针 v29（逐偏移扫"有几根文本层光标条"）实测死区：
//   `T⏎⏎---⏎⏎abc⏎`  ⇒ 偏移 **3–7** 一根光标都没有（`---` 三格 + 行尾 + **分界线下面那个空行**）
//   `T⏎⏎---⏎abc⏎`   ⇒ 3–6
//   `T⏎⏎---⏎⏎`（文末）⇒ 3–8（含文末）
//
// 根因（一条）：分界线块的**渲染文本是空的**（`_renderParts` 给 `('', 0)`）⇒
//   ① `acceptTo = renderBase + 0 = 行首` ⇒ `blankRunAfter` 看到的是 `-` 而不是 `\n`
//      ⇒ **分界线下面没有空行槽** ⇒ 光标没人画；文末槽同理（`_blankOffsetAfter` 返回 -1）；
//   ② `---` 这一行没有任何文本能挂光标 ⇒ 三格本身也是死区。
//
// 守的是**全域**：这份文档的每一个偏移都必须至少有一根可见光标条。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/core/paragraph_break.dart';
import 'package:mathlang/editor/edit_view.dart';

Future<void> _mount(WidgetTester tester, DocBuffer buf) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
  ));
  tester.state<EditViewState>(find.byType(EditView)).focusInput();
  await tester.pumpAndSettle();
}

/// 可见光标条 = `Container(width: 1.5, height: 字号×1.25)`（文本层 / 分界线 / 空行槽都是这个形状；
/// 数学层的竖条是 `CustomPaint` 画的，不走这里）。
int _bars(WidgetTester tester) {
  var n = 0;
  for (final Widget w in tester.allWidgets) {
    if (w is! Container) continue;
    final BoxConstraints? c = w.constraints;
    if (c != null && c.minWidth == 1.5 && c.maxWidth == 1.5) n++;
  }
  return n;
}

Future<int> _barsAt(WidgetTester tester, DocBuffer buf, int off) async {
  buf.setCaret(off);
  await tester.pump();
  await tester.pump();
  return _bars(tester);
}

void main() {
  group('批 27 · 分界线不是光标的死区', () {
    testWidgets('★★ ① 全域：每个偏移都要看得见光标（分界线后有空行）',
        (WidgetTester tester) async {
      const String doc = 'T\n\n---\n\nabc\n';
      final DocBuffer buf = DocBuffer(doc);
      await _mount(tester, buf);
      for (var off = 0; off <= doc.length; off++) {
        // ★ 2026-10-28（用户拍板"段间距不承接字符"）：段落分隔符那一格**不是位置**，
        //   它零高度、不画光标 —— 这是**对的**，不算死区。
        if (isParagraphSeparator(doc, off)) continue;
        expect(await _barsAt(tester, buf, off), greaterThan(0),
            reason: '偏移 $off 一根光标都没有（改前：3–7 全是死区）');
      }
    });

    testWidgets('★★ ② 全域：分界线后面**紧接文字**也不许有死区',
        (WidgetTester tester) async {
      const String doc = 'T\n\n---\nabc\n';
      final DocBuffer buf = DocBuffer(doc);
      await _mount(tester, buf);
      for (var off = 0; off <= doc.length; off++) {
        if (isParagraphSeparator(doc, off)) continue; // ★ 2026-10-28：分隔符不是位置
        expect(await _barsAt(tester, buf, off), greaterThan(0),
            reason: '偏移 $off（改前：3–6 死区）');
      }
    });

    testWidgets('★★ ③ 全域：分界线在**文末**也不许有死区', (WidgetTester tester) async {
      const String doc = 'T\n\n---\n\n';
      final DocBuffer buf = DocBuffer(doc);
      await _mount(tester, buf);
      for (var off = 0; off <= doc.length; off++) {
        if (isParagraphSeparator(doc, off)) continue; // ★ 2026-10-28：分隔符不是位置
        expect(await _barsAt(tester, buf, off), greaterThan(0),
            reason: '偏移 $off（改前：3–8 死区，含文末）');
      }
    });

    testWidgets('★ ④ 分界线**下面那个空行**上光标要画出来（用户报的那一格）',
        (WidgetTester tester) async {
      // ★ 2026-10-28：文档改成**两个**空行 —— 分界线下面第一个空行是**段落分隔符**
      //   （零高度、不是位置，见 `core/paragraph_break.dart`），真行从第二个起。
      //   用户报的那一格原本就是"分隔符"，以前靠"把光标塞进段距"才画出来。
      const String doc = 'T\n\n---\n\n\nabc\n';
      final DocBuffer buf = DocBuffer(doc);
      await _mount(tester, buf);
      // `---\n` 之后：第 1 个空行 = dash + 4（分隔符），第 2 个 = dash + 5（真行）
      final int separator = doc.indexOf('---') + 4;
      final int blank = separator + 1;
      expect(isParagraphSeparator(doc, separator), isTrue,
          reason: '前置：分界线下面第一个空行是段落分隔符');
      expect(doc[blank], '\n', reason: '前置：这一格确实是分界线下面那个空行');
      expect(await _barsAt(tester, buf, blank), greaterThan(0),
          reason: '用户点的就是这一格：光标不显示');
    });

    testWidgets('★ ⑤ 分界线那一行（`---` 三格 + 行尾）也要画', (WidgetTester tester) async {
      const String doc = 'T\n\n---\n\nabc\n';
      final DocBuffer buf = DocBuffer(doc);
      await _mount(tester, buf);
      final int dash = doc.indexOf('---');
      for (var off = dash; off <= dash + 3; off++) {
        expect(await _barsAt(tester, buf, off), greaterThan(0),
            reason: '分界线的第 ${off - dash} 格');
      }
    });
  });
}
