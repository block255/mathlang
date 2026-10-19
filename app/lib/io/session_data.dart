// 数语引擎 · **本地暂存的序列化**（S4-e-①，2026-10-18）
//
// 目标（用户拍板）："刷新 / 崩溃 / 误关都不丢"。
//
// 两次拍板的边界（**别再重开**）：
//   ① 存哪：**exe 同目录**（用户原话"可以 exe 同目录"）。
//      实现上仍留一条**兜底**：写不进去（如装在 Program Files）就退到 `%APPDATA%\mathlang\`，
//      并把实际路径记下来（设置页「高级」里能看到、也能清）。
//   ② 存什么：**文档 ＋ 设置全都存** —— 不然"改了半天快捷键/字号，刷新回到出厂"。
//
// ★ 纯 Dart（只依赖 dart:convert + 各模型自己的 toJson），可单测往返。

import 'dart:convert';

import '../core/doc_settings.dart';
import '../lang/shortcut_registry.dart';
import '../lang/word_triggers.dart';
import '../ui/app_settings.dart';

/// 一份会话快照（= 下次启动要恢复的全部状态）
class SessionData {
  const SessionData({
    required this.text,
    required this.title,
    required this.savedText,
    this.path,
    this.caret = 0,
    this.anchor = 0,
    this.scrollOffset = 0,
    this.app,
    this.doc,
    this.shortcuts,
    this.triggers,
    this.savedAt,
  });

  /// 正文（L0 原始字符流）
  final String text;

  /// 文档标题
  final String title;

  /// 用户选过的文件路径（`null` = 还没保存过）
  final String? path;

  /// 上次保存时的那份正文快照 —— **dirty 的唯一判据**（`text != savedText` ⇒ 有未保存改动）
  final String savedText;

  final int caret;
  final int anchor;

  /// 页面纵向滚动位置（回来时还在原地）
  final double scrollOffset;

  /// 应用设置 / 文档排版 / 快捷键 / 词表（`null` = 该件没有存过，用默认值）
  final AppSettings? app;
  final DocSettings? doc;
  final ShortcutSettings? shortcuts;
  final TriggerSettings? triggers;

  final DateTime? savedAt;

  bool get hasFile => path != null && path!.isNotEmpty;
  bool get dirty => text != savedText;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'v': 1,
        'text': text,
        'title': title,
        if (path != null) 'path': path,
        'savedText': savedText,
        'caret': caret,
        'anchor': anchor,
        'scroll': scrollOffset,
        if (app != null) 'app': appSettingsToJson(app!),
        if (doc != null) 'doc': docSettingsToJson(doc!),
        if (shortcuts != null) 'shortcuts': shortcutsToJson(shortcuts!),
        if (triggers != null) 'triggers': triggersToJson(triggers!),
        if (savedAt != null) 'savedAt': savedAt!.toIso8601String(),
      };

  /// 从 JSON 还原；**字段缺失/类型不对一律当作没有**（坏文件不许把编辑器带崩）
  static SessionData? tryParse(String source) {
    Map<String, dynamic> m;
    try {
      m = jsonDecode(source) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
    final Object? text = m['text'];
    if (text is! String) return null;
    return SessionData(
      text: text,
      title: (m['title'] as String?) ?? '',
      path: m['path'] as String?,
      savedText: (m['savedText'] as String?) ?? text,
      caret: (m['caret'] as num?)?.toInt() ?? 0,
      anchor: (m['anchor'] as num?)?.toInt() ?? 0,
      scrollOffset: (m['scroll'] as num?)?.toDouble() ?? 0,
      app: m['app'] is Map
          ? appSettingsFromJson(Map<String, dynamic>.from(m['app'] as Map))
          : null,
      doc: m['doc'] is Map
          ? docSettingsFromJson(Map<String, dynamic>.from(m['doc'] as Map))
          : null,
      shortcuts: m['shortcuts'] is Map
          ? shortcutsFromJson(Map<String, dynamic>.from(m['shortcuts'] as Map))
          : null,
      triggers: m['triggers'] is Map
          ? triggersFromJson(Map<String, dynamic>.from(m['triggers'] as Map))
          : null,
      savedAt: DateTime.tryParse((m['savedAt'] as String?) ?? ''),
    );
  }
}

