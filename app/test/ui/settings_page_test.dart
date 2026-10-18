// ★★ S4-b② 设置页守卫（《界面与布局.md》§6 / §6.2 / §6.3）
//
// 用户 2026-10-17 定的两条：
//   「设置可以设置一个单独的**设置页面**，而不是这样一个按钮列表，这样不太好精细调整。」
//   「把设置页面做成**半透明**，让用户在改动时也能透过它看到编辑器页面如何」
//
// 所以这里同时守**功能**与**"上限"**：
//   ① 每个数值项都能**改回去**（步进器可减、单项 ↺ 能恢复）——老实现"点一下 +2，回不去 7"；
//   ② 布局类设置**只平移不改宽**（`pageXDock` 任意值下 `EditView` 宽恒 = 页宽）；
//   ③ 文档类设置**允许**改正文宽（那是文档级排版），但要跟着改 `DocSettings`；
//   ④ 半透明覆盖层不换路由（编辑器还在后面）+ 有 peek + 有"全部恢复默认"。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/core/doc_settings.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/layout/page_metrics.dart';
import 'package:mathlang/ui/app_settings.dart';
import 'package:mathlang/ui/editor_page.dart';

import '../support/symbol_fixture.dart';

const double _pageWidth = 793.7007874015748;

Future<EditorPageState> _pump(WidgetTester tester, {int group = 0}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer('abc')..setCaret(1);
  await tester.pumpWidget(MaterialApp(
    home: EditorPage(library: testSymbolLibrary(), buffer: buf),
  ));
  await tester.pumpAndSettle();
  final EditorPageState st = tester.state<EditorPageState>(find.byType(EditorPage));
  st.openSettings(group: group);
  await tester.pumpAndSettle();
  return st;
}

double _editWidth(WidgetTester tester) =>
    tester.getSize(find.byType(EditView).first).width;
double _editLeft(WidgetTester tester) =>
    tester.getTopLeft(find.byType(EditView).first).dx;

