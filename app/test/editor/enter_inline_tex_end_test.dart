// N3a（2026-11-04）：**光标停在行内公式的 tex 末尾（收尾 `$` 之前）按 Enter ⇒ 只 +1 行**。
//
// 现场（用户 ③）：`a⏎⏎$\frac{x}{y}$⏎` 里光标停在公式末尾按 Enter
//   ⇒ 屏幕上"光标下两行"、输入落到第三行、第二行成了实空行（实测竖条 +79.2px）。
//   根因：那里 `c != le`（后面还有收尾 `$`）⇒ 掉进通用路径 ⇒ 载荷 `\n\n`
//   ⇒ 一次按键加两个换行；而 `_enter` 里只有"行间块末尾"被特判过（`displayTexEnd`）。
//   口径（只读基准 1/3）：**一次 Enter = 屏幕上多一行**。
//
// 改前必红：①（换行数 +2）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';

import '../support/math_fonts.dart';

Future<DocBuffer> mount(WidgetTester t, String doc, int caret) async {
  await t.pumpWidget(const SizedBox.shrink());
  final DocBuffer buf = DocBuffer(doc)..setCaret(caret);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 900,
        child: SingleChildScrollView(
          child: SizedBox(width: 793.7, child: EditView(buffer: buf)),
        ),
      ),
    ),
  ));
  t.state<EditViewState>(find.byType(EditView)).focusInput();
  await t.pumpAndSettle();
  return buf;
}

void main() {
  setUpAll(() async {
    await loadMathFonts();
  });

  final String doc = 'a\n\n' r'$\frac{x}{y}$' '\n';

  testWidgets('① 行内公式 tex 末尾按 Enter ⇒ 只多一行', (WidgetTester t) async {
    final int open = doc.indexOf(r'$');
    final int closeAt = doc.indexOf(r'$', open + 1); // 收尾 `$`
    final int caret = closeAt; // `$` 之前那一格 = tex 末尾
    final int nl0 = '\n'.allMatches(doc).length;
    final DocBuffer buf = await mount(t, doc, caret);
    expect(buf.buf, doc, reason: '前提：缓冲区没被挂载改动');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect('\n'.allMatches(buf.buf).length, nl0 + 1,
        reason: '改前：+2（一按两行）⇒ ${buf.buf.replaceAll('\n', '⏎')}');
    expect(buf.buf.startsWith('a\n\n' r'$\frac{x}{y}$'), isTrue,
        reason: '公式本身不许被劈开：${buf.buf}');
  });

  testWidgets('② 对照：行内公式**中间**按 Enter 仍是"就地断栅栏"',
      (WidgetTester t) async {
    // `$x+y$` 里 `x` 与 `+` 之间 ⇒ 既有口径（`enter_inline_math_test` 钉着）
    const String d2 = r'$x+y$';
    final DocBuffer buf = await mount(t, d2, 2);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(buf.buf.contains(r'$x$'), isTrue,
        reason: r'应断成 `$x$` + 换行 + `$+y$`：' '${buf.buf}');
  });
}
