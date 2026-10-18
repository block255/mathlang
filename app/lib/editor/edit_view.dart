// 数语引擎 · 编辑面（S3-2）
//
// 架构（2026-10-14 输入层重做后；依据见 notes/design/位点与结构导航.md §11.6 / §11.7 / §11.13 后的修订块）：
//
//   ① 渲染层：`DocView`（我们自己的 A4 分页视图）—— **唯一给用户看的东西**
//   ② 输入层：`TextInputSurfaceController`（自实现 `TextInputClient`）
//        · 平台元素里**几乎什么都不装**，被摆到「我们的光标」处 → IME 候选框落在光标处
//        · 它只负责把平台的**文本**交给我们 → `diffPlatformText` → 一次编辑进缓冲区
//        · ★ 组合中间态（打拼音时）**一个字都不写进缓冲区**（§11.7）
//   ③ **命令键**（退格 / Delete / 方向键 …）走 `Focus.onKeyEvent` —— 与文本严格两条通道
//
// ★ 为什么不让平台元素自己当编辑器：那样用户就会看见 `\frac{}{}` 的源码 —— 违背原则 2。
//   平台元素永远是**透明**的，用户看到的只有 ①。

import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/block.dart';
import '../core/doc_buffer.dart';
import '../core/doc_settings.dart';
import '../lang/auto_expand.dart';
import '../lang/block_ops.dart';
import '../lang/math_spans.dart';
import '../lang/smart_wrap.dart';
import '../lang/symbol_insert.dart';
import '../lang/word_triggers.dart';
import '../render/caret_sites.dart'
    show kCaretColorValue, CaretSiteTable, SlotSpan, buildCaretSites;
import '../render/delete_reclaim.dart';
import '../render/insert_guard.dart';
import '../lang/env_resize.dart';
import '../ui/env_size_dialog.dart';
import '../render/math_nav.dart';
import '../render/site_adjacency.dart';
import '../render/normalize.dart';
import '../render/selection_range.dart';
import '../render/smart_delete.dart';
import '../render/visible_atoms.dart' show VisibleAtom, lexVisibleAtoms;
import 'doc_view.dart';
import 'platform_text_diff.dart';
import 'text_input_surface.dart';

/// 编辑面给外部（状态栏 / 演示页 / 测试）看的统计。
class EditViewStats {
  const EditViewStats({
    required this.length,
    required this.caret,
    required this.edits,
    required this.composing,
    required this.composingText,
    this.autoWrapped = 0,
    this.autoWrappedSpans = const <MathSpan>[],
    this.pages = 0,
  });

  final int length;
  final int caret;

  /// 已写进缓冲区的编辑次数（组合中间态**不计**）
  final int edits;
  final bool composing;
  final String composingText;

  /// ★ S4-a A2：**最近一次粘贴**里"智能包裹"自动补了几处 `$…$`（打字/其它编辑会归零）。
  ///
  /// 为什么要有它：包裹是**编辑器替用户做的编码** ⇒ 必须可见（原则 5：可疑要可见）。
  /// 走状态栏 = **不进正文流**（不触发重排/分页）；同时它也是 S4-a A4「诊断清单」的数据来源。
  final int autoWrapped;

  /// ★ S4-b②：**这次自动包裹补出来的那几处数学段**（诊断清单点一条就跳过去）。
  /// `autoWrapped` 只是它的条数 —— 清单要的是**位置**，不是数量。
  final List<MathSpan> autoWrappedSpans;
  /// ★ 排完版后**实际页数**（由 `DocView` 的 `DocViewStats.pages` 回传；状态栏「页号」用它）。
  final int pages;

  @override
  bool operator ==(Object other) =>
      other is EditViewStats &&
      other.length == length &&
      other.caret == caret &&
      other.edits == edits &&
      other.composing == composing &&
      other.composingText == composingText &&
      other.autoWrapped == autoWrapped &&
      other.pages == pages &&
      listEquals(other.autoWrappedSpans, autoWrappedSpans);

  @override
  int get hashCode => Object.hash(
      length, caret, edits, composing, composingText, autoWrapped, pages,
      autoWrappedSpans.isEmpty ? 0 : Object.hashAll(autoWrappedSpans));

  @override
  String toString() => '$length 字符 · 光标 $caret · $edits 次编辑'
      '${pages > 0 ? ' · 第 $pages 页' : ''}'
      '${composing ? ' · 组合中「$composingText」' : ''}'
      '${autoWrapped > 0 ? ' · 自动包裹 $autoWrapped 处' : ''}';
}

/// ★ 提交规则 ①：`Enter` = 新块 → 写入 `\n\n`（《块模型与md往返.md》§四 输出侧约定）
///
/// 为什么放在 **formatter** 里：`formatEditUpdate` 是**纯函数**，可以直接单测；
/// 而且它处在「平台文本 → 缓冲区」这条链上，离输入最近。
///
/// 只处理"单独插入一个换行"；粘贴进来的一大段（含换行）**原样放行**。
class NewBlockOnEnterFormatter extends TextInputFormatter {
  const NewBlockOnEnterFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) {
      return newValue; // 组合中不干预
    }
    final PlatformEdit? e = diffPlatformText(oldValue.text, newValue.text);
    if (e == null || e.removed.isNotEmpty || e.inserted != '\n') return newValue;
    return newValue.copyWith(
      text: newValue.text.replaceRange(e.start, e.start + 1, '\n\n'),
      selection: TextSelection.collapsed(offset: e.start + 2),
      composing: TextRange.empty,
    );
  }
}

class EditView extends StatefulWidget {
  const EditView({
    super.key,
    required this.buffer,
    this.settings = DocSettings.defaults,
    this.onStats,
    this.triggers,
    this.autoSlashFraction = true,
    this.autoWordTriggers = true,
    this.autoShorthand = true,
    this.inputFormatters = const <TextInputFormatter>[
      NewBlockOnEnterFormatter(),
    ],
  });

  final DocBuffer buffer;
  final DocSettings settings;
  final void Function(EditViewStats stats)? onStats;
  final List<TextInputFormatter> inputFormatters;

  /// ★ S4-c：词触发表（`null` = 用默认八条）。设置页改的那份由外壳传进来。
  final TriggerSettings? triggers;

  /// ★ S4-c 三个开关（设置页「智能输入」里可关；关掉就是"这个键恢复成普通字符"）
  final bool autoSlashFraction;
  final bool autoWordTriggers;
  final bool autoShorthand;

  @override
  State<EditView> createState() => EditViewState();
}

/// 撤销分组用的"编辑类别"（只有同类才会合并成一步）
enum _EditKind { typing, deleting }

class EditViewState extends State<EditView> {
  final FocusNode _focus = FocusNode(debugLabel: 'edit-input');
  late final TextInputSurfaceController _input =
      TextInputSurfaceController(focusNode: _focus);

  /// 光标所在行的盒子（**DocView 局部坐标**）—— 给输入面定位 + 画组合中间态
  Rect? _caretRect;

  // ---------------- ⑤ 拖选 / 双击 / 三击 ----------------
  /// 拖选的**锚点**（按下时的偏移）；`null` = 这次按下还没有落点
  int? _dragAnchor;
  bool _dragging = false;
  Offset? _pressAt;

  /// 这次按下有没有命中到某个偏移（`onTapOffset` 是否被调用过）
  bool _pressHit = false;

