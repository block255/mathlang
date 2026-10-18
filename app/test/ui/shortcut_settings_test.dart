// ★★ S4-b② 快捷键设置页守卫（《界面与布局》§6.5）
//
// 这一页的存在意义是**不撒谎**：39 条里 17 条已接入，其余必须带"未接入"徽标。
// 同时守用户拍板的边界：
//   · "添加" = 给同一个动作加**副绑定**（≤2 条）；
//   · 浏览器独占键 / 已被占用的键 **当场拒收**（SnackBar 说原因，值不变）；
//   · 默认项只能"停用"或"恢复默认"，不能删主键。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/lang/shortcut_registry.dart';
import 'package:mathlang/ui/editor_page.dart';
import 'package:mathlang/ui/shortcut_page.dart';

import '../support/symbol_fixture.dart';

Future<EditorPageState> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1500, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer('abc')..setCaret(1);
  await tester.pumpWidget(MaterialApp(
    home: EditorPage(library: testSymbolLibrary(), buffer: buf),
  ));
  await tester.pumpAndSettle();
  final EditorPageState st = tester.state<EditorPageState>(find.byType(EditorPage));
  st.openSettings(group: 5);
  await tester.pumpAndSettle();
  return st;
}

/// 在某个"按键框"里按下一个组合键
Future<void> _capture(WidgetTester tester, String actionId, int index,
    {List<LogicalKeyboardKey> mods = const <LogicalKeyboardKey>[],
    required LogicalKeyboardKey key}) async {
  // ★ 快捷键组有 40+ 行 ⇒ 目标常常在折叠区外，必须先滚到可见（否则 tap 点空）
  await tester.ensureVisible(find.byKey(Key('shortcut-key-$actionId-$index')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('shortcut-key-$actionId-$index')));
  await tester.pumpAndSettle();
  for (final LogicalKeyboardKey m in mods) {
    await tester.sendKeyDownEvent(m);
  }
  await tester.sendKeyEvent(key);
  for (final LogicalKeyboardKey m in mods.reversed) {
    await tester.sendKeyUpEvent(m);
  }
  await tester.pumpAndSettle();
}

