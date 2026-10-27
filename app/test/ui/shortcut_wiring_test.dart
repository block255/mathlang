// 数语引擎 · **快捷键接线**的守卫（S4-c）
//
// 这一批的意义不是"多几条键"，而是**设置页那张表不再撒谎**：
//   ① 表里 `● 已接入` 的动作，按键真的有效；
//   ② 表里 `○ 未接入`（只有 `sourceView`）**不抢键**；
//   ③ 用户在设置页**改键 / 加副绑定 / 停用**之后立刻生效（因为按键是"查表"，不是硬编码）。
//
// ★ 按键一律用 `sendKeyDown/Up` 成对发送 —— 修饰键漏了 Up 会卡在系统里（本仓踩过）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/lang/shortcut_registry.dart';
import 'package:mathlang/ui/editor_page.dart';

import '../support/fake_file_gateway.dart';
import '../support/symbol_fixture.dart';

Future<(EditorPageState, DocBuffer)> _pump(
  WidgetTester tester, {
  String doc = '甲乙丙',
  bool atEnd = false,
}) async {
  tester.view.physicalSize = const Size(1500, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer(doc)..setCaret(atEnd ? doc.length : 0);
  await tester.pumpWidget(MaterialApp(
    home: EditorPage(
      library: testSymbolLibrary(),
      buffer: buf,
      gateway: FakeFileGateway(),
    ),
  ));
  await tester.pumpAndSettle();
  // 点正文 ⇒ 让编辑面拿到焦点（键事件是从焦点节点往祖先冒泡的）
  await tester.tap(find.textContaining('甲').first);
  await tester.pumpAndSettle();
  // ★ 光标位置固定下来（断言才好写）：默认行首，插入类用 atEnd
  buf.setCaret(atEnd ? doc.length : 0);
  await tester.pump();
  return (tester.state<EditorPageState>(find.byType(EditorPage)), buf);
}

/// 发一个组合键：修饰键按下 → 主键 → 修饰键抬起
Future<void> _combo(
  WidgetTester tester,
  List<LogicalKeyboardKey> mods,
  LogicalKeyboardKey key,
) async {
  for (final LogicalKeyboardKey m in mods) {
    await tester.sendKeyDownEvent(m);
  }
  await tester.sendKeyEvent(key);
  for (final LogicalKeyboardKey m in mods.reversed) {
    await tester.sendKeyUpEvent(m);
  }
  await tester.pump();
}

const List<LogicalKeyboardKey> kCtrl = <LogicalKeyboardKey>[
  LogicalKeyboardKey.controlLeft
];
const List<LogicalKeyboardKey> kCtrlAlt = <LogicalKeyboardKey>[
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.altLeft,
];
const List<LogicalKeyboardKey> kCtrlShift = <LogicalKeyboardKey>[
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.shiftLeft,
];

void main() {
  group('① 结构类：标题 / 列表 / 引用 / 代码块 / 分页符', () {
    testWidgets('Ctrl+1 ⇒ 行首变 `# `（再按一次回正文）', (WidgetTester tester) async {
      final (_, DocBuffer buf) = await _pump(tester);
      await _combo(tester, kCtrl, LogicalKeyboardKey.digit1);
      expect(buf.buf, '# 甲乙丙\n');

      await _combo(tester, kCtrl, LogicalKeyboardKey.digit1);
      expect(buf.buf, '甲乙丙\n');
    });

    testWidgets('Ctrl+2 / Ctrl+3 各自对应级别', (WidgetTester tester) async {
      final (_, DocBuffer buf) = await _pump(tester);
      await _combo(tester, kCtrl, LogicalKeyboardKey.digit2);
      expect(buf.buf, '## 甲乙丙\n');
      await _combo(tester, kCtrl, LogicalKeyboardKey.digit3);
      expect(buf.buf, '### 甲乙丙\n');
    });

    testWidgets('Ctrl+Shift+8 ⇒ 无序列表', (WidgetTester tester) async {
      final (_, DocBuffer buf) = await _pump(tester);
      await _combo(tester, kCtrlShift, LogicalKeyboardKey.digit8);
      expect(buf.buf, '- 甲乙丙\n');
    });

    testWidgets('Ctrl+Shift+7 ⇒ 有序列表；Ctrl+Shift+9 ⇒ 引用',
        (WidgetTester tester) async {
      final (_, DocBuffer buf) = await _pump(tester);
      await _combo(tester, kCtrlShift, LogicalKeyboardKey.digit7);
      expect(buf.buf, '1. 甲乙丙\n');
      await _combo(tester, kCtrlShift, LogicalKeyboardKey.digit9);
      expect(buf.buf, '> 甲乙丙\n');
    });

    testWidgets('Ctrl+Alt+C ⇒ 代码块（围栏独占一行）',
        (WidgetTester tester) async {
      final (_, DocBuffer buf) = await _pump(tester, atEnd: true);
      await _combo(tester, kCtrlAlt, LogicalKeyboardKey.keyC);
      expect(buf.buf, '```\n甲乙丙\n```\n');
    });

    testWidgets('Ctrl+Enter ⇒ 插入分页符（自成一行）',
        (WidgetTester tester) async {
      final (_, DocBuffer buf) = await _pump(tester);
      await _combo(tester, kCtrl, LogicalKeyboardKey.enter);
      expect(buf.buf.split('\n').contains('<!-- pagebreak -->'), isTrue,
          reason: buf.buf);
    });
  });

  group('② 数学类：模板来自符号库（不与面板漂）', () {
    testWidgets('Ctrl+Alt+F ⇒ 分式，光标落在第一个空槽',
        (WidgetTester tester) async {
      final (_, DocBuffer buf) = await _pump(tester, atEnd: true);
      await _combo(tester, kCtrlAlt, LogicalKeyboardKey.keyF);
      expect(buf.buf, '${r'甲乙丙$\frac{}{}$'}\n');
      expect(buf.caret, 10, reason: '模板插入后光标要在分子空槽里（3 + 7）');
    });

    testWidgets('Ctrl+Alt+R ⇒ 根号', (WidgetTester tester) async {
      final (_, DocBuffer buf) = await _pump(tester, atEnd: true);
      await _combo(tester, kCtrlAlt, LogicalKeyboardKey.keyR);
      expect(buf.buf, '${r'甲乙丙$\sqrt{}$'}\n');
    });

    testWidgets('Ctrl+Alt+S ⇒ 求和（符号库的 tex，原样）',
        (WidgetTester tester) async {
      final (_, DocBuffer buf) = await _pump(tester, atEnd: true);
      await _combo(tester, kCtrlAlt, LogicalKeyboardKey.keyS);
      expect(buf.buf, '${r'甲乙丙$\sum_{}^{}$'}\n');
    });

    testWidgets('★ `Alt+=` 已撤掉 ⇒ 什么都不发生（不造空公式壳）',
        (WidgetTester tester) async {
      // 平权口径（2026-10-18 用户拍板）：数学不是模式，对象由**内容**产生
      // ⇒ "先造空壳再往里写"这条路不存在了。
      final (_, DocBuffer buf) = await _pump(tester, atEnd: true);
      await _combo(tester, <LogicalKeyboardKey>[LogicalKeyboardKey.altLeft],
          LogicalKeyboardKey.equal);
      expect(buf.buf, '甲乙丙', reason: '按下去必须什么都不发生');
    });

    testWidgets('★ `Ctrl+Alt+E` 回来，语义是「插入行间公式段」',
        (WidgetTester tester) async {
      // 用户拍板（2026-10-18）：行间是**块**，不写内容也成立（空态有淡虚线小框）；
      // 而行内必须由内容产生（`Alt+=` 保持撤掉）。
      final (_, DocBuffer buf) = await _pump(tester, atEnd: true);
      await _combo(tester, kCtrlAlt, LogicalKeyboardKey.keyE);
      expect(buf.buf.contains(r'$$'), isTrue, reason: buf.buf);
      expect(buf.buf.split('\n').where((String l) => l == r'$$').length, 2,
          reason: '两道围栏各占一行：${buf.buf}');
    });

    testWidgets('Ctrl+ArrowUp ⇒ 上标模板（正文里自动建壳）',
        (WidgetTester tester) async {
      final (_, DocBuffer buf) = await _pump(tester, atEnd: true);
      await _combo(tester, kCtrl, LogicalKeyboardKey.arrowUp);
      // 正文里没有基座 ⇒ 用 `{}^{}`（直接写 `^{}` 会 `Parser Error: Expected group`）
      expect(buf.buf.contains(r'{}^{}'), isTrue, reason: buf.buf);
      expect(buf.buf.contains(r'$'), isTrue, reason: '正文里要自动建壳');
    });
  });

  group('③ 设置页说真话：改键 / 停用 / 未接入', () {
    testWidgets('★ 改键之后：新键有效、旧键失效', (WidgetTester tester) async {
      final (EditorPageState st, DocBuffer buf) =
          await _pump(tester, atEnd: true);
      // 把「分式」改到 Ctrl+Alt+Q
      st.shortcuts = ShortcutSettings.defaults()
          .withCombo('frac', 0, ShortcutCombo.parse('Ctrl+Alt+Q'));
      await tester.pump();

      await _combo(tester, kCtrlAlt, LogicalKeyboardKey.keyQ);
      expect(buf.buf, '${r'甲乙丙$\frac{}{}$'}\n', reason: '改了键就该按新键生效');

      buf.loadDocument('甲乙丙');
      buf.setCaret(0);
      await tester.pump();
      await _combo(tester, kCtrlAlt, LogicalKeyboardKey.keyF);
      expect(buf.buf, '甲乙丙\n', reason: '旧键已经不再绑这条动作');
    });

    testWidgets('★ 停用之后：按键不做事', (WidgetTester tester) async {
      final (EditorPageState st, DocBuffer buf) = await _pump(tester);
      st.shortcuts = ShortcutSettings.defaults().toggleEnabled('frac');
      await tester.pump();
      await _combo(tester, kCtrlAlt, LogicalKeyboardKey.keyF);
      expect(buf.buf, '甲乙丙');
    });

    testWidgets('★★ 源码视图（Ctrl+Alt+D）现在**真的开了只读浮层**，且不改正文（U1）',
        (WidgetTester tester) async {
      final (_, DocBuffer buf) = await _pump(tester);
      await _combo(tester, kCtrlAlt, LogicalKeyboardKey.keyD);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('source-dialog')), findsOneWidget,
          reason: 'U1 之后这条键接上了「高级 → 查看源码」同一个浮层');
      expect(buf.buf, '甲乙丙', reason: '看源码不许改正文');
      await tester.tap(find.byKey(const Key('source-close')));
      await tester.pumpAndSettle();
    });

    test('登记表口径：48 条**全部已接入**（U1 把源码视图接成只读浮层）', () {
      expect(kShortcutActions.length, 48);
      expect(ShortcutSettings.wiredCount, 48);
      final List<String> planned = <String>[
        for (final ShortcutAction a in kShortcutActions)
          if (!a.wired) a.id,
      ];
      expect(planned, isEmpty);
    });

    test('外壳接的动作必须是"已接入"的（否则说了不做）', () {
      for (final String id in kShellActions) {
        final ShortcutAction? a = ShortcutSettings.defaults().actionOf(id);
        expect(a, isNotNull, reason: '$id 不在登记表里');
        expect(a!.wired, isTrue, reason: '$id 未接入却被外壳接走了按键');
      }
    });
  });
}