  /// 焦点状态（失焦 ⇒ 不画光标与选区）
  /// 失焦过（首次进页面不算失焦，保持'上电就有光标'的既有观感）
  bool _blurred = false;

  // ---------------- 闪烁 / 拖到边缘自动滚动 ----------------
  /// 光标闪烁的"亮/灭"（530 ms 一个来回，与常见编辑器一致）
  bool _blinkOn = true;
  Timer? _blink;

  /// 拖选自动滚动
  Timer? _autoScroll;
  Offset? _pointerAt;

  /// 连击计数（同一处 400 ms 内）
  int _clickCount = 0;
  DateTime? _lastClickAt;
  Offset? _lastClickPos;

  /// 给拖选用的 DocView 句柄（对指针下的位置做**纯查询**）
  final GlobalKey<State<StatefulWidget>> _docKey = GlobalKey<State<StatefulWidget>>();

  int _edits = 0;

  /// ★ S4-a A2：最近一次**粘贴**里智能包裹了几处（0 = 没包裹 / 已被后续编辑清掉）
  int _autoWrapped = 0;


  /// ★ S4-b②：最近一次自动包裹补出来的数学段（诊断清单点一条就跳过去）
  List<MathSpan> _autoWrappedSpans = const <MathSpan>[];

  /// ★ S4-b②：`DocView` 回传的**实际页数**（状态栏「页号」读它）
  int _pages = 0;
  EditViewStats? _lastStats;

  /// `false` = 已经开始 dispose（此时一律不再 setState —— `mounted` 在 dispose 期间仍为 true）
  bool _alive = true;

  /// ★ S4-c：正在展开中（防止"保留终止符"的分支再次触发展开）
  bool _expanding = false;

  DocBuffer get _buf => widget.buffer;

  TriggerSettings get _triggers =>
      widget.triggers ?? TriggerSettings.defaults();

