// 数语引擎 · 「点屏幕 → 源偏移」命中映射
//
// 两侧按**同一次序** zip：
//   渲染侧 = 有效叶盒（leaf_boxes.dart，两级过滤后）
//   结构侧 = 可见原子（visible_atoms.dart，自己词法化）
// 引擎保证 `GreenNode.children` 顺序 == 光标访问顺序，所以两列可以按下标直接对齐。
// 详见 notes/design/技术选型与风险.md 9.8。

import 'package:flutter/rendering.dart';

import 'leaf_boxes.dart';
import 'visible_atoms.dart';

/// 一次命中的结果。`offset` 是**相对该段 tex 的源偏移**，调用方再加上段的绝对起点。
class MathHit {
  const MathHit({
    required this.offset,
    required this.boxIndex,
    required this.atomIndex,
    required this.how,
    required this.reliable,
    required this.boxCount,
    required this.atomCount,
    this.boxRect,
    this.onGlyph = false,
  });

  /// 命中得到的源偏移；`null` = 没命中，或叶盒数与原子数不等（映射不可靠）
  final int? offset;

  final int boxIndex;
  final int atomIndex;

  /// `包含命中` / `就近命中(x px)`
  final String how;

  /// ★ **这一下真的点在某个字形盒上吗**（包含 / 外扩命中 = `true`；"就近"兜底 = `false`）。
  ///
  /// 为 `false` 时调用方**不该**用 [offset]（那是"最近的字形"，可能隔着结构边界 ——
  /// 实测：点分式右端的装饰区会被判成"点分母"）⇒ 应当走
  /// `structure_geometry.glyphlessLanding`（§5.2 归属表）。
  final bool onGlyph;

  /// 叶盒数与原子数是否一致
  final bool reliable;

  final int boxCount;
  final int atomCount;

  /// 命中盒的矩形（诊断 / 调试用）
  final Rect? boxRect;

  @override
  String toString() => reliable
      ? 'MathHit(#$boxIndex ↔ 原子#$atomIndex → 段内 $offset, $how)'
      : 'MathHit(不可靠：叶盒 $boxCount vs 原子 $atomCount, $how)';
}

/// 在 Math 控件内做命中测试。
///
/// [localPos] 是相对 Math 根盒（`root`）的坐标；[tex] 是该段的源 tex。
/// [atoms] 可以预先算好复用（同一段 tex 反复命中时省一次词法化）。
MathHit hitTestMathTex({
  required RenderObject root,
  required Offset localPos,
  required String tex,
  List<VisibleAtom>? atoms,
  double inflate = 2.0,
}) {
  final LeafBoxScan scan = scanLeafBoxes(root);
  final List<LeafBox> boxes = scan.eligible;
  final List<VisibleAtom> list = atoms ?? lexVisibleAtoms(tex);

  // ★ 两趟命中（S3-2 实测修正）：
  //   只做"外扩后第一个包含"的话，**前一个盒会把点抢走** ——
  //   例：盒子 2 = x41..57、盒子 3 = x57..68，点 x=58 明明在盒子 3 内部，
  //   却先被盒子 2 的外扩矩形（39..59）匹配到 → 结果整整差一个原子。
  //   所以：**严格包含优先**，都落空时才退回"外扩 + 就近"。
  var hit = -1;
  for (var i = 0; i < boxes.length; i++) {
    if (boxes[i].rect.contains(localPos)) {
      hit = i;
      break;
    }
  }

  var how = '包含命中';
  // ★★ `onGlyph` 必须用**布尔标记**，不能比对 `how` 字符串 ——
  //    最近兜底那个 `how` 带着 `(x px)` 后缀，`how != '就近命中'` 恒真
  //    （实测踩到：③-B 接线后行为完全没变，就是这个判据写错）。
  var onGlyph = hit >= 0;
  if (hit < 0) {
    for (var i = 0; i < boxes.length; i++) {
      if (boxes[i].rect.inflate(inflate).contains(localPos)) {
        hit = i;
        how = '外扩命中';
        onGlyph = true;
        break;
      }
    }
  }
  if (hit < 0 && boxes.isNotEmpty) {
    var best = double.infinity;
    for (var i = 0; i < boxes.length; i++) {
      final double d = (boxes[i].rect.center - localPos).distance;
      if (d < best) {
        best = d;
        hit = i;
      }
    }
    how = '就近命中(${best.toStringAsFixed(1)}px)';
    onGlyph = false; // 只是"最近"，不是真的点中了
  }

  final bool reliable = hit >= 0 && boxes.length == list.length;
  int? offset;
  if (reliable) {
    final LeafBox box = boxes[hit];
    final VisibleAtom atom = list[hit];
    // 点在盒子的左半 → 取原子左边界；右半 → 取右边界
    offset = localPos.dx < box.rect.center.dx ? atom.start : atom.end;
  }

  return MathHit(
    offset: offset,
    boxIndex: hit,
    atomIndex: reliable ? hit : -1,
    how: how,
    reliable: reliable,
    boxCount: boxes.length,
    atomCount: list.length,
    boxRect: (hit >= 0 && hit < boxes.length) ? boxes[hit].rect : null,
    onGlyph: onGlyph,
  );
}
