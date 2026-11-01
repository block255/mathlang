// 反馈 2（2026-10-30 · R10）守卫：**行间公式块内部按 Enter 只多一行**。
//
// 实测病灶（真 EditView + 真 Enter 键）：光标在 `\frac{a}{b}` 的分子里时，
//   `_enterPayload` 判"既不在行首也不在行末" ⇒ 给 `\n\n`，而 `insert_guard`
//   把这两个换行整体推到块之后 ⇒ 一次按键多出**两行**（`$$` 后 2 个换行变 4 个）。
// 口径：只读基准 1/3 —— Enter 每按一次，屏幕上多一行。
//
// 改前必红：`$$` 与后面的正文之间是 **4** 个换行（应为 3）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';

Future<void> _mount(WidgetTester t, DocBuffer buf) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
  ));
  t.state<EditViewState>(find.byType(EditView)).focusInput();
  await t.pumpAndSettle();
}

/// 收尾 `$$` 与 [marker] 之间有几个换行
int _newlinesBetween(String s, String marker) {
  final int close = s.indexOf(r'$$', s.indexOf(r'\frac'));
  final int to = s.indexOf(marker);
  return close < 0 || to < 0
      ? -1
      : s.substring(close + 2, to).split('\n').length - 1;
}

void main() {
  testWidgets('分子里按 Enter ⇒ 块后只多一行', (WidgetTester t) async {
    final DocBuffer buf = DocBuffer('前\n\$\$\n\\frac{a}{b}\n\$\$\n\n后');
    await _mount(t, buf);
    expect(_newlinesBetween(buf.buf, '后'), 2, reason: '前提：原来是 2 个换行');

    buf.setCaret(buf.buf.indexOf('{a}') + 1);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();

    expect(_newlinesBetween(buf.buf, '后'), 3,
        reason: '一次 Enter 只多一行（改前是 4）');
    // 公式本体不许被弄坏
    expect(buf.buf.contains(r'\frac{a}{b}'), isTrue);
  });

  testWidgets('分母里按 Enter 同样只多一行', (WidgetTester t) async {
    final DocBuffer buf = DocBuffer('前\n\$\$\n\\frac{a}{b}\n\$\$\n\n后');
    await _mount(t, buf);
    buf.setCaret(buf.buf.indexOf('{b}') + 1);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(_newlinesBetween(buf.buf, '后'), 3);
  });

  testWidgets('**行内**公式的分式里按 Enter 也只多一行（用户 11-01 复验没修到的那条）',
      (WidgetTester t) async {
    final DocBuffer buf = DocBuffer('前\n文字 \$\\frac{a}{b}\$ 后\n');
    await _mount(t, buf);
    buf.setCaret(buf.buf.indexOf('{a}') + 1);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    // 公式之后只该多**一个** `\n`（改前多两个）
    final int at = buf.buf.indexOf(r'\frac');
    final int close = buf.buf.indexOf(r'$', at);
    final String tail = buf.buf.substring(close + 1);
    final int nl = tail.length - tail.replaceFirst(RegExp(r'^\n+'), '').length;
    // ★ 口径（2026-11-01 用户复验）：k=3 = **一个"真行"的空行**（k=2 只是零高度的段距）。
    expect(nl, 3, reason: '公式之后恰好一个真行空行（k=3）');
    expect(tail.contains('后'), isTrue);
    // ★★ 用户实测的那条：**光标不许消失**
    final Finder bars = find.byWidgetPredicate((Widget w) =>
        w is Container && w.color == const Color(0xFF1E88E5));
    expect(bars.evaluate().length, 1, reason: '回车之后光标必须画在新造出来的空行上');
  });
}
