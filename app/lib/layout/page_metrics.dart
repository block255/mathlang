// 数语引擎 · 页面度量：mm → 逻辑 px、页内容盒、页眉预留
//
// 约定：1 mm = 96/25.4 px（Web/CSS 的 1 inch = 96px）。
// 这是**屏幕/排版**用的换算；导出 300 DPI 图片时另有一套（S6）。
//
// 纯 Dart（只依赖 DocSettings），可单测。

import '../core/doc_settings.dart';

/// 1 mm = 多少逻辑 px
const double kPxPerMm = 96 / 25.4;

/// 从 [DocSettings] 算出来的页面几何（全部是逻辑 px）。
class PageGeometry {
  const PageGeometry({
    required this.pageWidth,
    required this.pageHeight,
    required this.marginTop,
    required this.marginBottom,
    required this.marginLeft,
    required this.marginRight,
    required this.headerHeight,
  });

  factory PageGeometry.from(DocSettings s) {
    final bool hasHeader = s.headerText.trim().isNotEmpty;
    return PageGeometry(
      pageWidth: s.pageWidthMm * kPxPerMm,
      pageHeight: s.pageHeightMm * kPxPerMm,
      marginTop: s.marginTopMm * kPxPerMm,
      marginBottom: s.marginBottomMm * kPxPerMm,
      marginLeft: s.marginLeftMm * kPxPerMm,
      marginRight: s.marginRightMm * kPxPerMm,
      // 页眉为空就**不预留**高度（省下一行）
      headerHeight: hasHeader ? s.headerFontSize * 1.6 + 10 : 0.0,
    );
  }

  final double pageWidth;
  final double pageHeight;
  final double marginTop;
  final double marginBottom;
  final double marginLeft;
  final double marginRight;

  /// 页眉占据的高度（含它与正文之间的间距）
  final double headerHeight;

  /// 页内容区宽（= 排版宽度，所有 FlowUnit 都按这个宽度测量与渲染）
  double get contentWidth => pageWidth - marginLeft - marginRight;

  /// 页内容区高（含页眉）
  double get contentHeight => pageHeight - marginTop - marginBottom;

  /// ★ 正文可用高 = 内容区高 − 页眉 —— **分页算法的输入**
  double get bodyHeight => contentHeight - headerHeight;

  @override
  String toString() => 'PageGeometry(page ${pageWidth.toStringAsFixed(1)}x'
      '${pageHeight.toStringAsFixed(1)}, content '
      '${contentWidth.toStringAsFixed(1)}x${contentHeight.toStringAsFixed(1)}, '
      'header ${headerHeight.toStringAsFixed(1)}, body '
      '${bodyHeight.toStringAsFixed(1)})';
}
