// ★★ 2026-10-20 守卫：顶栏顺序 + 手动分页（方案甲：下拉 + **接缝带**）
//
// 用户原话：
//   「文件 导入 保存 导出 都是文件级操作，放一起排左边；然后已恢复卡片；之后文档名；
//     再之后是 正文/标题 的按钮，然后才是分页的按钮」
//   「用户怎么知道分页符行在哪？…… 光标落在下一页的第一个字符之前或上一页的最后一个字符之后
//     （包括下面的空行）时 —— 这样才符合人类习惯」
// ⇒ 「删除分页」的判据 = **接缝带**（分页符行 ± 上下连续空行）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/block.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/lang/block_ops.dart';
import 'package:mathlang/ui/editor_page.dart';

import '../support/symbol_fixture.dart';

Future<(EditorPageState, DocBuffer)> _pump(WidgetTester tester, String doc,
    {int? caret}) async {
  tester.view.physicalSize = const Size(1500, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer(doc)..setCaret(caret ?? doc.length);
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
    testWidgets('★★ 文件级动作靠左且相邻：文件 < 导入 < 保存 < 导出 < 文档名',
        (WidgetTester tester) async {
      await _pump(tester, '甲乙');
      expect(_left(tester, 'file-menu'), lessThan(_left(tester, 'import-button')));
      expect(_left(tester, 'import-button'), lessThan(_left(tester, 'save-button')));
      expect(_left(tester, 'save-button'), lessThan(_left(tester, 'export-menu')));
      expect(_left(tester, 'export-menu'), lessThan(_left(tester, 'doc-title')));
    });

    testWidgets('★★ 文档名 → 块类型 → 分页', (WidgetTester tester) async {
      await _pump(tester, '甲乙');
      expect(_left(tester, 'doc-title'), lessThan(_left(tester, 'block-type-menu')));
      expect(_left(tester, 'block-type-menu'), lessThan(_left(tester, 'page-break-menu')));
    });
  });

  group('㉝ 接缝带：判断"光标在不在两页之间"', () {
    test('★★ 分页符行本身、上下空行都算接缝带；隔了正文就不算', () {
      const String doc = '甲\n\n<!-- pagebreak -->\n\n乙';
      final int brk = doc.indexOf('<!--');
      for (final int caret in <int>[
        doc.indexOf('甲') + 1,
        brk,
        brk + 3,
        doc.indexOf('乙'),
      ]) {
        expect(seamBand(doc, caret), isNotNull, reason: 'caret=$caret 应当算接缝带');
      }
      // 正文中间（离得远）⇒ 不是接缝带
      expect(seamBand('甲甲\n\n甲甲', 1), isNull);
    });

    test('★★ 删除接缝：两侧正文之间**只剩一个空行**，分页符消失', () {
      const String doc = '甲\n\n<!-- pagebreak -->\n\n乙';
      final int brk = doc.indexOf('<!--');
      final BlockOpResult? r = planRemoveSeam(doc, brk);
      expect(r, isNotNull);
      final String out = applyBlockOpTo(doc, r);
      expect(out.contains(kPageBreakMarker), isFalse);
      expect(out, '甲\n乙');
    });

    test('★ 文首/文末的接缝：删完不留空行', () {
      const String head = '<!-- pagebreak -->\n\n乙';
      final String h = applyBlockOpTo(head, planRemoveSeam(head, 0));
      expect(h.trimLeft().startsWith('乙'), isTrue, reason: '文首接缝删完不该留空行：${h.replaceAll('\n', '⏎')}');

      final String tail = '甲\n\n<!-- pagebreak -->\n';
      final String t = applyBlockOpTo(tail, planRemoveSeam(tail, 4));
      expect(t.trimRight(), '甲', reason: '文末接缝删完不该留空行');
    });

    test('★ 连续两个分页符：删一次只清一条（另一条还在，不会留下半截）', () {
      const String doc = '甲\n\n<!-- pagebreak -->\n<!-- pagebreak -->\n\n乙';
      final String out = applyBlockOpTo(doc, planRemoveSeam(doc, 4));
      expect(kPageBreakMarker.allMatches(out).length, 1,
          reason: '一次只删一道缝，但绝不能留下半截标记');
    });
  });

  group('㉞ 分页下拉（插入 / 删除 并列）', () {
    testWidgets('★★ 下拉里两项都在；光标不在接缝带时「删除分页」禁用',
        (WidgetTester tester) async {
      await _pump(tester, '甲\n\n<!-- pagebreak -->\n\n乙', caret: 0);
      await tester.tap(find.byKey(const Key('page-break-menu')));
      await tester.pumpAndSettle();
      expect(find.text('插入分页'), findsOneWidget);
      expect(find.text('删除分页'), findsOneWidget);
      final PopupMenuItem<String> remove =
          tester.widget<PopupMenuItem<String>>(find.byKey(const Key('page-break-remove')));
      expect(remove.enabled, isFalse, reason: '光标在文首，离接缝很远 ⇒ 删除项该灰显');
    });

    testWidgets('★★ 光标在接缝带（分页符下面的空行）⇒「删除分页」可用并真的删掉',
        (WidgetTester tester) async {
      // caret 放在分页符**下面**那个空行上（用户说的"下一页第一个字之前"）
      const String doc = '甲\n\n<!-- pagebreak -->\n\n乙';
      final int caret = doc.indexOf('<!--') + kPageBreakMarker.length + 1;
      final (EditorPageState st, DocBuffer buf) = await _pump(tester, doc, caret: caret);
      expect(st, isNotNull);
      await tester.tap(find.byKey(const Key('page-break-menu')));
      await tester.pumpAndSettle();
      final PopupMenuItem<String> remove =
          tester.widget<PopupMenuItem<String>>(find.byKey(const Key('page-break-remove')));
      expect(remove.enabled, isTrue, reason: '光标在接缝带里 ⇒ 删除项可用');
      await tester.tap(find.byKey(const Key('page-break-remove')));
      await tester.pumpAndSettle();
      expect(buf.buf.contains(kPageBreakMarker), isFalse);
    });

    testWidgets('★★ 点「插入分页」⇒ 分页符出现在缓冲区里', (WidgetTester tester) async {
      final (_, DocBuffer buf) = await _pump(tester, '甲乙\n丙丁', caret: 2);
      await tester.tap(find.byKey(const Key('page-break-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('page-break-insert')));
      await tester.pumpAndSettle();
      expect(buf.buf.contains(kPageBreakMarker), isTrue);
      expect(buf.canUndo, isTrue, reason: '插入必须可撤销');
    });
  });
}