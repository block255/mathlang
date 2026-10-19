// 多行环境（`aligned` / `cases`）的**格子落点**（P2-D，2026-10-18）
//
// 要解决的现象（用户实测）：
//   `aligned` 一行里**只有 `=` 有墨迹**，其它位置是空白 ⇒ 旧的"最近字形"判据把远处点击吸到 `=`
//   （甚至是**另一行**的 `=`）⇒ "点哪落哪"在环境里不成立。
//
// 判据：先把**格子**当单位——
//   ① 每个格子的矩形 = 落在它源区间里的原子组外框（`PairGroup.hull`）的并集；
//   ② 按 y 认**行**（同 `row` 的格子外框并集 = 行带；tap 落在哪条带里）；
//   ③ 行内按 x 认**列**（点在某格矩形内 ⇒ 那格；否则取最近的格）；
//   ④ 格子内再按 x 决定落在"内容首 / 内容尾"。
//   空格子没有墨迹 ⇒ 没有矩形 ⇒ 用**同一列的其它行**的 x 边界当它的边界（对齐保证同列 x 相同）。
//
// 返回的是**行列坐标**（不是偏移）：源 tex 与渲染 tex 的格子顺序一致，
//   由调用方在**源空间**里换成偏移，避免注入垫子造成的偏移映射问题。

import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import 'caret_sites.dart';
import 'leaf_boxes.dart';
import 'leaf_pairing.dart';

/// 一次格子落点的结果：第几行、第几列、落在该格哪一侧。
class EnvCellHit {
  const EnvCellHit(this.row, this.col, {required this.atEnd, this.onInk = false});

  final int row;
  final int col;

  /// ★ 点是否落在**这一格有墨迹的内容上**（而不是格子里的空白）。
  /// 用途：点在字与字之间时，调用方要能用**细粒度**命中（落到两个符号之间），
  /// 而不是被压到格首/格尾。
  final bool onInk;

  /// `true` = 落在这格**内容的末尾**（右侧）；`false` = 内容开头。
  final bool atEnd;

  @override
  String toString() => 'EnvCellHit($row,$col,${atEnd ? "尾" : "首"})';
}

