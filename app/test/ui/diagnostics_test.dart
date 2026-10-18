// ★★ S4-b② 诊断清单守卫（《界面与布局》§11-7 / 原则 5「可疑要可见」）
//
// 守的是三件事：
//   ① 自动包裹之后，状态栏出现**可点**的「自动包裹 N 处 · 查看清单 ›」；
//   ② 清单里列出**具体那几处**（不是只有数量），点一条 ⇒ 弹窗关闭 + 选中那一段（≠ 一次编辑）；
//   ③ 没有可疑项时清单也说人话（不空着）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/ui/editor_page.dart';

import '../support/symbol_fixture.dart';

Future<(EditorPageState, DocBuffer)> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1500, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer('开头。')..setCaret(3);
  await tester.pumpWidget(MaterialApp(
    home: EditorPage(library: testSymbolLibrary(), buffer: buf),
  ));
  await tester.pumpAndSettle();
  return (
    tester.state<EditorPageState>(find.byType(EditorPage)),
    buf,
  );
}

/// 做一次"会被智能包裹"的粘贴（`x^2+1` ⇒ `$x^2+1$`）
Future<void> _pasteMath(WidgetTester tester) async {
  final EditViewState v = tester.state<EditViewState>(find.byType(EditView));
  v.focusInput();
  v.pasteText('x^2+1');
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('没有可疑项时：没有可点的清单入口', (WidgetTester tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('diag-open')), findsNothing);
  });

  testWidgets('★ 自动包裹后出现可点入口，点开列出**具体区间**',
      (WidgetTester tester) async {
    final (EditorPageState st, DocBuffer buf) = await _pump(tester);
    await _pasteMath(tester);
    expect(buf.buf, contains(r'$'), reason: '前置：确实补了壳');

    expect(find.byKey(const Key('diag-open')), findsOneWidget);
    await tester.tap(find.byKey(const Key('diag-open')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('diagnostics-dialog')), findsOneWidget);
    expect(find.byKey(const Key('diagnostic-item-0')), findsWidgets);
    expect(st.dirty, isTrue);
    // 清单里的摘要应当是那段公式的源码
    expect(find.textContaining('x^2+1'), findsWidgets);
  });

  testWidgets('★ 点一条 ⇒ 关闭清单 + 选中那一段，且**不算一次编辑**',
      (WidgetTester tester) async {
    final (EditorPageState _, DocBuffer buf) = await _pump(tester);
    await _pasteMath(tester);
    final EditViewState v = tester.state<EditViewState>(find.byType(EditView));
    final int editsBefore = v.edits;
    final String before = buf.buf;

    await tester.tap(find.byKey(const Key('diag-open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('diagnostic-item-0')).first);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('diagnostics-dialog')), findsNothing);
    expect(buf.buf, before, reason: '跳转不是编辑');
    expect(v.edits, editsBefore);
    expect(buf.hasSelection, isTrue, reason: '必须**选中**那一段（高亮 = 看得见）');
    expect(buf.buf.substring(buf.selectionStart, buf.selectionEnd), contains('x^2+1'));
  });

  testWidgets('粘贴纯文本（不产生包裹）⇒ 入口不出现', (WidgetTester tester) async {
    await _pump(tester);
    final EditViewState v = tester.state<EditViewState>(find.byType(EditView));
    v.focusInput();
    v.pasteText('这是一段中文说明');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('diag-open')), findsNothing);
  });
}