void main() {
  group('① 这张表说实话', () {
    testWidgets('顶部报 已接入 23 / 共 45', (WidgetTester tester) async {
      await _pump(tester);
      expect(find.text('已接入 23 / 共 45'), findsOneWidget);
    });

    testWidgets('已接入的（撤销）与未接入的（分式）徽标不同',
        (WidgetTester tester) async {
      await _pump(tester);
      expect(
          find.descendant(
              of: find.byKey(const Key('shortcut-status-undo')),
              matching: find.text('已接入')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('shortcut-status-frac')),
              matching: find.text('未接入')),
          findsOneWidget);
    });

    testWidgets('默认表不报冲突（打开就该是干净的）', (WidgetTester tester) async {
      await _pump(tester);
      expect(find.byKey(const Key('shortcut-conflict-banner')), findsNothing);
    });
  });

  group('② 改键 / 添加副键 / 停用 / 恢复默认', () {
    testWidgets('★ 按键捕获：点框 + 按 Ctrl+Alt+K ⇒ 分式换成 Ctrl+Alt+K',
        (WidgetTester tester) async {
      final EditorPageState st = await _pump(tester);
      expect(st.shortcuts.combosOf('frac').first.label, 'Ctrl+Alt+F');

      await _capture(tester, 'frac', 0, mods: <LogicalKeyboardKey>[
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.altLeft,
      ], key: LogicalKeyboardKey.keyK);

      expect(st.shortcuts.combosOf('frac').first.label, 'Ctrl+Alt+K');
      expect(find.byKey(const Key('shortcut-reset-frac')), findsOneWidget,
          reason: '改过的项才亮 ↺');
    });

    testWidgets('★ 已被占用的键当场拒收（值不变）', (WidgetTester tester) async {
      final EditorPageState st = await _pump(tester);
      // Ctrl+Alt+S 是「求和」
      await _capture(tester, 'frac', 0, mods: <LogicalKeyboardKey>[
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.altLeft,
      ], key: LogicalKeyboardKey.keyS);
      expect(st.shortcuts.combosOf('frac').first.label, 'Ctrl+Alt+F',
          reason: '被占用 ⇒ 不改');
      expect(find.textContaining('已被「求和」占用'), findsOneWidget);
    });

    testWidgets('★ 浏览器独占键拒收', (WidgetTester tester) async {
      final EditorPageState st = await _pump(tester);
      await _capture(tester, 'frac', 0, mods: <LogicalKeyboardKey>[
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.shiftLeft,
      ], key: LogicalKeyboardKey.keyI);
      expect(st.shortcuts.combosOf('frac').first.label, 'Ctrl+Alt+F');
      expect(find.textContaining('浏览器独占'), findsOneWidget);
    });

    testWidgets('添加副键 ⇒ 两条；再删掉副键 ⇒ 回一条', (WidgetTester tester) async {
      final EditorPageState st = await _pump(tester);
      await tester.ensureVisible(find.byKey(const Key('shortcut-add-frac')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('shortcut-add-frac')));
      await tester.pumpAndSettle();
      expect(st.shortcuts.combosOf('frac').length, 2);

      await _capture(tester, 'frac', 1, mods: <LogicalKeyboardKey>[
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.altLeft,
      ], key: LogicalKeyboardKey.keyM);
      expect(st.shortcuts.combosOf('frac')[1].label, 'Ctrl+Alt+M');

      await tester.ensureVisible(find.byKey(const Key('shortcut-del-frac-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('shortcut-del-frac-1')));
      await tester.pumpAndSettle();
      expect(st.shortcuts.combosOf('frac').length, 1);
    });

    testWidgets('停用 / 恢复默认', (WidgetTester tester) async {
      final EditorPageState st = await _pump(tester);
      await tester.ensureVisible(find.byKey(const Key('shortcut-enable-frac')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('shortcut-enable-frac')));
      await tester.pumpAndSettle();
      expect(st.shortcuts.isDisabled('frac'), isTrue);
      expect(find.text('已停用'), findsWidgets);

      await tester.ensureVisible(find.byKey(const Key('shortcut-reset-frac')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('shortcut-reset-frac')));
      await tester.pumpAndSettle();
      expect(st.shortcuts.isDisabled('frac'), isFalse);
    });

    testWidgets('★ 冲突（默认表漂移造成）⇒ 顶部横幅 + 行内红字',
        (WidgetTester tester) async {
      // 换键时**会被当场拒收**（这是好事）⇒ 冲突只可能来自"默认表自己撞了"
      // （将来新增动作撞老键）。这条直接注入一份冲突状态，守横幅与红字。
      final ShortcutSettings bad = ShortcutSettings.defaults()
          .withCombo('sqrt', 0, ShortcutCombo.parse('Ctrl+Alt+F'));
      expect(bad.conflicts(), containsAll(<String>['sqrt', 'frac']));

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: ShortcutSettingsView(
              settings: bad,
              onChanged: (ShortcutSettings _) {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shortcut-conflict-banner')), findsOneWidget);
      expect(find.byKey(const Key('shortcut-conflict-frac')), findsOneWidget,
          reason: '行内也要指出"被谁占用"');
      expect(find.textContaining('已被「分式」占用'), findsWidgets);
    });

    testWidgets('搜索过滤', (WidgetTester tester) async {
      await _pump(tester);
      await tester.enterText(find.byKey(const Key('shortcut-search')), '撤销');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shortcut-row-undo')), findsOneWidget);
      expect(find.byKey(const Key('shortcut-row-frac')), findsNothing);
    });
  });

  group('③ 词触发表', () {
    testWidgets('默认 8 行，可加行可删行', (WidgetTester tester) async {
      final EditorPageState st = await _pump(tester);
      st.openSettings(group: 6);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('trigger-row-0')), findsOneWidget);
      final int before = st.triggers.triggers.length;

      await tester.tap(find.byKey(const Key('trigger-add')));
      await tester.pumpAndSettle();
      expect(st.triggers.triggers.length, before + 1);
      expect(find.byKey(const Key('trigger-invalid-8')), findsOneWidget,
          reason: '新行是空的 ⇒ 立刻标红（不假装能用）');

      await tester.tap(find.byKey(const Key('trigger-del-8')));
      await tester.pumpAndSettle();
      expect(st.triggers.triggers.length, before);
    });

    testWidgets('改词会写进 TriggerSettings', (WidgetTester tester) async {
      final EditorPageState st = await _pump(tester);
      st.openSettings(group: 6);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('trigger-word-0')), 'root');
      await tester.pumpAndSettle();
      expect(st.triggers.triggers[0].word, 'root');
    });
  });
}
