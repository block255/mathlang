// 落点统一（2026-11-04 · P4′）：**同一个位点，打字与面板必须落到同一行**。
//
// 现场（用户原话）："打完 `≠0` 按 Enter ⇒ 出现下两行；在此处打 `a` 与插 `α` 落到不同行"。
// 实测（改前）：文末空行行首那一格上
//   · 打字（走 `_commitText`，有行首 pad）⇒ dy = −0.2（对齐）
//   · 面板（`insertSymtTex`，绕过 pad）  ⇒ dy = −38.6（错位一整行）
//   ⇒ 同一个光标位置，两个通道给出两个形状。
//
// 改前必红：①②（面板那条不补 `\n`，缓冲区与竖条都对不上）。

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/caret_sites.dart' show kCaretColorValue;
import 'package:mathlang/render/math_caret.dart';

import '../support/math_fonts.dart';

/// 场上看得见的竖条（文本侧 Container / 数学侧 `MathCaretPainter`）
List<Rect> carets(WidgetTester t) {
  final List<Rect> out = <Rect>[];
  for (final Element e in find
      .byWidgetPredicate((Widget w) =>
          w is Container && w.color == const Color(kCaretColorValue))
      .evaluate()) {
    final RenderObject? ro = e.renderObject;
    if (ro is RenderBox && ro.hasSize && ro.size.height > 1) {
      out.add(ro.localToGlobal(Offset.zero) & ro.size);
    }
  }
  for (final Element e in find
      .byWidgetPredicate((Widget w) =>
          w is CustomPaint && w.foregroundPainter is MathCaretPainter)
      .evaluate()) {
    final RenderObject? ro = e.renderObject;
    if (ro is! RenderCustomPaint) continue;
    final MathCaretPainter p = ro.foregroundPainter! as MathCaretPainter;
    if (!p.caretVisible) continue;
    out.add(p.rect.shift(ro.localToGlobal(Offset.zero)));
  }
  return out;
}

Future<(EditViewState, DocBuffer)> mount(
  WidgetTester t,
  String doc,
  int caret,
) async {
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
  final EditViewState st = t.state<EditViewState>(find.byType(EditView));
  st.focusInput();
  await t.pumpAndSettle();
  return (st, buf);
}

TextEditingValue _v(String text) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );

void main() {
  setUpAll(() async {
    await loadMathFonts();
  });

  // 文末空行行首：`甲⏎⏎⏎` 的第 3 行行首（偏移 2）
  const String doc = '甲\n\n\n';
  const int at = 2;

  testWidgets('① 打字：落在光标所在那一行，缓冲形状 = 甲⏎⏎q⏎⏎',
      (WidgetTester t) async {
    final (_, DocBuffer buf) = await mount(t, doc, at);
    t.testTextInput.updateEditingValue(_v('q'));
    await t.pumpAndSettle();
    expect(buf.buf, '甲\n\nq\n\n', reason: '打字的行首 pad 是既有正确行为');
  });

  testWidgets('② 面板插 `\\alpha`：必须与打字落到**同一行**（同一形状的 `\\n`）',
      (WidgetTester t) async {
    final (EditViewState st, DocBuffer buf) = await mount(t, doc, at);
    st.insertSymbolTex(r'\alpha', template: false);
    await t.pumpAndSettle();
    expect(buf.buf, r'甲' '\n\n' r'$\alpha$' '\n\n',
        reason: r'改前：绕过行首 pad ⇒ 变成 甲⏎$α$⏎⏎（少一个换行，字高一行）');
  });

  testWidgets('③ 面板那条的竖条：不许比插入前**低一整行**（改前 −38.6px）',
      (WidgetTester t) async {
    final (EditViewState st, _) = await mount(t, doc, at);
    final double before = carets(t).first.top;
    st.insertSymbolTex(r'\alpha', template: false);
    await t.pumpAndSettle();
    final double after = carets(t).first.top;
    // 允许数学层与文本层的天然高度差（实测 ~5px），但绝不允许整行（38.6px）
    expect((after - before).abs(), lessThan(12.0),
        reason: '改前：字/竖条比光标低整整一行');
  });

  testWidgets('④ 段间真行**不许**补 `\\n`（pad 只在文末空行生效）',
      (WidgetTester t) async {
    const String doc2 = '甲\n\n\n乙\n';
    final int nl0 = '\n'.allMatches(doc2).length;
    final (EditViewState st, DocBuffer buf) = await mount(t, doc2, 3);
    st.insertSymbolTex(r'\alpha', template: false);
    await t.pumpAndSettle();
    expect('\n'.allMatches(buf.buf).length, nl0,
        reason: '段间真行上补 `\\n` 会多出一行（实测 dy +38.2）');
    expect(buf.buf.contains(r'$\alpha$'), isTrue);
  });
}
