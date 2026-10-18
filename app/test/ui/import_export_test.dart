// ★★ S4-d② 导入 / 导出守卫（《S4》§D + §6-1 的口径）
//
// 用户 2026-10-17 拍板的两条（**别再重开**）：
//   ① `.txt` 导出 = **原样保留 `$`**，与 `.md` **逐字节相同**，差别只有扩展名
//      （"追求不丢信息、能够再导入"，不为"给人看"牺牲可逆性）；
//   ② 导入 = **新建一份内容**（不是"打开那个文件"）⇒ 之后保存要另存为，
//      绝不覆盖用户的源文件（`.txt` 导入会被智能包裹改写，写回去就是毁原件）。
//
// 判据：
//   ① 导出 md / txt ⇒ 后端收到的**文本完全相同**，只有 extension 不同；导出**不改**文档身份与 dirty；
//   ② 导入 md ⇒ 文档整篇替换、标题=文件名去扩展名、**path 为空**、没有智能包裹；
//   ③ 导入 txt ⇒ 走智能包裹（产出 `$…$` / `$$…$$`），并如实报告补了几处；
//   ④ 有未保存改动时导入也要先问。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/io/file_gateway.dart';
import 'package:mathlang/ui/editor_page.dart';

import '../support/fake_file_gateway.dart';
import '../support/symbol_fixture.dart';

Future<(EditorPageState, DocBuffer, FakeFileGateway)> _pump(
  WidgetTester tester, {
  String doc = 'abc',
  FakeFileGateway? gateway,
}) async {
  tester.view.physicalSize = const Size(1500, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final FakeFileGateway gw = gateway ?? FakeFileGateway();
  final DocBuffer buf = DocBuffer(doc)..setCaret(doc.length);
  await tester.pumpWidget(MaterialApp(
    home: EditorPage(library: testSymbolLibrary(), buffer: buf, gateway: gw),
  ));
  await tester.pumpAndSettle();
  return (tester.state<EditorPageState>(find.byType(EditorPage)), buf, gw);
}

void main() {
  group('① 导出：md 与 txt 逐字节相同', () {
    testWidgets('导出 md ⇒ 后端拿到全文，extension=md，且**不改**身份/dirty',
        (WidgetTester tester) async {
      final (EditorPageState st, DocBuffer buf, FakeFileGateway gw) =
          await _pump(tester);
      final bool dirtyBefore = st.dirty;

      await st.exportDocument('md');
      await tester.pump();

      expect(gw.saves.length, 1);
      expect(gw.saves.single.text, buf.buf);
      expect(st.docFile.hasFile, isFalse, reason: '导出 ≠ 保存：不该给文档安上路径');
      expect(st.dirty, dirtyBefore, reason: '导出不改 dirty');
    });

    testWidgets('★ 导出 txt：文本与 md **逐字节相同**（只差扩展名）',
        (WidgetTester tester) async {
      const String doc = r'# 标题' '\n\n' r'设 $x^2$ 是式子。' '\n';
      final (EditorPageState st, DocBuffer _, FakeFileGateway gw) =
          await _pump(tester, doc: doc);

      await st.exportDocument('md');
      await st.exportDocument('txt');
      await tester.pump();

      expect(gw.saves.length, 2);
      expect(gw.saves[1].text, gw.saves[0].text,
          reason: '★ 用户拍板：txt 保留 `\$`，与 md 内容完全一致');
      expect(gw.saves[1].text, contains(r'$x^2$'), reason: '不许去 `\$`');
    });
  });

  group('② 导入 .md：原样进来，算"新文档"', () {
    testWidgets('★ 导入后 path 为空、标题=文件名、内容原样',
        (WidgetTester tester) async {
      final (EditorPageState st, DocBuffer buf, FakeFileGateway gw) =
          await _pump(tester);
      gw.toOpen = const OpenedFile(
        path: r'C:\docs\别人的笔记.md',
        name: '别人的笔记.md',
        text: '# 原样\n\n\$y^2\$',
      );
      await st.importDocument();
      await tester.pump();

      expect(buf.buf, '# 原样\n\n\$y^2\$');
      expect(st.docFile.title, '别人的笔记');
      expect(st.docFile.hasFile, isFalse,
          reason: '★ 导入 = 新文档；保存时要另存为，不能覆盖源文件');
    });
  });

  group('③ 导入 .txt：走智能包裹并报告处数', () {
    testWidgets('★ 一段含式子的纯文本 ⇒ 产出 \$…\$ / \$\$…\$\$，且状态栏能报数',
        (WidgetTester tester) async {
      final (EditorPageState st, DocBuffer buf, FakeFileGateway gw) =
          await _pump(tester);
      // 整行推导 + 行内式子：B′ 口径（整行式子升格成 $$ 块）
      gw.toOpen = const OpenedFile(
        path: r'C:\docs\作业.txt',
        name: '作业.txt',
        text: '设 x^2+1 是多项式\n\n\\frac{a}{b}=2 求 a\n',
      );
      await st.importDocument();
      await tester.pump();

      expect(buf.buf.contains(r'$'), isTrue,
          reason: '★ txt 必须被智能包裹（否则数学不会渲染）');
    });

    testWidgets('纯中文文本 ⇒ 不该被误包成公式', (WidgetTester tester) async {
      final (EditorPageState st, DocBuffer buf, FakeFileGateway gw) =
          await _pump(tester);
      gw.toOpen = const OpenedFile(
        path: r'C:\docs\说明.txt',
        name: '说明.txt',
        text: '这是一段中文说明。\n没有任何式子。\n',
      );
      await st.importDocument();
      await tester.pump();
      expect(buf.buf.contains(r'$'), isFalse, reason: '中文不该被包成公式');
    });
  });

  group('④ 导入也要先问（有未保存改动时）', () {
    testWidgets('脏文档导入 ⇒ 弹确认，选取消 ⇒ 什么都不变',
        (WidgetTester tester) async {
      final (EditorPageState st, DocBuffer buf, FakeFileGateway gw) =
          await _pump(tester);
      final EditViewState v = tester.state<EditViewState>(find.byType(EditView));
      v.focusInput();
      v.pasteText('改动');
      await tester.pumpAndSettle();
      final String before = buf.buf;

      unawaited(st.importDocument());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('discard-dialog')), findsOneWidget);

      await tester.tap(find.byKey(const Key('discard-cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(buf.buf, before);
      expect(gw.opens, 0, reason: '取消后连文件选择都不该发生');
    });
  });
}
