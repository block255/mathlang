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

  group('⑤ ★ pageXDock（横条滑块）：只平移，不改宽', () {
    test('pageLeft 纯函数：贴左 / 居中 / 贴右 / 放不下', () {
      // 1400 窗口 − 右栏 418 = 文档列的可用宽
      const double avail = 1400 - 418;
      const double span = avail - 2 * LayoutMetrics.pageOuterMargin - _pageWidth;
      expect(span, greaterThan(0), reason: '这组数字要真的有活动空间');
      expect(
          LayoutMetrics.pageLeft(
              availableWidth: avail, pageWidth: _pageWidth, dock: 0),
          closeTo(LayoutMetrics.pageOuterMargin, 0.01));
      expect(
          LayoutMetrics.pageLeft(
              availableWidth: avail, pageWidth: _pageWidth, dock: 0.5),
          closeTo(LayoutMetrics.pageOuterMargin + span * 0.5, 0.01));
      expect(
          LayoutMetrics.pageLeft(
              availableWidth: avail, pageWidth: _pageWidth, dock: 1),
          closeTo(LayoutMetrics.pageOuterMargin + span, 0.01));
      // 窗口太窄 ⇒ 贴左（配合 fit-width 缩放，不硬挤）
      expect(
          LayoutMetrics.pageLeft(
              availableWidth: 800, pageWidth: _pageWidth, dock: 0.5),
          LayoutMetrics.pageOuterMargin);
      // ★ 默认 dock = 0 = 老的"偏左"（语义等价迁移）
      expect(const AppSettings().pageXDock, 0);
    });

    testWidgets('★ 任何 dock 值下正文宽不变（变的只有 x）', (WidgetTester tester) async {
      final EditorPageState st =
          await _pump(tester, window: const Size(1400, 1000));
      final double w0 = _editWidth(tester);
      final double x0 = tester.getTopLeft(find.byType(EditView).first).dx;
      for (final double dock in <double>[0.25, 0.5, 0.75, 1.0]) {
        st.settings = st.settings.copyWith(pageXDock: dock);
        await tester.pumpAndSettle();
        expect(_editWidth(tester), closeTo(w0, 0.5),
            reason: 'dock=$dock 时正文宽必须不变');
        expect(tester.getTopLeft(find.byType(EditView).first).dx,
            greaterThanOrEqualTo(x0 - 0.5));
      }
      expect(tester.getTopLeft(find.byType(EditView).first).dx,
          greaterThan(x0), reason: '贴右必须真的往右挪');
    });

    // ★★ 2026-10-18 用户报："Windows 软件版里拖那根横条，编辑页面不动"
    //   根因：`dock: mode == sideBySide ? _s.pageXDock : 0.5` —— **覆盖式把设置丢了**，
    //   而 1920×1080 @150% 的 Windows 窗口只有 1265 逻辑像素（< 1280 阈值）⇒ 永远覆盖式。
    testWidgets('★★ 覆盖式（窗口 < 1280）下横条也必须生效',
        (WidgetTester tester) async {
      final EditorPageState st =
          await _pump(tester, window: const Size(1200, 900));
      expect(st.settings.effectivePanelMode(1200), PanelMode.overlay,
          reason: '这组数字必须走覆盖式，否则守不到那个 bug');
      final double w0 = _editWidth(tester);
      final double x0 = tester.getTopLeft(find.byType(EditView).first).dx;

      st.settings = st.settings.copyWith(pageXDock: 1);
      await tester.pumpAndSettle();
      final double x1 = tester.getTopLeft(find.byType(EditView).first).dx;

      expect(x1, greaterThan(x0 + 100),
          reason: '覆盖式下"贴右"必须真的移动（改前：一动不动，被写死成 0.5）');
      expect(_editWidth(tester), closeTo(w0, 0.5), reason: '仍然只平移、不改宽');
    });

    testWidgets('★ 窗口真的没余量时 ⇒ 贴左（不硬挤、不溢出）',
        (WidgetTester tester) async {
      // 830 < 页宽 793.7 + 2×24 = 841.7 ⇒ span < 0
      final EditorPageState st =
          await _pump(tester, window: const Size(830, 900));
      st.settings = st.settings.copyWith(pageXDock: 1);
      await tester.pumpAndSettle();
      expect(
          LayoutMetrics.pageSpan(
              availableWidth: 830, pageWidth: _pageWidth),
          lessThan(0),
          reason: '这组数字必须真的没余量');
      expect(tester.getTopLeft(find.byType(EditView).first).dx,
          closeTo(LayoutMetrics.pageOuterMargin, 1.0));
    });
  });

  group('⑥ 快捷栏 / 面板两个开关的四种组合：正文宽恒不变', () {
    testWidgets('★ 版面中性对"任意开关组合"成立', (WidgetTester tester) async {
      final EditorPageState st =
          await _pump(tester, window: const Size(1400, 1000));
      final double w0 = _editWidth(tester);
      for (final List<bool> combo in <List<bool>>[
        <bool>[true, false],
        <bool>[false, true],
        <bool>[true, true],
        <bool>[false, false],
      ]) {
        st.toggleQuickBar(open: combo[0]);
        st.togglePanel(open: combo[1]);
        await tester.pumpAndSettle();
        expect(_editWidth(tester), closeTo(w0, 0.5),
            reason: '快捷栏=${combo[0]} 面板=${combo[1]} 时正文宽必须不变');
      }
      // 都收起 ⇒ 右栏消失
      expect(find.byKey(const Key('right-column')), findsNothing);
    });
  });
}
