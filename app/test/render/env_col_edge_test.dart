// ★★★ 2026-10-24（批 22 ①）：**列左缘那个像素归左边那一格**。
//
// 用户实测（六张图第一张）：在**左格**打 `v`，光标在 `v` 后面（左格里），
//   可**右边的框**冒出来了 —— 打字却仍然进第 1 列。
// 机制：`&` 不占宽度 ⇒「左格末尾」与「右格开头」**是同一根 x**（= 右列的左缘）；
//   打完字光标落在偏移 16（`=` 之前），锚点被注入到**右列起点**
//   ⇒ 按"含"判据判成右格 ⇒ 框画到右格。
// 口径：那个像素属于**左格末尾**（与批 21「点 `=` 左边 ⇒ 落左格」一致）⇒ 往左让一列。
//   ★ 真正在右格里（`=` 之后）的光标 x 在 `=` 右缘之外，离右列左缘 ≥15px ⇒ 不会误伤。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/env_cells.dart';

/// 造一个两行两列的最小网格：左列 0..12、右列 18..34（中间 6px 是列间距）
EnvGrid grid() {
  final Map<int, Rect> cell = <int, Rect>{};
  final Map<int, Rect> rowBand = <int, Rect>{};
  final Map<int, Rect> colBand = <int, Rect>{};
  for (var r = 0; r < 2; r++) {
    rowBand[r] = Rect.fromLTWH(0, r * 24.0, 40, 24);
    for (var c = 0; c < 2; c++) {
      final double left = c == 0 ? 0 : 18;
      final double right = c == 0 ? 12 : 34;
      cell[r * 1000 + c] = Rect.fromLTRB(left, r * 24.0, right, r * 24.0 + 24);
    }
  }
  colBand[0] = const Rect.fromLTRB(0, 0, 12, 48);
  colBand[1] = const Rect.fromLTRB(18, 0, 34, 48);
  return EnvGrid(cell, rowBand, colBand, 1, 1);
}

void main() {
  test('★★ 正落在右列左缘（= 左格末尾那个像素）⇒ 归**左边**那一格', () {
    final EnvGrid g = grid();
    // 右列左缘 18.0：这就是"`&` 那根零宽像素"，属于左格末尾
    for (final double x in <double>[18.0, 17.5, 19.0, 19.4]) {
      final EnvCellHit? h = envCellHitIn(g, Offset(x, 12));
      expect(h?.col, 0, reason: 'x=$x 应归左列（改前：判成右列 ⇒ 框画到右格）');
    }
  });

  test('★ 真正在右格里（离左缘 1.5px 以上）⇒ 仍然是右列', () {
    final EnvGrid g = grid();
    for (final double x in <double>[20.0, 26.0, 33.0]) {
      final EnvCellHit? h = envCellHitIn(g, Offset(x, 12));
      expect(h?.col, 1, reason: 'x=$x 应归右列');
    }
  });

  test('★ 左格内部 / 右侧空白不受影响', () {
    final EnvGrid g = grid();
    expect(envCellHitIn(g, const Offset(6, 12))?.col, 0);
    expect(envCellHitIn(g, const Offset(40, 12))?.col, 1, reason: '再往右仍按"最近列"');
  });

  test('★ 行判定不受影响（第二行）', () {
    final EnvGrid g = grid();
    expect(envCellHitIn(g, const Offset(18.0, 36))?.row, 1);
    expect(envCellHitIn(g, const Offset(18.0, 36))?.col, 0,
        reason: '第二行同一个像素也归左列');
  });
}