/// 命中某个格子；`null` = 这次点击不该按"格子"处理（不是环境 / 量不到几何）。
///
/// ★★★ 2026-10-19 **重写**（用户："矩阵和行列式就重写这一块的代码"）。
/// 旧实现的三个硬伤（探针都复现过）：
///   ① 格子矩形只认"原子组的**起点**落在我这个槽里"（包含判据）⇒ 有字迹的格子有时算不出来；
///   ② 列是"扫到第一个命中就返回"⇒ **右边空列永远轮不到**（实测：点空列判成第 2 列）；
///   ③ 行带 / 列带只由**有墨迹**的格子并出来 ⇒ 空行、空列根本不存在，只能靠"最近"猜。
/// 新实现 = **网格**：格子矩形（含填充垫）→ 行带 → 列带 → 先选行再选列。
EnvCellHit? envCellHitAt({
  required RenderObject root,
  required Offset localPos,
  required String tex,
  required bool displayStyle,
}) {
  final CaretSiteTable t = buildCaretSites(tex);
  final List<SlotSpan> cells = t.slots
      .where((SlotSpan s) =>
          s.path.any((SlotStep st) => st.row != null || st.col != null))
      .toList();
  if (cells.isEmpty) return null;

  final List<LeafBox> boxes = scanLeafBoxes(root).eligible;
  if (boxes.isEmpty) return null;
  final LeafPairing pairing = buildLeafPairing(
    tex: tex,
    boxes: boxes,
    atoms: renderOrderAtoms(tex, displayStyle: displayStyle),
  );

  int rowOf(SlotSpan s) => s.path.last.row ?? 0;
  int colOf(SlotSpan s) => s.path.last.col ?? 0;
  int keyOf(int r, int c) => r * 1000 + c;

  final int maxRow =
      cells.map(rowOf).reduce((int a, int b) => a > b ? a : b);
  final int maxCol =
      cells.map(colOf).reduce((int a, int b) => a > b ? a : b);

  // ① 每个格子的矩形：**区间相交**判据（不再用"起点落在里面"）
  final Map<int, Rect> cellRect = <int, Rect>{};
  for (final SlotSpan s in cells) {
    Rect? r;
    for (final PairGroup g in pairing.groups) {
      if (g.srcEnd <= s.start || g.srcStart >= s.end) continue;
      final Rect h = g.hull(boxes);
      if (h.width <= 0 && h.height <= 0) continue;
      r = r == null ? h : r.expandToInclude(h);
    }
    if (r != null) cellRect[keyOf(rowOf(s), colOf(s))] = r;
  }

  // ② 行带 = 该行所有格子矩形（含填充垫）的并集
  final Map<int, Rect> rowBand = <int, Rect>{};
  cellRect.forEach((int k, Rect r) {
    final int row = k ~/ 1000;
    rowBand[row] =
        rowBand.containsKey(row) ? rowBand[row]!.expandToInclude(r) : r;
  });
  if (rowBand.isEmpty) return null;
  final double rowH = estimateRowHeight(rowBand.values.toList());
  for (var r = 0; r <= maxRow; r++) {
    if (rowBand.containsKey(r)) continue;
    Rect? anchor;
    var anchorRow = -1;
    for (var q = r + 1; q <= maxRow; q++) {
      if (rowBand.containsKey(q)) {
        anchor = rowBand[q];
        anchorRow = q;
        break;
      }
    }
    if (anchor == null) {
      for (var q = r - 1; q >= 0; q--) {
        if (rowBand.containsKey(q)) {
          anchor = rowBand[q];
          anchorRow = q;
          break;
        }
      }
    }
    if (anchor == null) continue;
    final double h = rowH > 0 ? rowH : anchor.height;
    final double top = anchorRow > r
        ? anchor.top - (anchorRow - r) * h
        : anchor.bottom + (r - anchorRow - 1) * h;
    rowBand[r] = Rect.fromLTRB(anchor.left, top, anchor.right, top + h);
  }

  // ③ 列带 = 该列所有格子矩形的并集（空列同样补：按邻列 + 列间距外推）
  final Map<int, Rect> colBand = <int, Rect>{};
  cellRect.forEach((int k, Rect r) {
    final int col = k % 1000;
    colBand[col] =
        colBand.containsKey(col) ? colBand[col]!.expandToInclude(r) : r;
  });
  final List<int> knownCols = colBand.keys.toList()..sort();
  double colGapEstimate = 0;
  if (knownCols.length >= 2) {
    final List<double> gaps = <double>[];
    for (var i = 1; i < knownCols.length; i++) {
      final int dc = knownCols[i] - knownCols[i - 1];
      if (dc <= 0) continue;
      gaps.add((colBand[knownCols[i]]!.left - colBand[knownCols[i - 1]]!.left) / dc);
    }
    if (gaps.isNotEmpty) {
      gaps.sort();
      colGapEstimate = gaps[gaps.length ~/ 2];
    }
  }
  if (colGapEstimate <= 0) colGapEstimate = rowH > 0 ? rowH : 16;
  for (var c = 0; c <= maxCol; c++) {
    if (colBand.containsKey(c)) continue;
    Rect? anchor;
    var anchorCol = -1;
    for (var q = c + 1; q <= maxCol; q++) {
      if (colBand.containsKey(q)) {
        anchor = colBand[q];
        anchorCol = q;
        break;
      }
    }
    if (anchor == null) {
      for (var q = c - 1; q >= 0; q--) {
        if (colBand.containsKey(q)) {
          anchor = colBand[q];
          anchorCol = q;
          break;
        }
      }
    }
    if (anchor == null) continue;
    final double w = anchor.width > 0 ? anchor.width : colGapEstimate;
    final double left = anchorCol > c
        ? anchor.left - (anchorCol - c) * colGapEstimate
        : anchor.right + (c - anchorCol - 1) * colGapEstimate;
    colBand[c] = Rect.fromLTRB(left, anchor.top, left + w, anchor.bottom);
  }

  // ④ 选行：含 → 否则最近（按带中心）
  var row = 0;
  var bestD = double.infinity;
  for (var r = 0; r <= maxRow; r++) {
    final Rect? band = rowBand[r];
    if (band == null) continue;
    if (localPos.dy >= band.top && localPos.dy <= band.bottom) {
      row = r;
      break;
    }
    final double d = (band.center.dy - localPos.dy).abs();
    if (d < bestD) {
      bestD = d;
      row = r;
    }
  }

  // ⑤ 选列：含 → 否则最近
  var col = 0;
  bestD = double.infinity;
  for (var c = 0; c <= maxCol; c++) {
    final Rect? band = colBand[c];
    if (band == null) continue;
    if (localPos.dx >= band.left && localPos.dx <= band.right) {
      col = c;
      break;
    }
    final double d = (band.center.dx - localPos.dx).abs();
    if (d < bestD) {
      bestD = d;
      col = c;
    }
  }

  // ⑥ 该格不存在（理论上不会）⇒ 取最近的已有格子
  final bool exists =
      cells.any((SlotSpan s) => rowOf(s) == row && colOf(s) == col);
  if (!exists) {
    SlotSpan? near;
    var nd = double.infinity;
    for (final SlotSpan s in cells) {
      final Rect? rb = rowBand[rowOf(s)];
      final Rect? cb = colBand[colOf(s)];
      if (rb == null || cb == null) continue;
      final double d = (rb.center.dy - localPos.dy).abs() +
          (cb.center.dx - localPos.dx).abs();
      if (d < nd) {
        nd = d;
        near = s;
      }
    }
    if (near == null) return null;
    row = rowOf(near);
    col = colOf(near);
  }

  final Rect? cell = cellRect[keyOf(row, col)];
  final Rect? cb = colBand[col];
  final bool atEnd = cell != null
      ? localPos.dx > cell.center.dx
      : (cb != null && localPos.dx > cb.center.dx);
  final bool onInk = cell != null && cell.inflate(2).contains(localPos);
  return EnvCellHit(row, col, atEnd: atEnd, onInk: onInk);
}
/// 把格子坐标换成**源空间**偏移（用于点击落点）。
///
/// ★★ 2026-10-18 晚（用户实测"点矩阵里面一定落在括号外面 / 落在格子之间的 `&` 上"）：
///   格子的槽区间**含两边的填充空格**（`\begin{pmatrix} A & B …` 里第一格是 `[16,18)`，
///   而 18 正好是 `&`）⇒ 旧代码 `atEnd` 直接返回 `s.end`，光标就停在**分隔符**上，
///   视觉上像"落在格子外面"。
///   ⇒ 返回**去掉首尾空白后的内容边界**：`atEnd` 给内容末尾（`A` 之后那一格），
///     `!atEnd` 给内容开头。空格子（没有内容）⇒ 首=尾=那个空位置本身。
int? envCellOffset(String sourceTex, EnvCellHit hit) {
  final CaretSiteTable t = buildCaretSites(sourceTex);
  for (final SlotSpan s in t.slots) {
    final int? row = s.path.last.row;
    final int? col = s.path.last.col;
    if (row != hit.row || col != hit.col) continue;
    var a = s.start;
    while (a < s.end && (sourceTex[a] == ' ' || sourceTex[a] == '\t')) {
      a++;
    }
    var b = s.end;
    while (b > a && (sourceTex[b - 1] == ' ' || sourceTex[b - 1] == '\t')) {
      b--;
    }
    return hit.atEnd ? b : a;
  }
  return null;
}

