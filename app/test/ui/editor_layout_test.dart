// ★★ S4-b 布局守卫：**面板开合不许改变正文宽度 / 分页**（《界面与布局.md》§1 不变量 1、§8-1）
//
// 判据（都是"可证"的，不是观感）：
//   ① 面板宽**由格数推算**（`LayoutMetrics.panelWidth`），不写死；
//   ② 并排 / 覆盖两种模式下，`EditView` 的**渲染宽度恒等于页宽**（793.7）⇒ 正文排版宽度不变；
//   ③ 面板开 / 关，`EditView` 宽度也不变；
//   ④ 形态自动切换：≥1280 并排、<1280 覆盖；手机预设恒为覆盖 + 状态栏隐藏。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/core/doc_settings.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/layout/page_metrics.dart';
import 'package:mathlang/ui/app_settings.dart';
import 'package:mathlang/ui/editor_page.dart';

import '../support/symbol_fixture.dart';

const double _pageWidth = 793.7007874015748; // 210mm @96dpi

Future<EditorPageState> _pump(
  WidgetTester tester, {
  required Size window,
  String doc = '甲乙丙',
  AppSettings settings = const AppSettings(),
}) async {
  tester.view.physicalSize = window;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer(doc)..setCaret(doc.length);
  await tester.pumpWidget(MaterialApp(
    home: EditorPage(
      library: testSymbolLibrary(),
      settings: settings,
      buffer: buf,
    ),
  ));
  await tester.pumpAndSettle();
  return tester.state<EditorPageState>(find.byType(EditorPage));
}

double _editWidth(WidgetTester tester) =>
    tester.getSize(find.byType(EditView).first).width;

void main() {
  group('① 面板宽由格数推算（不写死）', () {
    test('8 格 ⇒ 418px；6 格 ⇒ 6×44+5×6+24 = 318px', () {
      expect(LayoutMetrics.panelWidth(8), 8 * 44 + 7 * 6 + 24);
      expect(LayoutMetrics.panelWidth(8), 418);
      expect(LayoutMetrics.panelWidth(6), 6 * 44 + 5 * 6 + 24);
    });

    test('页宽（210mm）与正文宽（174mm）是常量', () {
      final PageGeometry g = PageGeometry.from(DocSettings.defaults);
      expect(g.pageWidth, closeTo(_pageWidth, 0.01));
      expect(g.contentWidth, closeTo(174 * kPxPerMm, 0.01));
    });
  });

  group('②③ 版面中性：面板开 / 关、并排 / 覆盖，正文宽度都不变', () {
    testWidgets('宽屏（1400）：并排；面板开合时 EditView 宽度恒为页宽',
        (WidgetTester tester) async {
      final EditorPageState st =
          await _pump(tester, window: const Size(1400, 1000));
      expect(
          st.settings.effectivePanelMode(1400), PanelMode.sideBySide);
      final double closed = _editWidth(tester);
      expect(closed, closeTo(_pageWidth, 0.5));

      st.togglePanel(open: true);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('symbol-search')), findsOneWidget,
          reason: '面板必须真的出现');
      expect(_editWidth(tester), closeTo(closed, 0.5),
          reason: '★ 面板并排时不许压窄正文（只挪位置）');

      st.togglePanel(open: false);
      await tester.pumpAndSettle();
      expect(_editWidth(tester), closeTo(closed, 0.5));
    });

    testWidgets('窄屏（1000）：覆盖式；面板打开后正文宽度仍不变（只是被遮住）',
        (WidgetTester tester) async {
      final EditorPageState st =
          await _pump(tester, window: const Size(1000, 800));
      expect(st.settings.effectivePanelMode(1000), PanelMode.overlay);
      final double closed = _editWidth(tester);
      st.togglePanel(open: true);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('panel-scrim')), findsOneWidget);
      expect(_editWidth(tester), closeTo(closed, 0.5),
          reason: '★ 覆盖式也必须"改位置不改宽"');
    });
  });

  group('④ 形态自动切换与手机预设', () {
    test('阈值 1280：≥1280 并排，<1280 覆盖', () {
      const AppSettings s = AppSettings();
      expect(s.effectivePanelMode(1279), PanelMode.overlay);
      expect(s.effectivePanelMode(1280), PanelMode.sideBySide);
    });

    testWidgets('手机预设：恒为覆盖 + 状态栏默认隐藏', (WidgetTester tester) async {
      final EditorPageState st = await _pump(
        tester,
        window: const Size(1600, 1000), // 即使窗口很宽
        settings: AppSettings.forPhone,
      );
      expect(st.settings.effectivePanelMode(1600), PanelMode.overlay,
          reason: '手机预设 = 覆盖（autoPanelMode 关掉）');
      expect(find.byKey(const Key('status-text')), findsNothing,
          reason: '手机默认隐藏状态栏');
    });

    testWidgets('桌面默认显示状态栏', (WidgetTester tester) async {
      await _pump(tester, window: const Size(1400, 1000));
      expect(find.byKey(const Key('status-text')), findsOneWidget);
    });
  });
}
