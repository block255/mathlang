import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_settings.dart';
import 'package:mathlang/layout/page_metrics.dart';

void main() {
  test('A4 默认值算下来是 210×297mm 与 174×257mm 内容区', () {
    final m = PageGeometry.from(DocSettings.defaults);
    expect(m.pageWidth, closeTo(210 * kPxPerMm, 0.01));
    expect(m.pageHeight, closeTo(297 * kPxPerMm, 0.01));
    expect(m.contentWidth, closeTo(174 * kPxPerMm, 0.01));
    expect(m.contentHeight, closeTo(257 * kPxPerMm, 0.01));
    // 得到 657.6 / 971.3 —— 与 S2-2 / S2-3 实验里用的数一致
    expect(m.contentWidth, closeTo(657.6, 0.2));
    expect(m.contentHeight, closeTo(971.3, 0.2));
  });

  test('页眉为空 → 不预留高度', () {
    final m = PageGeometry.from(DocSettings.defaults);
    expect(m.headerHeight, 0);
    expect(m.bodyHeight, closeTo(m.contentHeight, 0.001));
  });

  test('有页眉 → 正文可用高 = 内容区高 − 页眉', () {
    final m = PageGeometry.from(
      DocSettings.defaults.copyWith(headerText: '张三 20230101'),
    );
    expect(m.headerHeight, greaterThan(0));
    expect(m.bodyHeight, closeTo(m.contentHeight - m.headerHeight, 0.001));
  });

  test('页边距换算', () {
    final m = PageGeometry.from(DocSettings.defaults);
    expect(m.marginTop, closeTo(20 * kPxPerMm, 0.01));
    expect(m.marginLeft, closeTo(18 * kPxPerMm, 0.01));
  });
}
