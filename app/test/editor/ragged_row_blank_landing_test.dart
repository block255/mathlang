// ★ 2026-11-04（表批 B① 收口）：**参差行右侧空白**的点击落点。
//
// 现场（探针实测）：`\begin{bmatrix}a&b&c\\d\end{bmatrix}` 第 2 行只有 1 格，
// 但矩阵按 3 列撑开 ⇒ 那一行右边有一大片**没有墨迹**的空白。点它：
//   · x≈24–40 ⇒ 落 `d` 的格末（off 23）✅
//   · x≈44    ⇒ **落块前（off 0）** ❌
//   · x≈48–56 ⇒ **落块末（off 36）** ❌
//
// 根因链（`doc_view._mathTapTexOffset`）：
//   ① `hitTestMathTex` 没点中墨迹 ⇒ `onGlyph=false`，最近字形盒是**上一行**的 `b`；
//   ② `envCellHitAt` 按几何网格给出**幽灵格** (1,1)（`synthetic`，`onInk=false`）；
//   ③ `envCellOffset(tex,(1,1))` ⇒ **null**（源里这一行没有第 2 格）；
//   ④ 没有"该行最后真实格"的兜底 ⇒ 掉到 `envNearestEdge` ⇒ 块前 / 块后。
//
// 口径（本守卫钉住）：**点在短行右侧空白 ⇒ 落该行最后一格的内容末尾**；
// 并且**点击这条路也不许把光标送到块外**（`0` / `tex.length` 都不行）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/lang/env_table.dart';
import 'package:mathlang/render/env_cells.dart';
import 'package:mathlang/render/math_caret.dart';

import '../support/math_fonts.dart';

const String kRagged = r'\begin{bmatrix}a&b&c\\d\end{bmatrix}';

String _doc(String tex) => '${r'$$'}\n$tex\n${r'$$'}';

void main() {
  setUpAll(() async => loadMathFonts());

  testWidgets('参差行：短行右侧空白 ⇒ 落该行最后一格的内容末尾（不是块前/块后）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final DocBuffer buf = DocBuffer(_doc(kRagged))..setCaret(0);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
    ));
    tester.state<EditViewState>(find.byType(EditView)).focusInput();
    await tester.pumpAndSettle();

    final EnvTable t = envTablesIn(kRagged).first;
    final int bodyStart = t.bodyStart;
    final int bodyEnd = t.bodyEnd;
    final int blockEnd = kRagged.length;
    // 期望落点：第 2 行最后一格（`d`）的内容末尾 —— 用同一个 `envCellOffset` 求，
    // 免得测试自己写死数字（口径是"该行最后一格末尾"，不是"23"）。
    final int expectOff = envCellOffset(
      kRagged,
      EnvCellHit(1, t.rows[1].length - 1, atEnd: true, onInk: false),
    )!;

    // 短行行带里扫一遍（从 `d` 右边一路到右括号里侧）。
    // ★ 相邻两档必须 **≥8px**：`_onTapReport` 的连击判据是"**真实时钟** <400ms +
    //   距离 <6px"（`DateTime.now()`，不受 `tester.pump` 控制）⇒ 4px 间隔会被判成
    //   双击/三击（变成选词/选单元，光标被挪走）—— 探针里踩过一次，量出来的是假的。
    const List<double> xs = <double>[24, 32, 40, 48, 56, 64, 72, 80];
    for (final double x in xs) {
      buf.setCaret(0);
      await tester.pumpAndSettle();
      // ★ 坐标必须**每次重取**（点完光标会跳、滚动视图会动）
      final RenderBox root = find
          .byType(MathWithCaret)
          .last
          .evaluate()
          .single
          .renderObject! as RenderBox;
      final Rect cell = envCellBoxAt(
        root: root,
        tex: kRagged,
        displayStyle: true,
        row: 1,
        col: 0,
        fontSize: 20,
        envIx: 0,
      )!;
      await tester.pump(const Duration(milliseconds: 400)); // 避开双击判定
      await tester.tapAt(root.localToGlobal(Offset(x, cell.center.dy)));
      await tester.pumpAndSettle();
      final int off = buf.caret - 3; // `$$\n` = 3
      expect(off, expectOff, reason: 'x=$x 应落该行最后一格末尾（$expectOff）');
      expect(off, isNot(0), reason: 'x=$x 落到块前了');
      expect(off, isNot(blockEnd), reason: 'x=$x 落到块末了');
      expect(off >= bodyStart && off <= bodyEnd, isTrue,
          reason: 'x=$x 落到环境体外（off=$off，body=[$bodyStart,$bodyEnd]）');
    }
  });
}
