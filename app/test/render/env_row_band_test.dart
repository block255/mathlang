// ★★ L19 守卫：环境的**行带几何**（2026-10-19）
//
// 用户四张图报的现象（原文）：
//  ①「部分填写的行的空位的占位框和空行的空位的占位框**高度好像不太一样**」
//  ②「这个 4 列 5 行矩阵，我在第三行第三列填了之后，**第四行和第五行再次出现占位框和光标偏下**」
//  ③「你看像这里这个**最下行的占位框一半都跑出去了**」· 行列式也有
//
// 探针量出来的事实（4 列 5 行、display、字号 20）：
//  · 空格子的填充垫 `\rule{1em}{0pt}` 的 y **就是那一行的基线**：16.8 / 40.8 / 64.8 / 88.8 / 112.8；
//  · **行距恰好 24**（= 1.2 × 字号；行内 text 样式 19.2 = 1.2 × 16），
//    **根盒高 = 行数 × 行距**（5×24 = 120、6×24 = 144），首行基线在 **0.7 × 行距**；
//  · 旧代码用"内容字形盒的并集"当行带 ⇒ 有字的行 21~25 高、空行只有零高垫子（带高 0）⇒
//    补出来的带**顶在基线上**（低 18.9 px）、最后一行铺到根盒之外（底 133.8 > 120）。
//
// 本文件只认**引擎自己的行格**：`band_r = [基线_r − 0.7·行距, +1 行距)`。

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/env_cells.dart';
import 'package:mathlang/render/leaf_boxes.dart';
import 'package:mathlang/render/math_caret.dart';

import '../support/math_fonts.dart';

/// 用户的用例：4 列 5 行，左上 2×2 填满、第 3 行第 3 列 `3`、第 4 行第 2 列 `2`、第 5 行全空。
const String kUserEnv =
    r'\begin{pmatrix} a & b & & \\ c & d & & \\ & & 3 & \\ & 2 & & \\ & & & \end{pmatrix}';

/// 行列式 5×5（用户第 4 张图：只填左上 2×2，最下行的框跑出去）。
const String kDet5 =
    r'\begin{vmatrix} a & b & & & \\ c & d & & & \\ & & & & \\ & & & & \\ & & & & \end{vmatrix}';

/// 行内（text 样式）3 行 2 列：行距 19.2 ≠ 24 ⇒ 顺带证明**没有写死行距**。
const String kInline3 = r'甲$\begin{pmatrix} a & \\ c & d \\ & \end{pmatrix}$乙';

String _doc(String tex) => '${r'$$'}\n$tex\n${r'$$'}';

Future<DocBuffer> _pump(WidgetTester tester, String doc) async {
  tester.view.physicalSize = const Size(1400, 1600);
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

({RenderBox root, EnvGrid grid, List<LeafBox> boxes}) _rig(WidgetTester tester) {
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
    displayStyle: w.mathStyle == MathStyle.display,
    fontSize: w.fontSize,
  );
  expect(g, isNotNull, reason: '环境必须能量出网格');
  return (root: root, grid: g!, boxes: scanLeafBoxes(root).eligible);
}

/// 垫子的 y（= 基线）：去重后升序。
List<double> _baselines(List<LeafBox> boxes) {
  final Set<double> ys = <double>{
    for (final LeafBox b in boxes)
      if (b.kind == LeafBoxKind.pad && b.rect.height.abs() < 0.5)
        (b.rect.top * 10).roundToDouble() / 10,
  };
  return ys.toList()..sort();
}

