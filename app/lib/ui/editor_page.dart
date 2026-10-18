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

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/doc_buffer.dart';
import '../core/doc_settings.dart';
import '../core/document_file.dart';
import '../editor/edit_view.dart';
import '../io/pdf_builder.dart';
import '../lang/block_ops.dart';
import '../lang/math_spans.dart';
import '../lang/shortcut_registry.dart';
import '../lang/smart_wrap.dart';
import '../lang/symbol_library.dart';
import '../lang/word_triggers.dart';
import '../io/file_gateway.dart';
import '../io/file_gateway_platform.dart';
import '../io/session_data.dart';
import '../io/session_store.dart';
import '../io/session_store_platform.dart';
import '../layout/page_metrics.dart';
import '../spike/s3_edit/s3_edit_page.dart' show kEditSample;
import 'app_settings.dart';
import 'diagnostics_panel.dart';
import 'quick_bar.dart';
import 'settings_page.dart';
import 'symbol_panel.dart';

/// ★★ S4-c：**快捷键 → 符号库 id**（唯一的映射表；tex 一律取符号库里的那一份）。
///
/// 为什么不在这里另写一遍 tex：符号库是"符号表"的唯一数据源（《符号表-分类与关键词》），
/// 面板、快捷栏、快捷键三处必须插**同一个** tex —— 否则三处会漂（本仓已经因"两条写入路径"栽过）。
const Map<String, String> kShortcutSymbolIds = <String, String>{
  'frac': 'frac',
  'sqrt': 'sqrt',
  'integral': 'int',
  'summ': 'sum',
  'limit': 'lim',
  'aligned': 'aligned',
  'cases': 'cases',
  'pmatrix': 'mat2',
  'binom': 'binom',
};

/// ★★ S4-c：**外壳负责的**动作（其余动作由 `EditView` 自己的按键通道处理）。
///
/// 划这条线的判据：**"编辑缓冲区的字符级动作"留在 EditView，"插入/结构/文件"归外壳**。
/// 两边不重叠 ⇒ 不会有同一个键被处理两次（那是"按一下删两个字符"这类 bug 的来源）。
const Set<String> kShellActions = <String>{
  'newdoc', 'open', 'save', 'saveAs', 'settings', 'panelToggle', 'quickSlot',
  'h1', 'h2', 'h3', 'ol', 'ul', 'quote', 'codeblock', 'pagebreak', //
  'mathDisplay', 'frac', 'sqrt', 'sup', 'sub', 'integral',
  'summ', 'limit', 'aligned', 'cases', 'pmatrix', 'binom',
};

class EditorPage extends StatefulWidget {
  const EditorPage({
    super.key,
    this.library,
    this.settings,
    this.doc,
    this.buffer,
    this.gateway,
    this.session,
  });

  /// 测试注入（不传则从 `assets/symbols.json` 加载）
  final SymbolLibrary? library;
  final AppSettings? settings;
  final DocSettings? doc;
  final DocBuffer? buffer;

  /// 测试注入的文件后端（不传就用当前平台的真实现）
  final FileGateway? gateway;

  /// ★ S4-e-①：本地暂存后端（不传就用当前平台的真实现 —— 桌面写 exe 同目录的 JSON）
  final SessionStore? session;

  @override
  State<EditorPage> createState() => EditorPageState();
}

class EditorPageState extends State<EditorPage> {
  late final DocBuffer _buf = widget.buffer ?? DocBuffer(kEditSample);

  /// 进页面时缓冲区里的内容 —— 只有"还没人动过"时才允许被暂存覆盖
  late final String _initialBuffer = _buf.buf;
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

  /// 当前文档的身份与保存状态
  DocumentFile _docFile = const DocumentFile();

  /// 上次保存/打开/新建时的正文快照（dirty 的判据）
  late String _savedText = _buf.buf;

  /// 布局打点只打一次
  bool _layoutLogged = false;

  late final FileGateway _file = widget.gateway ?? platformFileGateway();

  // ---------------- ★ S4-e-① 本地暂存 ----------------

  /// 桌面 = exe 同目录的 JSON；Web = 不落盘（开发预览而已）
  late final SessionStore _session = widget.session ?? platformSessionStore();

  /// 节流保存：最后一次改动后 [kSessionSaveDelay] 落一次盘（不是每键写）
  Timer? _saveTimer;
  static const Duration kSessionSaveDelay = Duration(milliseconds: 800);

  /// 暂存落点与上次写入时间（设置页「高级」里显示 —— 让「存到哪了」可见）
  String _sessionPath = '';
  DateTime? _sessionSavedAt;

  /// 启动时是否从暂存里恢复过（顶栏提示用）
  bool _restored = false;

  /// 已经 dispose 了（异步落盘回来时不许再 setState —— 否则撞 defunct 断言）
  bool _disposed = false;