// ---------------------------------------------------------------------------
// AppSettings
// ---------------------------------------------------------------------------

Map<String, dynamic> appSettingsToJson(AppSettings s) => <String, dynamic>{
      'pageXDock': s.pageXDock,
      'panelMode': s.panelMode.name,
      'autoPanelMode': s.autoPanelMode,
      'gridColumns': s.gridColumns,
      'cellSize': s.cellSize,
      'quickBarPlacement': s.quickBarPlacement.name,
      'quickBarSlots': s.quickBarSlots,
      'favorites': s.favorites,
      'showStatusBar': s.showStatusBar,
      'statusItems': <String>[for (final StatusItem i in s.statusItems) i.name],
      'fitWidthOnPhone': s.fitWidthOnPhone,
      'showEmptySuggestions': s.showEmptySuggestions,
      'showCellLabels': s.showCellLabels,
      'autoWordTriggers': s.autoWordTriggers,
      'autoShorthand': s.autoShorthand,
  'desktopShortcut': s.desktopShortcut,
    };

AppSettings appSettingsFromJson(Map<String, dynamic> m) {
  T pick<T>(String k, T fallback) {
    final Object? v = m[k];
    return v is T ? v : fallback;
  }

  const AppSettings d = AppSettings();
  final Set<StatusItem> items = <StatusItem>{
    for (final Object? n in (m['statusItems'] as List<dynamic>?) ?? <dynamic>[])
      for (final StatusItem i in StatusItem.values)
        if (i.name == n) i,
  };
  return AppSettings(
    pageXDock: (m['pageXDock'] as num?)?.toDouble() ?? d.pageXDock,
    panelMode: PanelMode.values.firstWhere(
      (PanelMode x) => x.name == m['panelMode'],
      orElse: () => d.panelMode,
    ),
    autoPanelMode: pick('autoPanelMode', d.autoPanelMode),
    gridColumns: pick('gridColumns', d.gridColumns),
    cellSize: (m['cellSize'] as num?)?.toDouble() ?? d.cellSize,
    quickBarPlacement: QuickBarPlacement.values.firstWhere(
      (QuickBarPlacement x) => x.name == m['quickBarPlacement'],
      orElse: () => d.quickBarPlacement,
    ),
    quickBarSlots: pick('quickBarSlots', d.quickBarSlots),
    favorites: <String?>[
      for (final Object? f in (m['favorites'] as List<dynamic>?) ?? <dynamic>[])
        f is String ? f : null,
    ],
    showStatusBar: pick('showStatusBar', d.showStatusBar),
    // 一项都没解析出来 ⇒ 当作"没存过"，回到默认显示项（别把状态栏清空）
    statusItems: items.isEmpty ? d.statusItems : items,
    fitWidthOnPhone: pick('fitWidthOnPhone', d.fitWidthOnPhone),
    showEmptySuggestions: pick('showEmptySuggestions', d.showEmptySuggestions),
    showCellLabels: pick('showCellLabels', d.showCellLabels),
    autoWordTriggers: pick('autoWordTriggers', d.autoWordTriggers),
    autoShorthand: pick('autoShorthand', d.autoShorthand),
    desktopShortcut: pick('desktopShortcut', d.desktopShortcut),
  );
}

// ---------------------------------------------------------------------------
// DocSettings
// ---------------------------------------------------------------------------

Map<String, dynamic> docSettingsToJson(DocSettings s) => <String, dynamic>{
      'pageWidthMm': s.pageWidthMm,
      'pageHeightMm': s.pageHeightMm,
      'marginTopMm': s.marginTopMm,
      'marginBottomMm': s.marginBottomMm,
      'marginLeftMm': s.marginLeftMm,
      'marginRightMm': s.marginRightMm,
      'bodyFontSize': s.bodyFontSize,
      'lineHeight': s.lineHeight,
      if (s.displayFontSize != null) 'displayFontSize': s.displayFontSize,
      'heading1Size': s.heading1Size,
      'heading2Size': s.heading2Size,
      'heading3Size': s.heading3Size,
      'headerFontSize': s.headerFontSize,
      'headerText': s.headerText,
    };