void main() {
  group('① 覆盖层不换路由 + 半透明 + peek', () {
    testWidgets('打开设置：配置文件仍在、卡片出现、可返回',
        (WidgetTester tester) async {
      final EditorPageState st = await _pump(tester);
      expect(st.settingsOpen, isTrue);
      expect(find.byKey(const Key('settings-card')), findsOneWidget);
      expect(find.byType(EditView), findsOneWidget,
          reason: '★ 不是 Navigator.push 的新页 —— 编辑器始终在树里（半透明才看得见）');
      expect(find.byKey(const Key('settings-peek')), findsOneWidget);

      await tester.tap(find.byKey(const Key('settings-close')));
      await tester.pumpAndSettle();
      expect(st.settingsOpen, isFalse);
      expect(find.byKey(const Key('settings-card')), findsNothing);
    });

    testWidgets('九组都在（四组标"待接入"，不假装能用）', (WidgetTester tester) async {
      await _pump(tester);
      for (final String g in <String>[
        '文档与排版',
        '布局',
        '面板',
        '快捷栏',
        '状态栏',
        '快捷键',
        '智能输入',
        '高级',
        '关于',
      ]) {
        expect(find.byKey(Key('settings-group-$g')), findsOneWidget,
            reason: '缺分组：$g');
      }
    });
  });

  group('② 布局：只平移不改宽（pageXDock）', () {
    testWidgets('★ 任意 dock 值下 EditView 宽恒 = 页宽，只有 x 变',
        (WidgetTester tester) async {
      final EditorPageState st = await _pump(tester, group: 1);
      final double w0 = _editWidth(tester);
      final double x0 = _editLeft(tester);
      expect(w0, closeTo(_pageWidth, 0.5));

      // 拖到"居中"
      await tester.tap(find.byKey(const Key('dock-居中')));
      await tester.pumpAndSettle();
      expect(st.settings.pageXDock, 0.5);
      expect(_editWidth(tester), closeTo(w0, 0.5),
          reason: '★ 布局设置只挪位置，不许改宽（分页不变）');
      expect(_editLeft(tester), greaterThan(x0), reason: '居中也得真的往右挪');

      // 再拖到"贴右"
      await tester.tap(find.byKey(const Key('dock-贴右')));
      await tester.pumpAndSettle();
      expect(st.settings.pageXDock, 1);
      expect(_editWidth(tester), closeTo(w0, 0.5));
      expect(_editLeft(tester), greaterThan(x0));
    });

    testWidgets('单项 ↺ 能回默认（老实现"回不去"就是这个坑）',
        (WidgetTester tester) async {
      final EditorPageState st = await _pump(tester, group: 1);
      await tester.tap(find.byKey(const Key('dock-居中')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reset-页面位置')), findsOneWidget,
          reason: '★ 改过的项才亮 ↺');
      await tester.tap(find.byKey(const Key('reset-页面位置')));
      await tester.pumpAndSettle();
      expect(st.settings.pageXDock, 0);
    });
  });

  group('③ 面板：列数可加**可减**，面板宽跟着算', () {
    testWidgets('列数 8 ⇒ 9 ⇒ 7（双向、步进 1）', (WidgetTester tester) async {
      final EditorPageState st = await _pump(tester, group: 2);
      expect(st.settings.gridColumns, 8);
      expect(find.text('⇒ 面板宽 418 px'), findsNWidgets(2),
          reason: '列数与格子尺寸两处都会报同一句"后果"');

      await tester.tap(find.byKey(const Key('stepper-inc-网格列数')));
      await tester.pumpAndSettle();
      expect(st.settings.gridColumns, 9);

      await tester.tap(find.byKey(const Key('stepper-dec-网格列数')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('stepper-dec-网格列数')));
      await tester.pumpAndSettle();
      expect(st.settings.gridColumns, 7,
          reason: '★ 老实现只能 8→10→12，回不到 7');
      expect(
          find.text(
              '⇒ 面板宽 ${LayoutMetrics.panelWidth(7).toStringAsFixed(0)} px'),
          findsNWidgets(2));
    });

    testWidgets('关掉"格子显示中文名" ⇒ 面板不再画标签', (WidgetTester tester) async {
      final EditorPageState st = await _pump(tester, group: 2);
      await tester.tap(find.byKey(const Key('switch-格子里显示中文名')));
      await tester.pumpAndSettle();
      expect(st.settings.showCellLabels, isFalse);
    });
  });

  group('④ 文档与排版：改字号 / 页边距 / 行间公式字号', () {
    testWidgets('正文字号预设 ⇒ DocSettings 变，但页宽不变',
        (WidgetTester tester) async {
      final EditorPageState st = await _pump(tester, group: 0);
      await tester.tap(find.byKey(const Key('num-preset-正文字号-14')));
      await tester.pumpAndSettle();
      expect(st.doc.bodyFontSize, 14);
      expect(PageGeometry.from(st.doc).pageWidth, closeTo(_pageWidth, 0.01),
          reason: '字号不改页宽');
    });

    testWidgets('★ 行间公式字号：设了能改回"跟随正文"（copyWith 那个 null 坑）',
        (WidgetTester tester) async {
      final EditorPageState st = await _pump(tester, group: 0);
      expect(st.doc.displayFontSize, isNull);
      await tester.tap(find.byKey(const Key('num-preset-行间公式字号-20')));
      await tester.pumpAndSettle();
      expect(st.doc.displayFontSize, 20);

      await tester.tap(find.byKey(const Key('reset-行间公式字号')));
      await tester.pumpAndSettle();
      expect(st.doc.displayFontSize, isNull,
          reason: '★ "跟随正文"必须能真的恢复（copyWith 传 null = 不改，所以另开了开关）');
    });

    testWidgets('页边距锁着 ⇒ 四个一起动；关掉锁 ⇒ 只动一个',
        (WidgetTester tester) async {
      final EditorPageState st = await _pump(tester, group: 0);
      expect(find.byKey(const Key('margin-lock')), findsOneWidget);

      // 锁着：改"上"⇒ 四边都变
      await tester.enterText(find.byKey(const Key('numrow-field-上')), '30');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(st.doc.marginTopMm, 30);
      expect(st.doc.marginBottomMm, 30);
      expect(st.doc.marginLeftMm, 30);
      expect(st.doc.marginRightMm, 30);
      // ★ 文档级设置**允许**改正文宽（与"UI 不许改宽"不是一回事）
      expect(PageGeometry.from(st.doc).contentWidth,
          lessThan(PageGeometry.from(DocSettings.defaults).contentWidth));

      // 解锁：只改"上"
      await tester.tap(find.byKey(const Key('margin-lock')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('numrow-field-上')), '10');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(st.doc.marginTopMm, 10);
      expect(st.doc.marginBottomMm, 30, reason: '解锁后不该连坐');
    });
  });

  group('⑤ 状态栏与"全部恢复默认"', () {
    testWidgets('取消「字数」⇒ 状态栏不再显示字符数', (WidgetTester tester) async {
      final EditorPageState st = await _pump(tester, group: 4);
      expect(find.textContaining('字符'), findsWidgets);
      await tester.tap(find.byKey(const Key('status-item-字数')));
      await tester.pumpAndSettle();
      expect(st.settings.statusItems.contains(StatusItem.chars), isFalse);
      expect(find.textContaining('字符'), findsNothing);
    });

    testWidgets('全部恢复默认 ⇒ 设置与文档都回默认值', (WidgetTester tester) async {
      final EditorPageState st = await _pump(tester, group: 2);
      await tester.tap(find.byKey(const Key('stepper-inc-网格列数')));
      await tester.pumpAndSettle();
      expect(st.settings.gridColumns, 9);

      await tester.tap(find.byKey(const Key('settings-reset-all')));
      await tester.pumpAndSettle();
      expect(st.settings.gridColumns, LayoutMetrics.defaultGridColumns);
      expect(st.doc.bodyFontSize, DocSettings.defaults.bodyFontSize);
    });
  });
}
