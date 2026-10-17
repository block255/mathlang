// 数语引擎 · 「点屏幕 → 源偏移」命中映射
//
// 两侧按**引擎的渲染顺序**配对（`leaf_pairing.dart`）：
//   渲染侧 = 有效叶盒（`leaf_boxes.dart`，分字形/垫子两类）
//   结构侧 = 可见原子（`visible_atoms.dart` 词法 ＋ `renderOrderAtoms` 重排）
//
// ★★ 2026-10-17 换了判据（旧判据见下）：以前是"**第 k 个叶盒 ↔ 第 k 个原子**、
//   两列长度相等才算可靠"。探针量出两列**天然不等**：
//   · `\sin x` = 4 盒 / 2 原子（`\sin` 画成 s、i、n 三个字形盒）
//   · `\sum_{i=1}^{n}a_i` 的**盒序 ≠ 源序**（引擎把上限画在算子之前）
//   ⇒ 旧判据下"含多字母算子名的公式点了没反应"，而"数量碰巧相等"的那些又**点 A 落 B**。
//   现在改成：**一个原子吃掉它该占的那几个盒 ＋ 用"盒子画的是什么字"对账**，
//   对不上就整份判为不完整（调用方退回 ③-B 的结构层落点 —— 宁可粗，不许错）。
//
// 详见 `leaf_pairing.dart` 文件头（引擎的五条渲染顺序规则，全部探针实测）
// 与《位点与结构导航》§11.24 六 / §11.26 三 / §11.29。

import 'package:flutter/rendering.dart';

import 'leaf_boxes.dart';
import 'leaf_pairing.dart';
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
    this.pairing,
  });

  /// 命中得到的源偏移；`null` = 没命中，或两列**没对上**（映射不可靠）
  final int? offset;

  final int boxIndex;

  /// 命中的原子在**渲染顺序**原子表里的下标（不可靠时为 -1）
  final int atomIndex;

  /// `包含命中` / `外扩命中` / `就近命中(x px)`
  final String how;

  /// ★ **这一下真的点在某个字形盒上吗**（包含 / 外扩命中 = `true`；"就近"兜底 = `false`）。
  ///
  /// 为 `false` 时调用方**不该**用 [offset]（那是"最近的字形"，可能隔着结构边界 ——
  /// 实测：点分式右端的装饰区会被判成"点分母"）⇒ 应当走
  /// `structure_geometry.glyphlessLanding`（§5.2 归属表）。
  final bool onGlyph;

  /// 两列是否**全部对上**（`leaf_pairing.LeafPairing.complete`）
  final bool reliable;

  final int boxCount;
  final int atomCount;

  /// 命中盒的矩形（诊断 / 调试用）
  final Rect? boxRect;

  /// 这一份配对的完整结果（诊断用；调用方一般只用 [offset] / [reliable]）
  final LeafPairing? pairing;

  @override
  String toString() => reliable
      ? 'MathHit(#$boxIndex ↔ 原子#$atomIndex → 段内 $offset, $how)'
      : 'MathHit(不可靠：${pairing?.reason ?? "无配对"}；'
          '叶盒 $boxCount / 原子 $atomCount, $how)';
}

/// 本段**字形盒高度的中位数** —— 用来认"被拉伸的行盒"（高度远超它就不是正常一个字）。
///
/// 为什么用中位数而不是字号/em：① `hit_map` 只知道 tex，不知道字号；
/// ② 上下标本来就矮、大算符本来就高，**中位数**天然落在"这一段的常见行高"上
/// （实测 `\sum_{i=1}^{n}a_i`：盒高 [14, 46, 14, 18, 18, 21, 14] ⇒ 中位数 **18**，
///  而 `\sum` 的 46 > 1.6×18 ⇒ 被判为拉伸盒并裁到 18 ✓）。
double _medianGlyphHeight(List<LeafBox> boxes) {
  final List<double> hs = <double>[
    for (final LeafBox b in boxes)
      if (b.kind == LeafBoxKind.glyph) b.rect.height,
  ];
  if (hs.isEmpty) return 0;
  hs.sort();
  return hs[hs.length ~/ 2];
}

