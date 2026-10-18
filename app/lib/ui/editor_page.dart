// 数语引擎 · **编辑器页面（外壳）**（S4-b② 重写，2026-10-17）
//
// 规格：《界面与布局.md》§2 / §2.1（顶栏 + 文件菜单）/ §3 / §4（筛选器式面板）/ §5（快捷栏）/
//       §6（半透明设置页）。
//
// 骨架（从上到下）：
//   顶栏 `[☰ 文件▾] 标题 ● [导入][保存][导出▾] … [快捷栏][符号][⚙]`
//   文档列（A4，宽 793.7，**位置由 `AppSettings.pageXDock` 决定：0 贴左 · 0.5 居中 · 1 贴右**）
//   右栏（**快捷栏（上）+ 面板（下）**，两个开关互不牵连；都收起 ⇒ 右栏消失）
//   状态栏（显示项可配；点"自动包裹"进诊断清单 —— 诊断清单在 b2-②）
//
// ★★ 两条硬不变量（守卫测试会盯）：
//   ① **正文宽度不变**：`pageXDock` 只挪文档列的 **x**，**不挤压** ⇒ `PageGeometry.contentWidth` 恒定、
//      分页一个像素都不变（任何 dock 值、任何右栏开关组合下都必须成立）；
//   ② 面板 / 快捷栏 / 状态栏 / 设置页**都不进 `DocView` 的排版树** ⇒ 开合不改变分页。

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/doc_buffer.dart';
import '../core/doc_settings.dart';
import '../editor/edit_view.dart';
import '../lang/symbol_library.dart';
import '../layout/page_metrics.dart';
import '../spike/s3_edit/s3_edit_page.dart' show kEditSample;
import 'app_settings.dart';
import 'quick_bar.dart';
import 'settings_page.dart';
import 'symbol_panel.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({
    super.key,
    this.library,
    this.settings,
    this.doc,
    this.buffer,
  });

  /// 测试注入（不传则从 `assets/symbols.json` 加载）
  final SymbolLibrary? library;
  final AppSettings? settings;
  final DocSettings? doc;
  final DocBuffer? buffer;

  @override
  State<EditorPage> createState() => EditorPageState();
}

class EditorPageState extends State<EditorPage> {
  late final DocBuffer _buf = widget.buffer ?? DocBuffer(kEditSample);
  final GlobalKey<EditViewState> _editKey = GlobalKey<EditViewState>();
  final FocusNode _searchFocus = FocusNode();
  final FocusNode _shellFocus = FocusNode(debugLabel: 'shell-keys');
  final TextEditingController _titleCtl = TextEditingController();

  SymbolLibrary? _lib;
  late AppSettings _s = widget.settings ?? const AppSettings();
  late DocSettings _doc = widget.doc ?? DocSettings.defaults;

  bool _panelOpen = false;

  /// ★ 快捷栏与面板**各有自己的开关**（用户 2026-10-17 定）
  bool _quickOpen = true;
  bool _settingsOpen = false;

  /// 快捷栏**赋值模式**的目标格（`null` = 不在赋值模式）
  int? _assignSlot;

  String _title = '未命名文档';
  bool _editingTitle = false;

  /// "保存点"：编辑次数达到它就算已保存（**S4-d 接入真文件后才有意义**）
  final int _savedEdits = 0;

  EditViewStats _stats = const EditViewStats(
    length: 0,
    caret: 0,
    edits: 0,
    composing: false,
    composingText: '',
  );

  @override
  void initState() {
    super.initState();
    _lib = widget.library;
    if (_lib == null) {
      SymbolLibrary.load().then((SymbolLibrary lib) {
        if (mounted) setState(() => _lib = lib);
      });
    }
  }

  @override
  void dispose() {
    _searchFocus.dispose();
    _shellFocus.dispose();
    _titleCtl.dispose();
    super.dispose();
  }

  // ---------------- 对外（测试 / 诊断） ----------------

  AppSettings get settings => _s;
  set settings(AppSettings v) => setState(() => _s = v);

  DocSettings get doc => _doc;
  set doc(DocSettings v) => setState(() => _doc = v);

  bool get panelOpen => _panelOpen;
  bool get quickOpen => _quickOpen;
  bool get settingsOpen => _settingsOpen;
  int? get assignSlot => _assignSlot;
  String get title => _title;
  bool get dirty => _stats.edits != _savedEdits;

