// ★★ S4-d 文件动线守卫（新建 / 打开 / 保存 / 另存为）
//
// 用**假文件后端**（`FakeFileGateway`）守这条链：
//   `按钮/快捷键 → FileGateway → 缓冲区 + 标题 + dirty`。
// 真对话框（Windows 的另存为）由人工验收，不进测试。
//
// 五条判据：
//   ① `Ctrl+S` / 点「保存」⇒ 把**缓冲区原文**交给后端；成功后 dirty 变 ○，标题变成文件名；
//   ② 打开 ⇒ 缓冲区整篇换掉 + **撤销栈清空**（不能按 Ctrl+Z 撤回到上一个文件）+ 标题跟着换；
//   ③ 有未保存改动时「新建 / 打开」⇒ **先问**；选"取消" ⇒ 什么都不发生；
//   ④ 另存为被取消 ⇒ **dirty 不能清掉**（这是最容易做错的一条）；
//   ⑤ 改标题 ⇒ 下次保存要**另存**（不能偷偷写回旧文件）。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    home: EditorPage(
      library: testSymbolLibrary(),
      buffer: buf,
      gateway: gw,
    ),
  ));
  await tester.pumpAndSettle();
  return (tester.state<EditorPageState>(find.byType(EditorPage)), buf, gw);
}

Future<void> _type(WidgetTester tester, String text) async {
  final EditViewState v = tester.state<EditViewState>(find.byType(EditView));
  v.focusInput();
  v.pasteText(text);
  await tester.pumpAndSettle();
}

