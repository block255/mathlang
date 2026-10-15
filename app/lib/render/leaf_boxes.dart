// 数语引擎 · 渲染叶盒收集（"点屏幕 → 源偏移"的一半）
//
// 路线 (b)：零 src 依赖，见 notes/design/技术选型与风险.md 9.8。

import 'dart:math' as math;

import 'package:flutter/rendering.dart';

/// 渲染子树里的一个「叶盒」（无子节点的 RenderBox），坐标已换算到 Math 根盒坐标系。
class LeafBox {
  const LeafBox(this.rect);

  final Rect rect;

  @override
  String toString() => 'LeafBox(x ${rect.left.toStringAsFixed(0)}..'
      '${rect.right.toStringAsFixed(0)}, y ${rect.top.toStringAsFixed(0)}..'
      '${rect.bottom.toStringAsFixed(0)})';
}

/// 过滤标准 ②：我们注入的 `\cursor{}` 竖条宽 1.5px，真原子都 ≥ 2px。
const double kMinLeafWidth = 2.0;

/// 过滤标准 ①：**假叶盒（装饰盒）的特征是"大得离谱"**，不是"越界"。
///
/// ⚠️ **2026-10-15 修正（S3-2 实测推翻了 S1 的判据）**：
/// S1 用的判据是"真原子的矩形必然落在 Math 控件边界内"，**这条不成立** ——
/// 数学字形本来就会画出根盒之外（分子向上溢、分母向下溢）。实测：
///
/// | tex | Math 根盒 | 字形盒 | 老判据结果 |
/// |---|---|---|---|
/// | `x` | 16×**7** | y=-5..11（16 高） | 上边界 -5 < -4 → **误杀** |
/// | `\frac{a}{b}=\sqrt{2}` | 74×29 | 分母 y17..33 | `Rect.contains` 的下边界是**开区间** → **误杀** |
///
/// → 老判据下 6 个样本里只有 1 个"叶盒数 == 原子数"，**点屏幕定位对大多数公式静默失效**。
/// 新判据：真原子的盒宽与根盒同量级；`localToGlobal` 失真的装饰盒则**大出几十倍**
/// （实测根号分隔符 = 1878px 宽 vs 根盒 74px）→ 用**宽度上限**拦它。
const double kLeafMaxWidthRatio = 3.0;

/// 宽度上限的绝对兜底：根盒很窄时（如单个 `x`）给一点余量，避免误杀宽原子。
const double kLeafMinAbsWidth = 32.0;

/// 过滤标准 ③：**细线装饰**（`\overline` / `\underline` 的横线）**自己就是一个叶盒**。
///
/// ★★ 这是**既有 bug 的根因**（2026-10-15 晚探针量出，见设计稿 §11.21.2）：
/// `\overline{AB}` 的横线是 `[0..32.8 × 0..0.6]` = 32.8 × **0.6 px** 的
/// `_RenderColoredBox` ⇒ "叶盒 3 ≠ 原子 2" ⇒ `hitTestMathTex` **静默返回 null**
/// ⇒ **这些结构里点击一直是"点了没反应"**（与尾垫无关，早就存在）。
///
/// **判据取"严格正的极小高度"**（`0 < h < kMinLeafHeight`）——实测：
///
/// | tex | 叶盒节点 | 高 |
/// |---|---|---|
/// | `2` `-` `=` `\cdot` `\alpha` `\sum` `\int` | `RenderParagraph` | **16.0** |
/// | `x^2` 的上标 `2` | `RenderParagraph` | **11.0** |
/// | `\overline{AB}` / `\underline{AB}` 的横线 | `_RenderColoredBox` | **0.6** ← 装饰 |
/// | **我们的尾垫** `\rule{3pt}{0pt}` | `_RenderColoredBox` | **0.0** ← ★ 必须**留下** |
///
/// ⇒ 正常字形叶盒**一律是 `RenderParagraph`，高 11–16**（连 `-` `=` 这种"细字形"也是 16 ——
///   引擎给的是**行高盒**而不是墨迹盒）⇒ 高度下限**不可能误杀真原子**；
///   而尾垫是**零高**（不落在 `(0, 2)` 里）⇒ 它作为"结构末尾"的点击区（§11.18）不受影响 ✓。
const double kMinLeafHeight = 2.0;

