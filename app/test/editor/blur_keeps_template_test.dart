// ★★★ 2026-10-20（T-A 实测 F8，用户拍板"乙"）：**刚插进来的空模板，失焦不许消失**。
//
// 走**真实路径**：面板插模板 → 编辑器失焦（`_onFocusChanged` ⇒ `_normalizeOnCommit`）。
// 改前：`$\frac{}{}$`（11 字符）⇒ 失焦后 `$$`（2 字符），用户看到"我刚插的东西凭空没了"。
// 改后：一个字都不动。
//
// 同时锚住反例（免得把"保住"做成"永远不回收"）：**光标不在里面的**空壳照旧回收。
//
// ★ 测试必须注入 `NoopSessionStore`：否则 `EditorPage` 会去读**真实的**开发暂存
//   （`app\build\windows\x64\runner\Debug\mathlang-session.json`），异步恢复把测试文档顶掉
//   —— 我第一次跑就撞上了（文档莫名变成 `$$`）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/io/session_store.dart';
import 'package:mathlang/ui/editor_page.dart';

import '../support/fake_file_gateway.dart';
import '../support/symbol_fixture.dart';

Future<(DocBuffer, EditViewState)> _pump(
    WidgetTester tester, String doc) async {
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
      session: const NoopSessionStore(),
    ),
  ));
  await tester.pumpAndSettle();
  final EditViewState st = tester.state<EditViewState>(find.byType(EditView));
  return (buf, st);
}

/// 编辑器失焦（= normalize 的提交点）
Future<void> _blur(WidgetTester tester, EditViewState st) async {
  st.focusInput();
  await tester.pumpAndSettle();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('★ F8：插一个空分式模板 ⇒ 失焦后**一个字都不动**',
      (WidgetTester tester) async {
    final (DocBuffer buf, EditViewState st) = await _pump(tester, '');
    st.insertSymbolTex(r'\frac{}{}', template: true);
    await tester.pumpAndSettle();
    expect(buf.buf, '${r'$\frac{}{}$'}\n', reason: '模板插进来了（11 字符 + 行终止符）');

    await _blur(tester, st);
    expect(buf.buf, '${r'$\frac{}{}$'}\n',
        reason: r'改前这里会变成 `$$`（空分式被提交点回收）');
  });

  testWidgets('★ F8：光标贴着结构末尾（按过 → 出槽）也保住',
      (WidgetTester tester) async {
    final (DocBuffer buf, EditViewState st) = await _pump(tester, '');
    st.insertSymbolTex(r'\frac{}{}', template: true);
    await tester.pumpAndSettle();
    // 把光标挪到"整个空分式之后"（= 文末行末，行终止符之前那一格）
    buf.setCaret(buf.buf.length - 1);
    await tester.pumpAndSettle();
    await _blur(tester, st);
    expect(buf.buf, '${r'$\frac{}{}$'}\n');
  });

  testWidgets('★ F8 反例：光标在同段公式里、但不在那个空壳里 ⇒ 照旧回收',
      (WidgetTester tester) async {
    // `$x+\frac{}{}$`：光标放在 `+` 左边那一格（在公式里，但不在分式里）
    final (DocBuffer buf, EditViewState st) = await _pump(tester, r'$x+\frac{}{}$');
    buf.setCaret(2);
    await tester.pumpAndSettle();
    await _blur(tester, st);
    expect(buf.buf, '${r'$x+$'}\n',
        reason: '光标不在的空壳还是要回收（别做成"永远不回收"）');
  });
}