  /// 页面纵向滚动位置（恢复时回到原地）
  double _scrollOffset = 0;
  final ScrollController _pageScroll = ScrollController();

  String _title = DocumentFile.kUntitled;
  bool _editingTitle = false;

  /// ★ 快捷键偏好与词表（内存态；持久化随 S4-e）
  ShortcutSettings _shortcuts = ShortcutSettings.defaults();
  TriggerSettings _triggers = TriggerSettings.defaults();

  /// 测试/诊断用：快捷键偏好与词表
  ShortcutSettings get shortcuts => _shortcuts;

  /// 测试注入（守"用户改键即刻生效"这条：界面说的话必须是真的）
  @visibleForTesting
  set shortcuts(ShortcutSettings v) {
    setState(() => _shortcuts = v);
    _schedulePersist();
  }

  TriggerSettings get triggers => _triggers;

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
    // ★ S4-e-①：先尝试恢复上次会话（**同步入口、异步等待**，恢复完再挂监听去存）
    _buf.addListener(_onBufferEdited);
    _restoreSession();
  }

  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    // ★ 关闭前补一次（用户误关窗口不该丢内容）。`dispose` 里不能 await，所以 fire-and-forget。
    _buf.removeListener(_onBufferEdited);
    _persistNow();
    _pageScroll.dispose();
    _searchFocus.dispose();
    _shellFocus.dispose();
    _titleCtl.dispose();
    super.dispose();
  }

  // ---------------- ★ S4-e-①：本地暂存 ----------------

  /// 启动恢复（静默；成功后挂一条可关掉的提示）
  Future<void> _restoreSession() async {
    SessionData? d;
    try {
      d = await _session.load();
      _sessionPath = await _session.describe();
    } catch (_) {
      d = null;
    }
    // ★ 只有"还没人动过缓冲区"时才覆盖 —— 测试/外部注入的缓冲区不许被暂存悄悄顶掉
    final bool untouched = _buf.buf == _initialBuffer;
    if (d != null && untouched) {
      _buf.loadDocument(d.text);
      _buf.setSelection(d.anchor.clamp(0, d.text.length),
          d.caret.clamp(0, d.text.length));
      _savedText = d.savedText;
      _scrollOffset = d.scrollOffset;
      final DocumentFile df = DocumentFile(
        title: d.title.isEmpty ? DocumentFile.kUntitled : d.title,
        path: d.path,
      );
      if (!mounted) return;
      setState(() {
        _docFile = df;
        _title = df.title;
        if (d!.app != null) _s = d.app!;
        if (d.doc != null) _doc = d.doc!;
        if (d.shortcuts != null) _shortcuts = d.shortcuts!;
        if (d.triggers != null) _triggers = d.triggers!;
        _restored = true;
        _sessionSavedAt = d.savedAt;
      });
      // 回到上次的滚动位置（等这一帧建完）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_pageScroll.hasClients) {
          final double max = _pageScroll.position.maxScrollExtent;
          _pageScroll.jumpTo(_scrollOffset.clamp(0.0, max));
        }
      });
    } else {
      if (mounted) setState(() {});
    }
  }

  /// 缓冲区变了 ⇒ 排一次落盘（**节流**：连续打字只写最后一次）
  void _onBufferEdited() => _schedulePersist();

  void _schedulePersist() {
    _saveTimer?.cancel();
    _saveTimer = Timer(kSessionSaveDelay, _persistNow);
  }

  /// 真正写一次快照（失败安静返回，绝不打断编辑）
  Future<void> _persistNow() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (_pageScroll.hasClients) _scrollOffset = _pageScroll.offset;
    final SessionData data = SessionData(
      text: _buf.buf,
      title: _title,
      path: _docFile.path,
      savedText: _savedText,
      caret: _buf.caret,
      anchor: _buf.anchor,
      scrollOffset: _scrollOffset,
      app: _s,
      doc: _doc,
      shortcuts: _shortcuts,
      triggers: _triggers,
      savedAt: DateTime.now(),
    );
    final bool ok = await _session.save(data);
    if (!ok) return;
    _sessionSavedAt = data.savedAt;
    try {
      _sessionPath = await _session.describe();
    } catch (_) {
      // 描述只是给人看，失败不影响暂存
    }
    if (!_disposed && mounted) setState(() {});
  }

  /// 设置页「高级 → 清除本地暂存」
  Future<void> clearSession() async {
    await _session.clear();
    _sessionSavedAt = null;
    if (mounted) {
      setState(() {});
      _snack('已清除本地暂存（下次启动不会恢复这份内容）');
    }
  }

  /// 诊断/测试用：暂存落点与上次写入时间
  String get sessionPath => _sessionPath;
  DateTime? get sessionSavedAt => _sessionSavedAt;
  bool get sessionRestored => _restored;
  SessionStore get sessionStore => _session;

  // ---------------- 对外（测试 / 诊断） ----------------

  AppSettings get settings => _s;
  set settings(AppSettings v) {
    setState(() => _s = v);
    _schedulePersist();
  }

  DocSettings get doc => _doc;
  set doc(DocSettings v) {
    setState(() => _doc = v);
    _schedulePersist();
  }

  bool get panelOpen => _panelOpen;
  bool get quickOpen => _quickOpen;
  bool get settingsOpen => _settingsOpen;
  int? get assignSlot => _assignSlot;
  String get title => _title;
  /// ★ dirty 的唯一判据 = **正文与上次保存/打开/新建时的快照不同**
  ///
  /// 为什么不用"编辑次数比对"：打开另一个文件后 `EditView` 的计数器不会归零
  /// （实测：打开完立刻显示"未保存"），而且"改完又改回去"本来就该算干净。
  bool get dirty => _buf.buf != _savedText;

  /// 当前文档（测试与诊断用）
  DocumentFile get docFile => _docFile;

  /// 右栏当前宽度（0 = 右栏不存在）
  double get rightColumnWidth => _rightWidth();

  void togglePanel({bool? open}) {
    setState(() {
      _panelOpen = open ?? !_panelOpen;
      if (!_panelOpen && _assignSlot != null) _assignSlot = null;
    });
    // ★★ 2026-10-18：**打开面板不抢焦点**（用户拍板：覆盖只是视觉覆盖）。
    //   原来这里把焦点推给搜索框 ⇒ 编辑器失焦 ⇒ 光标不画、点编辑器会被当"点外面"。
    //   ⇒ 现在打字直接进正文（这正是"交互上不影响"）；要用搜索框就**点它一下**
    //     （那一刻编辑器才失焦、光标才隐藏 —— 那是合理的）。
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
    _editKey.currentState?.insertSymbolTex(item.tex,
        template: item.isTemplate, display: item.isDisplay);
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

  /// ★ 诊断清单：点状态栏「自动包裹 N 处」⇒ 列出那几处，点一条跳过去并高亮
  void openDiagnostics() {
    final List<MathSpan> spans = _stats.autoWrappedSpans;
    showDiagnostics(
      context,
      spans: spans,
      onJump: (MathSpan s) => _editKey.currentState?.jumpTo(s.start, s.end),
    );
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

  // ---------------- 文件动线（S4-d：新建 / 打开 / 保存 / 另存为） ----------------

  /// 新建：清空到空白文档（**先问要不要保存**）
  Future<void> newDocument() async {
    if (!await _confirmDiscard('新建')) return;
    _buf.loadDocument('');
    _savedText = _buf.buf;
    setState(() {
      _docFile = const DocumentFile();
      _title = DocumentFile.kUntitled;
    });
    _editKey.currentState?.focusInput();
    _persistNow(); // 新建 ⇒ 立刻覆盖暂存（别让下次启动恢复上一份）
  }

  /// 打开：从磁盘读一份 md/txt（整篇换掉，并清空撤销栈）
  Future<void> openDocument() async {
    if (!await _confirmDiscard('打开')) return;
    OpenedFile? f;
    try {
      f = await _file.openText();
    } catch (e) {
      // ★★ 2026-10-17：**文件出错必须让用户看见**（以前只进控制台 ⇒ "点了没反应"）。
      await _showFileError('打开', e);
      return;
    }
    if (f == null) return; // 用户取消
    _buf.loadDocument(f.text);
    _savedText = _buf.buf;
    final DocumentFile df = DocumentFile(
      title: DocumentFile.titleFromPath(f.path),
      path: f.path,
    );
    setState(() {
      _docFile = df;
      _title = df.title;
    });
    _editKey.currentState?.focusInput();
    _persistNow(); // 打开 ⇒ 立刻覆盖暂存
    _snack(f.lossy
        ? '已打开 ${f.name}（该文件可能不是 UTF-8，已按容错方式读入）'
        : '已打开 ${f.name}');
  }

  /// 保存（`saveAs = true` ⇒ 另存为：这次一定让用户挑位置）
  Future<bool> saveDocument({bool saveAs = false}) async {
    SaveOutcome out;
    try {
      out = await _file.saveText(
        text: _buf.buf,
        path: saveAs ? null : _docFile.path,
        suggestedName: _docFile.suggestedFileName(),
      );
    } catch (e) {
      await _showFileError(saveAs ? '另存为' : '保存', e);
      return false;
    }
    if (!out.ok) return false; // 取消 ⇒ 什么都不改（dirty 不能清掉）
    _savedText = _buf.buf; // 写下去的**就是**快照（之后再改才算脏）
    final DocumentFile df = DocumentFile(
      title: DocumentFile.titleFromPath(out.path!),
      path: out.path,
    );
    setState(() {
      _docFile = df;
      _title = df.title;
    });
    _persistNow(); // 保存 ⇒ 立刻把 savedText 写进暂存
    _snack('已保存到 ${DocumentFile.fileNameOf(out.path!)}');
    return true;
  }

  /// ★★ S4-d②：**导入**（`.md` 原样、`.txt` 走智能包裹）。
  ///
  /// 语义：导入 = **新建一份内容**（不是"打开那个文件"）⇒ `path = null`、标题取文件名。
  /// 为什么不能把 path 设成源文件：`.txt` 导入会**被包裹改写**，保存回去等于覆盖用户的原件。
  Future<void> importDocument() async {
    if (!await _confirmDiscard('导入')) return;
    OpenedFile? f;
    try {
      f = await _file.openText(
          extensions: const <String>['md', 'txt', 'markdown']);
    } catch (e) {
      await _showFileError('导入', e);
      return;
    }
    if (f == null) return;

    final String ext = DocumentFile.extensionOf(f.name);
    final String raw = f.text;
    var text = raw;
    var wrapped = 0;
    if (ext == 'txt') {
      // 纯文本 ≈ "用户手上的一段话" ⇒ 与粘贴同一条口径（A2 智能包裹）
      final SmartWrapPlan plan = planSmartWrap(raw);
      wrapped = plan.runs.length;
      if (plan.runs.isNotEmpty) text = applySmartWrap(raw, plan);
    }
    _buf.loadDocument(text);
    _savedText = _buf.buf;
    final DocumentFile df =
        DocumentFile(title: DocumentFile.titleFromPath(f.name));
    setState(() {
      _docFile = df; // path 故意留空：这是一份**新文档**
      _title = df.title;
    });
    _editKey.currentState?.focusInput();
    _snack(wrapped > 0
        ? '已导入 ${f.name}（智能包裹 $wrapped 处，可在状态栏查看）'
        : '已导入 ${f.name}');
  }

  /// ★★ S4-d②：**导出**（`md` / `txt`）。
  ///
  /// ★ **两者内容逐字节相同**（2026-10-17 用户拍板：txt 追求"不丢信息、能再导入"，
  ///   不为"给人看"去掉 `$`）——差别只有扩展名。
  /// ★ 导出**不改**当前文档的身份与 dirty：它是"另存一份出去"，不是"保存"。
  Future<void> exportDocument(String ext) async {
    SaveOutcome out;
    try {
      out = await _file.saveText(
        text: _buf.buf,
        suggestedName: _docFile.suggestedFileName(ext: ext),
        extension: ext,
      );
    } catch (e) {
      await _showFileError('导出', e);
      return;
    }
    if (!out.ok) return;
    _snack('已导出 ${DocumentFile.fileNameOf(out.path!)}');
  }

  // ---------------- 图片集 / PDF（S4-d③） ----------------

  /// 抓当前每一页的 PNG（`pixelRatio = 2` ⇒ 一页约 1588 × 2246，打印也够）
  Future<List<Uint8List>?> _capturePages(String action) async {
    final EditViewState? st = _editKey.currentState;
    if (st == null) return null;
    // ★ 这里**不**等 `endOfFrame`：`DocView.capturePages` 只在"这一页还没画过"时才等一帧。
    //   无条件等会把调用方**永远挂住**（测试里没有自动出帧；真机上点导出时页面早就画好了）。
    final List<Uint8List> pages;
    try {
      pages = await st.capturePages();
    } catch (e) {
      await _showFileError(action, e);
      return null;
    }
    if (pages.isEmpty) {
      await _showFileError(action, '还没有可以导出的页面（分页还没完成？）');
      return null;
    }
    return pages;
  }

  /// ★★ S4-d③：**图片集** —— 每页一张 PNG（作业辅导场景直接发学生）。
  ///
  /// 命名 `文档名-第01页.png`（补零 ⇒ 文件管理器里按名字就是页序）。
  Future<void> exportImages() async {
    final List<Uint8List>? pages = await _capturePages('导出图片集');
    if (pages == null) return;
    final String base =
        _title.trim().isEmpty ? DocumentFile.kUntitled : _title.trim();
    final List<ExportFile> files = <ExportFile>[
      for (var i = 0; i < pages.length; i++)
        ExportFile(
          name: '$base-第${(i + 1).toString().padLeft(2, '0')}页.png',
          bytes: pages[i],
        ),
    ];
    ExportBatch? batch;
    try {
      batch = await _file.saveBatch(
        files: files,
        dialogTitle: '选择图片集的保存位置',
      );
    } catch (e) {
      await _showFileError('导出图片集', e);
      return;
    }
    if (batch == null) return; // 取消 ⇒ 什么都不做
    _snack('已导出 ${batch.count} 张图片到 ${batch.directory}');
  }

  /// ★★ S4-d③：**PDF**（图片式 ＋ `.md` 内嵌附件）。
  ///
  /// 视觉 1:1（就是屏幕上的每一页），而"能不能无损导回"靠附件（PDF 规范支持的 embedded file）。
  /// ★ 导出**不改**文档身份与 dirty：它只是"另存一份出去"。
  Future<void> exportPdf() async {
    final List<Uint8List>? pages = await _capturePages('导出 PDF');
    if (pages == null) return;
    final String base =
        _title.trim().isEmpty ? DocumentFile.kUntitled : _title.trim();
    PdfExportResult r;
    try {
      r = await buildImagePdf(
        pagePngs: pages,
        markdown: _buf.buf,
        title: base,
      );
    } catch (e) {
      await _showFileError('导出 PDF', e);
      return;
    }
    SaveOutcome out;
    try {
      out = await _file.saveBytes(
        bytes: r.bytes,
        suggestedName: '$base.pdf',
        extension: 'pdf',
      );
    } catch (e) {
      await _showFileError('导出 PDF', e);
      return;
    }
    if (!out.ok) return;
    _snack('已导出 ${DocumentFile.fileNameOf(out.path!)}'
        '（${r.pageCount} 页，md 已内嵌 ${(r.attachmentBytes / 1024).toStringAsFixed(1)} KB）');
  }

  /// 有未保存改动时先确认（`true` = 可以继续）
  Future<bool> _confirmDiscard(String action) async {
    if (!dirty) return true;
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        key: const Key('discard-dialog'),
        title: Text('「$_title」有未保存的改动'),
        content: Text('继续$action会把它们丢掉。要先保存吗？'),
        actions: <Widget>[
          TextButton(
            key: const Key('discard-cancel'),
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('discard-no-save'),
            onPressed: () => Navigator.of(c).pop(true),
            child: Text('不保存，继续$action'),
          ),
          FilledButton(
            key: const Key('discard-save'),
            onPressed: () async {
              final bool ok = await saveDocument();
              if (c.mounted) Navigator.of(c).pop(ok);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    return go ?? false;
  }

  /// ★ 文件操作失败时**弹出来**：原因 + 一句"接下来往哪儿查"。
  ///
  /// 为什么必须有：用户 2026-10-17 在 Windows 上点「保存」时**界面毫无反应**
  /// （异常只进了控制台），这违反原则 5「可疑要可见」——出错比"没发生"更需要说清。
  Future<void> _showFileError(String action, Object e) async {
    final String raw = e.toString();
    final String detail = raw.length > 400 ? '${raw.substring(0, 400)}…' : raw;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        key: const Key('file-error-dialog'),
        icon: const Icon(Icons.error_outline, color: Color(0xFFC53030)),
        title: Text('$action失败'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SelectableText(detail,
                key: const Key('file-error-detail'),
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Color(0xFF2D3748))),
            const SizedBox(height: 10),
            const Text(
              '常见原因：文件被别的程序占用 / 只读 / 没有写权限 / 路径太长。\n'
              '换个位置或关掉占用它的程序再试。',
              style: TextStyle(fontSize: 11, color: Color(0xFF718096), height: 1.5),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('file-error-close'),
            onPressed: () => Navigator.of(c).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }
  // ---------------- 快捷键（外壳层） ----------------

  /// ★★ S4-c：外壳按键的**唯一入口** = 查 `ShortcutSettings` 这张表。
  ///
  /// 为什么不再写一堆 `if (kb.isControlPressed && k == keyN)`：
  ///   ① 用户在设置页改键/加副绑定之后，硬编码的 if **不会跟着变**（界面就会撒谎）；
  ///   ② 45 条动作硬编码无法维护。现在"按键 → 动作 id → 干活"三段式，
  ///      没接入的动作（`ShortcutStatus.planned`）**不抢键**，所以它照样是普通字符。
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

    // ★ Alt+1..8：快捷栏第 N 格（同一个动作的 8 个键，表里只登记了 `Alt+1`）
    if (kb.isAltPressed &&
        !kb.isControlPressed &&
        !kb.isMetaPressed &&
        !kb.isShiftPressed) {
      final int? n = _altDigit(k);
      if (n != null) {
        if (n <= _s.quickBarSlots && !_shortcuts.isDisabled('quickSlot')) {
          insertFavorite(n - 1);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }
    }
    // ★ `Ctrl+Shift+O` = 导入（表里没有这条动作：它是"新建一份内容"，不是"打开"）
    if (kb.isControlPressed &&
        kb.isShiftPressed &&
        !kb.isAltPressed &&
        k == LogicalKeyboardKey.keyO) {
      importDocument();
      return KeyEventResult.handled;
    }

    final String? id = _actionForKey(k, kb);
    if (id != null && _runShortcutAction(id)) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 这个按键（含修饰键）命中哪条**已接入的外壳动作**？
  String? _actionForKey(LogicalKeyboardKey k, HardwareKeyboard kb) {
    // 设置页 / 改标题时按键归那一层（否则会在输入框里抢键）
    if (_settingsOpen || _editingTitle) return null;
    final String? name = _comboKeyName(k);
    if (name == null) return null;
    for (final ShortcutAction a in kShortcutActions) {
      if (!kShellActions.contains(a.id)) continue;
      if (!a.wired) continue; // 未接入的动作**不抢键**
      if (_shortcuts.isDisabled(a.id)) continue;
      for (final ShortcutCombo c in _shortcuts.combosOf(a.id)) {
        if (c.isEmpty) continue;
        if (c.key.toUpperCase() != name.toUpperCase()) continue;
        if (c.ctrl != kb.isControlPressed) continue;
        if (c.alt != kb.isAltPressed) continue;
        if (c.shift != kb.isShiftPressed) continue;
        if (c.meta != kb.isMetaPressed) continue;
        return a.id;
      }
    }
    return null;
  }

  /// `LogicalKeyboardKey` → 登记表里的键名（`'F'` / `'1'` / `'ArrowUp'` / `'='` / `','` …）
  String? _comboKeyName(LogicalKeyboardKey k) {
    if (k == LogicalKeyboardKey.arrowUp) return 'ArrowUp';
    if (k == LogicalKeyboardKey.arrowDown) return 'ArrowDown';
    if (k == LogicalKeyboardKey.arrowLeft) return 'ArrowLeft';
    if (k == LogicalKeyboardKey.arrowRight) return 'ArrowRight';
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      return 'Enter';
    }
    if (k == LogicalKeyboardKey.tab) return 'Tab';
    if (k == LogicalKeyboardKey.escape) return 'Esc';
    if (k == LogicalKeyboardKey.space) return 'Space';
    final String label = k.keyLabel;
    if (label.isEmpty) return null;
    if (label.length == 1) {
      final int c = label.codeUnitAt(0);
      final bool letter =
          (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
      return letter ? label.toUpperCase() : label;
    }
    return label;
  }

  /// 执行一条外壳动作；返回 `false` = 这条动作在这个状态下**不做事**（键继续往下走）
  bool _runShortcutAction(String id) {
    switch (id) {
      case 'newdoc':
        newDocument();
        return true;
      case 'open':
        openDocument();
        return true;
      case 'save':
        saveDocument();
        return true;
      case 'saveAs':
        saveDocument(saveAs: true);
        return true;
      case 'settings':
        _settingsOpen ? closeSettings() : openSettings();
        return true;
      case 'panelToggle':
        togglePanel();
        return true;
      case 'h1':
        return _blockOp(BlockOp.h1);
      case 'h2':
        return _blockOp(BlockOp.h2);
      case 'h3':
        return _blockOp(BlockOp.h3);
      case 'ol':
        return _blockOp(BlockOp.ol);
      case 'ul':
        return _blockOp(BlockOp.ul);
      case 'quote':
        return _blockOp(BlockOp.quote);
      case 'codeblock':
        return _blockOp(BlockOp.codeblock);
      case 'pagebreak':
        return _blockOp(BlockOp.pagebreak);
      case 'mathDisplay':
        // ★ 2026-10-18：`Ctrl+Alt+E` 回来了，但语义**不再是造空壳** ——
        //   它是「**插入一个行间公式段**」（块级排版单位；空态有淡虚线小框 ⇒ 看得见、点得到）。
        //   与"行内空壳"的区别（用户论证过）：行间段是**块**，不写内容也成立；
        //   行内公式必须**由内容产生**（平权）。
        _editKey.currentState
            ?.insertSymbolTex('', template: true, display: true);
        return true;
      case 'sup':
        _editKey.currentState?.insertScript(sup: true);
        return true;
      case 'sub':
        _editKey.currentState?.insertScript(sup: false);
        return true;
      default:
        final String? symId = kShortcutSymbolIds[id];
        if (symId == null) return false;
        final SymbolItem? item = _lib?.byId(symId);
        if (item == null) return false; // 符号库还没加载完 ⇒ 这一下不接
        insertSymbol(item);
        return true;
    }
  }

  bool _blockOp(BlockOp op) {
    final EditViewState? st = _editKey.currentState;
    if (st == null) return false;
    st.insertBlockOp(op);
    return true;
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
          // ★ 一次性布局打点（只在调试构建）：用来核实"右栏宽度/DPR 到底是多少"。
          //   Windows 上按 125%/150% 缩放时，逻辑像素与物理像素容易看花眼。
          if (!kReleaseMode && !_layoutLogged) {
            _layoutLogged = true;
            final double dpr = MediaQuery.of(context).devicePixelRatio;
            debugPrint('[layout] window=${cons.maxWidth.toStringAsFixed(1)} '
                'dpr=$dpr '
                'pageW=${PageGeometry.from(_doc).pageWidth.toStringAsFixed(1)} '
                'panelW=${LayoutMetrics.panelWidth(_s.gridColumns, cell: _s.cellSize).toStringAsFixed(1)} '
                'quickSlots=${_s.quickBarSlots} cell=${_s.cellSize} '
                'rightW=${_rightWidth().toStringAsFixed(1)}');
          }
          final double rightW = _rightWidth();
          // ★ 页面横向可用宽（设置页横条那行"可移动 N px"读数用**同一份**数字）
          final double pageAvail = mode == PanelMode.sideBySide
              ? (cons.maxWidth - rightW)
              : cons.maxWidth;
          final Widget page = _pageColumn(
            // ★★ 2026-10-18 **修复**（用户报"Windows 里拖横条页面不动"）：
            //   原来是 `mode == PanelMode.sideBySide ? _s.pageXDock : 0.5`
            //   —— **覆盖式下把用户设置直接丢掉了**。
            //   而形态判据是"窗口宽 ≥ 1280 才并排"：1920×1080 @150% 的 Windows 窗口只有
            //   **1265 逻辑像素** ⇒ **永远走覆盖式** ⇒ 横条永远无效
            //   （Web 视口 1434 是并排，所以那边一切正常 —— 这就是"Web 能拖、Windows 不能"的全部原因）。
            //   ⇒ 两种模式**都吃** `pageXDock`；覆盖式的可用空间 = **整窗宽**（抽屉浮在上面、不挤压）。
            dock: _s.pageXDock,
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
                    if (rightW > 0)
                      // ★★ 2026-10-18（用户拍板）：**覆盖 = 视觉覆盖，不是模态**。
                      //   原来这里还有一层 `panel-scrim`（26% 黑 + 点它关面板）+ 打开面板时把焦点
                      //   抢给搜索框 ⇒ 编辑器失焦 ⇒ **光标不画**、点编辑器就关面板。
                      //   用户的原话（类比）："9336 打开可以悬浮在机甲网页上面，但是不影响机甲网页
                      //   其他部分的视觉；我操作机甲网页也不影响它们继续悬浮。"
                      //   ⇒ 遮罩整层删掉、焦点不抢：面板就是一张浮在页面上的卡片。
                      Positioned(
                        top: 0,
                        bottom: 0,
                        right: 0,
                        child: _rightColumn(rightW),
                      ),
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
                    // ★ 页面横向可用宽 ⇒ 设置页横条旁边那行"可移动 N px"（诚实读数）
                    pageSpace: pageAvail,
                    onSettings: (AppSettings v) {
                      setState(() => _s = v);
                      _schedulePersist();
                    },
                    onDoc: (DocSettings v) {
                      setState(() => _doc = v);
                      _schedulePersist();
                    },
                    shortcuts: _shortcuts,
                    triggers: _triggers,
                    // ★ S4-e-①：本地暂存的可见性（「高级」组）
                    sessionPath: _sessionPath,
                    sessionSavedAt: _sessionSavedAt,
                    onClearSession: clearSession,
                    onShortcuts: (ShortcutSettings v) =>
                        setState(() => _shortcuts = v),
                    onTriggers: (TriggerSettings v) =>
                        setState(() => _triggers = v),
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
            if (_restored) ...<Widget>[
              const SizedBox(width: 8),
              _restoredBadge(),
            ],
            const SizedBox(width: 12),
            _textButton('导入', const Key('import-button'),
                tip: '导入 .md / .txt（Ctrl+Shift+O）', onTap: importDocument),
            _textButton('保存', const Key('save-button'),
                tip: '保存（Ctrl+S）', onTap: () => saveDocument()),
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
          case 'new':
            newDocument();
          case 'open':
            openDocument();
          case 'save':
            saveDocument();
          case 'saveAs':
            saveDocument(saveAs: true);
          case 'import':
            importDocument();
          case 'settings':
            openSettings(group: 1);
          case 'about':
            openSettings(group: 8);
          default:
            _snack('这一项还没接入');
        }
      },
      itemBuilder: (BuildContext c) => <PopupMenuEntry<String>>[
        _fileItem('新建', 'Ctrl+N', value: 'new'),
        _fileItem('打开…', 'Ctrl+O', value: 'open'),
        _fileItem('最近打开', '', batch: 'S4-e'),
        const PopupMenuDivider(),
        _fileItem('保存', 'Ctrl+S', value: 'save'),
        _fileItem('另存为…', 'Ctrl+Shift+S', value: 'saveAs'),
        const PopupMenuDivider(),
        _fileItem('导入…', 'Ctrl+Shift+O', value: 'import'),
        // ★ 导出不在这里重复列：顶栏「导出 ▾」是唯一入口（md / txt / 图片集 / PDF）
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

  /// 文件菜单项：**没接入的给 `batch`（灰显 + 标批次，不假装能用）**；
  /// 接入了的给 `value`（可点）。
  PopupMenuItem<String> _fileItem(
    String label,
    String shortcut, {
    String? value,
    String? batch,
  }) {
    final bool on = value != null;
    final Color fg = on ? const Color(0xFF2D3748) : const Color(0xFFA0AEC0);
    return PopupMenuItem<String>(
      value: value ?? label,
      enabled: on,
      height: 36,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 76,
            child: Text(label,
                style: TextStyle(fontSize: 12, color: fg)),
          ),
          Text(shortcut,
              style: const TextStyle(fontSize: 10, color: Color(0xFFA0AEC0))),
          const Spacer(),
          if (batch != null)
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
    final String next =
        v.trim().isEmpty ? DocumentFile.kUntitled : v.trim();
    setState(() {
      // ★ 改了名字 = "这份文档要另存成新名字" ⇒ 断开旧路径，下一次保存会问存哪儿。
      final bool renamed = next != _docFile.title;
      _title = next;
      _docFile = _docFile.copyWith(
        title: next,
        clearPath: renamed && _docFile.hasFile,
      );
      _editingTitle = false;
    });
  }

  /// ★ 保存状态点：`●` 未保存 / `○` 已保存（S4-b 先放标题旁，S4-d 接真文件）
  /// ★ S4-e-①：从暂存恢复了内容 ⇒ 顶栏给一条**可关掉**的提示
  ///
  /// 为什么不弹窗：恢复是"常态"，弹窗会把每次启动变成一次审问。
  /// 为什么必须有：用户有权知道"这份内容不是新文档，而是上次没关干净的那份"（原则 5）。
  Widget _restoredBadge() {
    return Tooltip(
      message: '已从本地暂存恢复上次的编辑（点掉这条提示不会丢内容）',
      child: InkWell(
        key: const Key('session-restored'),
        onTap: () => setState(() => _restored = false),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFEBF4FF),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('已恢复上次编辑',
                  style: TextStyle(fontSize: 10, color: Color(0xFF2B6CB0))),
              SizedBox(width: 4),
              Text('×', style: TextStyle(fontSize: 11, color: Color(0xFF2B6CB0))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _saveDot() {    final bool d = dirty;
    return Tooltip(
      message: d ? '有未保存的改动' : '已保存',
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

  /// 顶栏文字按钮：`onTap == null` ⇒ 灰显（还没接入）
  Widget _textButton(String label, Key key,
      {String? tip, VoidCallback? onTap}) {
    return Tooltip(
      message: tip ?? label,
      child: TextButton(
        key: key,
        onPressed: onTap,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: onTap == null
                ? const Color(0xFFCBD5E0)
                : const Color(0xFF4A5568),
          ),
        ),
      ),
    );
  }

  Widget _exportMenu() {
    return PopupMenuButton<String>(
      key: const Key('export-menu'),
      tooltip: '导出',
      itemBuilder: (BuildContext c) => <PopupMenuEntry<String>>[
        _fileItem('Markdown (.md)', '', value: 'export:md'),
        _fileItem('纯文本 (.txt)', '', value: 'export:txt'),
        _fileItem('图片集（每页 PNG）', '', value: 'export:images'),
        _fileItem('PDF（图片式 + md 附件）', '', value: 'export:pdf'),
      ],
      onSelected: (String v) {
        if (v == 'export:images') {
          exportImages();
        } else if (v == 'export:pdf') {
          exportPdf();
        } else if (v.startsWith('export:')) {
          exportDocument(v.substring(7));
        }
      },
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: <Widget>[
            Text('导出',
                style: TextStyle(fontSize: 12, color: Color(0xFF4A5568))),
            Icon(Icons.arrow_drop_down, size: 16, color: Color(0xFF4A5568)),
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
        // ★ S4-e-①：用一个 controller，重启后能把滚动位置也恢复回去
        controller: _pageScroll,
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
                // ★ S4-c：词触发表 + 三个自动展开开关（设置页「智能输入」里改）
                triggers: _triggers,
                autoSlashFraction: _s.autoSlashFraction,
                autoWordTriggers: _s.autoWordTriggers,
                autoShorthand: _s.autoShorthand,
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
            child: Row(
              children: <Widget>[
                Flexible(
                  child: Text(
                    parts.join(' · '),
                    key: const Key('status-text'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF4A5568)),
                  ),
                ),
                if (_s.statusItems.contains(StatusItem.autoWrapped) &&
                    _stats.autoWrapped > 0)
                  InkWell(
                    key: const Key('diag-open'),
                    onTap: openDiagnostics,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        '自动包裹 ${_stats.autoWrapped} 处 · 查看清单 ›',
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFFDD6B20)),
                      ),
                    ),
                  ),
              ],
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