/// 供调用方判断"这段 tex 里有没有多行环境"
bool hasEnv(String tex) => tex.contains(r'\begin{');

/// 行高估计（用于给"空行"造带）——环境里每行高度一致，取中位数即可
double estimateRowHeight(List<Rect> rects) {
  if (rects.isEmpty) return 0;
  final List<double> hs = rects.map((Rect r) => r.height).toList()..sort();
  return hs[hs.length ~/ 2];
}

/// 给测试用：把若干矩形按 y 分组成行带
List<Rect> groupRowBands(List<Rect> rects) {
  if (rects.isEmpty) return const <Rect>[];
  final List<Rect> sorted = List<Rect>.of(rects)
    ..sort((Rect a, Rect b) => a.center.dy.compareTo(b.center.dy));
  final List<Rect> bands = <Rect>[];
  for (final Rect r in sorted) {
    if (bands.isEmpty) {
      bands.add(r);
      continue;
    }
    final Rect last = bands.last;
    final bool sameRow =
        r.center.dy >= last.top && r.center.dy <= last.bottom;
    bands[bands.length - 1] = sameRow ? last.expandToInclude(r) : r;
  }
  return bands;
}

/// 夹取工具（避免调用方自己写 clamp 时搞错边界）
int clampOffset(int v, int length) => math.max(0, math.min(v, length));