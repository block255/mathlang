// 数语引擎 · 渲染叶盒收集（"点屏幕 → 源偏移"的一半）
//
// 路线 (b)：零 src 依赖，见 notes/design/技术选型与风险.md 9.8。

import 'dart:math' as math;

import 'package:flutter/rendering.dart';

/// 叶盒的**三类**（2026-10-17 加：配对需要知道"这个盒是不是墨迹"）。
enum LeafBoxKind {
  /// **字形盒**：`RenderParagraph`，画出来的是字（`text` 是它画的那个字/那串字）。
  glyph,

  /// **垫子盒**：没有墨迹、只占版面 —— 我们注入的空槽宽度垫 / 结构尾垫
  /// （`\rule{…}{0pt}` ⇒ `_RenderColoredBox`，零高），以及引擎自己的零高空白
  /// （`\,` 的 3.3 px、`\limsup` 名内那道空格、`cases` 的列间距）。
  pad,

  /// **不是原子**（不参与配对）：光标锚点/细线装饰/变音字形/失真矢量图。
  spacer,
}

/// 渲染子树里的一个「叶盒」（无子节点的 RenderBox），坐标已换算到 Math 根盒坐标系。
class LeafBox {
  const LeafBox(
    this.rect, {
    this.text,
    this.kind = LeafBoxKind.glyph,
  });

  final Rect rect;

  /// 这个盒**画的是什么**（只有 [LeafBoxKind.glyph] 有）；`null` = 没墨迹。
  ///
  /// ★ 配对靠它把"盒子"和"源码里的字"对上号（§11.24 六 的两种坏法都在这上面收口）。
  final String? text;

  final LeafBoxKind kind;

  bool get isGlyph => kind == LeafBoxKind.glyph;

  @override
  String toString() => 'LeafBox(${kind.name}'
      '${text == null ? '' : ' "$text"'} '
      'x ${rect.left.toStringAsFixed(0)}..'
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

/// 文本是不是**只由私用区码位**组成（`\not` 那条斜杠 = U+E020）
bool _isPrivateUseOnly(String s) {
  if (s.isEmpty) return false;
  for (final int r in s.runes) {
    if (r < 0xE000 || r > 0xF8FF) return false;
  }
  return true;
}

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
///
/// ★★ 2026-10-17：滤完之后再**分三类**（[LeafBoxKind]）—— 配对（`leaf_pairing.dart`）
///   必须知道"这个盒画的是哪个字 / 它是不是只是一块垫子"。原来只留一个 `Rect`，
///   配对只能按下标 zip ⇒ 多字母算子名与"盒序 ≠ 源序"两种坏法都无从发现。
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
    final LeafBox box = _classify(o, rect, maxWidth);
    all.add(box);
    if (box.kind != LeafBoxKind.spacer) eligible.add(box);
  }

  walk(root);

  return LeafBoxScan(eligible: eligible, all: all, maxWidth: maxWidth);
}

/// 这个叶盒**是哪一类**？（四类假叶盒的判据集中在 [spacer] 这一支，见 [scanLeafBoxes]）
LeafBox _classify(RenderObject o, Rect rect, double? maxWidth) {
  LeafBox spacer() => LeafBox(rect, kind: LeafBoxKind.spacer);

  if (rect.width < kMinLeafWidth) return spacer(); // ① 光标条 / 零宽占位
  if (maxWidth != null && rect.width > maxWidth) return spacer(); // ② 失真矢量图
  // ③ 细线装饰：**严格正的极小高度**（尾垫是 0.0 ⇒ 留下，走下面那一支）
  if (rect.height > 0 && rect.height < kMinLeafHeight) return spacer();
  if (o is RenderParagraph) {
    final String text = o.text.toPlainText();
    // ④ 变音字形的装饰（几何上与内容完全重合 ⇒ 只能看它画的是什么）
    if (kDecorationGlyphs.contains(text)) return spacer();
    // ⑤ **叠加装饰字形**（`\not` 一族画的那条斜杠）：码位在**私用区**（U+E000–U+F8FF）。
    //    实测 `a\neq b` 的叶盒 = ["a", **U+E020**, "=", "b"] —— 那条斜杠是**另画的一个字形**，
    //    与 `=` 重合（KaTeX 的 `\not` 就是这个做法）。它不是源码里的一个字 ⇒ 不是原子。
    //    ★ 安全边界：引擎的符号表里**没有一个命令**映射到私用区（2026-10-17 grep 过
    //      `symbols.dart` / `symbols_extra.dart` / `unicode_accents.dart`）⇒ 这条判据不会误杀真原子。
    if (_isPrivateUseOnly(text)) return spacer();
    return LeafBox(rect, text: text, kind: LeafBoxKind.glyph);
  }
  // ★ 剩下的**没有墨迹**：我们自己注入的垫子（零高 `_RenderColoredBox`）
  //   与引擎的零高空白（`\,`、`\limsup` 名内空格、`cases` 列间距）都在这里。
  //   ⇒ 归 `pad`（"占版面但不画字"），配对时按"垫子原子"消费、或作为无害余量跳过。
  return LeafBox(rect, kind: LeafBoxKind.pad);
}
