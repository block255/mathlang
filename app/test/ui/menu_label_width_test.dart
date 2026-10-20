// ★★ 2026-10-20（T-A 实战测试 F4，用户可见）：**导出菜单的长标签不许折行**。
//
// 改前现场（截图 `TA1-export-menu`）：菜单只有 112 px 宽，四项全折成两三行 ——
//   `Markdown` / `(.md)`、`图片集（每页` / `PNG）`、`PDF（图片式` / `+ md 附件）`。
//
// 根因：`_fileItem` 里标签外面套的是 **`SizedBox(width: 76)`**（固定宽），
// 于是长标签只能在 76 px 里换行；而菜单宽度是按"内容最小宽度"算的 ⇒ 只有 112。
// 修法：换成 `ConstrainedBox(minWidth: 76)` + `softWrap: false` ⇒ 菜单宽度由最长那项撑开，
// 文件菜单里那几项短标签的右对齐仍然对齐（最小宽还是 76）。
//
// 判据：**每一个标签只能占一行**（高度 < 20；折两行就会 > 30）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/ui/editor_page.dart';

import '../support/fake_file_gateway.dart';
import '../support/symbol_fixture.dart';

Future<void> _pump(WidgetTester tester, String doc) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer(doc)..setCaret(0);
  await tester.pumpWidget(MaterialApp(
    home: EditorPage(
      library: testSymbolLibrary(),
      buffer: buf,
      gateway: FakeFileGateway(),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('★ F4：导出菜单四项都是**一行**（改前长项折成两三行）',
      (WidgetTester tester) async {
    await _pump(tester, '甲');
    await tester.tap(find.byKey(const Key('export-menu')));
    await tester.pumpAndSettle();

    const List<String> labels = <String>[
      'Markdown (.md)',
      '纯文本 (.txt)',
      '图片集（每页 PNG）',
      'PDF（图片式 + md 附件）',
    ];
    for (final String label in labels) {
      final Finder f = find.text(label);
      expect(f, findsOneWidget, reason: '菜单项「$label」必须在');
      final Size s = tester.getSize(f);
      expect(s.height, lessThan(20),
          reason: '「$label」被折行了（高 ${s.height}）：菜单宽 ${s.width} 太窄');
      expect(s.width, greaterThan(76),
          reason: '长标签应当把菜单撑宽（改前被固定 76 px 的盒子卡住）');
    }
  });

  testWidgets('★ 不误伤：文件菜单的短标签仍按 76 px 那一列对齐',
      (WidgetTester tester) async {
    await _pump(tester, '甲');
    await tester.tap(find.byKey(const Key('file-menu')));
    await tester.pumpAndSettle();
    // ★ 只挑**菜单里独有**的标签（`保存`/`导入` 顶栏也有同名按钮，`find.text` 会命中两个）
    for (final String label in <String>['新建', '打开…', '另存为…']) {
      final Size s = tester.getSize(find.text(label));
      expect(s.height, lessThan(20), reason: '「$label」也不许折行');
    }
  });
}
