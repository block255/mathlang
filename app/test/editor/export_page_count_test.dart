// A1 守卫（用户 2026-10-27 提、2026-10-28 拍板）：**导出 PDF / 图片集时，
// 只由"文末永久空行"撑出来的纯空行页不进产物**。
//
// 判据用**单元**、不用像素：一页上没有任何真实单元（只有尾部/分页前的空行占位项）
// ⇒ 那一页是白纸 ⇒ 导出时裁掉。三条边界：
//   · 只从**末尾连续**裁（中间那一页是用户真空出来的，不许动）；
//   · **至少留 1 页**；
//   · **屏幕上的页数不变**（用户还要在那几张白纸上点、按 Enter）。
//
// ★ 页码不会跟着错：`PageSheet` 里「第 x / y 页」画在 `RepaintBoundary` **外面**
//   （`page_sheet.dart:51-59`），抓图抓不到 ⇒ 裁页后不需要改分母。

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/doc_view.dart';

Future<DocViewState> _mount(WidgetTester tester, String doc) async {
  tester.view.physicalSize = const Size(900, 5200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer(doc);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: DocView(buffer: buf))),
  ));
  await tester.pumpAndSettle();
  return tester.state<DocViewState>(find.byType(DocView));
}

/// 一页 ≈ 24 行（A4 正文高 ≈ 930 px ÷ 一行 38.4）⇒ 40 段一定多页。
String _paras(int n) => List<String>.filled(n, '一行文字').join('\n\n');

void main() {
  group('A1 · 导出页数不把"纯空行页"算进去', () {
    testWidgets('单页文档：导出页数 == 屏幕页数', (WidgetTester tester) async {
      final DocViewState st = await _mount(tester, '甲\n\n乙\n');
      expect(st.pageCount, 1);
      expect(st.exportPageCount, 1);
    });

    testWidgets('多页文档、末页有内容 ⇒ 一页都不裁', (WidgetTester tester) async {
      final DocViewState st = await _mount(tester, '${_paras(40)}\n');
      expect(st.pageCount, greaterThan(1), reason: '前置：这份文档必须真的多页');
      expect(st.exportPageCount, st.pageCount,
          reason: '末页有真实单元 ⇒ 不许裁（否则会吞掉用户的内容）');
    });

    testWidgets('文末一大串空行撑出新页 ⇒ 那几页裁掉，但至少留 1 页',
        (WidgetTester tester) async {
      // 40 段（多页）+ 文末 30 个空行：空行按 `trailingBlankHeight = n × 行高` 结算，
      // 30 × 38.4 ≈ 1152 px > 一页正文高 ⇒ 必然溢出到后面的页，而那些页上一根单元都没有。
      final DocViewState st = await _mount(tester, '${_paras(40)}\n${'\n' * 30}');
      expect(st.pageCount, greaterThan(1), reason: '前置：必须真的多页');
      expect(st.exportPageCount, lessThan(st.pageCount),
          reason: '末尾那些纯空行页不该进导出产物');
      expect(st.exportPageCount, greaterThanOrEqualTo(1));
      // 屏幕上的页数**不变**（用户还要在那几张白纸上点、按 Enter）
      expect(st.pageCount, greaterThan(1));
    });

    testWidgets('导出只抓前 N 页：图数 == exportPageCount',
        (WidgetTester tester) async {
      final DocViewState st =
          await _mount(tester, '${_paras(40)}\n${'\n' * 30}');
      final int want = st.exportPageCount;
      final List<Uint8List> pages = await tester.runAsync(
        () => st.capturePages(pixelRatio: 1.0, count: want),
      ) as List<Uint8List>;
      expect(pages, hasLength(want),
          reason: '`capturePages(count:)` 只抓前 count 页（实测 ${pages.length} / 期望 $want）');
    });

    testWidgets('不传 count ⇒ 抓全部（编辑区/旧调用沿用原口径）',
        (WidgetTester tester) async {
      final DocViewState st = await _mount(tester, '甲\n\n乙\n');
      final List<Uint8List> pages = await tester.runAsync(
        () => st.capturePages(pixelRatio: 1.0),
      ) as List<Uint8List>;
      expect(pages, hasLength(1));
    });
  });
}