DocSettings docSettingsFromJson(Map<String, dynamic> m) {
  const DocSettings d = DocSettings.defaults;
  double num_(String k, double fallback) =>
      (m[k] as num?)?.toDouble() ?? fallback;
  return DocSettings(
    pageWidthMm: num_('pageWidthMm', d.pageWidthMm),
    pageHeightMm: num_('pageHeightMm', d.pageHeightMm),
    marginTopMm: num_('marginTopMm', d.marginTopMm),
    marginBottomMm: num_('marginBottomMm', d.marginBottomMm),
    marginLeftMm: num_('marginLeftMm', d.marginLeftMm),
    marginRightMm: num_('marginRightMm', d.marginRightMm),
    bodyFontSize: num_('bodyFontSize', d.bodyFontSize),
    lineHeight: num_('lineHeight', d.lineHeight),
    displayFontSize: (m['displayFontSize'] as num?)?.toDouble(),
    heading1Size: num_('heading1Size', d.heading1Size),
    heading2Size: num_('heading2Size', d.heading2Size),
    heading3Size: num_('heading3Size', d.heading3Size),
    headerFontSize: num_('headerFontSize', d.headerFontSize),
    headerText: (m['headerText'] as String?) ?? d.headerText,
  );
}

// ---------------------------------------------------------------------------
// ShortcutSettings / TriggerSettings
// ---------------------------------------------------------------------------

Map<String, dynamic> shortcutsToJson(ShortcutSettings s) => <String, dynamic>{
      'bindings': <String, dynamic>{
        for (final MapEntry<String, List<ShortcutCombo>> e
            in s.bindings.entries)
          e.key: <String>[for (final ShortcutCombo c in e.value) c.label],
      },
      'disabled': s.disabled.toList(),
    };

ShortcutSettings shortcutsFromJson(Map<String, dynamic> m) {
  final ShortcutSettings base = ShortcutSettings.defaults();
  final Map<String, List<ShortcutCombo>> bindings =
      <String, List<ShortcutCombo>>{...base.bindings};
  final Object? raw = m['bindings'];
  if (raw is Map) {
    for (final MapEntry<Object?, Object?> e in raw.entries) {
      final String id = '${e.key}';
      if (!bindings.containsKey(id)) continue; // 表里没有的动作 id 不理
      final Object? list = e.value;
      if (list is! List) continue;
      final List<ShortcutCombo> combos = <ShortcutCombo>[
        for (final Object? c in list)
          if (c is String && c.isNotEmpty) ShortcutCombo.parse(c),
      ];
      if (combos.isNotEmpty) bindings[id] = combos;
    }
  }
  return ShortcutSettings(
    bindings: bindings,
    disabled: <String>{
      for (final Object? d in (m['disabled'] as List<dynamic>?) ?? <dynamic>[])
        if (d is String) d,
    },
  );
}

Map<String, dynamic> triggersToJson(TriggerSettings t) => <String, dynamic>{
      'items': <Map<String, dynamic>>[
        for (final WordTrigger w in t.triggers)
          <String, dynamic>{
            'word': w.word,
            'tex': w.tex,
            'terminators': w.terminators,
            'enabled': w.enabled,
          },
      ],
    };

TriggerSettings triggersFromJson(Map<String, dynamic> m) {
  final Object? raw = m['items'];
  if (raw is! List) return TriggerSettings.defaults();
  return TriggerSettings(
    triggers: <WordTrigger>[
      for (final Object? it in raw)
        if (it is Map)
          WordTrigger(
            word: (it['word'] as String?) ?? '',
            tex: (it['tex'] as String?) ?? '',
            terminators: (it['terminators'] as String?) ?? 'Tab · 空格 · Enter',
            enabled: (it['enabled'] as bool?) ?? true,
          ),
    ],
  );
}