  @override
  void initState() {
    super.initState();
    _input.onCommitText = _commitText;
    _input.inputFormatters = widget.inputFormatters;
    _input.addListener(_onInputChanged);
    _buf.addListener(_onBufferChanged);
    _focus.addListener(_onFocusChanged);
    // 首帧之后补发一次统计（否则外部状态栏在用户敲第一个字之前一直显示 0）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _emitStats();
    });
  }

  @override
  void didUpdateWidget(EditView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.buffer != widget.buffer) {
      oldWidget.buffer.removeListener(_onBufferChanged);
      widget.buffer.addListener(_onBufferChanged);
      // 换了一份文档 = 新的一次编辑会话
      _edits = 0;
      // ★ 必须补报一次：新缓冲区的内容不会自己 notify，
      //   否则外部状态栏会一直停在**旧文档**的数字上（实测过：换文档后显示 0）
      _emitStats();
    }
    _input.inputFormatters = widget.inputFormatters;
  }

  @override
  void dispose() {
    _blink?.cancel();
    _autoScroll?.cancel();
    // ★ 顺序要紧：**先摘监听再 dispose**。
    //   `_input.dispose()` 内部会 `detach()` → `notifyListeners()` → 我们的监听器 `setState()`
    //   → 断言 `_lifecycleState != defunct` 炸掉（实测踩过；`mounted` 在 dispose 期间**仍是 true**，挡不住）。
    _alive = false;
    _input.removeListener(_onInputChanged);
    _buf.removeListener(_onBufferChanged);
    _focus.removeListener(_onFocusChanged);
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ---------------- 平台文本 → 缓冲区 ----------------

  /// 平台（含 IME 提交）的一段文本 → **一次**编辑写进缓冲区。
  ///
  /// ★ 这里**不碰输入设备**（不再有"回写镜像框"这一步）：
  ///   输入设备的内容由 [TextInputSurfaceController] 自己维持成"空的"。
  void _commitText(String rawText, {int autoWrapped = 0}) {
    if (rawText.isEmpty) return;
    // ★★ PC-1b（2026-10-18）：**行内数学里按 Enter ⇒ 在光标处断栅栏**（原子一个不动）。
    //   规则（用户拍板，按"层"分）：
    //     · 行内段里、且**不在任何结构内部**（一串平铺原子之间）⇒ 就地断：`$左$` + 断行 + `$右$`；
    //     · 结构内部（`\frac{}{}` 的分子里、上下标里）⇒ **不切**，交给 `insert_guard` 推到块后；
    //     · 行间块内部 ⇒ 同上（display 是块级单元，不切）。
    if (_splitInlineMathOnEnter(rawText)) return;
    // ★★ S4-c：**自动展开**（打字即渲染）先于插入守门人 —— 因为它是"改写用户刚打的那几个字符"，
    //   不是"往后插一段东西"。三条（`/`→分式、词触发、`>=`→`\ge`）都只对**单字符/终止符**生效，
    //   粘贴这种多字符载荷一律不参与（`planAutoExpand` 自己会拒）。
    //   ★ 有选区时不展开（用户已经表达了"替换这一段"的意思）。
    if (!_expanding && !_buf.hasSelection) {
      final AutoExpand? ex = planAutoExpand(
        doc: _buf.buf,
        caret: _buf.caret,
        typed: rawText,
        triggers: _triggers,
        slashFraction: widget.autoSlashFraction,
        wordTriggers: widget.autoWordTriggers,
        shorthand: widget.autoShorthand,
      );
      if (ex != null) {
        _applyAutoExpand(ex);
        return;
      }
    }
    // ★★ 自动分隔（2026-10-17 用户拍板）：**"命令词结不结束"不该由用户来判断**。
    //   TeX 的控制词只由字母组成，紧跟字母会被读成一个更长的命令名（`\sin` + `x` ⇒ `\sinx`）。
    //   ⇒ 插入字母、而光标正好停在控制词末尾时，**我们**先补一个空格（TeX 的规范分隔符）。
    final String text = _needsCommandSeparator(_buf.buf, _buf.caret, rawText)
        ? ' $rawText'
        : rawText;
    // ★★ 插入侧守门人（`render/insert_guard.dart`）：
    //   ① **块级换行不许落在数学段内部**（用户实测的路径：点进分式 → `→` 到行末
    //      （其实停在"闭合 `$` 之前那一格"）→ `Enter` → `$` 被配成单数 → **整行退化成源码**）。
    //   ② ★ 2026-10-17 加：**插在语法粘合处要挪位**（`\sum` 与它的上下限之间、裸参数里）——
    //      插入物会顶掉 `^`/`_` 的结合，版面当场变（用户实测"点 ∑ 就散架"）。
    //      ⇒ 与光标注入**同一条规则**（`caret_sites.neutralPoint`），保证"画在哪 = 插在哪"。
    //   ③④ ★★ 2026-10-17 S4-a 加：**多行载荷的行边界**（围栏行不可落 / 整行语法自成行）——
    //      用户报的"粘多行文本把 `$$` 打坏 ⇒ Parser Error"就在这两条上（见 `InsertPadding`）。
    //   ★ 只调整**落点**与**载荷边界的换行**，不吞内容：非换行的插入照样进公式
    // ★★ ⑤ 有选区 ⇒ **一次区间替换**（标准编辑器行为），而且必须是**一步撤销**。
    //   （原来是"先删选区、再插入" = 两次 `_mutate` ⇒ Ctrl+Z 要按两下 —— 记账里那条
    //    "撤销分组复核"就是查这个。）替换语义下也不走 `planInsert` 的粘合处挪位：
    //   用户已经把要替换的范围选中了，按选中的意图办。
    //   ★ 但**规则 ④（载荷边界）照样适用**：选区的两个端点也可能落在同一行中间。
    if (_buf.hasSelection) {
      final InsertPadding pad =
          padForRange(_buf.buf, _buf.selectionStart, _buf.selectionEnd, text);
      final String payload = pad.wrap(text);
      final int from = _buf.selectionStart;
      _mutate(() =>
          _buf.replace(_buf.selectionStart, _buf.selectionEnd, payload));
      _stampWrapped(autoWrapped,
          spans: _spansAround(from, from + payload.length));
      return;
    }
    final InsertPlan plan = planInsert(_buf.buf, _buf.caret, text);
    // ★★ S4-e-①（2026-10-18）**撤销分组**：只有"裸打一个字符、没有被守门人挪位/补换行"
    //   才算"打字型"编辑 ⇒ 500ms 内连打会合成**一步**撤销。粘贴/IME 整词/补行边界一律各算一步。
    final String paddedText = plan.padText(text);
    final bool typing = text.length == 1 &&
        !plan.padding.any &&
        plan.wrapBareArg == null &&
        plan.offset == _buf.caret &&
        paddedText == text;
    final bool coalesce = typing && _coalesceFor(_EditKind.typing);
    // ★ 诊断清单要"在哪"：裸参数被补花括号时落点会右移 2 格
    final int wrapShift = plan.wrapBareArg == null ? 0 : 2;
    final int from = plan.offset + wrapShift;
    final int to = from + plan.padText(text).length;
    _mutate(() {
      final ({int start, int end})? wrap = plan.wrapBareArg;
      if (wrap != null) {
        // 先把裸参数包上花括号（语义完全不变），落点就是"参数内容开头"
        final String arg = _buf.buf.substring(wrap.start, wrap.end);
        _buf.replace(wrap.start, wrap.end, '{$arg}');
      }
      if (_buf.caret != plan.offset) _buf.setCaret(plan.offset);
      _buf.replace(_buf.caret, _buf.caret, paddedText, coalesce: coalesce);
    });
    _stampWrapped(autoWrapped, spans: _spansAround(from, to));
  }

  /// 记下"这次自动包裹了几处（以及**在哪**）"并补一次上报。
  ///
  /// 为什么必须**之后**盖：`_mutate` 里会把上一次的计数清掉（它只描述最近一次插入）。
  /// ★ S4-b②：`spans` 是诊断清单的数据源 —— 「补了 3 处」不如「补的这 3 处点一下能跳过去」。
  void _stampWrapped(int n, {List<MathSpan> spans = const <MathSpan>[]}) {
    if (n <= 0) return;
    _autoWrapped = n;
    _autoWrappedSpans = spans;
    if (mounted) _emitStats();
  }

  /// 文档里与 `[from, to]` 有交集的数学段（给诊断清单用）
  List<MathSpan> _spansAround(int from, int to) {
    final List<MathSpan> all = scanMathSpans(_buf.buf);
    return <MathSpan>[
      for (final MathSpan s in all)
        if (s.end >= from - 1 && s.start <= to + 1) s,
    ];
  }

  /// ★★ S4-b：**面板插入**（符号 / 结构模板）—— 一次区间替换 = **一步撤销**。
  ///
  /// 三选一的语义（并入数学段 / 自动建壳 / 替换选区）在 `lang/symbol_insert.dart` 里，
  /// 这里只做"一次编辑"的落盘与光标定位（模板 ⇒ 第一个空槽）。
  void insertSymbolTex(String tex,
      {required bool template, bool display = false}) {
    _insertTexViaSymbolPath(tex, template: template, display: display);
  }

  /// 所有"插一段 tex"的入口共用的落盘逻辑（面板 / 快捷栏 / 快捷键 / 自动展开 / 上下标）。
  ///
  /// ★ 一次 `replace(0, len, …)` ⇒ **一步撤销**（`DocBuffer` 的撤销粒度是"每次 replace"，
  ///   所以"删掉触发的词 + 插入模板"必须合成**一次**写入，否则要按两下 `Ctrl+Z`）。
  void _insertTexViaSymbolPath(String tex,
      {required bool template, bool display = false}) {
    _breakUndoGroup(); // 模板/符号插入独占一步
    final SymbolInsertResult r = applySymbolInsert(
      doc: _buf.buf,
      caret: _buf.caret,
      selStart: _buf.selectionStart,
      selEnd: _buf.selectionEnd,
      tex: tex,
      template: template,
      display: display,
    );
    _mutate(() {
      _buf.replace(0, _buf.length, r.doc);
      _buf.setCaret(r.caret);
    });
    // ★ 建壳时的区间：光标所在的那个数学段（`mathRegionAt` 与插入侧同一条判据）
    final List<MathSpan> spans = <MathSpan>[];
    if (r.wrapped) {
      final MathRegion? mr = mathRegionAt(r.doc, r.caret);
      if (mr != null) {
        spans.add(MathSpan(
          start: mr.openStart,
          end: mr.closeEnd,
          tex: mr.tex,
          display: mr.isDisplay,
        ));
      }
    }
    _stampWrapped(r.wrapped ? 1 : 0, spans: spans);
  }

  /// ★★ S4-c：把一次**自动展开**落盘（`sqrt`+空格 / `/` / `>=` 都走这里）。
  ///
  /// 两步合成**一次**写入：① 删掉被吃掉的触发内容；② 在原位插入展开出来的 tex。
  void _applyAutoExpand(AutoExpand ex) {
    _breakUndoGroup(); // 自动展开独占一步
    final String trimmed = _buf.buf.replaceRange(ex.from, ex.caret, '');
    final SymbolInsertResult r = applySymbolInsert(
      doc: trimmed,
      caret: ex.from,
      selStart: ex.from,
      selEnd: ex.from,
      tex: ex.tex,
      template: ex.template,
    );
    _mutate(() {
      _buf.replace(0, _buf.length, r.doc);
      _buf.setCaret(r.caret);
    });
    _stampWrapped(r.wrapped ? 1 : 0, spans: _spansAround(ex.from, r.caret));
    // ★ 终止符：空格被吃掉（`''`），`Enter` 保留 ⇒ 再走一次普通提交（它是块级动作）
    final String tail = ex.keptTerminator;
    if (tail.isNotEmpty) {
      _expanding = true;
      try {
        _commitText(tail);
      } finally {
        _expanding = false;
      }
    }
  }

  /// ★★ S4-c：`Ctrl+↑` / `Ctrl+↓` —— 上标 / 下标（MathType Web 的真实约定）。
  ///
  /// 有基座 ⇒ `^{}`（作用于前面那个原子）；**没有基座**（公式开头 / 正文里）⇒ `{}^{}`
  /// —— 空的基座组 `{}` 在 TeX 里合法，直接写 `^{}` 会得到 `Parser Error: Expected group`。
  void insertScript({required bool sup}) {
    final String cmd = sup ? '^' : '_';
    final bool hasBase = _hasBaseAtom();
    _insertTexViaSymbolPath(hasBase ? '$cmd{}' : '{}$cmd{}', template: true);
  }

  /// 光标前（同一段数学里）有没有可以当基座的可见原子
  bool _hasBaseAtom() {
    final MathRegion? r = mathRegionAt(_buf.buf, _buf.caret);
    if (r == null) return false;
    final int rel = (_buf.caret - r.contentStart).clamp(0, r.tex.length);
    if (rel == 0) return false;
    for (final VisibleAtom a in lexVisibleAtoms(r.tex)) {
      if (a.kind == 'tail' || a.kind == 'slotpad') continue;
      if (a.end <= rel) return true;
    }
    return false;
  }

  /// ★★ S4-c：块类型快捷键（标题 / 列表 / 引用 / 代码块 / 分页符）。
  ///
  /// 只做"一次区间替换"（`lang/block_ops.dart` 已算出范围）⇒ **一步撤销**。
  void insertBlockOp(BlockOp op) {
    _breakUndoGroup(); // 块类型键独占一步
    final BlockOpResult? r = planBlockOp(_buf.buf, _buf.caret, op);
    if (r == null || r.isNoop) return;
    final String out = applyBlockOpTo(_buf.buf, r);
    final int caret = r.caret.clamp(0, out.length);
    _mutate(() {
      _buf.replace(0, _buf.length, out);
      _buf.setCaret(caret);
    });
  }

  /// ★★ S4-d③：把**每一页**抓成 PNG（图片集 / 图片式 PDF 的唯一入口）。
  ///
  /// 语义完全对齐原则 4「编辑时的分页预览 = 导出的 PDF 页 = 图片集的一张图」：
  /// 抓的就是屏幕上那棵 `PageSheet` 子树（外面套了 `RepaintBoundary`）。
  Future<List<Uint8List>> capturePages({double pixelRatio = 2.0}) async {
    final State<StatefulWidget>? st = _docKey.currentState;
    if (st is! DocViewState) return const <Uint8List>[];
    return st.capturePages(pixelRatio: pixelRatio);
  }

  /// 本机 UI 是否已经分好页（导出前判断"有没有东西可抓"，测试也用它）
  int get pageCount {
    final State<StatefulWidget>? st = _docKey.currentState;
    return st is DocViewState ? st.pageCount : 0;
  }

  /// ★★ S4-b②：诊断清单点一条 ⇒ **跳过去并高亮**那一段（不写缓冲区 ⇒ 不算一次编辑）。
  void jumpTo(int start, int end) {
    final int s = start.clamp(0, _buf.length);
    final int e = end.clamp(s, _buf.length);
    // ★ 顺序不能反：`setCaret` 会把选区**收起来**（anchor = caret）⇒ 必须"先落光标再拉选区"
    _buf.setCaret(e);
    _buf.setSelection(s, e);
    focusInput();
    if (mounted) setState(() {});
  }
  /// 插入 [insert] 之前需不需要先补一个**命令分隔符**（空格）？
  ///
  /// 条件：插入的是**字母**、光标前是字母、向前扫到 `\`（即光标停在控制词末尾）、
  /// 且光标后**不是字母**（否则是"插在命令名中间"，补分隔也救不了，不去动它）。
  bool _needsCommandSeparator(String s, int caret, String insert) {
    if (caret <= 0 || caret > s.length) return false;
    if (!_isLetterChar(insert[0])) return false;
    if (!_isLetterChar(s[caret - 1])) return false;
    if (caret < s.length && _isLetterChar(s[caret])) return false;
    var i = caret - 1;
    while (i >= 0 && _isLetterChar(s[i])) {
      i--;
    }
    return i >= 0 && s[i] == r'\';
  }

  static bool _isLetterChar(String ch) {
    final int c = ch.codeUnitAt(0);
    return (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
  }
  /// 跑一次可能改缓冲区的操作，**只在真的改动了**的时候记一次编辑。
  ///
  /// 两条通道（文本 / 命令键）都走这里，所以 `EditViewStats.edits` 的含义是
  /// "缓冲区实际被改了几次" —— 纯光标移动不算，落到边界上的删除也不算。
  ///
  /// ⚠️ `op()` 内部会 notify（→ 上报统计），那一次上报读到的还是**旧计数**，
  /// 所以这里改完必须**补一次上报**，否则统计永远慢一拍。
  /// **行内数学里按 Enter ⇒ 在光标处断栅栏**（PC-1b）。返回 true = 已处理。
  ///
  /// 判据见 [`_commitText`] 开头的注释：只有"行内段里且**不在结构内部**"才断。
  /// 断完光标落在**右段内容开头**（用户拍板乙案：与记事本一致，接着往下写）。
  bool _splitInlineMathOnEnter(String raw) {
    if (!raw.contains('\n')) return false;
    if (_buf.hasSelection) return false; // 有选区时让通用路径替换选区
    final MathRegion? r = mathRegionAt(_buf.buf, _buf.caret);
    if (r == null || r.isDisplay) return false;
    final int rel = _buf.caret - r.contentStart;
    if (rel <= 0 || rel >= r.tex.length) return false; // 段首/段尾：交给 insert_guard
    // **结构内部**（真有层级）⇒ 不切
    final CaretSiteTable t = buildCaretSites(r.tex);
    final SlotSpan? slot = innermostSlotAt(t, rel);
    if (slot != null && slot.path.isNotEmpty) return false;
    final String left = r.tex.substring(0, rel);
    final String right = r.tex.substring(rel);
    final String repl = '\$$left\$\n\n\$$right\$';
    _mutate(() => _buf.replace(r.openStart, r.closeEnd, repl));
    _buf.setCaret(r.openStart + 1 + left.length + 2 + 1);
    _pokeBlink();
    return true;
  }

  /// **右键改尺寸**（PC-5）：只对多行环境（矩阵/行列式）生效。
  ///
  /// 流程：定位数学段 ⇒ 认环境族与当前行列 ⇒ 弹面板（带当前值）⇒ `resizeEnvironment` 就地重写。
  /// 语义：既有内容左上对齐保留；缩小的内容进**一次撤销**（`_mutate` 记一步）。
  Future<void> _resizeEnvAt(int offset) async {
    if (!_alive) return;
    final MathRegion? r = mathRegionAt(_buf.buf, offset);
    if (r == null) return;
    final EnvStyle? style = envStyleOf(r.tex);
    if (style == null) return; // 不是多行环境 ⇒ 右键不做事
    final bool det = style == EnvStyle.det;
    final List<List<String>> cells = splitEnvCells(_envBody(r.tex, style));
    final int rows = cells.isEmpty ? 2 : cells.length;
    final int cols = cells.isEmpty ? 2 : cells.first.length;
    final EnvSizeChoice? choice = await showEnvSizeDialog(
      context,
      style: style,
      rows: rows < 1 ? 2 : rows,
      cols: cols < 1 ? 2 : cols,
      determinant: det,
      title: det ? '行列式' : '矩阵',
    );
    if (choice == null || !mounted) return;
    final String next = resizeEnvironment(r.tex,
        rows: choice.rows, cols: choice.cols, style: choice.style);
    if (next == r.tex) return;
    _mutate(() => _buf.replace(r.contentStart, r.contentEnd, next));
    _buf.setCaret(r.contentStart);
  }

  String _envBody(String tex, EnvStyle style) {
    final String name = switch (style) {
      EnvStyle.bracket => 'bmatrix',
      EnvStyle.paren => 'pmatrix',
      EnvStyle.det => 'vmatrix',
    };
    final String begin = '\\begin{$name}';
    final String end = '\\end{$name}';
    final int i = tex.indexOf(begin);
    final int j = tex.indexOf(end);
    if (i < 0 || j <= i) return '';
    return tex.substring(i + begin.length, j);
  }
  void _mutate(void Function() op) {    final String before = _buf.buf;
    op();
    if (identical(before, _buf.buf)) return;
    _edits++;
    // ★ 任何一次**普通**编辑都把"上次自动包裹"的记账清掉（它只描述**最近一次插入**）
    _autoWrapped = 0;
    _autoWrappedSpans = const <MathSpan>[];
    if (mounted) _emitStats();
  }

  // ---------------- 焦点 / 输入通道 ----------------

  void _onFocusChanged() {
    // ★ ⑤ 失焦 ⇒ **不画光标与选区**（数据保留）；同时停掉闪烁
    if (mounted) {
      setState(() => _blurred = !_focus.hasFocus);
    }
    if (_focus.hasFocus) {
      _startBlink();
      _input.ensureAttached();
    } else {
      _stopBlink();
      // ★ **提交点**（§七）：失焦时把光标所在的数学段 normalize 一遍。
      //   绝不在逐击键时回收 —— 否则用户删到一半，结构就被自动撤走了。
      _normalizeOnCommit();
      _input.detach();
    }
  }

  /// 光标移动/点击/打字后调用：把闪烁相位复位成亮，并重启计时。
  /// 否则点击可能正好落在"灭"的半周期里 ⇒ 光标最长 530 ms 不出现（用户实测时好时坏）。
  void _pokeBlink() {
    if (!mounted || !_focus.hasFocus) return;
    if (!_blinkOn) {
      setState(() => _blinkOn = true);
    }
    _startBlink();
  }
  void _startBlink() {
    _blink?.cancel();
    if (mounted && !_blinkOn) setState(() => _blinkOn = true);
    _blink = Timer.periodic(const Duration(milliseconds: 530), (Timer t) {
      if (!mounted || !_focus.hasFocus) {
        t.cancel();
        return;
      }
      setState(() => _blinkOn = !_blinkOn);
    });
  }

  void _stopBlink() {
    _blink?.cancel();
    _blink = null;
    if (mounted && !_blinkOn) setState(() => _blinkOn = true); // 重新聚焦时立刻可见
  }
  /// 提交点：**回收全空结构 + 去掉单原子参数的多余花括号**（设计稿 §七）。
  ///
  /// 只处理**光标所在的那一个数学段**（其余段落等它们各自成为提交点时再处理）——
  /// 这样既不用扫全文，也不会在用户没在看的地方悄悄改数据。
  void _normalizeOnCommit() {
    if (!_alive) return;
    final MathRegion? r = mathRegionAt(_buf.buf, _buf.caret);
    if (r == null) return;
    final NormalizeResult nr = normalizeTex(r.tex, _buf.caret - r.contentStart);
    if (!nr.changed) return;
    final int caret = r.contentStart + nr.caret;
    _mutate(() => _buf.replace(r.contentStart, r.contentEnd, nr.tex));
    _buf.setCaret(caret);
  }

  /// 让输入设备拿到焦点（必须由**用户手势**触发，浏览器才肯把 IME 接上）
  void focusInput() {
    if (!_focus.hasFocus) _focus.requestFocus();
    _input.ensureAttached(); // 手势内直接接上，不等焦点变更的异步链条
  }

  // ---------------- 命令键（键事件通道）----------------

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // ★ 组合中：所有命令键都**让给平台/输入法** —— 此时退格 = 取消一个拼音字母，
    //   方向键 = 在候选列表里选择，都不能被我们吃掉。
    if (_input.isComposing) return KeyEventResult.ignored;

    final HardwareKeyboard kb = HardwareKeyboard.instance;
    final bool shift = kb.isShiftPressed;
    final LogicalKeyboardKey k = event.logicalKey;

    // ★ `Ctrl/⌘ + Z` = 撤销、`Ctrl/⌘ + Shift + Z` / `Ctrl + Y` = 重做。
    //
    // 撤销栈在 `DocBuffer` 里**从 S0 就建好了**，只是之前一直没接键（所以"删了就回不来"）。
    // ★ 而 S3-4 的结构删除是"**一次区间替换**" —— 所以
    //   **一次结构删除 = 一步撤销**（`\frac{}{}` 9 个字符一次删、一次就撤回来）。
    //   这正是当初坚持「一次语义编辑只写一次缓冲区」的回报。
    // ★★ 2026-10-18（S4-c 接线时发现）：**带 Alt 的 Ctrl 组合不许在这里被吃掉**。
    //   `Ctrl+Alt+C` 本来是"代码块"，可原来 `k == keyC` 这一支不看 Alt，直接当"复制"吞掉
    //   ⇒ 外壳永远收不到那个键（这类 bug 的表现是"快捷键没反应"，很难看出来）。
    //   ⇒ 撤销/重做/剪贴板/全选只认**不带 Alt** 的组合；带 Alt 的一律交回上层。
    if ((kb.isControlPressed || kb.isMetaPressed) && !kb.isAltPressed) {
      if (k == LogicalKeyboardKey.keyZ) {
        _mutate(() {
          if (shift) {
            _buf.redo();
          } else {
            _buf.undo();
          }
        });
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyY) {
        _mutate(() => _buf.redo());
        return KeyEventResult.handled;
      }
      // ★★ ⑤ 剪贴板：**源切片就是剪贴板**（同权红利 —— 复制出去的是 `$x^2+1$` 这样的源码）
      if (k == LogicalKeyboardKey.keyA) {
        _buf.setSelection(0, _buf.length);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyC) {
        final String sel = _selectedText;
        if (sel.isNotEmpty) {
          Clipboard.setData(ClipboardData(text: sel));
        }
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyX) {
        final String sel = _selectedText;
        if (sel.isNotEmpty) {
          Clipboard.setData(ClipboardData(text: sel));
          _deleteRange(_buf.selectionStart, _buf.selectionEnd);
        }
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyV) {
        _pasteFromClipboard();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored; // 其余 Ctrl 组合键留给别处
    }
    if (kb.isAltPressed) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.backspace || k == LogicalKeyboardKey.delete) {
      // ★ ⑤ 有选区 ⇒ 删整个区间（一步撤销），不走结构删除
      if (_buf.hasSelection) {
        _deleteRange(_buf.selectionStart, _buf.selectionEnd);
        return KeyEventResult.handled;
      }
      _applyEdit(smartEditAt(_buf.buf, _buf.caret,
          forward: k == LogicalKeyboardKey.delete));
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft) {
      _buf.setCaret(prevCaretOffset(_buf.buf, _buf.caret), extend: shift);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      _buf.setCaret(nextCaretOffset(_buf.buf, _buf.caret), extend: shift);
      return KeyEventResult.handled;
    }
    // ★ `↑↓` = **竖直邻接**（分式分子↔分母、根号次数、大算符上下限）。
    //   没有竖直邻居时**不移动**（§三：不要乱跳）—— 所以 null 也算 handled。
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowDown) {
      final int? to =
          verticalStopAt(_buf.buf, _buf.caret, up: k == LogicalKeyboardKey.arrowUp);
      if (to != null) _buf.setCaret(to, extend: shift);
      return KeyEventResult.handled;
    }
    // ★ `Tab` = **走槽**（§十-①：下一个空槽 → 槽内容末尾 → 走出公式）。
    //   不在公式里时返回 null → 让给 Flutter 的焦点遍历。
    //   ★★ S4-c：但它**首先是词触发的终止符**（`sqrt` + `Tab` ⇒ 根号模板），
    //     这与"Tab 跳槽"不冲突：有词在光标前就展开，没有才走槽。
    if (k == LogicalKeyboardKey.tab) {
      if (!_expanding && !_buf.hasSelection) {
        final AutoExpand? ex = planAutoExpand(
          doc: _buf.buf,
          caret: _buf.caret,
          typed: '\t',
          triggers: _triggers,
          slashFraction: widget.autoSlashFraction,
          wordTriggers: widget.autoWordTriggers,
          shorthand: widget.autoShorthand,
        );
        if (ex != null) {
          _applyAutoExpand(ex);
          return KeyEventResult.handled;
        }
      }
      final int? to = tabStopAt(_buf.buf, _buf.caret, forward: !shift);
      if (to == null) return KeyEventResult.ignored;
      // ★★ PC-2（2026-10-18）：从**行间块**里走出去 ⇒ 落到**下一行行首**。
      //   旧行为只走到 `closeEnd`（= 紧跟收尾 `$$`），人一打字就接在块后面
      //   （用户实测："出去应该到下一个空的行，而不是接在这一块后面"）。
      int dest = to;
      final MathRegion? reg = mathRegionAt(_buf.buf, shift ? dest : _buf.caret);
      if (!shift && reg != null && reg.isDisplay && dest == reg.closeEnd) {
        if (dest < _buf.buf.length && _buf.buf[dest] == '\n') {
          dest += 1; // 下一行行首
        } else if (dest >= _buf.buf.length) {
          // 块在文末：先补一个换行，才有"下一行"可落
          _buf.setCaret(dest);
          _mutate(() => _buf.replace(dest, dest, '\n'));
          dest += 1;
        }
      }
      _buf.setCaret(dest);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.home) {
      _buf.setCaret(_lineStart(_buf.caret), extend: shift);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.end) {
      _buf.setCaret(_lineEnd(_buf.caret), extend: shift);
      return KeyEventResult.handled;
    }
    // ★★ 2026-10-18：**Enter 必须在键事件里处理**（改旧注释"走文本通道"的结论）。
    //   用户实测：行中/行末按 Enter ⇒ **文本不变、光标消失**。
    //   根因：Windows 上 Enter 到不了文本通道（不产生 `\n`、也不发 `TextInputAction`），
    //   而这里返回 `ignored` ⇒ 冒泡给祖先 ⇒ **Flutter 默认的焦点遍历把焦点移走** ⇒ 失焦 ⇒ 光标消失。
    //   ⇒ 自己插换行（与 formatter 同一条规则：`Enter` = 新块 ⇒ `\n\n`；`Shift+Enter` = 块内软换行）。
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _commitText(shift ? '  \n' : '\n\n');
      _pokeBlink();
      return KeyEventResult.handled;
    }
    // `Shift+Enter` = 块内硬换行（行尾两个空格，任何环节都不许 trim）——见上面那条。
    //
    // ★★ 2026-10-17 用户实测："按空格时**文本区自己往下滚**一小块"（标题栏不动 ⇒ 是 Flutter 侧滚动）。
    //   根因：这里对"可打印键"返回了 `ignored` ⇒ 键事件继续**冒泡给祖先 `Scrollable`**，
    //   而 Flutter 的默认快捷键里 **`空格` = 向下翻页**（`ScrollAction`）⇒ 文档区被翻走一块。
    //   ⇒ 其余可打印键（含空格）一律 `handled`：字符由**文本通道**插入（不靠键事件），
    //     我们只是**拦下冒泡**，不让它触发滚动/按钮激活等默认动作。
    // ★★ 2026-10-17 用户实测 + 探针坐实：**空格在 Flutter Web 上到不了文本通道**
    //   （按空格时 `updateEditingValue` 一次都没被调用，而 `a` / `啊` 都有），
    //   同时它会触发框架的默认动作（文本区自己往下翻一页）。
    //   ★ 也试过"把可打印键一律 handled"：那会让框架 `preventDefault`，
    //     **连字母都打不出来**（用户实测）⇒ 只能**只处理空格**：自己把它落进缓冲区。
    //   ★ 顺序：上面的 `_input.isComposing` 早退保证"拼音组合中的空格"仍归输入法。
    if (k == LogicalKeyboardKey.space) {
      // ★ 2026-10-17 用户拍板：**数学段里按空格 = "我要一个空隙"** ⇒ 插 `\ `（TeX 控制空格）；
      //   文本段里就是普通空格。这样"空格键"两边都**有可见效果**，
      //   也不会出现"存了裸空格、渲染时被丢掉"的诡异状态（裸空格在数学里只是词法分隔符）。
      final bool inMath = mathRegionAt(_buf.buf, _buf.caret) != null;
      _commitText(inMath ? r'\ ' : ' ');
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 把一次「结构感知删除」的处置落到缓冲区上。
  ///
  /// - `SmartEdit.remove` → 真删（**区间替换**，所以撤销栈里是"一次编辑"）
  /// - `SmartEdit.move` → **槽间跨越**：只跳不删（§4.2）
  /// - `SmartEdit.none` → 边界上没什么可删
  void _applyEdit(SmartEdit e) {
    if (e.isNone) return;
    if (e.deletes) {
      // ★★ 「删除要干脆」（2026-10-18 用户拍板）：**删空数学段 ⇒ 连定界符一起删**。
      //   口径：`删空留壳` **只针对结构里的子位点**（``\frac{□}{□}`` 的槽）；
      //   "把整个数学语言删掉"**没有留壳回打的义务**（用户原话）。
      final SmartEdit ed = reclaimEmptiedMath(_buf.buf, e);
      // ★ S4-e-① 撤销分组：只有"删掉一个字符、且没被扩成整段删"才算删除型编辑
      final bool single = (ed.to! - ed.from!) == 1 &&
          ed.from == e.from &&
          ed.to == e.to;
      final bool coalesce = single && _coalesceFor(_EditKind.deleting);
      _mutate(() => _buf.replace(ed.from!, ed.to!, '', coalesce: coalesce));
      // `replace` 会把光标放到删除点之后；扩成整段删之后要落回起点
      if (_buf.caret != ed.caret) _buf.setCaret(ed.caret);
      return;
    }
    _buf.setCaret(e.caret);
  }

  // ---------------- 撤销分组（S4-e-①）----------------

  /// 上一次"同类编辑"的时间：`null` = 没有可接续的分组
  ({_EditKind kind, DateTime at})? _lastEdit;

  /// 要不要把这次编辑并进上一步？**同类 + 500ms 内**才并。
  ///
  /// ★ 只有"打字 / 删一个字符"这两类会走到这里；粘贴、模板、自动展开、整段删一律不并
  ///   （它们是"一次语义操作"，本来就该独占一步）。
  bool _coalesceFor(_EditKind kind) {
    final DateTime now = DateTime.now();
    final bool merge = _lastEdit != null &&
        _lastEdit!.kind == kind &&
        now.difference(_lastEdit!.at) < const Duration(milliseconds: 500);
    _lastEdit = (kind: kind, at: now);
    return merge;
  }

  /// 显式打断分组（插入模板 / 粘贴 / 整段删之后调用）
  void _breakUndoGroup() => _lastEdit = null;

  /// 删一个区间（内部走「删空数学段 ⇒ 连定界符」那条判据）—— 选区删除 / 剪切共用。
  void _deleteRange(int from, int to) {
    _breakUndoGroup(); // 选区删除/剪切独占一步
    final SmartEdit ed =
        reclaimEmptiedMath(_buf.buf, SmartEdit.remove(from, to, from));
    _mutate(() => _buf.replace(ed.from!, ed.to!, ''));
    if (_buf.caret != ed.caret) _buf.setCaret(ed.caret);
  }

  int _lineStart(int offset) {
    final int i = _buf.buf.lastIndexOf('\n', offset > 0 ? offset - 1 : 0);
    return i < 0 ? 0 : i + 1;
  }

  int _lineEnd(int offset) {
    final int i = _buf.buf.indexOf('\n', offset);
    return i < 0 ? _buf.length : i;
  }

  // ---------------- 缓冲区 → 界面 ----------------

  void _onBufferChanged() {
    if (!_alive) return;
    _pokeBlink();
    _emitStats();
    if (mounted) setState(() {});
  }

  /// 输入面状态变化（组合中间态 / 连接）。
  ///
  /// ★ 组合串现在**参与排版**（见 [DocView.composingText]），所以这里必须重建 DocView，
  /// 不能像以前那样只重画一个叠画层。
  void _onInputChanged() {
    if (!_alive) return;
    _emitStats();
    if (mounted) setState(() {});
  }

  /// 光标是否落在**行间公式块**（`$$…$$`）里。
  ///
  /// 这类单元的排版文本**就是 LaTeX 源码**，把拼音接进去等于往源码里塞字符 → 渲染会崩。
  /// 所以那种情况退回**叠画**（见 [_composingOverlay]）。
  /// 判据与 `DocView._composingFor` 用的是同一份块模型，两边不会打架。
  bool get _caretInMathBlock {
    final BlockIndex idx = _buf.blocks;
    final int line = idx.lines.lineOf(_buf.caret);
    for (final Block b in idx.blocks) {
      if (line >= b.lineFrom && line < b.lineTo) return b.type == BlockType.math;
    }
    return false;
  }

  void _emitStats() {
    final EditViewStats s = EditViewStats(
      length: _buf.length,
      caret: _buf.caret,
      edits: _edits,
      composing: _input.isComposing,
      composingText: _input.composingText,
      autoWrapped: _autoWrapped,
      autoWrappedSpans: _autoWrappedSpans,
      pages: _pages,
    );
    if (_lastStats == s) return;
    _lastStats = s;
    widget.onStats?.call(s);
  }

  int get edits => _edits;
  bool get isComposing => _input.isComposing;
  String get composingText => _input.composingText;

  /// 输入面当前使用的定位矩形（**全局 / 屏幕坐标**）—— 测试与诊断用。
  /// 平台元素就被摆在这里，IME 候选框跟着它走。
  Rect get inputCaretRect => _input.caretRect;
  bool get inputAttached => _input.isAttached;

  // ---------------- 光标矩形 ----------------

  /// DocView 报的是**它自己的局部坐标**；输入面要的是**全局坐标**。
  void _onCaretRect(Rect? r) {
    if (r == _caretRect) return;
    setState(() => _caretRect = r);
    _pushCaretToInput();
  }

  // ---------------- ⑤ 拖选 / 双击 / 三击 ----------------

  /// 指针**按下**落在某个偏移上（DocView 命中后回吐）—— 决定这次是"点击"还是"连击"
  void _onPressHit(int offset) {
    _pressHit = true;
    _pokeBlink();
    final Offset? pos = _pressAt;
    final DateTime now = DateTime.now();
    final bool sameSpot =
        _lastClickPos != null && pos != null && (pos - _lastClickPos!).distance < 6;
    final bool quick = _lastClickAt != null &&
        now.difference(_lastClickAt!) < const Duration(milliseconds: 400);
    if (sameSpot && quick) {
      _clickCount = _clickCount >= 3 ? 1 : _clickCount + 1;
    } else {
      _clickCount = 1;
    }
    _lastClickAt = now;
    _lastClickPos = pos;

    if (HardwareKeyboard.instance.isShiftPressed) {
      // Shift+点击 = **扩展**（锚点不动）
      _buf.setSelection(_buf.anchor, offset);
      _dragAnchor = null;
      return;
    }
    if (_clickCount == 2) {
      final ({int start, int end}) r = wordRangeAt(_buf.buf, offset);
      _buf.setSelection(r.start, r.end);
      _dragAnchor = null;
      return;
    }
    if (_clickCount >= 3) {
      final ({int start, int end}) r = unitRangeAt(_buf.buf, offset);
      _buf.setSelection(r.start, r.end);
      _dragAnchor = null;
      return;
    }
    _buf.setCaret(offset);
    _dragAnchor = _buf.caret; // 拖选从这里开始拉
  }

  /// 指针移动：超过 3 px 才算拖（否则还是点击），落点与点击**同一套判据**
  void _onDragMove(Offset pos) {
    final int? anchor = _dragAnchor;
    if (anchor == null) return;
    final Offset? start = _pressAt;
    if (start == null) return;
    if (!_dragging && (pos - start).distance < 3) return;
    _dragging = true;
    _pointerAt = pos;
    _applyDragAt(pos, anchor);
    _maybeAutoScroll(pos, anchor);
  }

  /// 把拖选焦点落到 [pos]（与点击**同一套**判据：行间块走公式命中、文字走段落排版器）
  void _applyDragAt(Offset pos, int anchor) {
    final State<StatefulWidget>? st = _docKey.currentState;
    if (st is! DocViewState) return;
    final int? off = st.offsetAtGlobal(pos);
    if (off == null) return; // 页边/页间空隙 ⇒ 停住（不跳）
    _buf.setSelection(anchor, off);
  }

  /// ★ ⑤ 拖到视口**边缘**（或拖出视口）⇒ 持续滚动 = **跨页拖选**
  ///
  /// 为什么必须自己做：`SingleChildScrollView` 会**裁剪**子树，指针在裁剪区外
  /// **命中不到任何单元** ⇒ 不自己滚，就只能选到"当前可见的那一屏"。
  /// 滚动速度按"离边缘多近"线性加速；滚完立刻重算落点。
  void _maybeAutoScroll(Offset pos, int anchor) {
    final ScrollableState? sc = Scrollable.maybeOf(context);
    if (sc == null) return;
    // ★★ 用**视口**的盒子，不是本 widget 的盒子！
    //   本 widget（EditView）的高度是**整篇内容**（一千多像素），拿它当参照
    //   ⇒ 只有把指针拖到内容最底部才会触发 ⇒ 可视区里永远不滚（用户实测没反应）。
    final RenderObject? vpRo = sc.context.findRenderObject();
    if (vpRo is! RenderBox || !vpRo.hasSize) return;
    final RenderBox box = vpRo;
    final Offset local = box.globalToLocal(pos);
    // 感应带跟着字号走（不写死像素）：约 3 行字高
    final double edge = widget.settings.bodyFontSize * 3;
    final double over = local.dy < edge
        ? local.dy - edge
        : (local.dy > box.size.height - edge
            ? local.dy - (box.size.height - edge)
            : 0);
    if (over == 0) {
      _autoScroll?.cancel();
      _autoScroll = null;
      return;
    }
    if (_autoScroll != null) return; // 已经在滚
    _autoScroll = Timer.periodic(const Duration(milliseconds: 16), (Timer t) {
      final ScrollPosition sp = sc.position;
      final double step = (over.abs() / edge).clamp(0.15, 1.0) * 14.0;
      final double next = (sp.pixels + (over < 0 ? -step : step))
          .clamp(sp.minScrollExtent, sp.maxScrollExtent);
      if (next == sp.pixels) {
        t.cancel();
        _autoScroll = null;
        return;
      }
      sp.jumpTo(next);
      final Offset? at = _pointerAt;
      if (at != null && _dragAnchor != null) _applyDragAt(at, _dragAnchor!);
    });
  }

  void _endDrag(Offset? upAt) {
    // 用户实测：一行内拖选会少最后一个字符 —— 浏览器会合并/丢掉最后的 pointerMove，
    // 原来只在 move 里求落点 ⇒ 松手位置没被算进去。这里用松手坐标再求一次。
    if (_dragging && upAt != null && _dragAnchor != null) {
      _applyDragAt(upAt, _dragAnchor!);
    }
    // ★★ 用户实测："点了别的地方，选区没取消" —— 点在**页边 / 块间空隙**这类
    //   "没有任何单元命中"的地方时，`onTapOffset` 根本不会触发，选区就一直留着。
    //   标准编辑器行为：点页面里的空白也要**收起选区**。⇒ 没命中且没拖 ⇒ 折叠到当前光标。
    if (!_pressHit && !_dragging && _buf.hasSelection) {
      _buf.setCaret(_buf.caret);
    }
    _autoScroll?.cancel();
    _autoScroll = null;
    _pointerAt = null;
    _pressAt = null;
    _dragging = false;
    _dragAnchor = null;
    _pressHit = false;
  }
  /// 当前选中的源码（没有选区 ⇒ 空串）
  String get _selectedText => _buf.hasSelection
      ? _buf.buf.substring(_buf.selectionStart, _buf.selectionEnd)
      : '';

  /// 粘贴：读剪贴板 → **智能包裹** → 走**同一条**提交链（含选区替换与结构守门）
  ///
  /// ★ S4-a A2：**只在粘贴/导入这条入口跑智能包裹**，`updateEditingValue`（打字 / 中文 IME 提交）
  ///   **不跑** —— IME 一次提交一个词，跑包裹会把正常中文误伤成公式。
  Future<void> _pasteFromClipboard() async {
    final ClipboardData? d = await Clipboard.getData(Clipboard.kTextPlain);
    final String text = d?.text ?? '';
    if (text.isEmpty) return;
    pasteText(text);
  }

  /// ★★ 粘贴入口（`Ctrl+V` / 右键粘贴 / 未来的**导入**共用）——**智能包裹 ＋ 同一条提交链**。
  ///
  /// 顺序要紧：**先包裹、再算落点** —— 包裹出来的 `$…$` 仍是单行内联，
  /// 所以 `planInsert` 的 ③④⑤（围栏行不可落 / 整行语法补边界 / `$` 不许粘连）对**包裹后**的文本照样生效。
  ///
  /// ★ 一次语义动作 = **一次 `_mutate`** ⇒ 包裹 + 插入 + 补行边界合起来**一步撤销**。
  @visibleForTesting
  void pasteText(String raw) {
    final SmartWrapPlan plan = planSmartWrap(raw);
    final String text = plan.isEmpty ? raw : applySmartWrap(raw, plan);
    _commitText(text, autoWrapped: plan.runs.length);
  }

  void _pushCaretToInput() {
    final Rect? r = _caretRect;
    if (r == null) return;
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final Offset g = box.localToGlobal(r.topLeft);
    _input.setCaretRect(
      Rect.fromLTWH(g.dx, g.dy, r.width, r.height),
      fontSize: widget.settings.bodyFontSize,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: Stack(
        children: <Widget>[
          // ① 渲染层：**非定位子项** → 由它决定 Stack 的大小（这样放进滚动容器也不会没法定高）
          //    ★ 点击由 DocView 命中（文字走段落排版器、公式走 hit_map）后回吐绝对偏移
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (PointerDownEvent e) {
              focusInput();
              // ★★ 用户实测两次："点了别处，选区没取消"（点标题那次也没取消）。
              //   ⇒ 改成**按下就收起选区**（点哪儿都收起，包括页边/空隙/标题），
              //   之后如果真的是拖，拖到 >3px 时再按新锚点重新起选区。
              //   `Shift+点击` 例外（那是"扩展选区"的意思）。
              if (!HardwareKeyboard.instance.isShiftPressed && _buf.hasSelection) {
                _buf.setCaret(_buf.caret);
              }
              _pressAt = e.position;
              _dragging = false;
              _pressHit = false;
            },
            onPointerMove: (PointerMoveEvent e) => _onDragMove(e.position),
            onPointerUp: (PointerUpEvent e) => _endDrag(e.position),
            onPointerCancel: (_) => _endDrag(null),
            child: DocView(
              key: _docKey,
              buffer: widget.buffer,
              settings: widget.settings,
              onTapOffset: (int offset) {
                focusInput(); // 必须在用户手势里拿焦点，浏览器才肯把 IME 接上
                _onPressHit(offset);
              },
              // ★★ 2026-10-18（PC-5）：行间块上右键 ⇒ 改尺寸（只有多行环境接得住）
              onEnvResizeRequest: _resizeEnvAt,
              onCaretRect: _onCaretRect,
              // ★ 页数回传：状态栏「页号」与设置页的"后果可见"都读这一条
              onStats: (DocViewStats s) {
                if (s.pages == _pages) return;
                _pages = s.pages;
                if (_alive && mounted) _emitStats();
              },
              // ★ 组合串接进排版 → 后面的字被真的推开（只在文字类单元里；公式块见 _caretInMathBlock）
              composingText: _caretInMathBlock ? '' : _input.composingText,
              // ★ ⑤ 失焦不画光标与选区；聚焦时按 530 ms 闪烁
              hideCaretAndSelection: _blurred,
              caretVisible: !_blurred &&
                  !_buf.hasSelection &&
                  (_focus.hasFocus ? _blinkOn : true),
            ),
          ),

          // ② **仅当**组合串没法接进排版时（光标在行间公式块里，源码不能塞字符）才叠画
          _composingOverlay(),
        ],
      ),
    );
  }

  /// 叠画兜底：光标在**行间公式块**里时用（正常路径由 [DocView.composingText] 接进排版）。
  ///
  /// ★ 定位子项，不参与布局 → 绝不影响行宽与分页。
  Widget _composingOverlay() {
    if (!_caretInMathBlock) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: _input,
      builder: (BuildContext context, Widget? child) {
        final Rect? r = _caretRect;
        final String text = _input.composingText;
        if (r == null || text.isEmpty) return const SizedBox.shrink();
        return Positioned(
          left: r.left,
          top: r.top,
          child: IgnorePointer(
            child: Text(
              text,
              style: TextStyle(
                fontSize: widget.settings.bodyFontSize,
                height: 1.0,
                color: const Color(0xFF1F2937),
                decoration: TextDecoration.underline,
                decorationColor: const Color(kCaretColorValue),
                decorationThickness: 2,
              ),
            ),
          ),
        );
      },
    );
  }
}

