// 反馈 21（2026-10-30）守卫：**分段框里打了空格，框就该消失**。
//
// 用户实测（图 21）：`f(x)=\begin{cases}…\\\ \ \ \ \ \ \ \ \ &\end{cases}`
//   —— 空行里打了空格，框不但没消失，还变成一个**又窄又高的矩形**
//   （宽 = 该列被上面分式撑宽、高 = 行带被撑高）。
//
// 探针（2026-11-01，20 px，`scanLeafBoxes`）：
//   · `\ `（用户打的空格）画出来是**字形盒**：`" " w=5.0 h=25` ⇒ 文本 `trim()` 后为空
//     ⇒ 旧判据 `text.trim().isEmpty` 判"没内容" ⇒ 框照画；
//   · 模板塞的**普通空格**：`\begin{cases}x\\ \end{cases}` 的空格里**一个盒都没有**；
//   · 注入的 `\rule{1em}{0pt}` 是 `pad` 类，本就不参与判据。
// ⇒ 判据改成"**看得见的字，或者占了宽度**"：`\ ` 算内容（框消失），普通空格不算（框照画）。
//
// 改前必红：②（`\ ` 被判无内容）与 ⑦（接线）。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/env_cells.dart';
import 'package:mathlang/render/leaf_boxes.dart';
import 'package:mathlang/render/slot_marks.dart';

import '../support/math_fonts.dart';

LeafBox _box(double left, double width, {String? text, LeafBoxKind kind = LeafBoxKind.glyph}) =>
    LeafBox(Rect.fromLTWH(left, 10, width, 20), text: text, kind: kind);

void main() {
  setUpAll(() async => loadMathFonts());

  const Rect cell = Rect.fromLTWH(0, 0, 40, 24);

  group('21 · 格子内容判据', () {
    test('① 真字符算内容', () {
      expect(envCellHasContent(<LeafBox>[_box(10, 8, text: '1')], cell), isTrue);
    });

    test(r'② `\ `（文本是空白但宽度 5）算内容 —— 反馈 21 本体', () {
      expect(envCellHasContent(<LeafBox>[_box(10, 5, text: ' ')], cell), isTrue);
    });

    test('③ 零宽空白盒不算内容（普通空格 / 幻影盒）', () {
      expect(
          envCellHasContent(
              <LeafBox>[_box(10, 0, text: ' '), _box(10, 0, text: '')], cell),
          isFalse);
    });

    test('④ 垫子类盒不算内容（`\\rule{1em}{0pt}`）', () {
      expect(
          envCellHasContent(<LeafBox>[_box(10, 20, kind: LeafBoxKind.pad)], cell),
          isFalse);
    });

    test('⑤ `aligned` 的等号豁免仍然有效', () {
      final LeafBox eq = _box(10, 8, text: '=');
      expect(
          envCellHasContent(<LeafBox>[eq], cell, alignedEq: eq), isFalse,
          reason: '模板自带的 `&=` 不算用户填的内容');
    });

    test('⑥ 盒中心不在格子里 ⇒ 不算内容', () {
      expect(
          envCellHasContent(<LeafBox>[_box(200, 8, text: 'x')], cell), isFalse);
    });
  });

  testWidgets(r'⑦ 接线：空行里打 `\ ` ⇒ 判有内容；模板普通空格 ⇒ 判无内容',
      (WidgetTester tester) async {
    Future<bool> cellHasContent(String tex) async {
      final String injected = renderMathTex(tex, caretRel: -1, showCursor: false);
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: Math.tex(injected,
              mathStyle: MathStyle.display,
              textStyle: const TextStyle(fontSize: 20)),
        ),
      ));
      await tester.pumpAndSettle();
      final RenderObject root = tester.renderObject(find.byType(Math));
      final EnvGrid? g = buildEnvGrid(
          root: root, tex: tex, displayStyle: true, fontSize: 20);
      expect(g, isNotNull);
      final Rect? box = envCellBoxIn(g!, 1, 0);
      expect(box, isNotNull);
      List<LeafBox> all = scanLeafBoxes(root).eligible;
      return envCellHasContent(all, box!);
    }

    expect(await cellHasContent(r'\begin{cases}x\\\ \end{cases}'), isTrue,
        reason: r'用户打的 `\ ` 是内容 ⇒ 框消失');
    expect(await cellHasContent(r'\begin{cases}x\\ \end{cases}'), isFalse,
        reason: r'模板塞的普通空格不产生字形盒 ⇒ 框照画');
    expect(await cellHasContent(r'\begin{cases}x\\\end{cases}'), isFalse,
        reason: '真的空格子 ⇒ 框照画');
  });
}
