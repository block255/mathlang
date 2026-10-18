// 数语引擎 · **应用设置与布局常量**（S4-b②，2026-10-17 重写）
//
// 规格：《界面与布局.md》§6（设置页）＋ §6.3（逐项映射）。三条要点：
//   ① **页宽 / 正文宽不许变** ⇒ 布局设置只挪文档列的 **x**，不改宽（分页不变）；
//   ② 面板 / 快捷栏的宽度**由格数与格宽推出来**（不写死；设置里两个都能改）；
//   ③ 设置项先做成**内存态**（持久化随 S4-e「本地暂存」一起做）。
//
// ★ 2026-10-17 改动：`pageOffsetLeft`（布尔）→ **`pageXDock`（归一化 0..1）**。
//   用户拍板："页面位置做成一根横条，可以滑动调页面中心横坐标"。
//   语义 = 在**可用空间**里的位置：0 贴左 · 0.5 居中 · 1 贴右。
//   好处：面板开/关时可用空间变化 ⇒ "都收起 ⇒ 页面回居中"**不用额外的布尔量**就有了。
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

/// 快捷栏位置（用户拍板：手机也放"面板上方"，另提供底部方案，设置可切）
enum QuickBarPlacement { abovePanel, bottomBar }

/// 状态栏可显示的项（用户 2026-10-17：显示项可配）
enum StatusItem {
  page('页数'),
  chars('字数'),
  caret('光标'),
  edits('编辑次数'),
  autoWrapped('自动包裹'),
  saveState('保存状态');

  const StatusItem(this.label);
  final String label;
}

@immutable
class AppSettings {
  const AppSettings({
    this.pageXDock = 0,
    this.panelMode = PanelMode.sideBySide,
    this.autoPanelMode = true,
    this.gridColumns = LayoutMetrics.defaultGridColumns,
    this.cellSize = LayoutMetrics.cellSize,
    this.quickBarPlacement = QuickBarPlacement.abovePanel,
    this.quickBarSlots = LayoutMetrics.defaultGridColumns,
    this.favorites = const <String?>[],
    this.showStatusBar = true,
    this.statusItems = const <StatusItem>{
      StatusItem.page,
      StatusItem.chars,
      StatusItem.caret,
      StatusItem.edits,
      StatusItem.autoWrapped,
    },
    this.fitWidthOnPhone = true,
    this.showEmptySuggestions = true,
    this.showCellLabels = true,
  });

  /// ★ 页面在**可用空间**里的归一化位置：`0` 贴左 · `0.5` 居中 · `1` 贴右
  ///
  /// 可用空间 = 窗口宽 − 2×外边距 −（右栏可见时）右栏宽 − 列间距 ⇒ **只平移、不改宽**。
  final double pageXDock;

  /// 面板形态（`autoPanelMode = true` 时由窗口宽自动决定）
  final PanelMode panelMode;

  /// 窗口宽 ≥ [LayoutMetrics.sideBySideThreshold] 时自动用并排
  final bool autoPanelMode;

  /// 面板网格列数（4–10）
  final int gridColumns;

  /// 一格边长（36–64 px）
  final double cellSize;

  final QuickBarPlacement quickBarPlacement;

  /// 快捷栏格数（4–12）
  final int quickBarSlots;

  /// 快捷栏内容：长度 = [quickBarSlots]，`null` = 空格。
  /// ★ 用户拍板：**收藏 ≡ 快捷栏**（8 格、独立组件、不随筛选变化）。
  final List<String?> favorites;

  /// 状态栏是否显示（★ 手机默认隐藏，见 [forPhone]）
  final bool showStatusBar;

  /// 状态栏显示哪些项
  final Set<StatusItem> statusItems;

  /// 窄屏整页等比缩放（fit-width）
  final bool fitWidthOnPhone;

  /// 搜索无结果时给相近建议（《符号面板与符号表》§三：绝不静默空手而归）
  final bool showEmptySuggestions;

  /// 面板格子里显不显示中文名（关掉 ⇒ 格子更大、不再被截字）
  final bool showCellLabels;

  /// 手机默认值：状态栏隐藏、面板覆盖
  static const AppSettings forPhone = AppSettings(
    panelMode: PanelMode.overlay,
    autoPanelMode: false,
    showStatusBar: false,
  );

  /// 紧凑预设
  static const AppSettings compact = AppSettings(gridColumns: 6, cellSize: 40);

