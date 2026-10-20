// ★★ 2026-10-20 守卫：顶栏顺序（用户拍板）+ 手动分页的"插入/取消"与兜底
//
// 用户原话（2026-10-20）：
//   「文件 导入 保存 导出 都是属于文件级操作，可以放一起排在左边；然后是已恢复卡片；
//     之后是文档名；再之后是 正文/标题 的按钮，然后才是分页的按钮」
//   「能手动分页，我们是不是也需要能手动取消下面的分页」+「做好相关的兜底」

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/block.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/lang/block_ops.dart';
import 'package:mathlang/ui/editor_page.dart';

import '../support/symbol_fixture.dart';

Future<(EditorPageState, DocBuffer)> _pump(WidgetTester tester,
    {String doc = '甲乙丙\n丁戊'}) async {
  tester.view.physicalSize = const Size(1500, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer(doc)..setCaret(doc.length);
  await tester.pumpWidget(MaterialApp(
    home: EditorPage(library: testSymbolLibrary(), buffer: buf),
  ));
  await tester.pumpAndSettle();
  return (tester.state<EditorPageState>(find.byType(EditorPage)), buf);
}

double _left(WidgetTester tester, String key) =>
    tester.getTopLeft(find.byKey(Key(key))).dx;

void main() {
  group('㉜ 顶栏顺序（用户 2026-10-20 定）', () {
    testWidgets('★★ 文件级动作靠左且相邻：文件 < 导入 < 保存 < 导出', (WidgetTester tester) async {
      await _pump(tester);
      final double file = _left(tester, 'file-menu');
      final double imp = _left(tester, 'import-button');
      final double save = _left(tester, 'save-button');
      final double exp = _left(tester, 'export-menu');
      expect(file, lessThan(imp), reason: '「文件」在「导入」左边');
      expect(imp, lessThan(save), reason: '「导入」在「保存」左边');
      expect(save, lessThan(exp), reason: '「保存」在「导出」左边');
      // 这四个必须是**挨着的**（中间不夹文档名/块类型）
      final double title = _left(tester, 'doc-title');
      expect(exp, lessThan(title), reason: '文件级动作全在文档名左边');
    });

    testWidgets('★★ 文档名之后才是 块类型 → 分页', (WidgetTester tester) async {
      await _pump(tester);
      final double title = _left(tester, 'doc-title');
      final double blockType = _left(tester, 'block-type-menu');
      final double pageBreak = _left(tester, 'page-break-button');
      expect(title, lessThan(blockType), reason: '文档名在块类型左边');
      expect(blockType, lessThan(pageBreak), reason: '块类型在分页左边');
    });
  });

  group('㉝ 手动分页：插入 / 取消 / 兜底', () {
    testWidgets('★★ 点一次「分页」⇒ 插入分页符；光标落在分页符行 ⇒ 按钮变「取消分页」',
        (WidgetTester tester) async {
      final (EditorPageState st, DocBuffer buf) = await _pump(tester);
      st.openSettings();
      st.closeSettings();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('page-break-button')));
      await tester.pumpAndSettle();
      expect(buf.buf.contains(kPageBreakMarker), isTrue, reason: '插入分页符');
      expect(find.text('取消分页'), findsOneWidget, reason: '光标在分页符行上 ⇒ 按钮该变成取消');
    });

    testWidgets('★★ 再点一次 ⇒ 分页符被删掉（整行删，不留空行）',
        (WidgetTester tester) async {
      final (EditorPageState st, DocBuffer buf) = await _pump(tester);
      st.openSettings();
      st.closeSettings();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('page-break-button')));
      await tester.pumpAndSettle();
      final String afterInsert = buf.buf;
      await tester.tap(find.byKey(const Key('page-break-button')));
      await tester.pumpAndSettle();
      expect(buf.buf.contains(kPageBreakMarker), isFalse, reason: '取消分页');
      expect(buf.buf.length, lessThan(afterInsert.length));
      expect(buf.buf.contains('\n\n\n'), isFalse, reason: '不许留下连续三个空行');
    });

    test('★ 兜底：连续插分页符不叠加（同一处只认一个）', () {
      const String doc = '甲乙\n丙';
      final BlockOpResult? r1 = planBlockOp(doc, 2, BlockOp.pagebreak);
      expect(r1, isNotNull);
      final String once = applyBlockOpTo(doc, r1);
      // 光标落回同一位置再插一次 ⇒ 应该被幂等规则挡住
      final BlockOpResult? r2 = planBlockOp(once, 2, BlockOp.pagebreak);
      expect(r2 == null || r2.isNoop, isTrue, reason: '连按不许堆一串分页符');
    });

    test('★ 取消分页：中间行删「行+换行」，末行删「前面的换行」', () {
      const String mid = '甲\n<!-- pagebreak -->\n乙';
      final BlockOpResult? r = planRemovePageBreak(mid, 4);
      expect(r, isNotNull);
      expect(applyBlockOpTo(mid, r), '甲\n乙');

      const String last = '甲\n<!-- pagebreak -->';
      final BlockOpResult? r2 = planRemovePageBreak(last, 3);
      expect(r2, isNotNull);
      expect(applyBlockOpTo(last, r2), '甲');
    });

    test('★ 光标不在分页符行 ⇒ 取消什么都不做', () {
      expect(planRemovePageBreak('甲\n乙', 0), isNull);
    });
  });
}