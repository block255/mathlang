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
/// 网格（格子矩形 + 行带 + 列带）—— **命中**与**画框**共用同一份几何。
class EnvGrid {
  EnvGrid(this.cellRect, this.rowBand, this.colBand, this.maxRow, this.maxCol);

  /// key = row * 1000 + col
  final Map<int, Rect> cellRect;
  final Map<int, Rect> rowBand;
  final Map<int, Rect> colBand;
  final int maxRow;
  final int maxCol;

  Rect? cell(int r, int c) => cellRect[r * 1000 + c];
}

/// 量出环境的**网格**：每个格子的矩形、行带、列带。
///
/// ★★★ 2026-10-19 重写（用户："矩阵和行列式就重写这一块的代码"）。
/// 旧实现三个硬伤：① 格子矩形用**包含**判据（起点落在槽里）⇒ 有字迹的格子有时算不出来；
/// ② 列是"扫到第一个命中就返回"⇒ 右边空列永远轮不到；
/// ③ 行带/列带只由有墨迹的格子并出来 ⇒ 空行、空列根本不存在。
/// 新实现：格子矩形（含填充垫）→ 列带 → **行带 = 基线 + 行距**（见下面 ③ 的探针数据）；
/// 缺的行列按**中位间距**外推。★ [fontSize] 只在"量不出行距"时兜底（1.2 × 字号）。
EnvGrid? buildEnvGrid({
  required RenderObject root,
  required String tex,
  required bool displayStyle,
  double? fontSize,
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

  // ① 格子矩形：区间相交判据
  final Map<int, Rect> cellRect = <int, Rect>{};
  for (final SlotSpan s in cells) {
    Rect? r;
    for (final PairGroup g in pairing.groups) {
      if (g.srcEnd <= s.start || g.srcStart >= s.end) continue;
      final Rect h = g.hull(boxes);
      if (h.width <= 0 && h.height <= 0) continue;
      r = r == null ? h : r.expandToInclude(h);
    }
    if (r != null) cellRect[rowOf(s) * 1000 + colOf(s)] = r;
  }
  final int maxRow = cells.map(rowOf).reduce((int a, int b) => a > b ? a : b);
  final int maxCol = cells.map(colOf).reduce((int a, int b) => a > b ? a : b);
  if (cellRect.isEmpty) return null;

  // ② 列带 + 补缺列（先算：行带的左右界也用它）
  final Map<int, Rect> colBand = <int, Rect>{};
  cellRect.forEach((int k, Rect r) {
    final int col = k % 1000;
    colBand[col] = colBand.containsKey(col) ? colBand[col]!.expandToInclude(r) : r;
  });
  final List<int> known = colBand.keys.toList()..sort();
  double gap = 0;
  if (known.length >= 2) {
    final List<double> gaps = <double>[];
    for (var i = 1; i < known.length; i++) {
      final int dc = known[i] - known[i - 1];
      if (dc <= 0) continue;
      gaps.add((colBand[known[i]]!.left - colBand[known[i - 1]]!.left) / dc);
    }
    if (gaps.isNotEmpty) { gaps.sort(); gap = gaps[gaps.length ~/ 2]; }
  }
  if (gap <= 0) gap = (fontSize != null && fontSize > 0) ? fontSize : 16;
  final Rect base = colBand[known.first]!;
  for (var c = 0; c <= maxCol; c++) {
    if (colBand.containsKey(c)) continue;
    final double left = base.left + (c - known.first) * gap;
    colBand[c] = Rect.fromLTRB(left, base.top, left + (base.width > 0 ? base.width : gap), base.bottom);
  }

  // ③ 行几何 = **基线 + 行距**（独占区间）
  //
  // ★★★ 2026-10-19（L19；用户四张图："部分填写的空位框与空行的框**高度不一样**"、
  //   "第 4、5 行再次出现框和光标**偏下**"、"最下行的框**一半跑出去**"）。
  //   探针量到的三件事（4 列 5 行、display、字号 20；数据见 `notes\后优化清单.md` §九）：
  //   ① **空格子的填充垫 `\rule{1em}{0pt}` 的 y 就是那一行的基线** ——
  //      逐行 16.8 / 40.8 / 64.8 / 88.8 / 112.8 ⇒ **行距恰好 24.0 = 1.2 × 字号**
  //      （行内 text 样式同样成立：19.2 = 1.2 × 16）；
  //   ② **矩阵根盒高 = 行数 × 行距**（5×24 = 120、6×24 = 144、2×24.03 = 48.1），
  //      而首行基线在 16.8 = **0.7 × 行距** ⇒ **引擎自己把一格切成 0.7 上 / 0.3 下**；
  //   ③ 旧代码把"内容字形盒的并集"当行带 ⇒ 有字的行 21~25 高、**空行只有零高的垫子** ⇒ 带高 0，
  //      补出来的带**顶在基线上**（比字形顶低 18.9 px）⇒ 框与光标偏下、最后一行按"基线 + 行高"铺到
  //      根盒之外（实测底 133.8 > 根盒 120、括号墨迹 133.2）。
  //   ⇒ 正解：`rowBand[r] = [基线_r − 0.7·行距, +1 行距)` —— **高度恒等于行距、行与行不重叠**，
  //     正好铺满引擎自己的行格（探针验证：第 0 行顶 = 0.0、最后一行底 = 根盒底，逐像素相等）。
  //   ★ 基线不必靠"字形"推：**每一个空格子都有一个垫子**，所以只要这一行还有一格是空的，就有精确基线。
  final Map<int, List<double>> anchorOfRow = <int, List<double>>{};
  final Map<int, List<Rect>> inkOfRow = <int, List<Rect>>{};
  cellRect.forEach((int k, Rect r) {
    final int row = k ~/ 1000;
    if (r.height.abs() < 0.5) {
      (anchorOfRow[row] ??= <double>[]).add(r.top); // 零高 ⇒ 垫子 ⇒ 基线
    } else {
      (inkOfRow[row] ??= <Rect>[]).add(r);
    }
  });
  final Map<int, double> baseline = <int, double>{
    for (final MapEntry<int, List<double>> e in anchorOfRow.entries)
      e.key: _medianOf(e.value),
  };
  final List<int> anchors = baseline.keys.toList()..sort();
  double pitch = 0;
  if (anchors.length >= 2) {
    pitch = _medianOf(<double>[
      for (var i = 1; i < anchors.length; i++)
        if (anchors[i] > anchors[i - 1])
          (baseline[anchors[i]]! - baseline[anchors[i - 1]]!) /
              (anchors[i] - anchors[i - 1]),
    ]);
  }
  if (pitch <= 0 && inkOfRow.length >= 2) {
    // 只有一个基线锚点（其余行全填满了）⇒ 用"有内容的那几行"的**字形顶**差估行距。
    // ★ 量出来 `cases` = 24、`aligned` = **30**（它有额外的行间距）⇒ 这里**不能写死 1.2em**。
    final List<int> rows = inkOfRow.keys.toList()..sort();
    final Map<int, double> topOf = <int, double>{
      for (final int r in rows)
        r: inkOfRow[r]!.map((Rect x) => x.top).reduce((double a, double b) => a < b ? a : b),
    };
    pitch = _medianOf(<double>[
      for (var i = 1; i < rows.length; i++)
        if (rows[i] > rows[i - 1])
          (topOf[rows[i]]! - topOf[rows[i - 1]]!) / (rows[i] - rows[i - 1]),
    ]);
  }
  if (pitch <= 0 && fontSize != null && fontSize > 0) pitch = fontSize * 1.2;
  final Map<int, Rect> rowBand = <int, Rect>{};
  if (pitch > 0 && anchors.isNotEmpty) {
    // 缺基线的行（整行都填满的）按最近锚点 + 行距外推
    for (var r = 0; r <= maxRow; r++) {
      if (baseline.containsKey(r)) continue;
      int best = anchors.first;
      for (final int a in anchors) {
        if ((a - r).abs() < (best - r).abs()) best = a;
      }
      baseline[r] = baseline[best]! + (r - best) * pitch;
    }
    final double ascent = 0.7 * pitch;
    var left = double.infinity;
    var right = -double.infinity;
    for (final Rect r in cellRect.values) {
      if (r.left < left) left = r.left;
      if (r.right > right) right = r.right;
    }
    for (var r = 0; r <= maxRow; r++) {
      final double top = baseline[r]! - ascent;
      rowBand[r] = Rect.fromLTRB(left, top, right, top + pitch);
    }
  } else {
    // 兜底（整行都填满的环境 ⇒ 一个垫子都没有、量不出基线）：退回"字形盒并集"当行带。
    // 这种环境里**没有空格子** ⇒ 不画框；行带只服务于命中。
    cellRect.forEach((int k, Rect r) {
      final int row = k ~/ 1000;
      rowBand[row] = rowBand.containsKey(row) ? rowBand[row]!.expandToInclude(r) : r;
    });
  }
  return EnvGrid(cellRect, rowBand, colBand, maxRow, maxCol);
}

/// 中位数（空表 ⇒ 0）
double _medianOf(List<double> xs) {
  if (xs.isEmpty) return 0;
  final List<double> s = List<double>.of(xs)..sort();
  return s[s.length ~/ 2];
}

/// 命中某个格子；`null` = 这次点击不该按"格子"处理。
EnvCellHit? envCellHitAt({
  required RenderObject root,
  required Offset localPos,
  required String tex,
  required bool displayStyle,
  double? fontSize,
}) {
  final EnvGrid? g = buildEnvGrid(
      root: root, tex: tex, displayStyle: displayStyle, fontSize: fontSize);
  return g == null ? null : envCellHitIn(g, localPos);
}

/// 已经在网格上的命中（省一次重建：画框与命中走**同一份**几何）。
EnvCellHit? envCellHitIn(EnvGrid g, Offset localPos) {
  // 选行：含 → 否则最近中心（★ 行带现在是**独占区间**，含判据唯一）
  var row = 0;
  var best = double.infinity;
  for (var r = 0; r <= g.maxRow; r++) {
    final Rect? band = g.rowBand[r];
    if (band == null) continue;
    if (localPos.dy >= band.top && localPos.dy < band.bottom) { row = r; break; }
    final double d = (band.center.dy - localPos.dy).abs();
    if (d < best) { best = d; row = r; }
  }
  // 选列：含 → 否则**到带边缘的距离**（在两列之间的空隙里 ⇒ 归**左边**那一列）
  var col = 0;
  best = double.infinity;
  for (var c = 0; c <= g.maxCol; c++) {
    final Rect? band = g.colBand[c];
    if (band == null) continue;
    if (localPos.dx >= band.left && localPos.dx <= band.right) { col = c; break; }
    final double d = localPos.dx < band.left
        ? band.left - localPos.dx
        : localPos.dx - band.right;
    if (d < best) { best = d; col = c; }
  }
  final Rect? cell = g.cell(row, col);
  final Rect? cb = g.colBand[col];
  final bool atEnd = cell != null
      ? localPos.dx > cell.center.dx
      : (cb != null && localPos.dx > cb.center.dx);
  final bool onInk = cell != null && cell.inflate(2).contains(localPos);
  return EnvCellHit(row, col, atEnd: atEnd, onInk: onInk);
}

/// 第 (row, col) 格的矩形（给"画占位框"用）；没有 ⇒ null。
Rect? envCellRectAt({
  required RenderObject root,
  required String tex,
  required bool displayStyle,
  required int row,
  required int col,
  double? fontSize,
}) {
  final EnvGrid? g = buildEnvGrid(
      root: root, tex: tex, displayStyle: displayStyle, fontSize: fontSize);
  return g?.cell(row, col);
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
/// 第 (row, col) 格的**可视框**（给"画占位框"用）：x/宽取格子矩形，y/高取**行带**。
///
/// ★ 为什么 y 取行带而不取格子矩形：空格子只有零高的填充垫 ⇒ 自己的 y 没有意义；
///   行带是"那一行"的完整高度 ⇒ 框是规整的矩形，不会忽高忽低（用户实测的"框高度不一样"）。
/// ★★ 2026-10-19：行带已是**基线 + 行距**的独占区间 ⇒ 框高恒等于行距、不越出矩阵。
Rect? envCellBoxAt({
  required RenderObject root,
  required String tex,
  required bool displayStyle,
  required int row,
  required int col,
  double? fontSize,
}) {
  final EnvGrid? g = buildEnvGrid(
      root: root, tex: tex, displayStyle: displayStyle, fontSize: fontSize);
  return g == null ? null : envCellBoxIn(g, row, col);
}

/// 已经在网格上的格框。
Rect? envCellBoxIn(EnvGrid g, int row, int col) {
  final Rect? band = g.rowBand[row];
  if (band == null) return null;
  final Rect? cell = g.cell(row, col);
  final Rect? cb = g.colBand[col];
  final double left = cell?.left ?? cb?.left ?? band.left;
  final double right = cell?.right ?? cb?.right ?? band.right;
  return Rect.fromLTRB(left, band.top, right, band.bottom);
}