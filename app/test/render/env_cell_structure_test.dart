// ★★★ L20 守卫：**格子里放"带子位点的结构"**（2026-10-19 用户实测报的）
//
// 用户原话：「当矩阵和行列式里子位点放上根号等有子位点的东西可能会导致点击判定出问题
//   （比如放进去的那个有子位点的数学符号的子位点无法正确点到，以及可能矩阵和行列式本身的
//   点击判定可能出问题，可能是有的格子点不到，可能是点不到里面）……
//   也有可能是子位点结构多级嵌套都可能出现类似问题」
//
// 真根因（函数内探针，3×3、第 1 行第 2 列放 `\sqrt{2}`）：
//   格子里放结构时，**结构自己的槽**会作为**嵌套位点**出现，path 末尾是 `(null,null)`：
//
//     slot r0c0 [52,54)  path=(r0,c0)           → 22.2..32.8   ← 真正的 `a`
//     slot r0c0 [62,78)  path=(r0,c1)(null,null) → 74.2..90.2   ← ★ 把上面那一格**覆盖**了
//     slot r0c1 [55,80)  path=(r0,c1)           → 74.2..90.2
//
//   旧判据 `path.any(row != null || col != null)` + `?? 0` ⇒ 那个尾垫槽被当成 **(row, 0)**
//   ⇒ 第 0 列的矩形被顶掉 ⇒ **列带重叠**（col0 17.5..90.2 vs col1 63.8..90.2）
//   ⇒ 命中按"第一个包含的列"取 ⇒ **点中间列落到第 0 列**。
//
// 修法：只认**最后一步同时有 row 和 col** 的槽（真格子），嵌套子槽不参与。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/env_cells.dart';
import 'package:mathlang/render/math_caret.dart';

import '../support/math_fonts.dart';

/// 四种"格子里放结构"的场合（含两级嵌套）
const Map<String, String> kCases = <String, String>{
  r'sqrt 在第 1 行第 2 列': r'\begin{pmatrix} a & \sqrt{2} & \\ & & \\ & & \end{pmatrix}',
  r'x^2 在第 1 行第 2 列': r'\begin{pmatrix} a & x^2 & \\ & & \\ & & \end{pmatrix}',
  r'frac 在第 2 行第 2 列': r'\begin{pmatrix} a & b & \\ & \frac{1}{2} & \\ & & \end{pmatrix}',
  r'两级嵌套 sqrt(frac)': r'\begin{pmatrix} \sqrt{\frac{1}{2}} & & \\ & & \\ & & \end{pmatrix}',
  r'嵌套 sqrt(x^2+1)': r'\begin{pmatrix} \sqrt{x^2+1} & & \\ & & \\ & & \end{pmatrix}',
};

String _doc(String tex) => '${r'$$'}\n$tex\n${r'$$'}';

