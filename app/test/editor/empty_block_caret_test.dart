// 批 28：**渲染文本为空的块**（空标题 / 空引用 / 空列表项）也要看得见光标。
//
// 用户 2026-10-24 22:0x 两张图：「这个空隙不对吧，这像是分割线下面的第二个空行」。
// 拿他正在编辑的 session 文档一看，分界线后面是 `---\n\n### \n\n` —— 一个**空的「标题3」块**。
//
// 探针 v30 逐偏移量出来（`T⏎⏎---⏎⏎### ⏎⏎`）：
//   · 30–34（`###` + 空格 + 换行）**一根光标都没有** —— 空文本 ⇒ `InlineMathText` 一个 span 都不产出；
//   · 整个标记区还没人认领（`acceptFrom` 默认 = 标记之后 = 34）；
//   · 空标题比"有字的标题"**矮 7px**（25.4 vs 32.4）⇒ 打出第一个字时整块突然长高、页面跳。
//
// 本守卫守两件事：**每个偏移都看得见光标** + **空标题与有字标题同高**。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/inline_math_text.dart';

Future<void> _mount(WidgetTester tester, DocBuffer buf) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
  ));
  tester.state<EditViewState>(find.byType(EditView)).focusInput();
  await tester.pumpAndSettle();
}

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
  group('批 28 · 空标记块（`### ` / `> ` / `- `）的光标与行高', () {
    testWidgets('★★ ① 空标题块：标记区每一格都要有光标（改前必红）',
        (WidgetTester tester) async {
      const String doc = 'T\n\n---\n\n### \n\n';
      final DocBuffer buf = DocBuffer(doc);
      await _mount(tester, buf);
      final int dash = doc.indexOf('###');
      // `###` 三格 + 空格 + 换行
      for (var off = dash; off <= dash + 4; off++) {
        expect(await _barsAt(tester, buf, off), greaterThan(0),
            reason: '偏移 $off（空标题块的标记区）改前一根光标都没有');
      }
    });

    testWidgets('★★ ② 空引用 / 空列表项：同样要看得见光标',
        (WidgetTester tester) async {
      for (final String doc in <String>['T\n\n> \n\n', 'T\n\n- \n\n']) {
        final DocBuffer buf = DocBuffer(doc);
        await _mount(tester, buf);
        final int mark = doc.indexOf('\n\n') + 2;
        for (var off = mark; off <= mark + 1; off++) {
          expect(await _barsAt(tester, buf, off), greaterThan(0),
              reason: '文档 ${doc.replaceAll('\n', r'\n')} 偏移 $off');
        }
      }
    });

    testWidgets('★★ ③ 全域：分界线 + 空标题的文档，每个偏移都有光标',
        (WidgetTester tester) async {
      const String doc = 'T\n\n---\n\n### \n\n';
      final DocBuffer buf = DocBuffer(doc);
      await _mount(tester, buf);
      for (var off = 0; off <= doc.length; off++) {
        expect(await _barsAt(tester, buf, off), greaterThan(0),
            reason: '偏移 $off（用户报的就是这一段）');
      }
    });

    testWidgets('★ ④ 行高一致：空标题 == 有字标题（打出第一个字不许长高）',
        (WidgetTester tester) async {
      final DocBuffer empty = DocBuffer('T\n\n### \n\n');
      await _mount(tester, empty);
      final Size emptySize = tester.getSize(find.byType(InlineMathText).last);

      final DocBuffer filled = DocBuffer('T\n\n### T\n\n');
      await _mount(tester, filled);
      final Size filledSize = tester.getSize(find.byType(InlineMathText).last);

      expect(emptySize.height, closeTo(filledSize.height, 0.5),
          reason: '空标题 ${emptySize.height} vs 有字标题 ${filledSize.height}；'
              '改前空的那一个矮 7px ⇒ 打出第一个字时页面会跳');
    });
  });
}
