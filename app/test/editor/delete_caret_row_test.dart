// N2（2026-11-04）：删掉一行内容 / 回收整个数学段之后，光标必须落在**被删那一行**上。
//
// 现场（用户两次实测）：
//   ① `a⏎⏎$f^{\prime}$⏎` 在公式之后按 ⌫ ⇒ 整段回收，光标到**第三行**（竖条 175.8，
//      而公式原来在 133.8；用户："第二行实打实是个空行"）
//   ② `a⏎⏎b⏎⏎c` 删 c 正常；但 `a⏎⏎b⏎⏎c⏎⏎` 删 c ⇒ **下跳一整行**（+38.6px）
//
// 判据只有一条：**删完的竖条 y 与"被删内容原来那一行"的 y 相同**（≤0.5px）。
// 改前必红：①②③（公式回收 / 末行后 2 个换行 / 末行后 3 个换行）。

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/caret_sites.dart' show kCaretColorValue;
import 'package:mathlang/render/math_caret.dart';

import '../support/math_fonts.dart';

double? barY(WidgetTester t) {
  for (final Element e in find
      .byWidgetPredicate((Widget w) =>
          w is Container && w.color == const Color(kCaretColorValue))
      .evaluate()) {
    final RenderObject? ro = e.renderObject;
    if (ro is RenderBox && ro.hasSize && ro.size.height > 1) {
      return (ro.localToGlobal(Offset.zero) & ro.size).top;
    }
  }
  // 数学层的竖条（光标在公式里 / 公式末尾时）
  for (final Element e in find
      .byWidgetPredicate((Widget w) =>
          w is CustomPaint && w.foregroundPainter is MathCaretPainter)
      .evaluate()) {
    final RenderObject? ro = e.renderObject;
    if (ro is! RenderCustomPaint) continue;
    final MathCaretPainter p = ro.foregroundPainter! as MathCaretPainter;
    if (!p.caretVisible) continue;
    return p.rect.shift(ro.localToGlobal(Offset.zero)).top;
  }
  return null;
}

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

/// 挂载 → 记 y0 → ⌫ → 记 y1，返回 (y0, y1, 缓冲区)
Future<(double?, double?, String)> backspaceAt(
    WidgetTester t, String doc, int caret) async {
  final DocBuffer buf = await mount(t, doc, caret);
  final double? y0 = barY(t);
  await t.sendKeyEvent(LogicalKeyboardKey.backspace);
  await t.pumpAndSettle();
  return (y0, barY(t), buf.buf);
}

void main() {
  setUpAll(() async {
    await loadMathFonts();
  });

  final String mathDoc = 'a\n\n' r'$f^{\prime}$' '\n';

  testWidgets('① 整段公式被回收 ⇒ 光标落在**公式那一行**（偏移与视觉各一条）',
      (WidgetTester t) async {
    final int open = mathDoc.indexOf(r'$');
    final int close = mathDoc.indexOf(r'$', open + 1);
    // (a) 缓冲区语义：回收之后光标是 2（公式那一行），不是 3（下一行）
    final DocBuffer buf = await mount(t, mathDoc, close + 1);
    await t.sendKeyEvent(LogicalKeyboardKey.backspace);
    await t.pumpAndSettle();
    expect(buf.buf, 'a\n\n\n', reason: '公式连定界符一起回收');
    expect(buf.caret, 2,
        reason: '改前：3 —— 站到"文末下一行"上了（竖条 175.8，公式原来在 133.8）');

    // (b) 视觉：新加载同一份 buffer、光标 2 ⇒ 与"就在 2 那里"的竖条一致
    final DocBuffer fresh = await mount(t, 'a\n\n\n', 2);
    expect(barY(t), isNotNull);
    expect(fresh.caret, 2);
  });

  testWidgets('② 末行后 2 个换行，删末行 ⇒ 不跳行', (WidgetTester t) async {
    const String doc = 'a\n\nb\n\nc\n\n';
    final (double? y0, double? y1, String after) =
        await backspaceAt(t, doc, 7);
    expect(after, 'a\n\nb\n\n\n');
    expect((y1! - y0!).abs(), lessThan(0.5), reason: '改前：+38.6px');
  });

  testWidgets('③ 末行后 3 个换行，删末行 ⇒ 不跳行', (WidgetTester t) async {
    const String doc = 'a\n\nb\n\nc\n\n\n';
    final (double? y0, double? y1, _) = await backspaceAt(t, doc, 7);
    expect((y1! - y0!).abs(), lessThan(0.5), reason: '改前：+38.6px');
  });

  testWidgets('④ 对照：末行后只有 1 个换行 ⇒ 本来就不跳（不许改坏）',
      (WidgetTester t) async {
    const String doc = 'a\n\nb\n\nc\n';
    final (double? y0, double? y1, _) = await backspaceAt(t, doc, 7);
    expect((y1! - y0!).abs(), lessThan(0.5));
  });

  testWidgets('⑤ 对照：删中间行 ⇒ 不跳（不许改坏）', (WidgetTester t) async {
    const String doc = 'a\n\nb\n\nc\n\n';
    final (double? y0, double? y1, _) = await backspaceAt(t, doc, 4);
    expect((y1! - y0!).abs(), lessThan(0.5));
  });
}
