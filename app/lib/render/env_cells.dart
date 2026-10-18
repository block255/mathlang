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
import 'visible_atoms.dart';

/// 一次格子落点的结果：第几行、第几列、落在该格哪一侧。
class EnvCellHit {
  const EnvCellHit(this.row, this.col, {required this.atEnd});

  final int row;
  final int col;

  /// `true` = 落在这格**内容的末尾**（右侧）；`false` = 内容开头。
  final bool atEnd;

  @override
  String toString() => 'EnvCellHit($row,$col,${atEnd ? "尾" : "首"})';
}

/// 命中某个格子；`null` = 这次点击不该按"格子"处理（不是环境 / 量不到几何）。
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
  final List<VisibleAtom> atoms =
      renderOrderAtoms(tex, displayStyle: displayStyle);
  final LeafPairing pairing =
      buildLeafPairing(tex: tex, boxes: boxes, atoms: atoms);

  int rowOf(SlotSpan s) => s.path.last.row ?? 0;
  int colOf(SlotSpan s) => s.path.last.col ?? 0;

  // 每个格子的外框（落在它源区间里的原子组外框的并集）
  Rect? hullOf(SlotSpan s) {
    Rect? r;
    for (final PairGroup g in pairing.groups) {
      final bool inside = g.srcStart >= s.start && g.srcStart <= s.end;
      if (!inside) continue;
      final Rect h = g.hull(boxes);
      r = r == null ? h : r.expandToInclude(h);
    }
    return r;
  }

  final Map<String, Rect?> hulls = <String, Rect?>{
    for (final SlotSpan s in cells) '${rowOf(s)},${colOf(s)}': hullOf(s),
  };

  // 行带 = 该行所有有墨迹格子的并集
  final Map<int, Rect> rows = <int, Rect>{};
  hulls.forEach((String k, Rect? r) {
    if (r == null) return;
    final int row = int.parse(k.split(',')[0]);
    rows[row] = rows.containsKey(row) ? rows[row]!.expandToInclude(r) : r;
  });
  if (rows.isEmpty) return null;

  // ② 认行：先找"竖直含点击点"的带，再退到最近的带
  int? row;
  for (final MapEntry<int, Rect> e in rows.entries) {
    if (localPos.dy >= e.value.top && localPos.dy <= e.value.bottom) {
      row = e.key;
      break;
    }
  }
  row ??= rows.entries
      .reduce((MapEntry<int, Rect> a, MapEntry<int, Rect> b) {
        final double da = (a.value.center.dy - localPos.dy).abs();
        final double db = (b.value.center.dy - localPos.dy).abs();
        return da <= db ? a : b;
      })
      .key;

  // ③ 认列：这一行里、x 落在哪个格子的矩形里；否则取最近的
  final List<SlotSpan> rowCells =
      cells.where((SlotSpan s) => rowOf(s) == row).toList()
        ..sort((SlotSpan a, SlotSpan b) => colOf(a).compareTo(colOf(b)));
  if (rowCells.isEmpty) return null;

  SlotSpan? pick;
  for (final SlotSpan s in rowCells) {
    final Rect? r = hulls['${rowOf(s)},${colOf(s)}'];
    if (r == null) continue;
    // 列向也留一点宽容度（指向两列之间的空白时归左边那列）
    if (localPos.dx >= r.left - 4 && localPos.dx <= r.right + 4) {
      pick = s;
      break;
    }
  }
  if (pick == null) {
    // 点在该行的空白列：用"同列其它行的 x 边界"求最近列
    double bestDx = double.infinity;
    for (final SlotSpan s in rowCells) {
      final Rect? r = hulls['${rowOf(s)},${colOf(s)}'];
      final double cx = r?.center.dx ??
          _columnAnchor(hulls, colOf(s), rows[row]!) ??
          rows[row]!.left;
      final double d = (cx - localPos.dx).abs();
      if (d < bestDx) {
        bestDx = d;
        pick = s;
      }
    }
  }
  if (pick == null) return null;

  final Rect? cellRect = hulls['${rowOf(pick)},${colOf(pick)}'];
  bool atEnd;
  if (cellRect == null) {
    // 空格子：点在这列左边 ⇒ 内容首；右边 ⇒ 内容尾
    final double anchor = _columnAnchor(hulls, colOf(pick), rows[row]!) ??
        rows[row]!.left;
    atEnd = localPos.dx > anchor;
  } else {
    atEnd = localPos.dx > cellRect.center.dx;
  }
  return EnvCellHit(rowOf(pick), colOf(pick), atEnd: atEnd);
}

/// 某一列在**其它行**里的 x 中心（空格子靠它定位）；都没有 ⇒ null。
double? _columnAnchor(Map<String, Rect?> hulls, int col, Rect rowBand) {
  for (final MapEntry<String, Rect?> e in hulls.entries) {
    final List<String> parts = e.key.split(',');
    if (int.parse(parts[1]) != col) continue;
    final Rect? r = e.value;
    if (r == null) continue;
    return r.center.dx;
  }
  return null;
}

/// 把格子坐标换成**源空间**偏移（用于点击落点）。
int? envCellOffset(String sourceTex, EnvCellHit hit) {
  final CaretSiteTable t = buildCaretSites(sourceTex);
  for (final SlotSpan s in t.slots) {
    final int? row = s.path.last.row;
    final int? col = s.path.last.col;
    if (row != hit.row || col != hit.col) continue;
    return hit.atEnd ? s.end : s.start;
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