/// 过滤标准 ④：**单个变音字形的装饰盒**（`\hat` `\tilde` `\dot` `\ddot` `\bar`）。
///
/// 引擎把 accent 画成**一个字**，于是装饰是一个 `RenderParagraph`，而且
/// **与内容的盒完全重合**（实测两者都是 `[0..16 × -0.9..15.1]`，16 × 16）
/// ⇒ 几何上**分不开**（高度够、宽度够、位置一样）。
/// 唯一可用的判据是**它画的是什么**（实测的 ¶ 文本）：
///
/// | tex | 装饰叶盒 | ¶ 文本 |
/// |---|---|---|
/// | `\hat{x}` | `RenderParagraph` | `^` |
/// | `\tilde{x}` | 同上 | `~` |
/// | `\dot{x}` / `\ddot{x}` | 同上 | `˙` / `¨` |
/// | `\bar{x}` / `\bar{AB}` | 同上 | `ˉ` |
///
/// ★ 这一条与"宽度上限""高度下限"是**同一层判据**：都在回答
/// "这个叶盒**是不是一个可见原子**"，依据都是**渲染事实**（引擎实测，见 §11.21.2）。
///
/// ⚠️ 代价（诚实记账）：用户若把**单独的**变音符号当正文手打进来（`$\text{^}$`），
/// 它也会被摘掉 —— 那种情形会退化成本来的"叶盒数 ≠ 原子数 ⇒ 命中静默 null"（点不动，不会点错），
/// 且由守门人测试的语料覆盖。本仓的主路径（符号面板 / 模板）不会产生它。
/// （`\cdot` 的 ¶ 文本是 `⋅` U+22C5，`\dot` 的是 `˙` U+02D9 —— **不同码位**，
/// 所以下面这张表**只收 `˙`**，`\cdot` 这个真原子不会被误摘 ✓）
const Set<String> kDecorationGlyphs = <String>{
  '^', 'ˆ', // hat
  '~', '˜', // tilde
  '˙', // dot（U+02D9；`\cdot` 的 `⋅` U+22C5 **不在**表里）
  '¨', // ddot
  'ˉ', '¯', // bar
  'ˇ', '˘', '´', '`', '˚', // check / breve / acute / grave / ring（同族，同一机制）
};

/// 一次叶盒扫描的结果。
class LeafBoxScan {
  const LeafBoxScan({
    required this.eligible,
    required this.all,
    this.maxWidth,
  });

  /// 过滤后的**有效叶盒** —— 与「可见原子」一一对应
  final List<LeafBox> eligible;

  /// 过滤前的全部叶盒（诊断用）
  final List<LeafBox> all;

  int get rawCount => all.length;

  /// 宽度上限（超过它的盒 = `localToGlobal` 失真的装饰盒）
  final double? maxWidth;
}

/// 遍历 [root] 的渲染子树，收集所有叶盒，再过滤出**有效叶盒**。
///
/// 要滤掉**四类**假叶盒（四类**全部**是实测出来的，见设计稿 §11.21.2 的数据表）：
///   ① **我们自己注入的 `\cursor{}` 光标条**：第一次点击后它才出现在渲染树里
///      → 判据 = 宽度 ≥ [kMinLeafWidth] px
///   ② **失真的装饰矢量图**（根号 `√`、`\widehat`、`\vec`…）：由父节点绘制、
///      `localToGlobal` 结果尺寸大出几十倍（实测 2364 / 400000 px 宽）
///      → 判据 = **宽度上限**（见 [kLeafMaxWidthRatio]）
///   ③ **细线装饰**（`\overline` / `\underline` 的横线，0.6 px 高）
///      → 判据 = **高度下限**（见 [kMinLeafHeight]；★ 零高的尾垫要留下）
///   ④ **变音字形的装饰**（`\hat` / `\tilde` / `\dot` / `\bar` 的 `^` `~` `˙` `ˉ`）
///      → 判据 = 画的是不是"一个变音符号"（见 [kDecorationGlyphs]）
///
/// ③④ 是 2026-10-15 晚新增：它们让 accent 家族符合守门人（叶盒数 == 原子数），
/// 顺带修好"**accent 里点击一直没反应**"这个既有 bug。
LeafBoxScan scanLeafBoxes(RenderObject root) {
  final Rect bounds = (root is RenderBox && root.hasSize)
      ? (Offset.zero & root.size)
      : Rect.largest;
  final double? maxWidth = bounds.width.isFinite
      ? math.max(bounds.width * kLeafMaxWidthRatio, kLeafMinAbsWidth)
      : null;
  final all = <LeafBox>[];
  final eligible = <LeafBox>[];

  void walk(RenderObject o) {
    var hasChild = false;
    o.visitChildren((RenderObject c) {
      hasChild = true;
      walk(c);
    });
    if (hasChild || o is! RenderBox || !o.hasSize) return;
    final Rect rect = o.localToGlobal(Offset.zero, ancestor: root) & o.size;
    all.add(LeafBox(rect));
    if (_isAtomBox(o, rect, maxWidth)) eligible.add(LeafBox(rect));
  }

  walk(root);

  return LeafBoxScan(eligible: eligible, all: all, maxWidth: maxWidth);
}

/// 这个叶盒**是一个可见原子吗**？（四类假叶盒的判据集中在这一处，见 [scanLeafBoxes]）
bool _isAtomBox(RenderObject o, Rect rect, double? maxWidth) {
  if (rect.width < kMinLeafWidth) return false; // ① 光标条（1.5 px）
  if (maxWidth != null && rect.width > maxWidth) return false; // ② 失真矢量图
  // ③ 细线装饰：**严格正的极小高度**（尾垫是 0.0 ⇒ 留下）
  if (rect.height > 0 && rect.height < kMinLeafHeight) return false;
  // ④ 变音字形的装饰（几何上与内容完全重合 ⇒ 只能看它画的是什么）
  if (o is RenderParagraph && kDecorationGlyphs.contains(o.text.toPlainText())) {
    return false;
  }
  return true;
}
