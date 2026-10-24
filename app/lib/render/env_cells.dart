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
import 'slot_pad.dart';
import 'visible_atoms.dart';

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
  EnvGrid(this.cellRect, this.rowBand, this.colBand, this.maxRow, this.maxCol,
      {this.synthetic = const <int>{}});

  /// key = row * 1000 + col
  final Map<int, Rect> cellRect;
  final Map<int, Rect> rowBand;
  final Map<int, Rect> colBand;
  final int maxRow;
  final int maxCol;

  /// ★ 2026-10-24（D3 续）：这些格子是**补出来的**（原环境里那一格没有墨迹）
  /// ⇒ 框照画，但**不算"点在墨迹上"**（`EnvCellHit.onInk` 的口径不许被它污染）。
  final Set<int> synthetic;

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
  // ★★★ 2026-10-19（L20；用户："矩阵/行列式里放进**带子位点的结构**（根号等）⇒
  //   那个结构的子位点点不到 / 有的格子点不到 / 点不到里面"）。
  //   真根因：**格子坐标不能取"path 里任意带 row/col 的步骤"**。
  //   格子里放 `\sqrt{…}` / `x^2` / `\frac{}{}` 时，**结构自己的槽**会作为**嵌套位点**出现，
  //   它的 path 末尾是 `(row: null, col: null)`。实测（3×3，第 1 行第 2 列放 `\sqrt{2}`）：
  //
  //     slot r0c0 [52,54)  path=(r0,c0)           → 22.2..32.8   ← 真正的 `a`
  //     slot r0c0 [62,78)  path=(r0,c1)(null,null) → 74.2..90.2   ← ★ 顶掉上面那一格
  //     slot r0c1 [55,80)  path=(r0,c1)           → 74.2..90.2
  //
  //   原因是旧判据 `s.path.any(row != null || col != null)` + `?? 0` ⇒ 那个尾垫槽被当成
  //   **第 0 列**的格子、并把它的矩形**覆盖**掉 ⇒ 列带重叠（col0 17.5..90.2 vs col1 63.8..90.2）
  //   ⇒ 命中按"第一个包含的列"取 ⇒ **点中间列落到第 0 列**。
  //   ⇒ 只认**真正的格子槽**：`path` 的**最后一步**同时有 row 和 col。
  //     （嵌套子槽永远不是格子；它的内容已经落在外层格子的区间里。）
  //   ⇒ 判据收进 `SlotSpan.isEnvCell`（只看 path 的**最后一步**，见 caret_sites 里的说明）。
  final List<SlotSpan> cells =
      t.slots.where((SlotSpan s) => s.isEnvCell).toList();
  if (cells.isEmpty) return null;
  final List<LeafBox> boxes = scanLeafBoxes(root).eligible;
  if (boxes.isEmpty) return null;
  int rowOf(SlotSpan s) => s.path.last.row ?? 0;
  int colOf(SlotSpan s) => s.path.last.col ?? 0;
  final int maxRow = cells.map(rowOf).reduce((int a, int b) => a > b ? a : b);
  final int maxCol = cells.map(colOf).reduce((int a, int b) => a > b ? a : b);

  // ★★★ 2026-10-24（D3 续）：**先把"格子垫"从"大家抢"的配对里摘出来**，再量格子。
  //   完整根因与判据见 `_envFillPlan` 的注释（一句话：`&` 的列间距和空格子的垫子
  //   在盒这一层同形，配对会把列间距当成格子垫吃掉 ⇒ 整行错位一位 ⇒ 点 2 落 1）。
  final List<VisibleAtom> atoms = renderOrderAtoms(tex, displayStyle: displayStyle);
  final _EnvFillPlan? plan =
      _envFillPlan(tex: tex, boxes: boxes, cells: cells, atoms: atoms);
  LeafPairing? pairing;
  if (plan != null) {
    final List<VisibleAtom> noFill = <VisibleAtom>[
      for (final VisibleAtom a in atoms)
        if (!plan.fillAtoms.contains(a)) a
    ];
    if (noFill.isEmpty) {
      // ★ 整块环境**一个字都没有**（全空的分段/矩阵）：没有墨迹要配对 ⇒
      //   别去走配对（空的配对会被判"一个组都没配上"而退回老路）。
      pairing = LeafPairing(groups: plan.fillGroups, complete: true);
    } else {
      final LeafPairing p = buildLeafPairing(
        tex: tex,
        boxes: boxes,
        atoms: noFill,
      );
      if (p.complete) {
        pairing = LeafPairing(
          groups: <PairGroup>[...p.groups, ...plan.fillGroups],
          complete: true,
        );
      }
    }
  }
  // 认不出来（有别的垫子混进来）⇒ **整份不认**，退回老路：宁可点不准，也不猜。
  pairing ??= buildLeafPairing(tex: tex, boxes: boxes, atoms: atoms);

  // ① 格子矩形：区间相交判据
  final Map<int, Rect> cellRect = <int, Rect>{};
  for (final SlotSpan s in cells) {
    Rect? r;
    for (final PairGroup g in pairing.groups) {
      if (g.srcEnd <= s.start || g.srcStart >= s.end) continue;
      final Rect? h = _groupInkRect(g, boxes);
      if (h == null) continue;
      r = r == null ? h : r.expandToInclude(h);
    }
    if (r != null) cellRect[rowOf(s) * 1000 + colOf(s)] = r;
  }

  // ★★ 2026-10-24（D3）：**格子全都还空着**的环境（刚插出来的 `cases`）也要有网格 ——
  //   旧代码 `cellRect.isEmpty ⇒ return null` ⇒ 那种块**一个框都不画**（用户："点进去没有框"）。
  //   这种时候没有墨迹可量 ⇒ 按"根盒 ÷ 行列数"均分，行格仍用 0.7 / 1.2 那套常量。
  if (cellRect.isEmpty) {
    final double w = (root is RenderBox && root.hasSize) ? root.size.width : 0;
    final double h = (root is RenderBox && root.hasSize) ? root.size.height : 0;
    if (w <= 0 || h <= 0) return null;
    final int rows = maxRow + 1;
    final int cols = maxCol + 1;
    final double pitch = h / rows;
    final double cw = w / cols;
    final Map<int, Rect> bands = <int, Rect>{};
    final Map<int, Rect> cols2 = <int, Rect>{};
    final Map<int, Rect> cr = <int, Rect>{};
    final Set<int> synth = <int>{};
    for (var r = 0; r < rows; r++) {
      bands[r] = Rect.fromLTRB(0, r * pitch, w, (r + 1) * pitch);
    }
    for (var c = 0; c < cols; c++) {
      cols2[c] = Rect.fromLTRB(c * cw, 0, (c + 1) * cw, h);
    }
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final int k = r * 1000 + c;
        cr[k] = Rect.fromLTRB(cols2[c]!.left, bands[r]!.top, cols2[c]!.right,
            bands[r]!.bottom);
        synth.add(k);
      }
    }
    return EnvGrid(cr, bands, cols2, maxRow, maxCol, synthetic: synth);
  }

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
  // ★★ 2026-10-24（批 3 · E4，用户："分段的第二段我鼠标好像点不到"）：
  //   一个**基线锚点都没有**的环境（整行都没字、连垫子也没配对出来）时，
  //   用引擎自己的行格：**根盒高 = 行数 × 行距**、**首行基线 = 0.7 × 行距**
  //   （两条都是 2026-10-19 实测过的常量，见下面 ③ 的注释）。
  //   旧代码在这种情况下只给"有墨迹的行"建带 ⇒ 空行（如 `cases` 的第二段）**根本不在网格里**
  //   ⇒ 点第二行会被落到第一行（实测：`\begin{cases}1,&x\in Q\\&\end{cases}` 的 grid 只有 1 行）。
  if (pitch <= 0 && root is RenderBox && root.hasSize && maxRow >= 0) {
    final double h = root.size.height;
    if (h > 0) pitch = h / (maxRow + 1);
  }
  final Map<int, Rect> rowBand = <int, Rect>{};
  if (pitch > 0) {
    if (baseline.isEmpty) {
      // 没有任何垫子 ⇒ 按"首行基线 = 0.7 × 行距"铺满（同上实测）
      for (var r = 0; r <= maxRow; r++) {
        baseline[r] = (r + 0.7) * pitch;
      }
    } else {
      // 缺基线的行（整行都填满的）按最近锚点 + 行距外推
      for (var r = 0; r <= maxRow; r++) {
        if (baseline.containsKey(r)) continue;
        int best = anchors.first;
        for (final int a in anchors) {
          if ((a - r).abs() < (best - r).abs()) best = a;
        }
        baseline[r] = baseline[best]! + (r - best) * pitch;
      }
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
  // ★★ 2026-10-24（D3 续）：**空格子的矩形**用"列带 × 行带"补出来。
  //   框（`envCellBoxIn`）与命中都读 `cellRect`；不补的话空格子只能退到"列带"，
  //   而列带是**所有行**合并出来的并集 ⇒ 框会看起来落在"别的行有内容的那一列"上
  //   （用户实测："第二排框却在这里"、"点正确的位置反而不出框"）。
  final Set<int> synthetic = <int>{};
  for (var r = 0; r <= maxRow; r++) {
    final Rect? band = rowBand[r];
    if (band == null) continue;
    for (var c = 0; c <= maxCol; c++) {
      final int k = r * 1000 + c;
      if (cellRect.containsKey(k)) continue;
      final Rect? cb = colBand[c];
      final double left = cb?.left ?? band.left;
      final double right = cb?.right ?? band.right;
      if (right <= left) continue;
      cellRect[k] = Rect.fromLTRB(left, band.top, right, band.bottom);
      synthetic.add(k);
    }
  }
  return EnvGrid(cellRect, rowBand, colBand, maxRow, maxCol,
      synthetic: synthetic);
}

/// 一次"格子垫归位"的计划（见 [_envFillPlan]）。
class _EnvFillPlan {
  const _EnvFillPlan({
    required this.fillAtoms,
    required this.fillGroups,
  });

  /// 这些"垫子原子"**不进配对** —— 它们的盒由 [fillGroups] 直接钉死。
  final Set<VisibleAtom> fillAtoms;

  /// 每个空格子一个组：垫子原子 ↔ **它自己那一格**的格子垫盒。
  final List<PairGroup> fillGroups;
}

/// 认出**空格子的格子垫盒**，并把它们从"大家抢"的配对里摘出来。
///
/// ## 要解决的问题（2026-10-24 探针坐实 · 用户："点第 2 段落第 1 段"）
///
/// `cases` / 矩阵的**列间距**（`&` 那一下）在渲染里是一个 **1em 宽、零高的垫子盒**，
/// 而我们给空格子注入的 `kEnvCellFillTex`（`\rule{1em}{0pt}`）**也是 1em 宽零高** —— 同形。
/// `_pairOnce` 给垫子原子找盒时是"下一个 pad 盒就是你的" ⇒ 列间距被当成格子垫吃掉
/// ⇒ **整行错位一位**（实测 4 段全空：8 个垫子原子拿到 12 个盒里的前 8 个，
/// 于是 r0c1 拿列间距、r1c0 拿 r0c1 的垫子…）⇒ 行带串成
/// `[0,24) [24,48) [24,48) [48,72)` ⇒ 点 2 落 1、点 4 落 3。
///
/// ★ 顺带说明：**这不是"几何该按源 tex 量"的问题**（2026-10-23 的猜测）——
///   按源 tex 量只会把同一份错位换到另一套坐标里。真问题在"盒 ↔ 原子"的配对。
///
/// ## 判据（**个数对不上就整份不认**，宁可点不准也不猜）
///
/// 一行从左到右的垫子序列是确定的：
/// `[格0的垫子?] 间距 [格1的垫子?] 间距 … [格N的垫子?]（行尾对齐垫?）`
/// —— 某一格**空着**才有它的垫子（空 = trim 后为空 **或** 已经是 `kEnvCellFillTex`，
/// 与注入侧 `slot_marks.injectSlotMarks` 同一判据）；列与列之间**恒有**一个间距；
/// 行比列窄时引擎还会补**一个**行尾对齐垫（所以每行允许"多一个"）。
/// 按 y 把零高垫子盒分行、按 x 排好，与期望序列逐个对位：
///   · 落到"格垫"位 ⇒ 认成那一格的垫子（**盒 ↔ 原子直接钉死**）
///   · 落到"间距 / 行尾"位 ⇒ 进 skip（不归任何原子）
///
/// 任何一处对不上（多出嵌套结构的尾垫、`\,` 的间距、列数不足的行…）⇒ 返回 null。
_EnvFillPlan? _envFillPlan({
  required String tex,
  required List<LeafBox> boxes,
  required List<SlotSpan> cells,
  required List<VisibleAtom> atoms,
}) {
  // ① 每行有哪几列、哪几格空着
  //
  // ★★ 判据取"这一格里**含**格子垫"（不是"等于"）：光标停在该格时，
  //   注入链会在这格里再塞一个**光标锚点** `\textcolor{#1E88E5}{\rule{0pt}{0pt}}`
  //   ⇒ 格子内容变成 `锚点 + \rule{1em}{0pt}`，"等于"就认不出来（实测：光标一进格子，
  //   后面的点击全部退回错位老路 —— 4 段用例里第 1 击对、第 2 击起错）。
  //   ★ 反过来不会误认：格子垫**只**注入给"trim 后为空"的格子（`slot_marks`），
  //     非空格子里不可能出现它。
  final Map<int, List<int>> colsOfRow = <int, List<int>>{};
  final Set<int> emptyKeys = <int>{};
  for (final SlotSpan s in cells) {
    final int r = s.path.last.row ?? 0;
    final int c = s.path.last.col ?? 0;
    (colsOfRow[r] ??= <int>[]).add(c);
    final String t = tex.substring(s.start, s.end);
    if (t.trim().isEmpty || t.contains(kEnvCellFillTex)) emptyKeys.add(r * 1000 + c);
  }
  for (final List<int> cs in colsOfRow.values) {
    cs.sort();
  }

  // ② 零高垫子盒，按 y 分行、每行按 x 排
  //
  // 一行里的垫子**一定把这一行铺满**：`[格0垫?] [格0的行内对齐垫?] [列间距] [格1垫?] …`
  // —— 格子里的内容比列宽窄时，引擎会**在格内右侧补一个对齐垫**；
  // 格子空着时补的是我们的 1em 格子垫。两者都是零高 pad ⇒ 光看个数分不出来。
  // ★ 实测（用户 2026-10-24 的 `\begin{cases}3&\\&\\…\end{cases}`）：第 1 行是
  //   `[3][10px 对齐垫][列间距][格1垫]` = **3 个垫子**，而我按"每行最多多一个"去对位
  //   ⇒ 把对齐垫当成了列间距、把列间距当成格1垫 ⇒ 整行错位 ⇒ 第 2 段起判定全歪。
  final List<int> padIdx = <int>[
    for (var i = 0; i < boxes.length; i++)
      if (boxes[i].kind == LeafBoxKind.pad && boxes[i].rect.height.abs() < 0.5) i
  ];
  if (padIdx.isEmpty) return null;
  padIdx.sort((int a, int b) {
    final int dy = boxes[a].rect.top.compareTo(boxes[b].rect.top);
    return dy != 0 ? dy : boxes[a].rect.left.compareTo(boxes[b].rect.left);
  });
  final List<List<int>> padRows = <List<int>>[];
  for (final int i in padIdx) {
    final double y = boxes[i].rect.top;
    if (padRows.isEmpty ||
        (boxes[padRows.last.first].rect.top - y).abs() > 1.0) {
      padRows.add(<int>[i]);
    } else {
      padRows.last.add(i);
    }
  }

  // ③ 学"每一格的左缘"。
  //
  // 一行里垫子的**槽位顺序**是确定的：`[格0][间距0][格1][间距1]…`（`2*cols-1` 个槽位），
  // 但槽位后面还可能**跟着行内对齐垫**（格子里的内容比列宽窄时，引擎在格内右侧补一块）。
  // ⇒ **只取每行前 `2*cols-1` 个垫子当槽位**，后面的都当对齐垫忽略。
  // 槽位里放的东西分两种：
  //   · 格子空着 ⇒ 我们的 1em 格子垫，**左缘 = 这一格的左缘**；
  //   · 格子里有内容（或内容不足列宽）⇒ 对齐垫，左缘 = **内容的右缘**（只会更靠右）。
  // ⇒ 同一列取**最小值**就是格子左缘。
  //
  // ★ **只学"这一列里有空格子"的列**：那一列全填满时槽位里只剩对齐垫（左缘是内容右缘）
  //   ⇒ 学出来是假值。实测（3 段 `1,&x>0 / &-1 / &0`）：第 2 列没有空格子 ⇒ 假 colLeft
  //   会把对齐垫当成格子垫 ⇒ 个数对不上 ⇒ 整份不认。
  final int cols =
      cells.map((SlotSpan s) => s.path.last.col ?? 0).reduce((int a, int b) => a > b ? a : b) + 1;
  final List<int> emptyOfCol = List<int>.filled(cols, 0);
  for (final int key in emptyKeys) {
    emptyOfCol[key % 1000]++;
  }
  final int slotsPerRow = 2 * cols - 1;
  final List<double> colLeft = List<double>.filled(cols, double.infinity);
  var learned = 0;
  for (final List<int> g in padRows) {
    if (g.length < slotsPerRow) continue; // 槽位都没铺满（有格子填得满满的）⇒ 这行不当参考
    learned++;
    for (var c = 0; c < cols; c++) {
      if (emptyOfCol[c] == 0) continue;
      final double x = boxes[g[2 * c]].rect.left;
      if (x < colLeft[c]) colLeft[c] = x;
    }
  }
  if (learned == 0) return null;

  // ④ 归位：**左缘落在某个格子左缘上**的垫子才是格子垫；其余（列间距、行内对齐垫）不是原子。
  final List<int> fillBoxes = <int>[];
  final List<int> fillOfCol = List<int>.filled(cols, 0);
  for (final List<int> g in padRows) {
    for (final int box in g) {
      final double x = boxes[box].rect.left;
      for (var c = 0; c < cols; c++) {
        if (emptyOfCol[c] == 0) continue;
        if ((colLeft[c] - x).abs() <= 0.5) {
          fillBoxes.add(box);
          fillOfCol[c]++;
          break;
        }
      }
    }
  }
  // 每一列的格子垫个数必须恰好等于"这一列的空格子数" —— 多一个少一个都是认错了
  for (var c = 0; c < cols; c++) {
    if (fillOfCol[c] != emptyOfCol[c]) return null;
  }

  // ⑤ 垫子原子（按 tex 顺序 = 行主序）↔ 格子垫盒（按 y、x = 行主序）
  final List<VisibleAtom> fillAtoms = <VisibleAtom>[
    for (final VisibleAtom a in atoms)
      if (isPadAtom(a) && tex.substring(a.start, a.end) == kEnvCellFillTex) a
  ]..sort((VisibleAtom a, VisibleAtom b) => a.start.compareTo(b.start));
  if (fillAtoms.length != fillBoxes.length) return null;
  if (fillBoxes.length != emptyKeys.length) return null;
  final List<PairGroup> fillGroups = <PairGroup>[
    for (var i = 0; i < fillBoxes.length; i++)
      PairGroup(
        fillAtoms[i].start,
        fillAtoms[i].end,
        fillBoxes[i],
        fillBoxes[i] + 1,
        fillAtoms[i],
      )
  ];
  return _EnvFillPlan(
    fillAtoms: fillAtoms.toSet(),
    fillGroups: fillGroups,
  );
}

/// **一个组的"墨迹"外框**：只取**字形盒**，垫子盒不算。
///
/// ★★ 2026-10-24（D3 续）：配对时 `peek` 会把"夹在中间的垫子"跳过去，但**不改 `bi`**
///   ⇒ 组的 `[boxFrom, boxTo)` 里常常**挂着前面那个垫子**（列间距、空格子的垫子、行尾对齐垫）。
///   拿 `g.hull()` 当格子矩形，格子就会**向左/向上溢出到邻行邻列**
///   （实测两列布局里 c0 的带被撑到 17.8..105.9，与 c1 重叠 ⇒ 点哪都判到第 0 列）。
///   墨迹才是"这一格里的内容"，垫子是排版细节 ⇒ 只量字形盒。
///
/// 整组没有字形盒（格子垫 / 尾垫这类纯垫子）⇒ 退回整组外框（零高，正好当基线锚点）。
Rect? _groupInkRect(PairGroup g, List<LeafBox> boxes) {
  Rect? r;
  for (var i = g.boxFrom; i < g.boxTo && i < boxes.length; i++) {
    final LeafBox b = boxes[i];
    if (b.kind != LeafBoxKind.glyph) continue;
    if ((b.text ?? '').trim().isEmpty) continue;
    r = r == null ? b.rect : r.expandToInclude(b.rect);
  }
  if (r != null) return r;
  final Rect h = g.hull(boxes);
  if (h.width <= 0 && h.height <= 0) return null;
  return h;
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
  final bool onInk = cell != null &&
      !g.synthetic.contains(row * 1000 + col) &&
      cell.inflate(2).contains(localPos);
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
  // ★★ 2026-10-19（L20）：只认**最后一步是 (row, col)** 的槽，并且在多个匹配里取
  //   **最外层那个**（区间最宽）—— 格子里放结构时会有嵌套子槽，别让它们冒充格子。
  SlotSpan? best;
  for (final SlotSpan s in t.slots) {
    if (s.path.isEmpty) continue;
    final SlotStep st = s.path.last;
    if (st.row != hit.row || st.col != hit.col) continue;
    if (best == null || (s.end - s.start) > (best.end - best.start)) best = s;
  }
  if (best == null) return null;
  var a = best.start;
  while (a < best.end && (sourceTex[a] == ' ' || sourceTex[a] == '\t')) {
    a++;
  }
  var b = best.end;
  while (b > a && (sourceTex[b - 1] == ' ' || sourceTex[b - 1] == '\t')) {
    b--;
  }
  return hit.atEnd ? b : a;
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