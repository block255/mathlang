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

/// 把**左缘对齐、上下分开**的一对"块"的可点横向范围取并集（y 带各自不变）。
///
/// 用户 2026-10-17 的原话：「这个求和的 `n`……取**上下两块的最长者**的长度来决定它们的
/// 点击判定矩形框如何？」⇒ `\sum_{k=2}^{n}` 的上限 `n` 只有 8.4px 宽、下限 `k=2` 25.6px 宽，
/// 两者的可点宽度应当一致（KaTeX 把上下限**左对齐**排：实测都是 x 21.1 起）。
///
/// 做法（纯几何，不动任何渲染）：
///   ① 对本块 `a`（字号级、非拉伸盒），找**左缘对齐**（±2px）、**竖直不相交**且间距 ≤1.5 行高的兄弟块；
///   ② 从那个兄弟块的第一个字形起，沿**同一行**把**相邻**（间隙 ≤1.5px）的字形并成一整块；
///   ③ 把 `a` 的可点横向范围放宽到"本块 ∪ 兄弟整块"。
/// ★ 只改**横向**：竖向各自保留自己的带 ⇒ 分式分数线那一带仍不属于任何字形，
///   ③-B"点装饰区 ⇒ 结构之前/之后"完全不受影响；兄弟块内部各字形**逐个保持原样**（精度不降）。
List<Rect> _widenAlignedScriptBlocks(List<Rect> rects, double rowH) {
  final List<Rect> out = List<Rect>.of(rects);
  if (rects.length < 2 || rowH <= 0) return out;
  bool small(Rect r) => r.height <= rowH * 1.2;
  bool disjointY(Rect a, Rect b) => a.bottom <= b.top + 0.01 || b.bottom <= a.top + 0.01;
  double gapY(Rect a, Rect b) =>
      a.bottom <= b.top ? b.top - a.bottom : a.top - b.bottom;

  for (var i = 0; i < rects.length; i++) {
    final Rect a = rects[i];
    if (!small(a)) continue; // 基座（拉伸的行盒）不参与
    double left = a.left;
    double right = a.right;
    var found = false;

    for (var j = 0; j < rects.length; j++) {
      if (j == i) continue;
      final Rect b = rects[j];
      if (!small(b)) continue;
      if (!disjointY(a, b)) continue;
      if (gapY(a, b) > rowH * 1.5) continue;
      if ((b.left - a.left).abs() > 2.0) continue; // 必须左缘对齐（= 同一列的上下两块）

      // 从 b 起沿同一行把相邻字形并成"整块"
      double l = b.left;
      double r = b.right;
      final double bandTop = b.top;
      final double bandBottom = b.bottom;
      var grew = true;
      while (grew) {
        grew = false;
        for (var k = 0; k < rects.length; k++) {
          final Rect c = rects[k];
          if (!small(c)) continue;
          if (c.top >= bandBottom - 0.01 || c.bottom <= bandTop + 0.01) continue;
          final bool adjacent = c.left <= r + 1.5 && c.right >= l - 1.5;
          final bool outside = c.left < l - 0.01 || c.right > r + 0.01;
          if (adjacent && outside) {
            if (c.left < l) l = c.left;
            if (c.right > r) r = c.right;
            grew = true;
          }
        }
      }
      if (l < left) left = l;
      if (r > right) right = r;
      found = true;
    }
    if (found && right - left > a.width + 0.01) {
      // ★ 只放宽**本行里"孤立"的那个字**：若本行还有别的字形落在放宽后的范围里
      //   （典型＝较宽那一块自己的第一个字，如 k=2 的 k），就不许放宽 ——
      //   否则它会把同块里的 `=` `2` 全吞掉，逐字精度反而变差。
      var occupied = false;
      for (var k = 0; k < rects.length; k++) {
        if (k == i) continue;
        final Rect c = rects[k];
        if (!small(c)) continue;
        // ★ 必须“有实质的竖直重叠”才算同一行：下限块的 = 与 2 和上限 n 的带只重叠 0.5px，
        //   若按“有任何重叠”算，它们会把 n 的放宽判据顶掉（实测踩到）。
        final double ovY = (c.bottom < a.bottom ? c.bottom : a.bottom) -
            (c.top > a.top ? c.top : a.top);
        final double minH = c.height < a.height ? c.height : a.height;
        if (ovY <= minH * 0.3) continue;
        if (c.right > a.left + 0.01 && c.left < right - 0.01) {
          occupied = true;
          break;
        }
      }
      if (!occupied) out[i] = Rect.fromLTRB(left, a.top, right, a.bottom);
    }
  }
  return out;
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

  // ★★ **"上下两块的最长者"**（2026-10-17 用户提出的第二条手感修正）：
  //   见 `_widenLoneBandGlyphs` —— 只放宽"独字带"（如 `\sum_{k=2}^{n}` 的上限 `n`），
  //   多字形的带（下限 `k=2`）逐字精度保持不变。y 带一律不变。
  final List<Rect> cropped = <Rect>[for (var i = 0; i < boxes.length; i++) hitRect(i)];
  final List<Rect> hitRects = _widenAlignedScriptBlocks(cropped, rowH);

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
    if (hitRects[i].contains(localPos)) {
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
      if (hitRects[i].inflate(inflate).contains(localPos)) {
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
      final Rect r = hitRects[i];
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
      final double d = (hitRects[i].center - localPos).distance;
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
      final Rect r = hitRects[i];
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

/// **选区高亮**：把源区间 `[from, to)` 映射成**按叶盒铺底的矩形**（§⑤ 高亮）。
///
/// 为什么按原子铺、而不是给整段公式套一个框：
///   "同权"的意思是**行内公式就是一串字符**，所以拖选时高亮应当跟着**被选中的那几个字符**走
///   （用户原话：「行内的话多项式根本就不是一个整体公式，完全可以丝滑地当作普通文本地拖选处理」）。
///   相邻原子的盒是紧挨着的 ⇒ 看起来就是一条连续的底；下标/上限那个原子会稍微凸出来 ——
///   那正是"公式里的字符"该有的样子。
///
/// ★★ 2026-10-18 晚（用户报「拖选时部分数学没被蓝底覆盖，但确实选中了」）：
///   旧做法是"**每个原子取一次外框**"（`PairGroup.hull`）—— 于是**主行之外的一切**
///   （上限 / 下标 / 环境格子里的字）都被并进主行那个外框里、或者干脆没被铺到。
///   ⇒ 改成**一个叶盒一块**：盒是墨迹的最小单位，上下限、上下标、矩阵格子天然各归各位。
///   ⇒ 顺带的好处：不再需要为每个原子做一次 hull 循环（**线性扫一遍盒**）。
///   ★ 仍然**纯几何**：不改任何尺寸 ⇒ 不影响排版与分页。
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
  // ★ 盒 → 组 的直查表：`groupOfBox` 是线性扫，盒多、组多时是 O(盒×组)；
  //   拖选每帧都要算一次 ⇒ 这里先铺一张 O(盒) 的表（`PairGroup.boxFrom/boxTo` 是区间）。
  final List<PairGroup?> owner = List<PairGroup?>.filled(boxes.length, null);
  for (final PairGroup g in pairing.groups) {
    for (var i = g.boxFrom; i < g.boxTo && i < owner.length; i++) {
      owner[i] = g;
    }
  }
  // ★★ 2026-10-20（用户实测"整段拖选时个别数学块漏底"）：**没有归属的盒按"就近归属"处理**。
  //   配对（`buildLeafPairing`）在某些结构上（例如 `\bigcup_{i=1}^{n}U_{x_i}` 这种
  //   "大算符 + 上下限 + 下标"叠在一起的 display 块）会把一部分叶盒**配不上组**，
  //   旧代码 `if (g == null) continue;` 就把这些盒直接丢掉了 ⇒ 用户看到"这一块里几个字没被选中"。
  //   现在：没主的盒跟**最近的有主盒**（先向前找、找不到再向后找）走 —— 视觉上连续，
  //   而"是否落在选区里"仍由**那个组**的源区间决定（不会把选区外的盒也涂上）。
  final List<PairGroup?> near = List<PairGroup?>.filled(boxes.length, null);
  PairGroup? prevGroup;
  for (var i = 0; i < boxes.length; i++) {
    final PairGroup? g0 = owner[i];
    if (g0 != null) prevGroup = g0;
    near[i] = prevGroup;
  }
  PairGroup? nextGroup;
  for (var i = boxes.length - 1; i >= 0; i--) {
    final PairGroup? g0 = owner[i];
    if (g0 != null) nextGroup = g0;
    if (near[i] == null) near[i] = nextGroup;
  }
  final List<bool> picked = List<bool>.filled(boxes.length, false);
  for (var i = 0; i < boxes.length; i++) {
    final LeafBox b = boxes[i];
    // 垫子 / 空字盒没有墨迹 ⇒ 不铺（它们不是"字符"）
    if (b.kind == LeafBoxKind.pad) continue;
    if ((b.text ?? '').isEmpty) continue;
    final PairGroup? g = owner[i] ?? near[i];
    if (g == null) continue;
    final int a = renderToSourceOffset(tex, g.srcStart);
    final int bb = renderToSourceOffset(tex, g.srcEnd);
    if (bb <= from || a >= to) continue;
    picked[i] = true;
    out.add(b.rect);
  }
  // ★★ 2026-10-20（第三轮实测：`x\in[a,b]` 里的 `∈` 仍然没有底色）：
  //   极少数盒**连"就近归属"都拿不到组**（配对算法在这类紧凑结构上会漏），
  //   于是无论怎么挑都轮不到它 ⇒ 视觉上就是"夹在两个蓝块中间的一个白字"。
  //   兜底：**紧邻已选中盒的墨迹盒**跟着一起铺（选区本来就是连续的字符区间，
  //   不可能"选了两个邻居却漏掉中间这一个"）。只传播一轮，避免越界扩大选区。
  for (var i = 0; i < boxes.length; i++) {
    if (picked[i]) continue;
    final LeafBox b = boxes[i];
    if (b.kind == LeafBoxKind.pad) continue;
    if ((b.text ?? '').isEmpty) continue;
    final bool neighbour = (i > 0 && picked[i - 1]) ||
        (i + 1 < boxes.length && picked[i + 1]);
    if (!neighbour) continue;
    picked[i] = true;
    out.add(b.rect);
  }
  // ★★ 2026-10-20（用户实测"拖选时看着漏字"）：**把同一行相邻的块并成一条**。
  //   每个字形盒单独铺色 ⇒ 盒与盒之间总有 1px 左右的缝，放大看就是"字与字之间漏了"。
  //   合并只按 (top,bottom) 相同的行内、且间隙 ≤0.75px 的块做 —— 上下标/上下限的**行不同**，
  //   所以不会被错误地并成一大块（"按原子铺"这条原则不变，只是把同一行的接上）。
  return mergeBands(out);
}

/// ★★ 2026-10-20（第三轮）：把一个公式的底色**按"视觉行"合成整条**。
///
/// 为什么还要这一步：逐字铺色总会留下"字与字之间的白缝"，而用户拖选时看到的
/// 就是**一条连续的蓝底**。这里把垂直中心落在同一行的块合成一条
/// （分数/上下限/上下标是**不同的行**，各自成条 —— "按原子铺"的层级不变）。
List<Rect> rowBands(List<Rect> rects) {
  if (rects.length < 2) return rects;
  final List<Rect> sorted = <Rect>[...rects]
    ..sort((Rect a, Rect b) => a.center.dy.compareTo(b.center.dy));
  final List<List<Rect>> rows = <List<Rect>>[];
  for (final Rect r in sorted) {
    if (rows.isEmpty) {
      rows.add(<Rect>[r]);
      continue;
    }
    final List<Rect> cur = rows.last;
    final double mid =
        cur.fold<double>(0, (double a, Rect e) => a + e.center.dy) / cur.length;
    final double h = cur.first.height > r.height ? cur.first.height : r.height;
    if ((r.center.dy - mid).abs() <= 0.45 * h) {
      cur.add(r);
    } else {
      rows.add(<Rect>[r]);
    }
  }
  return <Rect>[
    for (final List<Rect> row in rows)
      Rect.fromLTRB(
        row.map((Rect r) => r.left).reduce((double a, double b) => a < b ? a : b),
        row.map((Rect r) => r.top).reduce((double a, double b) => a < b ? a : b),
        row.map((Rect r) => r.right).reduce((double a, double b) => a > b ? a : b),
        row.map((Rect r) => r.bottom).reduce((double a, double b) => a > b ? a : b),
      ),
  ];
}

/// 同一行内相邻/重叠的底色块合并成一条（纯几何，不改任何尺寸）。
List<Rect> mergeBands(List<Rect> rects) {
  if (rects.length < 2) return rects;
  final Map<String, List<Rect>> rows = <String, List<Rect>>{};
  for (final Rect r in rects) {
    final String k = '${r.top.round()}_${r.bottom.round()}';
    (rows[k] ??= <Rect>[]).add(r);
  }
  final List<Rect> out = <Rect>[];
  for (final List<Rect> row in rows.values) {
    row.sort((Rect a, Rect b) => a.left.compareTo(b.left));
    Rect cur = row.first;
    for (var i = 1; i < row.length; i++) {
      final Rect r = row[i];
      if (r.left <= cur.right + 1.5) {
        cur = Rect.fromLTRB(cur.left, cur.top, r.right > cur.right ? r.right : cur.right,
            cur.bottom);
      } else {
        out.add(cur);
        cur = r;
      }
    }
    out.add(cur);
  }
  return out;
}
