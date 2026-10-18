// ★★ S4-d③：**图片集 / PDF** 的端到端守卫（编辑页 → 抓页 → 后端）
//
// 这一层守的是"用户按下去会发生什么"：
//   ① 图片集 ⇒ 后端收到 **N 张 PNG**，命名带页序（`第01页`）；
//   ② PDF ⇒ 后端收到**一份二进制**，头是 `%PDF-`，文件名以 `.pdf` 结尾；
//   ③ 用户取消 ⇒ 什么都不做（不 snack、不留半截文件）；
//   ④ 导出**不改**文档身份与 dirty（它只是"另存一份出去"）。
//
// ★ 页面是真的从 `RepaintBoundary` 抓出来的（`toImage`）——
//   所以这条同时也守住了"PageSheet 外面真的套了 RepaintBoundary"。
// ★★ 但不能在 fake-async 里直接 `await`：`toImage` 的 Future 由引擎完成，
//   必须放进 `tester.runAsync(...)`（否则测试会**永远挂在 await 上**，本仓实测）。

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/io/file_gateway.dart';
import 'package:mathlang/ui/editor_page.dart';

import '../support/fake_file_gateway.dart';
import '../support/symbol_fixture.dart';

Future<(EditorPageState, DocBuffer, FakeFileGateway)> _pump(
  WidgetTester tester, {
  String doc = '# 例 1\n\n设 \$x^2+1\$ 是式子。\n',
  FakeFileGateway? gateway,
}) async {
  tester.view.physicalSize = const Size(1500, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final FakeFileGateway gw = gateway ?? FakeFileGateway();
  final DocBuffer buf = DocBuffer(doc)..setCaret(0);
  await tester.pumpWidget(MaterialApp(
    home: EditorPage(library: testSymbolLibrary(), buffer: buf, gateway: gw),
  ));
  await tester.pumpAndSettle();
  return (tester.state<EditorPageState>(find.byType(EditorPage)), buf, gw);
}

void main() {
  group('① 图片集（每页一张 PNG）', () {
    testWidgets('★ 导出一批 PNG，命名带页序，且随后端成功',
        timeout: const Timeout(Duration(seconds: 20)),
        (WidgetTester tester) async {
      final (EditorPageState st, _, FakeFileGateway gw) = await _pump(tester);
      final bool dirtyBefore = st.dirty;

      await tester.runAsync(() => st.exportImages());
      await tester.pump();

      expect(gw.batches.length, 1, reason: '没有走批量写盘');
      final ExportBatch b = gw.batches.single;
      expect(b.count, greaterThanOrEqualTo(1));
      expect(b.paths.first, endsWith('第01页.png'));
      // 页序补零 ⇒ 文件管理器按名字就是页序
      if (b.count > 1) expect(b.paths[1], endsWith('第02页.png'));
      expect(st.dirty, dirtyBefore, reason: '导出不改 dirty');
      expect(st.docFile.hasFile, isFalse, reason: '导出 ≠ 保存');
    });

    testWidgets('用户取消 ⇒ 什么都不做',
        timeout: const Timeout(Duration(seconds: 20)),
        (WidgetTester tester) async {
      final (EditorPageState st, _, FakeFileGateway gw) = await _pump(tester);
      gw.cancelBatch = true;
      await tester.runAsync(() => st.exportImages());
      await tester.pump();
      expect(gw.batches, isEmpty);
    });

    testWidgets('空文档**没有可抓的页** ⇒ 弹错误对话框（不静默成功）',
        timeout: const Timeout(Duration(seconds: 20)),
        (WidgetTester tester) async {
      final (EditorPageState st, _, FakeFileGateway gw) =
          await _pump(tester, doc: '');
      // ⚠️ 必须在 fake-async 里驱动：`_showFileError` 会 **await 对话框**
      //   （测试里不去点它 ⇒ 永远不返回；这正是"没人关的对话框会挂住流程"的例子）
      unawaited(st.exportImages());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('file-error-dialog')), findsOneWidget);
      expect(gw.batches, isEmpty, reason: '抓不到页就不该写文件');
      await tester.tap(find.byKey(const Key('file-error-close')));
      await tester.pump();
    });
  });

  group('② PDF（图片式 + md 附件）', () {
    testWidgets('★ 后端收到一份 %PDF，建议名以 .pdf 结尾',
        timeout: const Timeout(Duration(seconds: 20)),
        (WidgetTester tester) async {
      final (EditorPageState st, DocBuffer buf, FakeFileGateway gw) =
          await _pump(tester);

      await tester.runAsync(() => st.exportPdf());
      await tester.pump();

      expect(gw.savesBytes.length, 1, reason: 'PDF 走的是 saveBytes');
      final ({String? path, int length, String suggestedName}) rec =
          gw.savesBytes.single;
      expect(rec.suggestedName, endsWith('.pdf'));
      expect(rec.length, greaterThan(1000), reason: '一页图 + 附件不可能只有几百字节');

      final Uint8List bytes = Uint8List.fromList(gw.savedPayloads.single);
      expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
      // md 全文以附件形式在内（`/EmbeddedFiles` 是 PDF 规范的名字树）
      expect(String.fromCharCodes(bytes).contains('/EmbeddedFile'), isTrue);
      expect(buf.buf, isNotEmpty);
      expect(st.dirty, isFalse, reason: '导出不改 dirty（这份文档本来就没改过）');
    });

    testWidgets('用户取消 ⇒ 不写文件',
        timeout: const Timeout(Duration(seconds: 20)),
        (WidgetTester tester) async {
      final (EditorPageState st, _, FakeFileGateway gw) = await _pump(tester);
      gw.cancelSave = true;
      await tester.runAsync(() => st.exportPdf());
      await tester.pump();
      expect(gw.savedPayloads, isEmpty);
    });
  });
}
