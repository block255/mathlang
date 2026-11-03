// ★★ 2026-11-03（双环境）：**一个公式块里两个环境**时，点第二个环境要落进第二个。
//
// 用户实测（2026-11-03 截图）：4×6 矩阵后面接一个 2×2 行列式 ⇒ 点行列式里的位点，
//   光标只能落到**前面那个矩阵**那一行第一格的末尾；那一行全空时"乱跳"。
//
// 根因（探针）：格子坐标只有 `(row, col)`、没有"属于哪个环境" ⇒
//   `pmatrix` 的 `(0,0)` 与 `vmatrix` 的 `(0,0)` 撞键；`envCellOffset` 只按 (row,col) 找槽，
//   还在多个匹配里取"最宽的" ⇒ 永远选中第一个环境。
//   探针原文：`EnvCellHit(1,1) ⇒ 偏移 22 ⇒ 「d\end{」，而 w 在 58`。
//
// 本文件是**改前红**的守卫：三条在旧实现上全部红（点 x/y/z/w 都落进第一个矩阵）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/lang/env_table.dart';
import 'package:mathlang/render/env_cells.dart';
import 'package:mathlang/render/leaf_boxes.dart';
import 'package:mathlang/render/math_caret.dart';

import '../support/math_fonts.dart';

/// 矩阵 + 行列式并排（用户截图那种形态）。
const String kTwo = r'\begin{pmatrix}a&b\\c&d\end{pmatrix}'
    r'\begin{vmatrix}x&y\\z&w\end{vmatrix}';

/// 第一个环境**全空**、第二个有内容（"都没内容就乱跳"那种）。
const String kFirstEmpty = r'\begin{pmatrix}&&\\&&\end{pmatrix}'
    r'\begin{vmatrix}x&y\\z&w\end{vmatrix}';

/// 第二个环境里有一格**空着**（点它一定不走"点中字形"的细粒度路径）。
const String kGap = r'\begin{pmatrix}a&b\\c&d\end{pmatrix}'
    r'\begin{vmatrix}x&\\&w\end{vmatrix}';

String _doc(String tex) => '${r'$$'}\n$tex\n${r'$$'}';

Future<DocBuffer> _pump(WidgetTester tester, String doc) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer(doc)..setCaret(0);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
  ));
  tester.state<EditViewState>(find.byType(EditView)).focusInput();
  await tester.pumpAndSettle();
  return buf;
}

({RenderBox root, List<LeafBox> boxes}) _rig() {
  final RenderBox root =
      find.byType(MathWithCaret).last.evaluate().single.renderObject! as RenderBox;
  return (root: root, boxes: scanLeafBoxes(root).eligible);
}

/// 点字形 [ch] 的中心（光标偏移由调用方读 buffer）。
Future<void> _tapGlyph(WidgetTester tester, String ch) async {
  final ({RenderBox root, List<LeafBox> boxes}) r = _rig();
  final LeafBox b = r.boxes.firstWhere((LeafBox x) => x.text == ch);
  await tester.tapAt(r.root.localToGlobal(b.rect.center));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async => loadMathFonts());

  group('★ 格子坐标必须带环境身份', () {
    test('同一个 (1,1)，两个环境各给各的偏移（改前：两个都返回第一个的）', () {
      const String tex = kTwo;
      final int d = tex.indexOf('d');
      final int w = tex.indexOf('w');
      expect(envCellOffset(tex, const EnvCellHit(1, 1, atEnd: false, envIx: 0)),
          d);
      expect(envCellOffset(tex, const EnvCellHit(1, 1, atEnd: false, envIx: 1)),
          w);
    });
  });

  group('★ 两个环境并排：点谁落谁', () {
    testWidgets('点第二个环境（行列式）的四格 ⇒ 每次都落在那一格里',
        (WidgetTester tester) async {
      final String doc = _doc(kTwo);
      final DocBuffer buf = await _pump(tester, doc);
      final EnvTable det = envTablesIn(kTwo).last;
      expect(det.name, 'vmatrix');

      for (final ({int r, int c, String ch}) item in <({int r, int c, String ch})>[
        (r: 0, c: 0, ch: 'x'),
        (r: 0, c: 1, ch: 'y'),
        (r: 1, c: 0, ch: 'z'),
        (r: 1, c: 1, ch: 'w'),
      ]) {
        await _tapGlyph(tester, item.ch);
        final ({int start, int end}) cell = det.rows[item.r][item.c];
        final int base = doc.indexOf(kTwo);
        final int lo = base + cell.start;
        final int hi = base + cell.end;
        expect(buf.caret, inInclusiveRange(lo, hi),
            reason: '点「${item.ch}」应落在第 ${item.r} 行第 ${item.c} 列 '
                '[$lo,$hi)，实际 ${buf.caret}');
      }
    });

    testWidgets('第一个环境全空时，点第二个环境仍落在第二个',
        (WidgetTester tester) async {
      final String doc = _doc(kFirstEmpty);
      final DocBuffer buf = await _pump(tester, doc);
      final EnvTable det = envTablesIn(kFirstEmpty).last;
      final int base = doc.indexOf(kFirstEmpty);

      await _tapGlyph(tester, 'x');
      final ({int start, int end}) cell = det.rows[0][0];
      expect(buf.caret, inInclusiveRange(base + cell.start, base + cell.end),
          reason: '点 `x` 不许落回前面那个空矩阵，实际 ${buf.caret}');
    });

    testWidgets('点第二个环境里**空格子** ⇒ 落在那一格（不许落回第一个环境的同名列）',
        (WidgetTester tester) async {
      final String doc = _doc(kGap);
      final DocBuffer buf = await _pump(tester, doc);
      final EnvTable det = envTablesIn(kGap).last;
      final int base = doc.indexOf(kGap);
      final RenderBox root = _rig().root;

      final Rect? box = envCellBoxAt(
        root: root,
        tex: kGap,
        displayStyle: true,
        row: 0,
        col: 1,
        fontSize: 20,
        envIx: 1,
      );
      expect(box, isNotNull, reason: '量不到第二个环境的空格子');
      await tester.tapAt(root.localToGlobal(box!.center));
      await tester.pumpAndSettle();

      final ({int start, int end}) cell = det.rows[0][1];
      expect(buf.caret,
          inInclusiveRange(base + cell.start, base + cell.end),
          reason: '空格子也要落在第二个环境（改前会落到第一个环境的 `b`，实际 ${buf.caret}）');
    });
  });
}
