// 数语引擎 · 文档级排版设置
//
// 约定（2026-10-13 已确认）：字号是**文档级**的（正文 / 标题 1–3 / 行距 / 页边距 / 页眉），
// 局部选中改字号留到行内富文本阶段。
// 纯 Dart，不依赖 Flutter —— 单位换算（mm → 逻辑 px）放在 lib/layout/page_metrics.dart（S2-3）。

/// 页面与排版的文档级设置。**默认值 = A4 + 上下 20mm / 左右 18mm。**
class DocSettings {
  const DocSettings({
    this.pageWidthMm = 210.0,
    this.pageHeightMm = 297.0,
    this.marginTopMm = 20.0,
    this.marginBottomMm = 20.0,
    this.marginLeftMm = 18.0,
    this.marginRightMm = 18.0,
    this.bodyFontSize = 16.0,
    this.lineHeight = 1.7,
    this.displayFontSize,
    this.heading1Size = 28.0,
    this.heading2Size = 24.0,
    this.heading3Size = 20.0,
    this.headerFontSize = 11.0,
    this.headerText = '',
  });

  // ---- 页面（mm）----
  final double pageWidthMm;
  final double pageHeightMm;
  final double marginTopMm;
  final double marginBottomMm;
  final double marginLeftMm;
  final double marginRightMm;

  // ---- 排版（逻辑 px / 倍数）----
  final double bodyFontSize;
  final double lineHeight;

  /// ★★ **行间公式的独立字号**（④-5，2026-10-16 用户提出）——
  /// `null` ⇒ 跟随正文（[effectiveDisplayFontSize] = 正文 × 1.25）。
  ///
  /// 为什么它**该**和正文分开：行间公式是**排版意图**（源码里的 `$$` 就是那个记号），
  /// 与"列表项有一点缩进"同一类，**允许**有自己的大小；
  /// 而**编辑行为**一律不因它而不同（§7.3）。
  /// ★ 块**内部**的光标不另设判据 —— 它取自当地 ¶ 盒（`math_caret`）⇒ **自动跟随**本项；
  /// 块**之前 / 之后**那两格仍按**段落文本层**标准（§11.27）。
  final double? displayFontSize;

  /// 行间公式**实际**用的字号（[displayFontSize] 未设时 = 正文 × 1.25）
  double get effectiveDisplayFontSize => displayFontSize ?? bodyFontSize * 1.25;

  final double heading1Size;
  final double heading2Size;
  final double heading3Size;
  final double headerFontSize;

  /// 页眉文本（姓名 / 学号）；新建文档时可用文件名自动填充
  final String headerText;

  /// A4 + 上下 20mm / 左右 18mm
  static const DocSettings defaults = DocSettings();

  /// 页内容宽 / 高（mm）
  double get contentWidthMm => pageWidthMm - marginLeftMm - marginRightMm;
  double get contentHeightMm => pageHeightMm - marginTopMm - marginBottomMm;

  DocSettings copyWith({
    double? pageWidthMm,
    double? pageHeightMm,
    double? marginTopMm,
    double? marginBottomMm,
    double? marginLeftMm,
    double? marginRightMm,
    double? bodyFontSize,
    double? lineHeight,
    double? displayFontSize,
    double? heading1Size,
    double? heading2Size,
    double? heading3Size,
    double? headerFontSize,
    String? headerText,
  }) {
    return DocSettings(
      pageWidthMm: pageWidthMm ?? this.pageWidthMm,
      pageHeightMm: pageHeightMm ?? this.pageHeightMm,
      marginTopMm: marginTopMm ?? this.marginTopMm,
      marginBottomMm: marginBottomMm ?? this.marginBottomMm,
      marginLeftMm: marginLeftMm ?? this.marginLeftMm,
      marginRightMm: marginRightMm ?? this.marginRightMm,
      bodyFontSize: bodyFontSize ?? this.bodyFontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      displayFontSize: displayFontSize ?? this.displayFontSize,
      heading1Size: heading1Size ?? this.heading1Size,
      heading2Size: heading2Size ?? this.heading2Size,
      heading3Size: heading3Size ?? this.heading3Size,
      headerFontSize: headerFontSize ?? this.headerFontSize,
      headerText: headerText ?? this.headerText,
    );
  }

  @override
  String toString() =>
      'DocSettings(${pageWidthMm}x${pageHeightMm}mm, body=$bodyFontSize, '
      'display=${effectiveDisplayFontSize.toStringAsFixed(1)}, '
      'lh=$lineHeight, header="$headerText")';
}
