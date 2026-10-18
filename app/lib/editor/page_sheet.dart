// 数语引擎 · A4 单页纸张（页眉 + 正文区 + 页下告警）
//
// 原则 4：**编辑时的分页预览 = 导出的 PDF 页 = 图片集的一张图** —— 所以这一页以后要能直接
// 交给 S6 导出（`RepaintBoundary.toImage` 就是图片集，同一棵子树就是 PDF 的排版依据）。
// ★ 2026-10-18（S4-d③）：`sheetKey` 现在挂在一层 `RepaintBoundary` 上（图片集与图片式 PDF 的
//   唯一抓取点）。RepaintBoundary 是**单子节点、尺寸 = 子节点尺寸** ⇒ 版面一个像素都不变。

import 'package:flutter/material.dart';

import '../core/doc_settings.dart';
import '../layout/page_metrics.dart';

/// 一页 A4。
class PageSheet extends StatelessWidget {
  const PageSheet({
    super.key,
    required this.settings,
    required this.metrics,
    required this.pageNumber,
    required this.pageCount,
    required this.children,
    this.warnings = const <String>[],
    this.sheetKey,
  });

  final DocSettings settings;
  final PageGeometry metrics;
  final int pageNumber;
  final int pageCount;

  /// 已经按"页内 y"排好（中间用 SizedBox 填了间距）的内容
  final List<Widget> children;

  /// 本页的告警（如"有块高于一页"）
  final List<String> warnings;

  /// 给 S6 导出图片集用的边界 key
  final Key? sheetKey;

  @override
  Widget build(BuildContext context) {
    final bool hasHeader = metrics.headerHeight > 0;
    final double headerTextH = settings.headerFontSize * 1.6;
    final double headerGap = metrics.headerHeight - headerTextH - 1;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '第 $pageNumber / $pageCount 页',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 4),
          // ★ 图片集 / 图片式 PDF 就是抓这一层（`RepaintBoundary.toImage`）。
          //   它不参与排版（尺寸 = 子节点尺寸）⇒ 版面中性。
          RepaintBoundary(
            key: sheetKey,
            child: Container(
              width: metrics.pageWidth,
              height: metrics.pageHeight,
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: EdgeInsets.fromLTRB(
                metrics.marginLeft,
                metrics.marginTop,
                metrics.marginRight,
                metrics.marginBottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (hasHeader) ...<Widget>[
                    SizedBox(
                      height: headerTextH,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          settings.headerText,
                          style: TextStyle(
                            fontSize: settings.headerFontSize,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                    ),
                    Container(height: 1, color: Colors.grey.shade300),
                    SizedBox(height: headerGap > 0 ? headerGap : 0),
                  ],
                  Expanded(
                    // 正文区：宽度已定，超页的内容**裁掉**（溢出由告警说明，原则 5）
                    child: ClipRect(
                      child: SingleChildScrollView(
                        physics: const NeverScrollableScrollPhysics(),
                        child: SizedBox(
                          width: metrics.contentWidth,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: children,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (warnings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (final String w in warnings)
                    Text(
                      '⚠️ $w',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange.shade900,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
