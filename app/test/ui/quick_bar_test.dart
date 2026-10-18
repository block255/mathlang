// ★★ S4-b② 快捷栏守卫（《界面与布局.md》§5）
//
// 用户 2026-10-17 定的流程原话：
//   「先点某个栏位"选中" ⇒ 再点面板里任意符号 ⇒ 放进该格（替换旧的）；
//     空格点一下进入赋值模式、`Esc` 取消；长按格子可清空」；「`Alt+1..8` 直接插入第 N 格」。
//
// 三条被判据化的东西：
//   ① **赋值 ≠ 插入**：赋值模式下点符号**不往正文里写字**（这是最容易做错的一条）；
//   ② 快捷栏与面板**各有自己的开关**（互不牵连）；
//   ③ `Alt+N` 在面板关着时也能用（外壳层快捷键，不走面板）。

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/ui/app_settings.dart';
import 'package:mathlang/ui/editor_page.dart';
import 'package:mathlang/ui/quick_bar.dart';

import '../support/symbol_fixture.dart';

Future<(EditorPageState, DocBuffer)> _pump(
  WidgetTester tester, {
  String doc = 'abc',
  int caret = 1,
  AppSettings settings = const AppSettings(),
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer(doc)..setCaret(caret);
  await tester.pumpWidget(MaterialApp(
    home: EditorPage(
      library: testSymbolLibrary(),
      settings: settings,
      buffer: buf,
    ),
  ));
  await tester.pumpAndSettle();
  return (tester.state<EditorPageState>(find.byType(EditorPage)), buf);
}

void main() {
  group('① 形态与独立开关', () {
    testWidgets('默认 8 格都在，快捷栏宽度 = 格数推算', (WidgetTester tester) async {
      await _pump(tester);
      for (var i = 0; i < 8; i++) {
        expect(find.byKey(Key('quick-slot-$i')), findsOneWidget);
      }
      expect(tester.getSize(find.byType(QuickBar)).width,
          LayoutMetrics.panelWidth(8));
    });

    testWidgets('★ 空栏位不画加号，只留序号（2026-10-18 晚用户定）',
        (WidgetTester tester) async {
      await _pump(
        tester,
        settings: const AppSettings(
          favorites: <String?>['plus', null, null, null],
        ),
      );
      await tester.pumpAndSettle();
      // ★ 判据：快捷栏里**一个** `+` 图标都没有（空位靠序号辨认，不靠加号）
      expect(
        find.descendant(
          of: find.byType(QuickBar),
          matching: find.byIcon(Icons.add),
        ),
        findsNothing,
        reason: '用户原话：「快捷栏空栏位不要加号，简洁一点」',
      );
      // 空位仍要**看得出这是第几格**（序号在左上角，字号 8）
      expect(
        find.descendant(
          of: find.byKey(const Key('quick-slot-7')),
          matching: find.text('8'),
        ),
        findsOneWidget,
        reason: '空位不能变成"什么都没有"：序号是唯一的身份线索',
      );
      // 有内容的格子照旧画符号预览（`symbolPreview` = FittedBox + Math.tex）
      expect(
        find.descendant(
          of: find.byKey(const Key('quick-slot-0')),
          matching: find.byType(FittedBox),
        ),
        findsOneWidget,
      );
      // 空位**除了序号什么都不画**
      expect(
        find.descendant(
          of: find.byKey(const Key('quick-slot-7')),
          matching: find.byType(FittedBox),
        ),
        findsNothing,
      );
    });

    testWidgets('★ 关掉快捷栏不影响面板；两者都关 ⇒ 右栏消失',
        (WidgetTester tester) async {
      final (EditorPageState st, DocBuffer _) = await _pump(tester);
      st.togglePanel(open: true);
      await tester.pumpAndSettle();
      expect(find.byType(QuickBar), findsOneWidget);
      expect(find.byKey(const Key('symbol-search')), findsOneWidget);

      st.toggleQuickBar(open: false);
      await tester.pumpAndSettle();
      expect(find.byType(QuickBar), findsNothing);
      expect(find.byKey(const Key('symbol-search')), findsOneWidget,
          reason: '★ 快捷栏收起不影响面板');

      st.togglePanel(open: false);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('right-column')), findsNothing,
          reason: '都收起 ⇒ 右栏消失');
    });
  });

  group('② 赋值流程（选中栏位 ⇒ 点符号 ⇒ 入格）', () {
    testWidgets('点空格 ⇒ 进入赋值模式并出提示条', (WidgetTester tester) async {
      final (EditorPageState st, DocBuffer _) = await _pump(tester);
      await tester.tap(find.byKey(const Key('quick-slot-2')));
      await tester.pumpAndSettle();
      expect(st.assignSlot, 2);
      expect(find.byKey(const Key('quick-assign-hint')), findsOneWidget);
    });

    testWidgets('★ 赋值模式点面板符号 ⇒ 只入格、**不写正文**', (WidgetTester tester) async {
      final (EditorPageState st, DocBuffer buf) = await _pump(tester);
      st.togglePanel(open: true);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quick-slot-2')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('symbol-frac')));
      await tester.pumpAndSettle();

      expect(st.settings.favoriteAt(2), 'frac');
      expect(st.assignSlot, isNull, reason: '赋值完自动退出赋值模式');
      expect(buf.buf, 'abc', reason: '★ 赋值不是插入：正文一个字都不该变');
      expect(buf.caret, 1);
    });

    testWidgets('Esc 取消赋值模式（不改内容）', (WidgetTester tester) async {
      final (EditorPageState st, DocBuffer _) = await _pump(tester);
      st.beginAssign(3);
      await tester.pumpAndSettle();
      // 键事件从**主焦点**向上冒泡才到外壳 Focus ⇒ 先让编辑器拿到焦点（真实使用里它一直有）
      tester.state<EditViewState>(find.byType(EditView)).focusInput();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(st.assignSlot, isNull);
      expect(st.settings.favoriteAt(3), isNull);
    });

    testWidgets('长按已有格 ⇒ 清空', (WidgetTester tester) async {
      final (EditorPageState st, DocBuffer _) = await _pump(
        tester,
        settings: const AppSettings(favorites: <String?>['frac', null, null, null]),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const Key('quick-slot-0')));
      await tester.pumpAndSettle();
      expect(st.settings.favoriteAt(0), isNull);
    });

    testWidgets('★★ 右键已有格 ⇒ **换掉**这一格（不插入、面板自动打开）',
        (WidgetTester tester) async {
      // 用户 2026-10-18 晚：「左键已占的格就是打出这个东西；之前设计稿里还有个选中功能，
      //   我觉得可以右键……选中时再点面板里一个符号，可以进行替换」
      final (EditorPageState st, DocBuffer buf) = await _pump(
        tester,
        settings: const AppSettings(favorites: <String?>['plus', null, null, null]),
      );
      await tester.pumpAndSettle();
      // 先把面板关掉，验"右键会顺手把它打开"
      st.togglePanel(open: false);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('quick-slot-0')),
          buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      expect(st.assignSlot, 0, reason: '右键 = 选中这一格（进赋值模式）');
      expect(st.panelOpen, isTrue, reason: '下一步必然要点面板符号 ⇒ 顺手打开');
      expect(find.byKey(const Key('quick-assign-hint')), findsOneWidget);
      expect(buf.buf, 'abc', reason: '右键本身**不插入**任何东西');

      // 换掉：点面板里的分式
      await tester.tap(find.byKey(const Key('symbol-frac')));
      await tester.pumpAndSettle();
      expect(st.settings.favoriteAt(0), 'frac', reason: '第 1 格被换成 `\\frac`');
      expect(st.assignSlot, isNull);
      expect(buf.buf, 'abc', reason: '★ 赋值不是插入');
    });

    testWidgets('★ 右键**空格**也进赋值模式（统一成"右键 = 编辑这一格"）',
        (WidgetTester tester) async {
      final (EditorPageState st, DocBuffer _) = await _pump(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quick-slot-5')),
          buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(st.assignSlot, 5);
    });
  });

  group('③ 使用：点格子 / Alt+1..8', () {
    testWidgets('点已有内容的格子 ⇒ 插入一次编辑', (WidgetTester tester) async {
      final (EditorPageState st, DocBuffer buf) = await _pump(
        tester,
        settings: const AppSettings(favorites: <String?>['plus', null, null, null]),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quick-slot-0')));
      await tester.pumpAndSettle();
      expect(buf.buf, r'a$+$bc', reason: r'紧邻文字 ⇒ 自动建壳 `$+$`');
      expect(tester.state<EditViewState>(find.byType(EditView)).edits, 1);
      expect(st.assignSlot, isNull, reason: '插入模式不该顺带进赋值模式');
    });

    testWidgets('★ Alt+1 在面板关着时也能插入', (WidgetTester tester) async {
      final (EditorPageState st, DocBuffer buf) = await _pump(
        tester,
        settings: const AppSettings(
          favorites: <String?>['frac', null, null, null],
        ),
      );
      await tester.pumpAndSettle();
      // ★ 2026-10-18 晚：面板**默认已打开**（用户定的），这条测的是"面板关着也插入"
      //   ⇒ 先显式关掉（判据不变：Alt+N 不依赖面板状态）。
      st.togglePanel(open: false);
      await tester.pumpAndSettle();
      expect(st.panelOpen, isFalse);
      // 让编辑器拿到焦点（键事件从主焦点向上冒泡到外壳 Focus）
      tester.state<EditViewState>(find.byType(EditView)).focusInput();
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();

      expect(buf.buf, contains(r'\frac'), reason: '★ Alt+1 = 快捷栏第 1 格');
    });

    testWidgets('空格 Alt+N ⇒ 什么也不插入', (WidgetTester tester) async {
      final (EditorPageState _, DocBuffer buf) = await _pump(tester);
      tester.state<EditViewState>(find.byType(EditView)).focusInput();
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(buf.buf, 'abc');
    });
  });
}
