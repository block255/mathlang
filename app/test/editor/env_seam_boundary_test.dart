// ★ 2026-11-03 深夜（边界收尾）：三条口径的守卫（**改前红**）。
//
//  ① 行列式的竖线是 `∣`(U+2223) / `∥`(U+2225) —— 必须被当成**定界符**
//     （否则行列式的"完整盒"不含自己的竖线 ⇒ 缝宽算错）。
//  ② 相邻环境的**完整盒不许重叠** —— 实测那一块里 env2 的左缘被配对组撑到 127.6
//     （吃进了左边矩阵的 `⎤⎦`），导致"矩阵↔行列式"那条缝是 −13.3px、一个像素都点不到。
//  ③ 行间块**右侧空白** ⇒ "环境之后"（用户："我点右边是要点到外面"），
//     不是"该行行末"（那是 2026-10-24 给 `cases` 定的旧口径）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/lang/env_table.dart';
import 'package:mathlang/render/env_cells.dart';
import 'package:mathlang/render/leaf_boxes.dart';
import 'package:mathlang/render/math_caret.dart';

import '../support/math_fonts.dart';

/// 用户 2026-11-03 给的四个环境（行列式 · 矩阵 · 行列式 · 4×4 行列式）。
const String kFour = r'\begin{vmatrix}a&b\\c&d\end{vmatrix}'
    r'\begin{bmatrix}a&b\\c&d\\&\end{bmatrix}'
    r'\begin{vmatrix}a&b\\c&d\end{vmatrix}'
    r'\begin{vmatrix}a&b&&\\c&d&&\\&&&\\&&&\end{vmatrix}';

/// 矩阵 + 行列式并排（右侧空白那条用）。
const String kTwo = r'\begin{bmatrix}a&b\\c&d\end{bmatrix}'
    r'\begin{vmatrix}x&y\\z&w\end{vmatrix}';

Future<DocBuffer> _pump(WidgetTester tester, String doc) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const SizedBox.shrink());
  final DocBuffer buf = DocBuffer(doc)..setCaret(0);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
  ));
  tester.state<EditViewState>(find.byType(EditView)).focusInput();
  await tester.pumpAndSettle();
  return buf;
}

RenderBox _root() =>
    find.byType(MathWithCaret).last.evaluate().single.renderObject! as RenderBox;

/// 画出来的竖条（`MathCaretPainter.caretVisible` 那一个）
Rect? _paintedBar(WidgetTester tester) {
  for (final Element e in find.byType(CustomPaint).evaluate()) {
    final CustomPainter? p = (e.widget as CustomPaint).foregroundPainter;
    if (p is MathCaretPainter && p.caretVisible) return p.rect;
  }
  return null;
}