  /// 右栏当前宽度（0 = 右栏不存在）
  double get rightColumnWidth => _rightWidth();

  void togglePanel({bool? open}) {
    setState(() {
      _panelOpen = open ?? !_panelOpen;
      if (!_panelOpen && _assignSlot != null) _assignSlot = null;
    });
    if (_panelOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    }
  }

  void toggleQuickBar({bool? open}) {
    setState(() {
      _quickOpen = open ?? !_quickOpen;
      if (!_quickOpen && _assignSlot != null) _assignSlot = null;
    });
  }

  void openSettings({int group = 0}) => setState(() {
        _settingsOpen = true;
        _settingsGroup = group;
      });

  void closeSettings() => setState(() {
        _settingsOpen = false;
        _assignSlot = null;
      });

  int _settingsGroup = 0;

  /// 面板插入（也供测试直接调）
  void insertSymbol(SymbolItem item) {
    _editKey.currentState?.insertSymbolTex(item.tex, template: item.isTemplate);
  }

  /// 赋值模式：**选一个符号 ⇒ 只放进那一格，不插入正文**（用户拍的流程）
  void assignSymbol(SymbolItem item) {
    final int? slot = _assignSlot;
    if (slot == null) return;
    setState(() {
      _s = _s.withFavorite(slot, item.id);
      _assignSlot = null;
    });
  }

  /// `Alt+1..8` / 点格子：插入快捷栏第 [i] 格
  void insertFavorite(int i) {
    final String? id = _s.favoriteAt(i);
    if (id == null) return;
    final SymbolItem? item = _lib?.byId(id);
    if (item != null) insertSymbol(item);
  }

  /// 点空格 / 点已有格：进入赋值模式
  void beginAssign(int i) => setState(() => _assignSlot = i);
  void cancelAssign() => setState(() => _assignSlot = null);
  void clearFavorite(int i) => setState(() {
        _s = _s.withFavorite(i, null);
        if (_assignSlot == i) _assignSlot = null;
      });

  /// 格子被点：空格 ⇒ 赋值模式；有内容 ⇒ 插入（赋值模式下点格子 = 换目标）
  void tapQuickSlot(int i) {
    if (_assignSlot != null) {
      setState(() => _assignSlot = _assignSlot == i ? null : i);
      return;
    }
    if (_s.favoriteAt(i) == null) {
      beginAssign(i);
    } else {
      insertFavorite(i);
    }
  }

