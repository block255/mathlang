// ★★ 初始文档必须是**空白**（2026-10-19 用户实测）
//
// 用户原话：「我们初次打开时编辑面应该是空白，不过目前好像是我们开发时的基准文档」。
// 原因：`EditorPage` 里 `_buf = widget.buffer ?? DocBuffer(kEditSample)` ——
//   `kEditSample` 是 S3 开发期的**基准样例**（`spike/s3_edit`），不该出现在产品里。
// 现在初始 = `DocBuffer('')`；空白文档的可编辑性由 P3 兜底（零单元也分页 + 满页空行槽）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/ui/editor_page.dart';

import '../support/symbol_fixture.dart';

Future<DocBuffer> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: EditorPage(library: testSymbolLibrary()),
  ));
  await tester.pumpAndSettle();
  return tester.widget<EditView>(find.byType(EditView)).buffer;
}

void main() {
  group('㉖ 初次打开 = 空白文档', () {
    testWidgets('★★ 不传 buffer ⇒ 缓冲区是空的（改前：开发基准样例 kEditSample）',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester);
      expect(buf.buf, isEmpty,
          reason: '★★ 打开软件应当是一张白纸；实际 "${buf.buf.length} 字符"'
              '（开头：${buf.buf.length > 40 ? buf.buf.substring(0, 40) : buf.buf}）');
      expect(buf.buf, isNot(contains('一元二次方程')),
          reason: '`kEditSample` 的开头就是"# 例 1 · 一元二次方程"');
    });

    testWidgets('★ 空白文档也能落光标（编辑面不是死的）', (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester);
      expect(buf.caret, 0);
      // 点页面里那一片空白 ⇒ 光标落在 0（满页空行槽兜底）
      await tester.tapAt(const Offset(200, 300));
      await tester.pumpAndSettle();
      expect(buf.caret, 0, reason: '空文档点空白应当落在文档开头');
    });
  });
}