  /// 宽松预设
  static const AppSettings relaxed = AppSettings(gridColumns: 8, cellSize: 52);

  /// 第 [i] 格装的是哪个符号（越界 / 空位 ⇒ null）
  String? favoriteAt(int i) =>
      i >= 0 && i < favorites.length ? favorites[i] : null;

  /// 写一格（**返回新对象**；列表短了自动补齐）
  AppSettings withFavorite(int i, String? id) {
    final int n = i + 1 > quickBarSlots ? i + 1 : quickBarSlots;
    final List<String?> next = <String?>[
      for (var k = 0; k < n; k++)
        if (k < favorites.length) favorites[k] else null,
    ];
    if (i >= 0 && i < next.length) next[i] = id;
    return copyWith(favorites: next);
  }

  AppSettings copyWith({
    double? pageXDock,
    PanelMode? panelMode,
    bool? autoPanelMode,
    int? gridColumns,
    double? cellSize,
    QuickBarPlacement? quickBarPlacement,
    int? quickBarSlots,
    List<String?>? favorites,
    bool? showStatusBar,
    Set<StatusItem>? statusItems,
    bool? fitWidthOnPhone,
    bool? showEmptySuggestions,
    bool? showCellLabels,
  }) =>
      AppSettings(
        pageXDock: pageXDock ?? this.pageXDock,
        panelMode: panelMode ?? this.panelMode,
        autoPanelMode: autoPanelMode ?? this.autoPanelMode,
        gridColumns: gridColumns ?? this.gridColumns,
        cellSize: cellSize ?? this.cellSize,
        quickBarPlacement: quickBarPlacement ?? this.quickBarPlacement,
        quickBarSlots: quickBarSlots ?? this.quickBarSlots,
        favorites: favorites ?? this.favorites,
        showStatusBar: showStatusBar ?? this.showStatusBar,
        statusItems: statusItems ?? this.statusItems,
        fitWidthOnPhone: fitWidthOnPhone ?? this.fitWidthOnPhone,
        showEmptySuggestions: showEmptySuggestions ?? this.showEmptySuggestions,
        showCellLabels: showCellLabels ?? this.showCellLabels,
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

  /// 面板一格宽（px，默认值；设置可改，见 [AppSettings.cellSize]）
  static const double cellSize = 44;

  /// 格间距
  static const double cellGap = 6;

  /// 面板内边距
  static const double panelPadding = 12;

  /// ★ 面板默认格数（快捷栏格数读同一个默认值）
  static const int defaultGridColumns = 8;

  /// 面板宽 = 格数 × 格宽 + 间隙 + 内边距（**由格数推算，不写死**）
  static double panelWidth(int columns, {double cell = cellSize}) =>
      columns * cell + (columns - 1) * cellGap + 2 * panelPadding;

  /// 并排阈值：页宽 793.7 + 面板 418 + 间距 24 + 外边距 2×24 ≈ 1284 ⇒ 取 1280
  static const double sideBySideThreshold = 1280;

  static const double topBarHeight = 48;
  static const double statusBarHeight = 28;
  static const double quickBarHeight = 56;

  /// 文档列与窗口左缘的距离（偏左布局时）
  static const double pageOuterMargin = 24;

  /// 文档列与右栏之间的间距
  static const double columnGap = 24;

  /// 面板/快捷栏收起动画
  static const Duration panelAnimation = Duration(milliseconds: 120);

  /// 手机：整页缩放到"适应宽度"时的外边距
  static const double phonePageMargin = 8;

  /// ★ 页面左缘的 x：**只平移、不改宽**（《界面与布局》§1-1）
  ///
  /// - [availableWidth] = 文档列**真正可用的宽度**（右栏已被扣掉；覆盖式为整窗宽）
  /// - [dock] = 归一化位置（0 贴左 · 0.5 居中 · 1 贴右）
  ///
  /// ★ 故意**不**在这里吃掉 `columnGap`：调用方给什么宽就是什么宽，
  /// 否则"页面宽 + 右栏宽 + 间隙"会被重复扣两次（本仓踩过这类"扣两遍"的坑）。
  static double pageLeft({
    required double availableWidth,
    required double pageWidth,
    required double dock,
  }) {
    final double span = availableWidth - 2 * pageOuterMargin - pageWidth;
    if (span <= 0) return pageOuterMargin; // 放不下 ⇒ 贴左（配合 fit-width 缩放）
    return pageOuterMargin + span * dock.clamp(0.0, 1.0);
  }
}
