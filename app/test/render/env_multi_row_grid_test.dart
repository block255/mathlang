// ★★ 2026-10-24（批 3 · D3 续）：**3 段以上的分段函数，点第几段落第几段**。
//
// 用户原话：「只有第一段有框；点第 2 段落到第 1 段、点第 4 段落到第 3 段；第 2 段后面还冒出一个位点」。
//
// ★ 探针（2026-10-24）坐实的根因**不是**"几何拿注入后的 tex 量"，而是：
//   **`cases` 的列间距（`&` 那一下）本身就是一个 1em 宽、零高的垫子盒** ——
//   而我们的空格子预留垫 `kEnvCellFillTex = \rule{1em}{0pt}` **也是 1em 宽零高**，
//   两者在"盒"这一层长得一模一样。
//   `_pairOnce` 给垫子原子找盒时是"下一个 pad 盒就是你的"⇒ 列间距盒被当成**格子垫**吃掉
//   ⇒ 从第 2 个垫子开始**整行错位一位**（实测 4 段全空：8 个垫子原子拿到 12 个盒里的前 8 个，
//   于是 r0c1 拿到列间距、r1c0 拿到 r0c1 的垫子…）。
//   行带因此串成 `[0,24) [24,48) [24,48) [48,72)` ⇒ 点 2 落 1、点 4 落 3。
//
// 修法：见 `env_cells.dart` 的 `_envGapBoxes` —— 按"每行有几格空着"算出**期望的垫子序列**
//   （`[格0] 间距 [格1] 间距 …`），个数对得上才认，对不上就**整份不认**（退回老路，不猜）。
//   认出来之后把它们作为 `skip` 交给配对 ⇒ 格子垫各归各位。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/env_cells.dart';
import 'package:mathlang/render/slot_marks.dart';

import '../support/math_fonts.dart';

/// 渲染（走**真实注入链**）并按**生产口径**量网格：`tex` = 注入后的那一份
/// （`math_caret` / `doc_view` 都是这么传的）。
Future<EnvGrid?> _grid(WidgetTester tester, String tex) async {
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
  return buildEnvGrid(root: root, tex: injected, displayStyle: true, fontSize: 20);
}

/// 逐格点它自己的中心 ⇒ 必须落回它自己
void _everyCellLandsOnItself(EnvGrid g, {String? reason}) {
  for (var r = 0; r <= g.maxRow; r++) {
    for (var c = 0; c <= g.maxCol; c++) {
      final Rect? cell = g.cell(r, c);
      expect(cell, isNotNull, reason: '${reason ?? ''} r${r}c$c 没有矩形');
      final EnvCellHit? hit = envCellHitIn(g, cell!.center);
      expect(hit?.row, r,
          reason: '${reason ?? ''} 点 r${r}c$c 中心（${cell.center}）落在 '
              'r${hit?.row}c${hit?.col}');
      expect(hit?.col, c);
    }
  }
}