void main() {
  setUpAll(() async => loadMathFonts());

  group('⑫ 行带 = 引擎自己的行格（高度恒等 / 不重叠 / 正好铺满根盒）', () {
    testWidgets('★★ 4 列 5 行部分填写：五条带**等高、首尾相接、铺满根盒**',
        (WidgetTester tester) async {
      await _pump(tester, _doc(kUserEnv));
      final ({RenderBox root, EnvGrid grid, List<LeafBox> boxes}) r = _rig(tester);
      final EnvGrid g = r.grid;
      expect(g.maxRow, 4);
      final Rect band0 = g.rowBand[0]!;
      // ① 等高（改前：21 / 21 / 25 / 25 / 21 —— 用户看到的"高度不一样"）
      for (var i = 0; i <= g.maxRow; i++) {
        expect(g.rowBand[i]!.height, closeTo(band0.height, 0.01),
            reason: '第 $i 行带高 ${g.rowBand[i]!.height} 必须与第 0 行 '
                '${band0.height} 相同（用户："框高度好像不太一样"）');
      }
      // ② 首尾相接、**不重叠**（改前：r1 底 46.6 > r2 顶 45.9 —— 含 y 的命中会串行）
      for (var i = 0; i + 1 <= g.maxRow; i++) {
        expect(g.rowBand[i]!.bottom, closeTo(g.rowBand[i + 1]!.top, 0.01),
            reason: '第 $i / ${i + 1} 行带必须首尾相接（不许重叠、不许留缝）');
      }
      // ③ 正好铺满**根盒**（改前：底 133.8 > 根盒 120）
      expect(band0.top, closeTo(0, 1.5), reason: '第 0 行带的顶应当就是矩阵的顶');
      expect(g.rowBand[g.maxRow]!.bottom,
          closeTo(r.root.size.height, 1.5),
          reason: '最后一行带的底应当就是矩阵的底（不许跑出去）');
      // ④ 高度 = 行距 24（= 1.2 × 字号 20），不是"字形盒高度的中位数"
      expect(band0.height, closeTo(24.0, 0.6),
          reason: '行距是引擎给的 24（1.2 × 20），实测 ${band0.height}');
    });

    testWidgets('★★ 行列式 5×5（只填左上 2×2）：同样铺满，最下行的框不越出根盒',
        (WidgetTester tester) async {
      await _pump(tester, _doc(kDet5));
      final ({RenderBox root, EnvGrid grid, List<LeafBox> boxes}) r = _rig(tester);
      final EnvGrid g = r.grid;
      final Rect last = g.rowBand[g.maxRow]!;
      expect(last.bottom, lessThanOrEqualTo(r.root.size.height + 0.5),
          reason: '最后一行带底 ${last.bottom} 越出了根盒 ${r.root.size.height}'
              '（用户第 4 张图："一半都跑出去了"）');
      final Rect box = envCellBoxIn(g, g.maxRow, 0)!;
      expect(box.bottom, lessThanOrEqualTo(r.root.size.height + 0.5),
          reason: '最下行的**格框**也不许越出根盒');
      expect(box.height, closeTo(g.rowBand[0]!.height, 0.01),
          reason: '最下行的框高必须与第一行相同');
    });

    testWidgets('★ 行内（text 样式）：行距 19.2，同样铺满 —— 证明没有写死 24',
        (WidgetTester tester) async {
      await _pump(tester, kInline3);
      final ({RenderBox root, EnvGrid grid, List<LeafBox> boxes}) r = _rig(tester);
      final EnvGrid g = r.grid;
      expect(g.maxRow, 2, reason: '行内矩阵是 3 行');
      expect(g.rowBand[0]!.height, closeTo(19.2, 0.6),
          reason: '行内行距 = 1.2 × 16 = 19.2，实测 ${g.rowBand[0]!.height}');
      expect(g.rowBand[2]!.bottom, closeTo(r.root.size.height, 1.5));
    });
  });

  group('⑬ 格框对得上"那一行"（框、光标、打出来的字同一个行格）', () {
    testWidgets('★★ "部分填写的空位" 与 "空行的空位" 框高一致、框顶同一相对位置',
        (WidgetTester tester) async {
      await _pump(tester, _doc(kUserEnv));
      final ({RenderBox root, EnvGrid grid, List<LeafBox> boxes}) r = _rig(tester);
      final EnvGrid g = r.grid;
      final Rect partial = envCellBoxIn(g, 0, 2)!; // 第一行第三列（这一行有 a、b）
      final Rect emptyRow = envCellBoxIn(g, 4, 0)!; // 第五行（整行都空）
      expect(partial.height, closeTo(emptyRow.height, 0.01),
          reason: '两个框高必须一致：部分填写 ${partial.height} vs 空行 ${emptyRow.height}');
      // 相对位置：框底到基线的距离 = 0.3 × 框高（引擎自己就是 0.7 / 0.3 切一格）
      final List<double> baselines = _baselines(r.boxes);
      expect(baselines.length, greaterThanOrEqualTo(5), reason: '每一行都该有垫子基线');
      for (final int row in <int>[0, 2, 4]) {
        final Rect box = envCellBoxIn(g, row, row == 2 ? 0 : 2)!;
        final double b = baselines[row];
        expect(box.top, lessThan(b), reason: '第 $row 行的框顶必须在基线上方（改前顶在基线上 ⇒ 偏下）');
        expect(box.bottom, greaterThan(b), reason: '框必须**含住**基线');
        expect(b - box.top, closeTo(box.height * 0.7, 0.6),
            reason: '第 $row 行：框顶到基线应当是 0.7 个格高');
      }
    });

    testWidgets('★★ 每一行的"带中点"都命中它自己（独占区间 ⇒ 不许串行）',
        (WidgetTester tester) async {
      await _pump(tester, _doc(kUserEnv));
      final ({RenderBox root, EnvGrid grid, List<LeafBox> boxes}) r = _rig(tester);
      final EnvGrid g = r.grid;
      final Rect col = g.colBand[0]!;
      for (var row = 0; row <= g.maxRow; row++) {
        final Rect band = g.rowBand[row]!;
        final Offset p = Offset(col.center.dx, band.center.dy);
        final EnvCellHit? hit = envCellHitIn(g, p);
        expect(hit?.row, row,
            reason: '点第 $row 行带的中心 y=${band.center.dy} ⇒ 必须命中第 $row 行，'
                '实际 ${hit?.row}');
      }
    });
  });

  group('⑭ 端到端：画出来的**框与竖条**都在那一行里（像素级）', () {
    /// 画出来的格框 + 竖条（只取"有格框"的那一个 painter）
    ({List<SlotPad> pads, Rect bar, bool caretVisible})? painted(
        WidgetTester tester) {
      for (final RenderObject ro in tester.allRenderObjects) {
        if (ro is RenderCustomPaint &&
            ro.foregroundPainter is MathCaretPainter) {
          final MathCaretPainter p =
              ro.foregroundPainter! as MathCaretPainter;
          if (p.pads.isEmpty) continue;
          return (pads: p.pads, bar: p.rect, caretVisible: p.caretVisible);
        }
      }
      return null;
    }

    testWidgets('★★ 点最后一行（整行空）⇒ 框与竖条**同 y 同高**、且都不越出矩阵',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, _doc(kUserEnv));
      final ({RenderBox root, EnvGrid grid, List<LeafBox> boxes}) r = _rig(tester);
      final List<double> bases = _baselines(r.boxes);
      expect(bases.length, greaterThanOrEqualTo(5), reason: '五行都该有垫子基线');
      // ★ 用**物理位置**点：最后一行基线上方 8 px（字身所在的高度），不依赖行带表
      final Rect col = r.grid.colBand[1]!;
      final Offset global =
          r.root.localToGlobal(Offset(col.center.dx, bases.last - 8));
      buf.setCaret(0);
      await tester.tapAt(global);
      await tester.pumpAndSettle();

      final int lastSep = buf.buf.lastIndexOf(r'\\');
      expect(buf.caret, greaterThan(lastSep),
          reason: '点最后一行 ⇒ 光标必须落在最后一个 `\\\\` 之后，实际 ${buf.caret}（$lastSep）');

      final ({List<SlotPad> pads, Rect bar, bool caretVisible})? p =
          painted(tester);
      expect(p, isNotNull, reason: '空格子里必须有格框与竖条');
      expect(p!.pads.length, 1, reason: '只给**当前格**画框，实际 ${p.pads.length} 个');
      final Rect box = p.pads.single.rect;
      // ① 框不许越出矩阵（用户第 3/4 张图："最下行的占位框一半都跑出去了"）
      expect(box.bottom, lessThanOrEqualTo(r.root.size.height + 0.5),
          reason: '框底 ${box.bottom} 越出矩阵根盒 ${r.root.size.height}');
      expect(box.top, greaterThanOrEqualTo(-0.5),
          reason: '框顶 ${box.top} 跑到矩阵上面去了');
      // ② 竖条与框**同 y 同高**（P10 的契约，这里从**画出来的东西**验）
      expect(p.bar.top, closeTo(box.top, 0.01), reason: '竖条与框必须同顶');
      expect(p.bar.height, closeTo(box.height, 0.01), reason: '竖条与框必须同高');
    });

    testWidgets('★ 点第 4 行（有 `2` 的那一行）⇒ 落在第 4 行，不是第 3 / 第 5 行',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, _doc(kUserEnv));
      final ({RenderBox root, EnvGrid grid, List<LeafBox> boxes}) r = _rig(tester);
      final List<double> bases = _baselines(r.boxes);
      final Rect col = r.grid.colBand[2]!; // 第 3 列（第 4 行这一格是空的）
      final Offset global =
          r.root.localToGlobal(Offset(col.center.dx, bases[3] - 8));
      buf.setCaret(0);
      await tester.tapAt(global);
      await tester.pumpAndSettle();
      final int seps1 = buf.buf.indexOf(r'\\');
      final int seps2 = buf.buf.indexOf(r'\\', seps1 + 2);
      final int seps3 = buf.buf.indexOf(r'\\', seps2 + 2);
      final int seps4 = buf.buf.indexOf(r'\\', seps3 + 2);
      expect(buf.caret, greaterThan(seps3),
          reason: '必须在第 3 个行分隔符之后（= 第 4 行），实际 ${buf.caret}、分隔符 $seps3');
      expect(buf.caret, lessThanOrEqualTo(seps4 + 1),
          reason: '也不许越过第 4 个分隔符（= 掉进第 5 行），实际 ${buf.caret}、分隔符 $seps4');
    });
  });
}
