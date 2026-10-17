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

import 'injection_map.dart';
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

/// ★★ **行内宽容**（像素）：同一个行带里，点离某个字形水平不超过这个距离，就认作"点在它旁边"。
///
/// 为什么需要它（2026-10-17 用户实测）：字形盒是**精确**的、外扩只有 2px ⇒ 偏 2px 以上就从
/// "精确到某个字"掉成 `glyphlessLanding` 的"**整个结构之前/之后**"。实测那一处：
/// 行内 `A_n = \sum_{k=2}^n |a_k|` 的上标 `n`（盒 68.9,−3.6–80.1,7.4），
/// **右边缘 +2px 就落到 9（= `\sum` 之前）**，只有贴边 0–2px 才落 `n` 之后。
/// ⇒ 取半个正文汉字宽（16px 的一半）：0–8px 都能点中"旁边那个字"。
const double kHitRowSlackPx = 8.0;

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

  // ★★ **行优先**（2026-10-17 用户实测"n 后面还是点不到"）：点在某个字形盒的**竖直范围之内**
  //   （`dy == 0`）⇒ 就落**那一行**里水平最近的那个盒。
  //   为什么必须加这一趟：`\sum` 的节点盒把上下限**整片盖住**，而"点上限右边"那一点
  //   虽然竖直上就落在 `n` 这一行里，却也在 `\sum` 节点的范围里 ⇒ 只按"包含"判就会给 `\sum`。
  //   行优先之后：点 `n` 右边 = `n` 这一行最近的字形 = `n` ⇒ 落 `n` 之后 ✓。
  //   ★ 竖直落在**两行之间**（`dy > 0`，例如分式分数线那一带）⇒ 不算行内命中，
  //     仍走下面的"严格包含 / 外扩 / 就近"⇒ 保留 ③-B（点分式右边 = 结构之后）。
  var hit = -1;
  var how = '';
  var onGlyph = false;

  // ★ 两趟命中（S3-2 实测修正）：
  //   只做"外扩后第一个包含"的话，**前一个盒会把点抢走** ——
  //   例：盒子 2 = x41..57、盒子 3 = x57..68，点 x=58 明明在盒子 3 内部，
  //   却先被盒子 2 的外扩矩形（39..59）匹配到 → 结果整整差一个原子。
  //   所以：**严格包含优先**，都落空时才退回"外扩 + 就近"。
  how = '包含命中';
  for (var i = 0; i < boxes.length; i++) {
    if (hitRect(i).contains(localPos)) {
      hit = i;
      break;
    }
  }
  // ★★ `onGlyph` 必须用**布尔标记**，不能比对 `how` 字符串 ——
  //    最近兜底那个 `how` 带着 `(x px)` 后缀，`how != '就近命中'` 恒真
  //    （实测踩到：③-B 接线后行为完全没变，就是这个判据写错）。
  onGlyph = hit >= 0;
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
  // ★★ **行内宽容**（2026-10-17，用户实测"上标 n 右边稍远一点就跳到 ∑ 之前"）：
  //   竖直落在某个字形盒的带内（= **同一行**）时，取这一行**水平最近**的字形；
  //   距离 ≤ [kHitRowSlackPx] ⇒ 认作"点在它旁边"（仍然 onGlyph ⇒ 走左/右半给端点）。
  //   ★ 安全性：③-B 的两个既有行为都**竖直上不在任何字形带里**
  //     （点分式右侧的装饰区 = 分数线那一带；点公式外侧留白 = 字形并集之外）⇒ 不会被这一档抢走。
  if (hit < 0 && boxes.isNotEmpty) {
    var slackBest = double.infinity;
    var slackHit = -1;
    for (var i = 0; i < boxes.length; i++) {
      final Rect r = hitRect(i);
      if (localPos.dy < r.top - 0.01 || localPos.dy > r.bottom + 0.01) continue;
      final double dx = localPos.dx < r.left
          ? r.left - localPos.dx
          : (localPos.dx > r.right ? localPos.dx - r.right : 0);
      if (dx < slackBest) {
        slackBest = dx;
        slackHit = i;
      }
    }
    if (slackHit >= 0 && slackBest <= kHitRowSlackPx) {
      hit = slackHit;
      how = '行内宽容(${slackBest.toStringAsFixed(1)}px)';
      onGlyph = true;
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

  // ★★ **大盒按行分带**（2026-10-17 用户拍板："∑ 上面这一块隶属于上部子层级，点击上下部不该落在 ∑ 侧面"）：
  //   `\sum` 那种**被拉伸的行盒**（高 46，把上下限整片盖住）一旦被"包含"命中，
  //   就改判成**最近的那一行**（先比竖直距离、再比水平距离）里的字形 —— 于是：
  //   点上限那一带（含 `n` 与主行之间的那条缝）⇒ 上限；点下限那一带 ⇒ 下限；**都不再落到 ∑ 的左右侧**。
  //   ★ 为什么是"最近的**行**"而不是"点必须落在那一行的可见带里"：
  //     上限字形的可见带只有 14 高，而 ∑ 的带从 19.9 才开始 —— 中间那条**缝**（11.4..19.9）
  //     原来谁都不命中，于是落回 ∑（用户实测："偏下一点就落到 ∑ 和 a_i 之间"）。
  //   ★ 只对**拉伸盒**生效：尾垫（零高）、字形、分式分子分母**一律不动**
  //     （否则"点分式右边 ⇒ 结构之后"（③-B）和"点尾垫 ⇒ 结构末尾"（§11.18）会被破坏）。
  if (hit >= 0 && rowH > 0 && boxes[hit].rect.height > rowH * 1.6) {
    var band = -1;
    var bestDy = double.infinity;
    var bestDx = double.infinity;
    for (var i = 0; i < boxes.length; i++) {
      final Rect r = hitRect(i);
      final double dy = localPos.dy < r.top
          ? r.top - localPos.dy
          : (localPos.dy > r.bottom ? localPos.dy - r.bottom : 0);
      final double dx = localPos.dx < r.left
          ? r.left - localPos.dx
          : (localPos.dx > r.right ? localPos.dx - r.right : 0);
      if (dy < bestDy - 0.01 || (dy < bestDy + 0.01 && dx < bestDx)) {
        bestDy = dy;
        bestDx = dx;
        band = i;
      }
    }
    if (band >= 0 && band != hit) {
      hit = band;
      how = '行内命中（大盒按最近的行分带）';
      onGlyph = true;
    }
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

/// **选区高亮**：把源区间 `[from, to)` 映射成**按原子铺底的矩形**（§⑤ 高亮）。
///
/// 为什么按原子铺、而不是给整段公式套一个框：
///   "同权"的意思是**行内公式就是一串字符**，所以拖选时高亮应当跟着**被选中的那几个字符**走
///   （用户原话：「行内的话多项式根本就不是一个整体公式，完全可以丝滑地当作普通文本地拖选处理」）。
///   相邻原子的盒是紧挨着的 ⇒ 看起来就是一条连续的底；下标/上限那个原子会稍微凸出来 ——
///   那正是"公式里的字符"该有的样子。
///
/// ★ 纯几何：不改任何尺寸 ⇒ 不影响排版与分页。
List<Rect> selectionBands({
  required RenderObject root,
  required String tex,
  required int from,
  required int to,
  List<VisibleAtom>? atoms,
  bool displayStyle = false,
}) {
  if (to <= from) return const <Rect>[];
  final List<LeafBox> boxes = scanLeafBoxes(root).eligible;
  final LeafPairing pairing = buildLeafPairing(
    tex: tex,
    boxes: boxes,
    atoms: atoms ?? renderOrderAtoms(tex, displayStyle: displayStyle),
  );
  // ★★ 关键：`PairGroup.srcStart/srcEnd` 是**渲染 tex**（含空槽垫、光标锚点注入）里的偏移，
  //   而调用方给的 `[from, to)` 是**源 tex** 的偏移 ⇒ 必须换回源坐标再比较，
  //   否则一旦这段公式里有空槽/光标注入，整条区间就**错位**（用户实测："复杂结构的
  //   数学语言有的子层级被漏掉"）。`renderToSourceOffset` 就是点击定位用的那个映射。
  final List<Rect> out = <Rect>[];
  for (final PairGroup g in pairing.groups) {
    final int a = renderToSourceOffset(tex, g.srcStart);
    final int b = renderToSourceOffset(tex, g.srcEnd);
    if (b <= from || a >= to) continue;
    out.add(g.hull(boxes));
  }
  return out;
}