void main() {
  setUpAll(() async => loadMathFonts());

  testWidgets(r'★ 4 段全空：4 条行带互不重叠，点第几段落第几段', (WidgetTester tester) async {
    const String tex = r'f(x)=\begin{cases}&\\&\\&\\&\end{cases}';
    final EnvGrid? g = await _grid(tester, tex);
    expect(g, isNotNull);
    expect(g!.maxRow, 3, reason: '四段');

    // ① 四条行带：互不重叠、等高、首尾相接（改前是 3 条，第 2/3 段共用一条）
    expect(g.rowBand.length, 4, reason: '改前 r1/r2 串成同一条 ⇒ 只有 3 条');
    for (var r = 0; r < 3; r++) {
      expect(g.rowBand[r]!.bottom, closeTo(g.rowBand[r + 1]!.top, 0.01),
          reason: 'r$r 与 r${r + 1} 必须首尾相接');
    }
    for (var r = 0; r <= 3; r++) {
      expect(g.rowBand[r]!.height, closeTo(24.0, 0.5), reason: 'r$r 行高 = 1.2em');
    }

    // ② 两列不重叠（改前两列带退化成同一条 [80.7,140.7]）
    expect(g.colBand[0]!.right, lessThanOrEqualTo(g.colBand[1]!.left + 0.01),
        reason: 'c0 ${g.colBand[0]} 与 c1 ${g.colBand[1]} 重叠了');

    // ③ 点哪落哪
    _everyCellLandsOnItself(g);
  });

  testWidgets('★ 4 段全空：点击换算成源偏移也逐格对（点哪落哪的最后一公里）',
      (WidgetTester tester) async {
    const String tex = r'f(x)=\begin{cases}&\\&\\&\\&\end{cases}';
    final EnvGrid? g = await _grid(tester, tex);
    expect(g, isNotNull);
    // 源格子的起点：r0c0=18 r0c1=19 r1c0=21 r1c1=22 r2c0=24 r2c1=25 r3c0=27 r3c1=28
    const List<List<int>> expectOffset = <List<int>>[
      <int>[18, 19],
      <int>[21, 22],
      <int>[24, 25],
      <int>[27, 28],
    ];
    for (var r = 0; r <= 3; r++) {
      for (var c = 0; c <= 1; c++) {
        final EnvCellHit? hit = envCellHitIn(g!, g.cell(r, c)!.center);
        expect(hit, isNotNull);
        expect(envCellOffset(tex, hit!), expectOffset[r][c],
            reason: 'r${r}c$c ⇒ $hit');
      }
    }
  });

  testWidgets(r'3 段（首段有字、后两段空）：后两段也要各点得中', (WidgetTester tester) async {
    const String tex = r'f(x)=\begin{cases}1,&x>0\\&-1\\&0\end{cases}';
    final EnvGrid? g = await _grid(tester, tex);
    expect(g, isNotNull);
    expect(g!.maxRow, 2);
    expect(g.rowBand.length, 3);
    for (var r = 0; r < 2; r++) {
      expect(g.rowBand[r]!.bottom, closeTo(g.rowBand[r + 1]!.top, 0.01));
    }
    // 第 2、3 段的第一格是空的 ⇒ 必须有矩形且落在自己那一行
    for (final int r in <int>[1, 2]) {
      final Rect? cell = g.cell(r, 0);
      expect(cell, isNotNull, reason: 'r${r}c0 改前拿到的是别的行的垫子');
      final EnvCellHit? hit = envCellHitIn(g, cell!.center);
      expect(hit?.row, r, reason: '点 r${r}c0 ⇒ $hit');
      expect(hit?.col, 0);
    }
  });

  testWidgets('全填满的矩阵不受影响（列间距不参与配对）', (WidgetTester tester) async {
    const String tex = r'\begin{pmatrix}A&B\\C&D\end{pmatrix}';
    final EnvGrid? g = await _grid(tester, tex);
    expect(g, isNotNull);
    expect(g!.maxRow, 1);
    expect(g.maxCol, 1);
    _everyCellLandsOnItself(g);
  });

  group('★ 6 行 × 2 列（老两列分段模板）：每格都要判到自己', () {
    // 「每行还是有第二个位点」= 两列分段里每行有两个格子；两列 + 多行时
    // 行带曾只剩 5 条（6 行）、列带曾重叠（c0 17.8..105.9 vs c1 57.8..105.9）。
    const String empty6 =
        r'\begin{cases}&\\&\\&\\&\\&\\&\end{cases}';
    const String filled6 =
        r'\begin{cases}&\\&\\1,&x>0\\&\\&\\&\end{cases}';

    testWidgets('全空：6 条行带 + 2 条不重叠的列带', (WidgetTester tester) async {
      final EnvGrid? g = await _grid(tester, empty6);
      expect(g, isNotNull);
      expect(g!.maxRow, 5, reason: '六段');
      expect(g.maxCol, 1);
      expect(g.rowBand.length, 6);
      for (var r = 0; r < 5; r++) {
        expect(g.rowBand[r]!.bottom, closeTo(g.rowBand[r + 1]!.top, 0.01),
            reason: 'r$r / r${r + 1} 必须首尾相接');
      }
      expect(g.colBand[0]!.right, lessThanOrEqualTo(g.colBand[1]!.left + 0.01),
          reason: 'c0 ${g.colBand[0]} 与 c1 ${g.colBand[1]} 不许重叠');
      _everyCellLandsOnItself(g);
    });

    testWidgets('★ 中间一段填了东西：其余各段照旧各判各的', (WidgetTester tester) async {
      final EnvGrid? g = await _grid(tester, filled6);
      expect(g, isNotNull);
      expect(g!.maxRow, 5);
      expect(g.rowBand.length, 6);
      for (var r = 0; r < 5; r++) {
        expect(g.rowBand[r]!.bottom, closeTo(g.rowBand[r + 1]!.top, 0.01),
            reason: 'r$r / r${r + 1} 必须首尾相接（有字的那行也不许把行高撑歪）');
      }
      // 每一格的中心都必须判回它自己（点哪落哪）
      for (var r = 0; r <= 5; r++) {
        for (var c = 0; c <= 1; c++) {
          final Rect? cell = g.cell(r, c);
          expect(cell, isNotNull, reason: 'r${r}c$c');
          final EnvCellHit? hit = envCellHitIn(g, cell!.center);
          expect(hit?.row, r, reason: '点 r${r}c$c ⇒ $hit');
          expect(hit?.col, c, reason: '点 r${r}c$c ⇒ $hit');
        }
      }
    });

    testWidgets('★ 填了一段之后，源偏移仍逐格对', (WidgetTester tester) async {
      final EnvGrid? g = await _grid(tester, filled6);
      expect(g, isNotNull);
      // 源槽：r0c0[13,13) r0c1[14,14) r1c0[16,16) r1c1[17,17)
      //       r2c0[19,21) r2c1[22,25) r3c0[27,27) r3c1[28,28)
      //       r4c0[30,30) r4c1[31,31) r5c0[33,33) r5c1[34,34)
      const List<List<int>> want = <List<int>>[
        <int>[13, 14],
        <int>[16, 17],
        <int>[19, 22],
        <int>[27, 28],
        <int>[30, 31],
        <int>[33, 34],
      ];
      for (var r = 0; r <= 5; r++) {
        for (var c = 0; c <= 1; c++) {
          final EnvCellHit? hit = envCellHitIn(g!, g.cell(r, c)!.center);
          expect(hit, isNotNull);
          expect(envCellOffset(filled6, hit!), want[r][c],
              reason: 'r${r}c$c ⇒ $hit');
        }
      }
    });
  });
}