/// 在 Math 控件内做命中测试。
///
/// [localPos] 是相对 Math 根盒（`root`）的坐标；[tex] 是该段**渲染用的** tex。
/// [atoms] 可以预先算好复用（同一段 tex 反复命中时省一次词法化 + 区域表）——
/// ★ 必须是**渲染顺序**（`renderOrderAtoms(tex, displayStyle: …)` 的产物）。
/// [displayStyle] 决定"堆叠的上下限"（见 `leaf_pairing.dart` 规则 3）。
MathHit hitTestMathTex({
  required RenderObject root,
  required Offset localPos,
  required String tex,
  List<VisibleAtom>? atoms,
  double inflate = 2.0,
  bool displayStyle = false,
}) {
  final LeafBoxScan scan = scanLeafBoxes(root);
  final List<LeafBox> boxes = scan.eligible;
  final List<VisibleAtom> list =
      atoms ?? renderOrderAtoms(tex, displayStyle: displayStyle);
  final LeafPairing pairing = buildLeafPairing(
    tex: tex,
    boxes: boxes,
    atoms: list,
  );

  // ★★ **拉伸的行盒要按行高裁剪**（2026-10-17，用户实测"点 `n` 后面落到 ∑ 与 `a_i` 之间"）：
  //   `\sum` 的字形盒是引擎给的**行盒** —— 实测 **28.9 × 46**，把上限 `n`（y −2.6..11.4）
  //   与下限 `i=1`（y 43.4..61.4）的格子**整片盖住** ⇒ "第一个包含点的盒"总是它
  //   ⇒ 点上限右边、点下限 `i` 后面，都落到 `\sum` 的左右半（= 结构之前/之后）。
  //   ⇒ 命中时把"高度远超本段常见行高"的盒**竖直裁到行高**（横向不动）。
  //   ★ 判据用本段**字形盒高度的中位数**（不写死 em）：本段大多数盒就是正常字的高度。
  final double rowH = _medianGlyphHeight(boxes);
  Rect hitRect(int i) {
    final Rect r = boxes[i].rect;
    if (rowH <= 0 || r.height <= rowH * 1.6) return r;
    return Rect.fromCenter(center: r.center, width: r.width, height: rowH);
  }

  // ★ 两趟命中（S3-2 实测修正）：
  //   只做"外扩后第一个包含"的话，**前一个盒会把点抢走** ——
  //   例：盒子 2 = x41..57、盒子 3 = x57..68，点 x=58 明明在盒子 3 内部，
  //   却先被盒子 2 的外扩矩形（39..59）匹配到 → 结果整整差一个原子。
  //   所以：**严格包含优先**，都落空时才退回"外扩 + 就近"。
  var hit = -1;
  for (var i = 0; i < boxes.length; i++) {
    if (hitRect(i).contains(localPos)) {
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
      if (hitRect(i).inflate(inflate).contains(localPos)) {
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
      final double d = (hitRect(i).center - localPos).distance;
      if (d < best) {
        best = d;
        hit = i;
      }
    }
    how = '就近命中(${best.toStringAsFixed(1)}px)';
    onGlyph = false; // 只是"最近"，不是真的点中了
  }

  final PairGroup? g = hit >= 0 ? pairing.groupOfBox(hit) : null;
  final bool reliable = hit >= 0 && pairing.complete && g != null;
  int? offset;
  if (reliable) {
    // 点在**这一组的外框**左半 → 取区间左端；右半 → 取右端。
    // （多字母算子名是一组 3 个盒 ⇒ 点 `s` 的左半 = `\sin` 之前，点 `n` 的右半 = 之后。）
    offset = localPos.dx < g.hull(boxes).center.dx ? g.srcStart : g.srcEnd;
  }

  return MathHit(
    offset: offset,
    boxIndex: hit,
    atomIndex: reliable ? list.indexOf(g.atom) : -1,
    how: how,
    reliable: reliable,
    boxCount: boxes.length,
    atomCount: list.length,
    boxRect: (hit >= 0 && hit < boxes.length) ? boxes[hit].rect : null,
    onGlyph: onGlyph,
    pairing: pairing,
  );
}