Future<DocBuffer> _pump(WidgetTester tester, String doc) async {
  tester.view.physicalSize = const Size(1200, 1400);
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

({RenderBox root, EnvGrid grid}) _rig(WidgetTester tester) {
  final MathWithCaret w =
      tester.widget<MathWithCaret>(find.byType(MathWithCaret).last);
  final RenderBox root = find
      .byType(MathWithCaret)
      .last
      .evaluate()
      .single
      .renderObject! as RenderBox;
  final EnvGrid? g = buildEnvGrid(
    root: root,
    tex: w.tex,
    displayStyle: true,
    fontSize: w.fontSize,
  );
  expect(g, isNotNull, reason: '环境必须能量出网格');
  return (root: root, grid: g!);
}

void main() {
  setUpAll(() async => loadMathFonts());

  for (final MapEntry<String, String> c in kCases.entries) {
    group('⑰ ${c.key}', () {
      testWidgets('★★ 列带**互不重叠**（改前：中间列被第 0 列吞掉）',
          (WidgetTester tester) async {
        await _pump(tester, _doc(c.value));
        final EnvGrid g = _rig(tester).grid;
        for (var i = 0; i + 1 <= g.maxCol; i++) {
          final Rect a = g.colBand[i]!;
          final Rect b = g.colBand[i + 1]!;
          expect(a.right, lessThanOrEqualTo(b.left + 0.5),
              reason: '第 $i 列 ${a.left.toStringAsFixed(1)}..${a.right.toStringAsFixed(1)} '
                  '与第 ${i + 1} 列 ${b.left.toStringAsFixed(1)}..${b.right.toStringAsFixed(1)} '
                  '**重叠** ⇒ 命中会串列（改前 col0 一直伸到 90.2）');
        }
      });

      testWidgets('★★ 每格中心点出的都是**它自己**（行、列都要对）',
          (WidgetTester tester) async {
        await _pump(tester, _doc(c.value));
        final ({RenderBox root, EnvGrid grid}) r = _rig(tester);
        for (var row = 0; row <= r.grid.maxRow; row++) {
          for (var col = 0; col <= r.grid.maxCol; col++) {
            final Rect cb = r.grid.colBand[col]!;
            final Rect band = r.grid.rowBand[row]!;
            final EnvCellHit? hit = envCellHitIn(
                r.grid, Offset(cb.center.dx, band.center.dy));
            expect(hit?.row, row,
                reason: '点第 $row 行第 $col 列的中心 ⇒ 行必须是 $row，实际 ${hit?.row}');
            expect(hit?.col, col,
                reason: '点第 $row 行第 $col 列的中心 ⇒ 列必须是 $col，实际 ${hit?.col}'
                    '（改前：中间列一律落到第 0 列）');
          }
        }
      });

      testWidgets('★★ 同一行里点各列 ⇒ 光标**严格递增**（改前：第 2 列 ≡ 第 1 列）',
          (WidgetTester tester) async {
        final DocBuffer buf = await _pump(tester, _doc(c.value));
        final ({RenderBox root, EnvGrid grid}) r = _rig(tester);
        // 取**最后一行**（整行都是空格子）—— 这一行最容易被串列
        final int row = r.grid.maxRow;
        final Rect band = r.grid.rowBand[row]!;
        var prev = -1;
        for (var col = 0; col <= r.grid.maxCol; col++) {
          final Rect cb = r.grid.colBand[col]!;
          buf.setCaret(buf.buf.length);
          await tester.pumpAndSettle();
          await tester.tapAt(
              r.root.localToGlobal(Offset(cb.center.dx, band.center.dy)));
          await tester.pumpAndSettle();
          expect(buf.caret, greaterThan(prev),
              reason: '第 $row 行第 $col 列的光标（${buf.caret}）必须比上一列（$prev）**更靠右**'
                  '（改前第 2 列给出的是第 1 列的位置）');
          prev = buf.caret;
        }
      });

      testWidgets('★ 格子矩形不许伸进**下一列**（改前：(0,0) 变成 74.2..90.2 = 中间列那块）',
          (WidgetTester tester) async {
        await _pump(tester, _doc(c.value));
        final EnvGrid g = _rig(tester).grid;
        for (var row = 0; row <= g.maxRow; row++) {
          for (var col = 0; col + 1 <= g.maxCol; col++) {
            final Rect? cell = g.cell(row, col);
            if (cell == null) continue;
            final Rect next = g.colBand[col + 1]!;
            expect(cell.right, lessThanOrEqualTo(next.left + 0.5),
                reason: '第 ($row,$col) 格的矩形 ${cell.left.toStringAsFixed(1)}..'
                    '${cell.right.toStringAsFixed(1)} 伸进了第 ${col + 1} 列'
                    '（${next.left.toStringAsFixed(1)} 起）'
                    ' ⇒ 它的矩形被"格子里那个结构的子槽"顶掉了（改前正是这样）');
          }
        }
      });
    });
  }
}