  void _onStats(EditViewStats s) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _stats = s);
    });
  }

  double _rightWidth() {
    if (_lib == null) return 0;
    double w = 0;
    if (_quickOpen) {
      w = math.max(
          w, LayoutMetrics.panelWidth(_s.quickBarSlots, cell: _s.cellSize));
    }
    if (_panelOpen) {
      w = math.max(
          w, LayoutMetrics.panelWidth(_s.gridColumns, cell: _s.cellSize));
    }
    return w;
  }

  // ---------------- 快捷键（外壳层） ----------------

  KeyEventResult _onShellKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey k = e.logicalKey;
    final HardwareKeyboard kb = HardwareKeyboard.instance;

    if (k == LogicalKeyboardKey.escape) {
      if (_assignSlot != null) {
        cancelAssign();
        return KeyEventResult.handled;
      }
      if (_settingsOpen) {
        closeSettings();
        return KeyEventResult.handled;
      }
      if (_panelOpen) {
        togglePanel(open: false);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // ★ Alt+1..8 直接插入快捷栏第 N 格（不管面板开没开）
    if (kb.isAltPressed && !kb.isControlPressed && !kb.isMetaPressed) {
      final int? n = _altDigit(k);
      if (n != null && n <= _s.quickBarSlots) {
        insertFavorite(n - 1);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (kb.isControlPressed || kb.isMetaPressed) {
      if (k == LogicalKeyboardKey.comma) {
        _settingsOpen ? closeSettings() : openSettings();
        return KeyEventResult.handled;
      }
      // Ctrl+/ = 开 / 关符号面板（《快捷键系统》§二·符号面板）
      if (k == LogicalKeyboardKey.slash) {
        togglePanel();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  int? _altDigit(LogicalKeyboardKey k) {
    final Map<LogicalKeyboardKey, int> digits = <LogicalKeyboardKey, int>{
      LogicalKeyboardKey.digit1: 1,
      LogicalKeyboardKey.digit2: 2,
      LogicalKeyboardKey.digit3: 3,
      LogicalKeyboardKey.digit4: 4,
      LogicalKeyboardKey.digit5: 5,
      LogicalKeyboardKey.digit6: 6,
      LogicalKeyboardKey.digit7: 7,
      LogicalKeyboardKey.digit8: 8,
      LogicalKeyboardKey.digit9: 9,
    };
    return digits[k];
  }

  // ---------------- 构建 ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEDF2F7),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(LayoutMetrics.topBarHeight),
        child: _topBar(),
      ),
      body: Focus(
        focusNode: _shellFocus,
        onKeyEvent: _onShellKey,
        child: LayoutBuilder(builder: (BuildContext c, BoxConstraints cons) {
          final PanelMode mode = _s.effectivePanelMode(cons.maxWidth);
          final double rightW = _rightWidth();
          final Widget page = _pageColumn(
            // 覆盖式：页面居中（抽屉只遮不改）
            dock: mode == PanelMode.sideBySide ? _s.pageXDock : 0.5,
          );
          final Widget body = mode == PanelMode.sideBySide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(child: page),
                    if (rightW > 0) _rightColumn(rightW),
                  ],
                )
              : Stack(
                  children: <Widget>[
                    Positioned.fill(child: page),
                    if (rightW > 0) ...<Widget>[
                      Positioned.fill(
                        child: GestureDetector(
                          key: const Key('panel-scrim'),
                          onTap: () {
                            togglePanel(open: false);
                            toggleQuickBar(open: false);
                          },
                          child: const ColoredBox(color: Color(0x1A000000)),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        bottom: 0,
                        right: 0,
                        child: _rightColumn(rightW),
                      ),
                    ],
                  ],
                );
          return Stack(
            children: <Widget>[
              body,
              if (_settingsOpen)
                Positioned.fill(
                  child: SettingsOverlay(
                    key: const Key('settings-overlay'),
                    initialGroup: _settingsGroup,
                    settings: _s,
                    doc: _doc,
                    library: _lib,
                    onSettings: (AppSettings v) => setState(() => _s = v),
                    onDoc: (DocSettings v) => setState(() => _doc = v),
                    onClose: closeSettings,
                  ),
                ),
            ],
          );
        }),
      ),
      bottomNavigationBar: _s.showStatusBar ? _statusBar() : null,
    );
  }

  // ---------------- 顶栏 ----------------

  Widget _topBar() {
    return Material(
      color: Colors.white,
      elevation: 1,
      child: SizedBox(
        height: LayoutMetrics.topBarHeight,
        child: Row(
          children: <Widget>[
            const SizedBox(width: 6),
            _fileMenu(),
            const SizedBox(width: 8),
            _titleWidget(),
            const SizedBox(width: 4),
            _saveDot(),
            const SizedBox(width: 12),
            _deadButton('导入', const Key('import-button'), 'S4-d 接入'),
            _deadButton('保存', const Key('save-button'), 'S4-d 接入'),
            _exportMenu(),
            const Spacer(),
            _toggleButton(
              key: const Key('open-quick-bar'),
              icon: Icons.star_outline,
              label: '快捷栏',
              on: _quickOpen,
              onTap: () => toggleQuickBar(),
            ),
            _toggleButton(
              key: const Key('open-symbol-panel'),
              icon: Icons.functions,
              label: '符号',
              on: _panelOpen,
              onTap: () => togglePanel(),
            ),
            IconButton(
              key: const Key('open-settings'),
              tooltip: '设置（Ctrl+,）',
              icon: const Icon(Icons.settings_outlined, size: 18),
              onPressed: () => _settingsOpen ? closeSettings() : openSettings(),
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }

  Widget _fileMenu() {
    return PopupMenuButton<String>(
      key: const Key('file-menu'),
      tooltip: '文件',
      onSelected: (String v) {
        switch (v) {
          case 'settings':
            openSettings(group: 1);
          case 'about':
            openSettings(group: 8);
          default:
            // 文件动线（新建/打开/保存/另存为/导入/导出/最近）归 S4-d
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('「文件」动线在 S4-d 接入（现在菜单项是灰的）'),
                duration: Duration(seconds: 2),
              ),
            );
        }
      },
      itemBuilder: (BuildContext c) => <PopupMenuEntry<String>>[
        _fileItem('新建', 'Ctrl+N', 'S4-d'),
        _fileItem('打开…', 'Ctrl+O', 'S4-d'),
        _fileItem('最近打开', '', 'S4-e'),
        const PopupMenuDivider(),
        _fileItem('保存', 'Ctrl+S', 'S4-d'),
        _fileItem('另存为…', 'Ctrl+Shift+S', 'S4-d'),
        const PopupMenuDivider(),
        _fileItem('导入…', '', 'S4-d'),
        _fileItem('导出', '', 'S4-d'),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'settings',
          height: 36,
          child: Text('设置…    Ctrl+,', style: TextStyle(fontSize: 12)),
        ),
        const PopupMenuItem<String>(
          value: 'about',
          height: 36,
          child: Text('关于', style: TextStyle(fontSize: 12)),
        ),
      ],
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: <Widget>[
            Icon(Icons.menu, size: 17),
            SizedBox(width: 4),
            Text('文件', style: TextStyle(fontSize: 12)),
            Icon(Icons.arrow_drop_down, size: 16),
          ],
        ),
      ),
    );
  }

  /// 文件菜单里**还没接入**的项：灰显 + 标归属批次（★ 不假装能用）
  PopupMenuItem<String> _fileItem(String label, String shortcut, String batch) {
    return PopupMenuItem<String>(
      value: label,
      enabled: false,
      height: 36,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 76,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: Color(0xFFA0AEC0))),
          ),
          Text(shortcut,
              style: const TextStyle(fontSize: 10, color: Color(0xFFCBD5E0))),
          const Spacer(),
          Text(batch,
              style: const TextStyle(fontSize: 9, color: Color(0xFFCBD5E0))),
        ],
      ),
    );
  }

  Widget _titleWidget() {
    if (_editingTitle) {
      return SizedBox(
        width: 200,
        child: TextField(
          key: const Key('doc-title-field'),
          controller: _titleCtl,
          autofocus: true,
          style: const TextStyle(fontSize: 13),
          onSubmitted: (String v) => _commitTitle(v),
          onTapOutside: (_) => _commitTitle(_titleCtl.text),
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            border: OutlineInputBorder(),
          ),
        ),
      );
    }
    return InkWell(
      key: const Key('doc-title'),
      onTap: () => setState(() {
        _titleCtl.text = _title;
        _editingTitle = true;
      }),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(_title, style: const TextStyle(fontSize: 13)),
      ),
    );
  }

  void _commitTitle(String v) {
    setState(() {
      _title = v.trim().isEmpty ? '未命名文档' : v.trim();
      _editingTitle = false;
    });
  }

  /// ★ 保存状态点：`●` 未保存 / `○` 已保存（S4-b 先放标题旁，S4-d 接真文件）
  Widget _saveDot() {
    final bool d = dirty;
    return Tooltip(
      message: d ? '未保存（S4-d 接入真文件后这里才有意义）' : '已保存',
      child: Text(
        d ? '●' : '○',
        key: const Key('save-dot'),
        style: TextStyle(
          fontSize: 10,
          color: d ? const Color(0xFF1E88E5) : const Color(0xFFA0AEC0),
        ),
      ),
    );
  }

  Widget _deadButton(String label, Key key, String tip) {
    return Tooltip(
      message: tip,
      child: TextButton(
        key: key,
        onPressed: null,
        child: Text(label,
            style: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E0))),
      ),
    );
  }

  Widget _exportMenu() {
    return PopupMenuButton<String>(
      key: const Key('export-menu'),
      tooltip: '导出（S4-d 接入）',
      itemBuilder: (BuildContext c) => <PopupMenuEntry<String>>[
        _fileItem('Markdown', '', 'S4-d'),
        _fileItem('纯文本', '', 'S4-d'),
        _fileItem('图片集', '', 'S4-d'),
        _fileItem('PDF', '', 'S4-d'),
      ],
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: <Widget>[
            Text('导出',
                style: TextStyle(fontSize: 12, color: Color(0xFFCBD5E0))),
            Icon(Icons.arrow_drop_down, size: 16, color: Color(0xFFCBD5E0)),
          ],
        ),
      ),
    );
  }

  Widget _toggleButton({
    required Key key,
    required IconData icon,
    required String label,
    required bool on,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: TextButton.icon(
        key: key,
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: on ? const Color(0xFFEBF4FF) : null,
          foregroundColor:
              on ? const Color(0xFF1E88E5) : const Color(0xFF4A5568),
        ),
        icon: Icon(icon, size: 17),
        label: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  // ---------------- 文档列（只平移，不改宽） ----------------

  Widget _pageColumn({required double dock}) {
    final PageGeometry geo = PageGeometry.from(_doc);
    return LayoutBuilder(builder: (BuildContext c, BoxConstraints cons) {
      // ★ 这里传的是 Row 已经扣掉右栏之后的可用宽（覆盖式为整窗宽）
      final double left = LayoutMetrics.pageLeft(
        availableWidth: cons.maxWidth,
        pageWidth: geo.pageWidth,
        dock: dock,
      );
      return SingleChildScrollView(
        key: const Key('page-scroll'),
        // ★ Align 不是装饰：`SingleChildScrollView` 会把父级的**紧**宽度往下传，
        //   不套一个 Align 放成 loose constraint，`SizedBox(width: 页宽)` 就会被
        //   "minWidth = 可用宽"顶掉 ⇒ EditView 变成整栏宽（正文宽变了 = 版面不中性）。
        //   2026-10-17 实测撞到：EditView 宽 958 而不是 793.7。
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: EdgeInsets.only(left: left, top: 12, bottom: 24),
            child: SizedBox(
              width: geo.pageWidth,
              child: EditView(
                key: _editKey,
                buffer: _buf,
                settings: _doc,
                onStats: _onStats,
              ),
            ),
          ),
        ),
      );
    });
  }

  // ---------------- 右栏（快捷栏 + 面板） ----------------

  Widget _rightColumn(double width) {
    final bool showPanel = _panelOpen && _lib != null;
    final Widget? quick = (_quickOpen && _lib != null)
        ? QuickBar(
            key: const Key('quick-bar-widget'),
            library: _lib!,
            settings: _s,
            assignSlot: _assignSlot,
            placement: _s.quickBarPlacement,
            onTapSlot: tapQuickSlot,
            onClearSlot: clearFavorite,
          )
        : null;
    final Widget? panel = showPanel
        ? SymbolPanel(
            key: const Key('symbol-panel'),
            library: _lib!,
            columns: _s.gridColumns,
            cellSize: _s.cellSize,
            showLabels: _s.showCellLabels,
            showEmptySuggestions: _s.showEmptySuggestions,
            searchFocus: _searchFocus,
            assignSlot: _assignSlot,
            onAssign: assignSymbol,
            onInsert: insertSymbol,
          )
        : null;

    final bool quickBottom =
        _s.quickBarPlacement == QuickBarPlacement.bottomBar;
    return Container(
      key: const Key('right-column'),
      // ★ +1：左边那条 1px 描边会吃掉 1px 内容宽，不补上的话面板/快捷栏会比
      //   `panelWidth` 窄 1px（实测 QuickBar 417 vs 418 ⇒ 8 格被挤到需要滚动）。
      width: width + 1,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (quick != null && !quickBottom) ...<Widget>[
            quick,
            const Divider(height: 1),
          ],
          if (panel != null) Expanded(child: panel) else const Spacer(),
          if (quick != null && quickBottom) ...<Widget>[
            const Divider(height: 1),
            quick,
          ],
        ],
      ),
    );
  }

  // ---------------- 状态栏 ----------------

  Widget _statusBar() {
    final List<String> parts = <String>[
      if (_s.statusItems.contains(StatusItem.page))
        '共 ${_stats.pages <= 0 ? 1 : _stats.pages} 页',
      if (_s.statusItems.contains(StatusItem.chars)) '${_stats.length} 字符',
      if (_s.statusItems.contains(StatusItem.caret)) '光标 ${_stats.caret}',
      if (_s.statusItems.contains(StatusItem.edits)) '${_stats.edits} 次编辑',
      if (_s.statusItems.contains(StatusItem.autoWrapped) &&
          _stats.autoWrapped > 0)
        '自动包裹 ${_stats.autoWrapped} 处',
      if (_s.statusItems.contains(StatusItem.saveState))
        dirty ? '未保存' : '已保存',
    ];
    return Container(
      height: LayoutMetrics.statusBarHeight,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              parts.join(' · '),
              key: const Key('status-text'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Color(0xFF4A5568)),
            ),
          ),
          if (_stats.composing)
            Text('组合中「${_stats.composingText}」',
                style: const TextStyle(fontSize: 10, color: Color(0xFF1E88E5))),
        ],
      ),
    );
  }
}
