// ★★★ 2026-10-24（批 18）：**汉字 = 断点**（打字链路，真实 `_commitText`）
//
// 纯函数那份（`break_split_test.dart`）钉规则；这里钉**接线**：
// 平台文本通道 → `_commitText` → **拆段**（顶层）/ 不拆（结构槽、脚本位、行间块、边界）。
//
// 口径（用户 2026-10-24 拍板）：
//   · 行内公式顶层打汉字 ⇒ `$左$` + 汉字 + `$右$`，汉字在围栏外；
//   · 结构槽 / 行间块 ⇒ 接受数学字体（文档不变，只把那一个字插进 tex）；
//   · 边界格（内容首/末）⇒ 汉字落围栏外，不补空围栏。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/lang/math_spans.dart';

/// 每个文档都以 `甲` 打头：点它取焦点（没有真 IME，必须有人持有焦点键才会进来）
Future<DocBuffer> _pump(WidgetTester tester, String doc, int caret) async {
  final DocBuffer buf = DocBuffer(doc)..setCaret(caret);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 600,
        child: SingleChildScrollView(child: EditView(buffer: buf)),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('甲').first);
  await tester.pumpAndSettle();
  buf.setCaret(caret); // 点击会挪光标，放回目标位置
  await tester.pumpAndSettle();
  return buf;
}

Future<void> _type(WidgetTester tester, String text) async {
  tester.testTextInput.enterText(text);
  await tester.pumpAndSettle();
}

int _dollars(String s) => r'$'.allMatches(s).length;

void main() {
  testWidgets(r'★ 顶层打汉字 ⇒ 拆成两段，汉字在围栏外', (WidgetTester tester) async {
    //           0123456789...
    //          甲$\alpha\beta$
    final DocBuffer buf = await _pump(tester, r'甲$\alpha\beta$', 8);
    await _type(tester, '任');
    expect(buf.buf, r'甲$\alpha$任$\beta$', reason: '实际=${buf.buf}');
    expect(buf.caret, r'甲$\alpha$任'.length, reason: '光标停在汉字之后（围栏外）');
    expect(inlineDoubleDollarLines(buf.buf), isEmpty, reason: r'不许造出行内 `$$`');
  });

  testWidgets(r'★ 结构槽里（分母）打汉字 ⇒ 不拆，接受数学字体', (WidgetTester tester) async {
    final String doc = r'甲$\frac{1}{2}$';
    final DocBuffer buf = await _pump(tester, doc, doc.indexOf('2') + 1);
    await _type(tester, '任');
    expect(_dollars(buf.buf), 2, reason: '不该拆段：${buf.buf}');
    expect(buf.buf.contains(r'\frac'), isTrue);
  });

  testWidgets(r'★ 脚本位（`^` 之前）打汉字 ⇒ 不拆（自检拦住）', (WidgetTester tester) async {
    final String doc = r'甲$x^{2}$';
    final DocBuffer buf = await _pump(tester, doc, doc.indexOf('^'));
    await _type(tester, '任');
    expect(_dollars(buf.buf), 2, reason: '切了会得到裸 `^{2}`：${buf.buf}');
  });

  testWidgets(r'★ 边界格（内容首）打汉字 ⇒ 落围栏外，不造空段', (WidgetTester tester) async {
    final String doc = r'甲$\alpha$';
    final DocBuffer buf = await _pump(tester, doc, 2); // 内容首 = `$` 之后
    await _type(tester, '任');
    expect(buf.buf, r'甲任$\alpha$', reason: '实际=${buf.buf}');
    expect(inlineDoubleDollarLines(buf.buf), isEmpty);
  });

  testWidgets(r'★ 行间块里打汉字 ⇒ 不拆，接受数学字体', (WidgetTester tester) async {
    const String doc = '甲\n\$\$\na+b\n\$\$\n';
    final int caret = doc.indexOf('+') + 1;
    final DocBuffer buf = await _pump(tester, doc, caret);
    await _type(tester, '任');
    expect(_dollars(buf.buf), 4, reason: '行间块不该被切开：${buf.buf}');
    expect(buf.buf.contains('任'), isTrue);
  });
}
