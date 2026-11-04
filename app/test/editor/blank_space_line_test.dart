// N1（2026-11-04）：**含空格的行 = 普通段落**（块模型层）+ N3b：**文首不许补行首换行**。
//
// N1 现场：`甲⏎⏎⏎乙` 的空行里打 3 个空格 ⇒ 竖条消失。
//   上一批只改了 `blank_runs.blankRunFrom`（版面高度那一侧），**块模型的 `LineIndex.isBlank`
//   还是 `trim()`** ⇒ 空格行仍被当成"空行 = 边界"、不产生块 ⇒ 仍走空行槽
//   ⇒ 空行槽只在行首画竖条 ⇒ 行内位置一根都没有。
//
// N3b 现场：新建 → 打 `w` → ⌫ → 打 `a` ⇒ `a` 落到**第二行**、第一行成了实空行。
//   根因：`_needsLineHeadPad` 在**文首空行**也补了一个 `\n`（文首没有"上一段"要分隔）。
//
// 改前必红：①②（竖条 0 根 / 块不是 paragraph）、④（`\n` 被偷偷加出来）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/block.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/caret_sites.dart' show kCaretColorValue;

import '../support/math_fonts.dart';

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
  return out;
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

TextEditingValue _v(String text) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );

Future<void> type(WidgetTester t, String s) async {
  for (final String ch in s.split('')) {
    t.testTextInput.updateEditingValue(_v(ch));
    await t.pump();
  }
  await t.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await loadMathFonts();
  });

  testWidgets('① 空行里打 3 个空格 ⇒ 竖条还在（不再消失）', (WidgetTester t) async {
    final DocBuffer buf = await mount(t, '甲\n\n\n乙\n', 3);
    await type(t, '   ');
    expect(buf.buf, '甲\n\n   \n乙\n');
    expect(carets(t), isNotEmpty,
        reason: '改前：竖条 0 根（空格行仍走空行槽，只在行首画）');
  });

  testWidgets('② 那一行必须是**段落块**（不是"空行边界"）', (WidgetTester t) async {
    final DocBuffer buf = await mount(t, '甲\n\n\n乙\n', 3);
    await type(t, '   ');
    final BlockIndex idx = BlockIndex.parse(buf.buf);
    final bool hasSpaceParagraph = idx.blocks.any((Block b) =>
        b.type == BlockType.paragraph &&
        idx.lines.text(b.lineFrom).trim().isEmpty &&
        idx.lines.text(b.lineFrom).isNotEmpty);
    expect(hasSpaceParagraph, isTrue,
        reason: '块：${idx.blocks.map((Block b) => b.type.name).toList()}');
  });

  testWidgets('③ 竖条跟着空格右移（空格有宽度）', (WidgetTester t) async {
    final DocBuffer buf = await mount(t, '甲\n\n\n乙\n', 3);
    final double x0 = carets(t).first.left;
    await type(t, '   ');
    expect(buf.buf.contains('   '), isTrue);
    final double x1 = carets(t).first.left;
    expect(x1 - x0, greaterThan(10.0), reason: '三个空格的宽度');
  });

  testWidgets('④ 文首空行打 a ⇒ 不许偷偷补 `\\n`（N3b）', (WidgetTester t) async {
    // `w` → ⌫ 之后的形状：缓冲区只剩一个换行
    final DocBuffer buf = await mount(t, '\n', 0);
    await type(t, 'a');
    expect(buf.buf, 'a\n',
        reason: '改前：`\\na\\n` —— 文首凭空多出一行（用户："第一行成了实空行"）');
  });

  testWidgets('⑤ 对照：文末空行打字**仍然**补 `\\n`（N3b 只挡文首）',
      (WidgetTester t) async {
    final DocBuffer buf = await mount(t, '甲\n\n', 2);
    await type(t, 'q');
    expect(buf.buf, '甲\n\nq\n', reason: '文末那格必须补，否则字比光标高 11.4px');
  });
}
