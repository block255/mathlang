// 数语引擎 · **应用设置与布局常量**（S4-b）
//
// 规格：《界面与布局.md》。三条要点：
//   ① **页宽 / 正文宽不许变** ⇒ 面板「并排」时只挪列的位置，不挤压正文（分页不变）；
//   ② 面板宽**由格数推出来**（快捷栏以后读同一个 `kSymbolGridColumns`）；
//   ③ 设置项先做成**内存态**（持久化随 S4-e「本地暂存」一起做）。
//
// 纯 Dart（无 Flutter 依赖），可单测。

import 'package:flutter/foundation.dart';

/// 面板形态
enum PanelMode {
  /// 宽屏并排（页面偏左、面板占右侧）
  sideBySide,

  /// 覆盖式抽屉（页面居中、面板从右滑出）
  overlay,
}

/// 快捷栏位置（S4-c 用；用户拍板：手机也放"面板上方"，另提供底部方案，设置可切）
enum QuickBarPlacement { abovePanel, bottomBar }

@immutable
class AppSettings {
  const AppSettings({
    this.pageOffsetLeft = true,
    this.panelMode = PanelMode.sideBySide,
    this.autoPanelMode = true,
    this.gridColumns = LayoutMetrics.defaultGridColumns,
    this.quickBarPlacement = QuickBarPlacement.abovePanel,
    this.showStatusBar = true,
    this.fitWidthOnPhone = true,
  });

  /// 桌面：宽屏时页面**偏左**（右侧给面板/快捷栏）；关掉则页面居中
  final bool pageOffsetLeft;

  /// 面板形态（`autoPanelMode = true` 时由窗口宽自动决定）
  final PanelMode panelMode;

  /// 窗口宽 ≥ [LayoutMetrics.sideBySideThreshold] 时自动用并排
  final bool autoPanelMode;

  final int gridColumns;
  final QuickBarPlacement quickBarPlacement;

  /// 状态栏是否显示（★ 手机默认隐藏，见 [forPhone]）
  final bool showStatusBar;

  /// 窄屏整页等比缩放（fit-width）
  final bool fitWidthOnPhone;

  /// 手机默认值：状态栏隐藏、面板覆盖
  static const AppSettings forPhone = AppSettings(
    panelMode: PanelMode.overlay,
    autoPanelMode: false,
    showStatusBar: false,
  );

  AppSettings copyWith({
    bool? pageOffsetLeft,
    PanelMode? panelMode,
    bool? autoPanelMode,
    int? gridColumns,
    QuickBarPlacement? quickBarPlacement,
    bool? showStatusBar,
    bool? fitWidthOnPhone,
  }) =>
      AppSettings(
        pageOffsetLeft: pageOffsetLeft ?? this.pageOffsetLeft,
        panelMode: panelMode ?? this.panelMode,
        autoPanelMode: autoPanelMode ?? this.autoPanelMode,
        gridColumns: gridColumns ?? this.gridColumns,
        quickBarPlacement: quickBarPlacement ?? this.quickBarPlacement,
        showStatusBar: showStatusBar ?? this.showStatusBar,
        fitWidthOnPhone: fitWidthOnPhone ?? this.fitWidthOnPhone,
      );

  /// 实际生效的面板形态（把 [autoPanelMode] 与窗口宽算进来）
  PanelMode effectivePanelMode(double windowWidth) {
    if (!autoPanelMode) return panelMode;
    return windowWidth >= LayoutMetrics.sideBySideThreshold
        ? PanelMode.sideBySide
        : PanelMode.overlay;
  }
}

/// 布局常量（**唯一**的数值来源；守卫测试也读它）
class LayoutMetrics {
  const LayoutMetrics._();

  /// 面板一格宽（px）
  static const double cellSize = 44;

  /// 格间距
  static const double cellGap = 6;

  /// 面板内边距
  static const double panelPadding = 12;

  /// ★ 面板默认格数（S4 决定：快捷栏格数读同一个常量）
  static const int defaultGridColumns = 8;

  /// 面板宽 = 格数 × 格宽 + 间隙 + 内边距（**由格数推算，不写死**）
  static double panelWidth(int columns) =>
      columns * cellSize + (columns - 1) * cellGap + 2 * panelPadding;

  /// 并排阈值：页宽 793.7 + 面板 418 + 间距 24 + 外边距 2×24 ≈ 1284 ⇒ 取 1280
  static const double sideBySideThreshold = 1280;

  static const double topBarHeight = 48;
  static const double statusBarHeight = 28;

  /// 文档列与窗口左缘的距离（偏左布局时）
  static const double pageOuterMargin = 24;

  /// 文档列与右栏之间的间距
  static const double columnGap = 24;

  /// 面板/快捷栏收起动画
  static const Duration panelAnimation = Duration(milliseconds: 120);

  /// 手机：整页缩放到"适应宽度"时的外边距
  static const double phonePageMargin = 8;
}
