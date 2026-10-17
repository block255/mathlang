// 数语引擎 · **编辑器页面（外壳）**（S4-b）
//
// 规格：《界面与布局.md》。骨架（从上到下）：
//   顶栏（文档名 / 符号 / 设置）· 文档列（A4 页面，宽 793.7，**偏左**）· 右侧面板（宽由格数推算）
//   · 状态栏（页号·字数·光标·编辑次数·自动包裹）
//
// ★★ 两条硬不变量（守卫测试会盯）：
//   ① **正文宽度不变**：并排时只挪文档列的 x，**不挤压** ⇒ `PageGeometry.contentWidth` 恒定；
//   ② 面板/快捷栏/状态栏**不进 `DocView` 的排版树** ⇒ 开合不改变分页。

import 'package:flutter/material.dart';

import '../core/doc_buffer.dart';
import '../core/doc_settings.dart';
import '../editor/edit_view.dart';
import '../lang/symbol_library.dart';
import '../layout/page_metrics.dart';
import '../spike/s3_edit/s3_edit_page.dart' show kEditSample;
import 'app_settings.dart';
import 'symbol_panel.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({super.key, this.library, this.settings, this.buffer});

  /// 测试注入（不传则从 `assets/symbols.json` 加载）
  final SymbolLibrary? library;
  final AppSettings? settings;
  final DocBuffer? buffer;

  @override
  State<EditorPage> createState() => EditorPageState();
}

class EditorPageState extends State<EditorPage> {
  late final DocBuffer _buf = widget.buffer ?? DocBuffer(kEditSample);
  final GlobalKey<EditViewState> _editKey = GlobalKey<EditViewState>();
  final FocusNode _searchFocus = FocusNode();

  SymbolLibrary? _lib;
  late AppSettings _s = widget.settings ?? const AppSettings();
  bool _panelOpen = false;
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
    super.dispose();
  }

  // ---------------- 对外（测试/诊断） ----------------

  /// 当前应用的设置（测试改这里）
  AppSettings get settings => _s;
  set settings(AppSettings v) => setState(() => _s = v);

  bool get panelOpen => _panelOpen;

  void togglePanel({bool? open}) {
    setState(() => _panelOpen = open ?? !_panelOpen);
    if (_panelOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    }
  }

  /// 面板插入（也供测试直接调）
  void insertSymbol(SymbolItem item) {
    _editKey.currentState?.insertSymbolTex(item.tex, template: item.isTemplate);
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
      body: LayoutBuilder(builder: (BuildContext c, BoxConstraints cons) {
        final PanelMode mode = _s.effectivePanelMode(cons.maxWidth);
        final bool showPanel = _panelOpen && _lib != null;
        if (mode == PanelMode.sideBySide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: _pageColumn(offsetLeft: _s.pageOffsetLeft),
              ),
              if (showPanel) _panel(cons.maxWidth),
            ],
          );
        }
        // 覆盖式：页面居中 + 抽屉从右侧滑出（★ 只遮不改宽）
        return Stack(
          children: <Widget>[
            _pageColumn(offsetLeft: false),
            if (showPanel) ...<Widget>[
              Positioned.fill(
                child: GestureDetector(
                  key: const Key('panel-scrim'),
                  onTap: () => togglePanel(open: false),
                  child: const ColoredBox(color: Color(0x1A000000)),
                ),
              ),
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                child: _panel(cons.maxWidth),
              ),
            ],
          ],
        );
      }),
      bottomNavigationBar: _s.showStatusBar ? _statusBar() : null,
    );
  }

  Widget _topBar() {
    return Material(
      color: Colors.white,
      elevation: 1,
      child: SizedBox(
        height: LayoutMetrics.topBarHeight,
        child: Row(
          children: <Widget>[
            const SizedBox(width: 16),
            const Icon(Icons.description_outlined, size: 18),
            const SizedBox(width: 8),
            const Text('未命名文档', style: TextStyle(fontSize: 14)),
            const Spacer(),
            TextButton.icon(
              key: const Key('open-symbol-panel'),
              onPressed: () => togglePanel(),
              icon: const Icon(Icons.functions, size: 18),
              label: const Text('符号'),
            ),
            _settingsMenu(),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _settingsMenu() {
    return PopupMenuButton<String>(
      key: const Key('settings-menu'),
      tooltip: '设置',
      icon: const Icon(Icons.tune, size: 18),
      onSelected: (String v) {
        switch (v) {
          case 'offset':
            settings = _s.copyWith(pageOffsetLeft: !_s.pageOffsetLeft);
          case 'status':
            settings = _s.copyWith(showStatusBar: !_s.showStatusBar);
          case 'mode':
            settings = _s.copyWith(
              autoPanelMode: false,
              panelMode: _s.panelMode == PanelMode.sideBySide
                  ? PanelMode.overlay
                  : PanelMode.sideBySide,
            );
          case 'cols':
            final int next = _s.gridColumns >= 10 ? 6 : _s.gridColumns + 2;
            settings = _s.copyWith(gridColumns: next);
        }
      },
      itemBuilder: (BuildContext c) => <PopupMenuEntry<String>>[
        CheckedPopupMenuItem<String>(
          value: 'offset',
          checked: _s.pageOffsetLeft,
          child: const Text('页面偏左（面板占右侧）'),
        ),
        CheckedPopupMenuItem<String>(
          value: 'status',
          checked: _s.showStatusBar,
          child: const Text('显示状态栏'),
        ),
        CheckedPopupMenuItem<String>(
          value: 'mode',
          checked: _s.panelMode == PanelMode.sideBySide,
          child: const Text('面板并排（否则覆盖）'),
        ),
        PopupMenuItem<String>(
          value: 'cols',
          child: Text('网格列数：${_s.gridColumns}（点一下 +2）'),
        ),
      ],
    );
  }

  /// 文档列：**固定页宽**（不随之变宽变窄）＋ 可选偏左
  Widget _pageColumn({required bool offsetLeft}) {
    final double pageWidth = PageGeometry.from(DocSettings.defaults).pageWidth;
    return SingleChildScrollView(
      child: Align(
        alignment: offsetLeft ? Alignment.topLeft : Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.only(
            left: offsetLeft ? LayoutMetrics.pageOuterMargin : 0,
            top: 12,
            bottom: 24,
          ),
          child: SizedBox(
            width: pageWidth,
            child: EditView(
              key: _editKey,
              buffer: _buf,
              settings: DocSettings.defaults,
              onStats: (EditViewStats s) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _stats = s);
                });
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _panel(double windowWidth) {
    final double w = LayoutMetrics.panelWidth(_s.gridColumns);
    return Container(
      width: w,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: SymbolPanel(
        library: _lib!,
        columns: _s.gridColumns,
        onInsert: insertSymbol,
        searchFocus: _searchFocus,
      ),
    );
  }

  Widget _statusBar() {
    return Container(
      height: LayoutMetrics.statusBarHeight,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      child: Text(
        '$_stats',
        key: const Key('status-text'),
        style: const TextStyle(fontSize: 11, color: Color(0xFF4A5568)),
      ),
    );
  }
}
