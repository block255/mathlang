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
/// 要滤掉两类假叶盒（两类都是实测出来的）：
///   ① **装饰盒**：根号分隔符等，由父节点绘制、在 AST 里不是子节点，
///      且 `localToGlobal` 结果尺寸严重失真（实测 x=45..1878，根盒才 74 宽）
///      → 判据 = **宽度上限**（见 [kLeafMaxWidthRatio]）
///   ② **我们自己注入的 `\cursor{}` 光标条**：第一次点击后它才出现在渲染树里
///      → 判据 = 宽度 ≥ [kMinLeafWidth] px
LeafBoxScan scanLeafBoxes(RenderObject root) {
  final Rect bounds = (root is RenderBox && root.hasSize)
      ? (Offset.zero & root.size)
      : Rect.largest;
  final double? maxWidth = bounds.width.isFinite
      ? math.max(bounds.width * kLeafMaxWidthRatio, kLeafMinAbsWidth)
      : null;
  final all = <LeafBox>[];

  void walk(RenderObject o) {
    var hasChild = false;
    o.visitChildren((RenderObject c) {
      hasChild = true;
      walk(c);
    });
    if (!hasChild && o is RenderBox && o.hasSize) {
      all.add(LeafBox(o.localToGlobal(Offset.zero, ancestor: root) & o.size));
    }
  }

  walk(root);

  final eligible = all
      .where((LeafBox b) =>
          b.rect.width >= kMinLeafWidth &&
          (maxWidth == null || b.rect.width <= maxWidth))
      .toList();
  return LeafBoxScan(eligible: eligible, all: all, maxWidth: maxWidth);
}