void main() {
  setUpAll(() async => loadMathFonts());

  test('① 行列式的竖线 `∣` / `∥` 算定界符', () {
    expect(isLeftDelimiterText('∣'), isTrue, reason: '`∣`(U+2223) 是 vmatrix 的竖线');
    expect(isRightDelimiterText('∣'), isTrue);
    expect(isLeftDelimiterText('∥'), isTrue, reason: '`∥`(U+2225) 是 `\\|` 的竖线');
    expect(isRightDelimiterText('∥'), isTrue);
  });

  testWidgets('② 相邻环境的完整盒不许重叠（colBand 不许被邻居的括号撑大）',
      (WidgetTester tester) async {
    final String doc = '${r'$$'}\n$kFour\n${r'$$'}';
    await _pump(tester, doc);
    final RenderBox root = _root();
    final List<LeafBox> boxes = scanLeafBoxes(root).eligible;
    final List<EnvTable> tables = envTablesIn(kFour);
    final List<Rect> full = <Rect>[];
    for (var i = 0; i < tables.length; i++) {
      final EnvGrid g = buildEnvGrid(
          root: root, tex: kFour, displayStyle: true, fontSize: 20, envIx: i)!;
      full.add(envFullBox(g, boxes)!);
    }
    for (var i = 0; i + 1 < full.length; i++) {
      expect(full[i].right, lessThanOrEqualTo(full[i + 1].left + 0.5),
          reason: 'env$i 的盒子右缘 ${full[i].right.toStringAsFixed(1)} '
              '不该越过 env${i + 1} 的左缘 ${full[i + 1].left.toStringAsFixed(1)}');
    }
    // ① 的效果：每个行列式的完整盒含**自己的竖线**（左缘 0 / 右缘 348.6，不是格区 6.7..337.5）
    expect(full.first.left, lessThan(2));
    expect(full.last.right, greaterThan(348));
    // ② 的效果：env2 的列带第 0 列**不许被邻居的 `⎤⎦` 撑大**（改前 128..158，应为 148..158）
    final EnvGrid g2 = buildEnvGrid(
        root: root, tex: kFour, displayStyle: true, fontSize: 20, envIx: 2)!;
    expect(g2.colBand[0]!.left, greaterThan(147),
        reason: 'env2 第 0 列的左缘 ${g2.colBand[0]!.left.toStringAsFixed(1)} '
            '应当 ≥ 148（改前 128 = 吃进了邻居的 `⎤⎦`）');
    // 两条盒子**相接**（不是重叠、也不是大缝）⇒ 4px 宽容才能造出"两盒带"
    expect((full[1].right - full[2].left).abs(), lessThan(0.6));
  });

  testWidgets('③ 行间块右侧空白 ⇒ 落在"环境之后"（不是该行行末）',
      (WidgetTester tester) async {
    final String doc = '${r'$$'}\n$kTwo\n${r'$$'}';
    final DocBuffer buf = await _pump(tester, doc);
    final RenderBox root = _root();
    final Offset tl = root.localToGlobal(Offset.zero);
    final List<EnvTable> tables = envTablesIn(kTwo);
    final int afterAll = tables.last.endEnd + 3;
    final int lastCellEnd = tables.last.rows.last.last.end + 3;
    expect(afterAll, isNot(lastCellEnd), reason: '这两个落点必须不同，否则守卫没意义');
    // 行带内（第 0 行中线）点右侧 40px
    await tester.tapAt(Offset(tl.dx + root.size.width + 40, tl.dy + 12));
    await tester.pumpAndSettle();
    expect(buf.caret, afterAll,
        reason: '点右侧空白应落"环境之后"（$afterAll），实际 ${buf.caret}'
            '（$lastCellEnd = 该行行末，是旧口径）');
  });

  testWidgets('④ 边界位点（两个环境之间）的竖条：整条落在**某一条行带**里',
      (WidgetTester tester) async {
    // 改前：边界位点没有格框 ⇒ 竖条走 `字号 × 1.25` 的兜底尺子
    //   （display 字号 20 ⇒ 高 25px，而行带只有 24px）⇒ 必然跨过行界，看着"不上不下"。
    final String doc = '${r'$$'}\n$kTwo\n${r'$$'}';
    final DocBuffer buf = await _pump(tester, doc);
    buf.setCaret(envTablesIn(kTwo).first.endEnd + 3); // 两个环境之间
    await tester.pumpAndSettle();
    final RenderBox root = _root();
    final List<Rect> bands = <Rect>[];
    for (var i = 0; i < envTablesIn(kTwo).length; i++) {
      final EnvGrid? g = buildEnvGrid(
          root: root, tex: kTwo, displayStyle: true, fontSize: 20, envIx: i);
      if (g != null) bands.addAll(g.rowBand.values);
    }
    expect(bands, isNotEmpty);
    final Rect? maybeBar = _paintedBar(tester);
    expect(maybeBar, isNotNull, reason: '边界位点也必须有竖条');
    final Rect bar = maybeBar!;
    final bool fits =
        bands.any((Rect b) => bar.top >= b.top - 0.5 && bar.bottom <= b.bottom + 0.5);
    expect(fits, isTrue,
        reason: '竖条 ${bar.top.toStringAsFixed(1)}..${bar.bottom.toStringAsFixed(1)}'
            '（高 ${bar.height.toStringAsFixed(1)}）必须整条落在某一条行带内；'
            '行带=${bands.map((Rect b) => '${b.top.toStringAsFixed(0)}..${b.bottom.toStringAsFixed(0)}').join(',')}');
  });
}