void main() {
  group('① 保存', () {
    testWidgets('★ 点「保存」⇒ 后端收到**缓冲区原文**，成功后 dirty 变 ○、标题=文件名',
        (WidgetTester tester) async {
      final (EditorPageState st, DocBuffer buf, FakeFileGateway gw) =
          await _pump(tester);
      await _type(tester, 'xyz');
      expect(st.dirty, isTrue);
      expect(find.text('●'), findsWidgets, reason: '未保存要亮 ●');

      await tester.tap(find.byKey(const Key('save-button')));
      await tester.pumpAndSettle();

      expect(gw.saves.length, 1);
      expect(gw.saves.single.text, buf.buf, reason: '★ 存的必须是原文（含编码）');
      expect(gw.saves.single.path, isNull, reason: '第一次没有路径 ⇒ 走"另存为"');
      expect(st.docFile.hasFile, isTrue);
      expect(st.docFile.title, '未命名文档', reason: '假后端返回 未命名文档.md');
      expect(st.dirty, isFalse);
      expect(find.text('○'), findsWidgets);
    });

    testWidgets('★ 已有路径 ⇒ 直接写回（不再弹另存为）', (WidgetTester tester) async {
      final (EditorPageState st, DocBuffer _, FakeFileGateway gw) =
          await _pump(tester);
      gw.savePath = r'C:\docs\作业1.md';
      await _type(tester, 'A');
      await tester.tap(find.byKey(const Key('save-button')));
      await tester.pumpAndSettle();
      expect(st.docFile.path, r'C:\docs\作业1.md');
      expect(st.docFile.title, '作业1');

      await _type(tester, 'B');
      await tester.tap(find.byKey(const Key('save-button')));
      await tester.pumpAndSettle();
      expect(gw.saves.length, 2);
      expect(gw.saves.last.path, r'C:\docs\作业1.md',
          reason: '★ 第二次必须带着路径直接写回');
    });

    testWidgets('★ 另存为被取消 ⇒ dirty 不许清掉', (WidgetTester tester) async {
      final (EditorPageState st, DocBuffer _, FakeFileGateway gw) =
          await _pump(tester);
      gw.cancelSave = true;
      await _type(tester, 'X');
      expect(st.dirty, isTrue);
      await tester.tap(find.byKey(const Key('save-button')));
      await tester.pumpAndSettle();
      expect(st.dirty, isTrue, reason: '★ 用户点了取消 ⇒ 什么都没保存');
      expect(st.docFile.hasFile, isFalse);
    });

    testWidgets('Ctrl+S 也能存（走外壳快捷键）', (WidgetTester tester) async {
      final (EditorPageState _, DocBuffer _, FakeFileGateway gw) =
          await _pump(tester);
      await _type(tester, 'K');
      tester.state<EditViewState>(find.byType(EditView)).focusInput();
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(gw.saves.length, 1);
    });
  });

  group('② 打开', () {
    testWidgets('★ 打开 ⇒ 整篇换掉 + 标题跟着换 + **撤销栈清空**',
        (WidgetTester tester) async {
      final (EditorPageState st, DocBuffer buf, FakeFileGateway gw) =
          await _pump(tester);
      await _type(tester, '改一下'); // 造一步可撤销的编辑
      expect(buf.canUndo, isTrue);

      gw.toOpen = const OpenedFile(
        path: r'C:\docs\新文件.md',
        name: '新文件.md',
        text: '# 打开的内容\n\n\$y^2\$',
      );
      await tester.tap(find.byKey(const Key('file-menu'))); // 只是确认菜单存在
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开…').last);
      await tester.pumpAndSettle();

      // 有未保存改动 ⇒ 先问；这里选"不保存，继续"
      expect(find.byKey(const Key('discard-dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('discard-no-save')));
      await tester.pumpAndSettle();

      expect(buf.buf, '# 打开的内容\n\n\$y^2\$');
      expect(st.docFile.title, '新文件');
      expect(st.docFile.path, r'C:\docs\新文件.md');
      expect(st.dirty, isFalse, reason: '刚打开的文件是干净的');
      expect(buf.canUndo, isFalse, reason: '★ 撤销栈必须清空（否则能撤回到上一个文件）');
    });

    testWidgets('打开时用户取消 ⇒ 什么也不变', (WidgetTester tester) async {
      final (EditorPageState st, DocBuffer buf, FakeFileGateway gw) =
          await _pump(tester);
      gw.toOpen = null; // 用户在选择框里点了取消
      final String before = buf.buf;
      await st.openDocument();
      await tester.pumpAndSettle();
      expect(gw.opens, 1, reason: '后端确实被问过');
      expect(buf.buf, before);
      expect(st.docFile.hasFile, isFalse);
    });
  });

  group('③ 新建要问、④ 取消要拦住', () {
    testWidgets('★ 有未保存改动时新建 ⇒ 弹确认；选"取消" ⇒ 文档原样',
        (WidgetTester tester) async {
      final (EditorPageState st, DocBuffer buf, FakeFileGateway _) =
          await _pump(tester);
      await _type(tester, 'Z');
      final String before = buf.buf;

      st.newDocument();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('discard-dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('discard-cancel')));
      await tester.pumpAndSettle();
      expect(buf.buf, before, reason: '取消 ⇒ 一个字都不许动');
      expect(st.dirty, isTrue);
    });

    testWidgets('干净文档直接新建（不弹窗）', (WidgetTester tester) async {
      final (EditorPageState st, DocBuffer buf, FakeFileGateway _) =
          await _pump(tester);
      await tester.tap(find.byKey(const Key('file-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('discard-dialog')), findsNothing);
      expect(buf.buf, '');
      expect(st.docFile.title, '未命名文档');
      expect(st.dirty, isFalse);
    });
  });

  group('⑤ 改标题 = 另存为语义', () {
    testWidgets('★ 有文件时改标题 ⇒ 清掉旧路径，下次保存重新选位置',
        (WidgetTester tester) async {
      final (EditorPageState st, DocBuffer _, FakeFileGateway gw) =
          await _pump(tester);
      gw.savePath = r'C:\docs\甲.md';
      await _type(tester, 'a');
      await tester.tap(find.byKey(const Key('save-button')));
      await tester.pumpAndSettle();
      expect(st.docFile.path, r'C:\docs\甲.md');

      await tester.tap(find.byKey(const Key('doc-title')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('doc-title-field')), '乙');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(st.docFile.title, '乙');
      expect(st.docFile.hasFile, isFalse,
          reason: '★ 改了名字 ⇒ 不能偷偷写回旧文件（甲.md）');
      expect(st.docFile.suggestedFileName(), '乙.md');
    });
  });
  group('⑥ 文件出错必须**可见**（2026-10-17 Windows 实测"点了没反应"的反面）', () {
    testWidgets('★ 保存抛异常 ⇒ 弹「保存失败」+ 原因，且 dirty 不清',
        (WidgetTester tester) async {
      final FakeFileGateway gw = FakeFileGateway(
        throwOnSave: Exception('拒绝访问: C:\\docs\\作业1.md'),
      );
      final (EditorPageState st, DocBuffer buf, FakeFileGateway _) =
          await _pump(tester, gateway: gw);
      await _type(tester, 'Q');
      expect(st.dirty, isTrue);

      await tester.tap(find.byKey(const Key('save-button')));
      // ★ 不用 pumpAndSettle：编辑器有 530ms 光标闪烁（无限动画）⇒ settle 永远等不到
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const Key('file-error-dialog')), findsOneWidget,
          reason: '★ 出错不许静默（原则 5）');
      expect(find.byKey(const Key('file-error-detail')), findsOneWidget);
      expect(find.textContaining('拒绝访问'), findsWidgets,
          reason: '原因要原样给用户看（可选中复制）');
      expect(find.text('保存失败'), findsOneWidget);
      expect(st.dirty, isTrue, reason: '写失败了当然还脏');

      await tester.tap(find.byKey(const Key('file-error-close')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('file-error-dialog')), findsNothing);
    });

    testWidgets('★ 打开抛异常 ⇒ 弹「打开失败」，文档原样',
        (WidgetTester tester) async {
      final FakeFileGateway gw =
          FakeFileGateway(throwOnOpen: Exception('文件被占用'));
      final (EditorPageState st, DocBuffer buf, FakeFileGateway _) =
          await _pump(tester, gateway: gw);
      final String before = buf.buf;
      // ★ 不能 `await`：`openDocument()` 内部 `await showDialog(...)`，对话框没人关就永远不返回
      unawaited(st.openDocument());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const Key('file-error-dialog')), findsOneWidget);
      expect(find.text('打开失败'), findsOneWidget);
      expect(buf.buf, before);
      expect(st.docFile.hasFile, isFalse);
      // 关掉对话框（不关会留 pending 路由 ⇒ 测试收尾挂住）
      await tester.tap(find.byKey(const Key('file-error-close')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });
  });
}