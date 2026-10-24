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
import '../core/text_normalize.dart';
import '../lang/auto_expand.dart';
import '../lang/block_ops.dart';
import '../lang/break_split.dart';
import '../lang/clipboard_slice.dart';
import '../lang/math_spans.dart';
import '../lang/paste_context.dart';
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
    this.pasteNote,
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

  /// ★★ 2026-10-23（批 1）：粘贴时"我们替你动了手脚"的一句话说明（没有就是 `null`）。
  ///
  /// 只在**跨语境**那几种兜底里出现：剥定界符 / 整块替换 / 多行提升成块 / 混合文本推出去。
  /// 走状态栏（不进正文流 ⇒ 不触发重排分页），下一次编辑自动清掉。
  final String? pasteNote;

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
      other.pasteNote == pasteNote &&
      listEquals(other.autoWrappedSpans, autoWrappedSpans);

  @override
  int get hashCode => Object.hash(length, caret, edits, composing,
      composingText, autoWrapped, pages, pasteNote,
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

  /// ★★ 2026-10-21（L10）：**同一次物理按下可能上报多次**（行内公式上就有两条路径：
  /// 文本层粗落点 + 公式层精确落点）。这里用"这一按是否已处理"去重 ——
  /// 第一次上报走完整判定（[_commitPress]），后续上报**只升级光标落点**、不重新计数。
  ///
  /// ★ 事件顺序（实测）：`文本层上报 → 父层 Listener.onPointerDown → 公式层上报`
  ///   （`onTapDown` 在手势竞技场结算后才回调）⇒ **父层当不了"最后裁决点"**，
  ///   所以判据放在上报处，而不是父层。
  bool _tapHandledThisPress = false;

  /// 这一按**已经应用的落点优先级**（同一次按下里更高的来源可以覆盖，见 [TapSource.priority]）
  int _tapAppliedPriority = -1;

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

  /// ★★ 2026-10-20（T-A 实测 F2）：上次看到的"文档载入序号"（`DocBuffer.docEpoch`）。
  ///
  /// 为什么不能只看 `didUpdateWidget`：`newDocument()` / `openDocument()` 是**同一个 buffer
  /// 实例整篇换掉**（`loadDocument`）⇒ 那个钩子看不到 ⇒ 状态栏"0 字符 · 2 次编辑"。
  int _docEpoch = 0;

  /// ★ S4-a A2：最近一次**粘贴**里智能包裹了几处（0 = 没包裹 / 已被后续编辑清掉）
  int _autoWrapped = 0;


  /// ★ S4-b②：最近一次自动包裹补出来的数学段（诊断清单点一条就跳过去）
  List<MathSpan> _autoWrappedSpans = const <MathSpan>[];

  /// ★★ 2026-10-23（批 1）：粘贴时"**我们替你动了手脚**"的说明（走状态栏）。
  ///
  /// 为什么必须可见（原则 5）：剥定界符 / 整块替换 / 把多行提升成块 / 把混合文本推出去 ——
  /// 这些都不是用户显式要求的，静默做掉就成了"粘了但好像没反应"。
  String? _pasteNote;

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
    _docEpoch = _buf.docEpoch;
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
      _docEpoch = widget.buffer.docEpoch;
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

  /// ★★ 2026-10-18 晚（§11.46 真修）：**Enter 该插什么**。
  ///
  /// | 光标在哪 | 插什么 | 为什么 |
  /// |---|---|---|
  /// | **普通行**（本行有字） | `\n\n` | 新段（md 的段落边界） |
  /// | **空行**（本行一个字都没有） | `\n` | 用户要的是"**再加一行空行**"（真空段落），不是又开一段 |
  ///
  /// 这条是"空行是一等公民"的最后一块：`A` + Enter + Enter 现在得到
  /// `A\n\n\n`（= 段距 + **一整行**空行，看得见、能落光标、能再按 Enter 接着长），
  /// 而不是以前那种 `A\n\n\n\n`（多出一段"看不见的段距"）。
  /// ★ `Shift+Enter` 不走这里（它是"段内硬换行"）。
  String _enterPayload() {
    final String s = _buf.buf;
    final int c = _buf.caret.clamp(0, s.length);
    var ls = c;
    while (ls > 0 && s[ls - 1] != '\n') {
      ls--;
    }
    var le = c;
    while (le < s.length && s[le] != '\n') {
      le++;
    }
    final bool lineBlank = s.substring(ls, le).trim().isEmpty;
    return lineBlank ? '\n' : '\n\n';
  }

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
    // ★★★ 2026-10-24（批 18）：**汉字 / 全角标点 = 断点**（平权 · 推论 ④「围栏不是对象边界」）。
    //   用户口径（2026-10-24 拍板）：行内公式**顶层**打汉字 ⇒ 把这一段**拆成两半**
    //   （`$左$` + 汉字 + `$右$`，汉字落文本层）；结构槽里 / 行间块里 ⇒ 接受数学字体。
    //   纯函数与自检在 `lang/break_split.dart`（那边的注释写全了判据与理由）。
    if (_splitInlineMathOnBreakChar(rawText)) return;
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

  /// ★★ F18（2026-10-21，用户实测）：**导入**也算"最近一次自动包裹"。
  ///
  /// 为什么需要这个公开入口：导入走的是 `_buf.loadDocument(...)`（整篇替换），
  /// **不经过粘贴链** `_commitText` ⇒ 从来不会调到 [_stampWrapped] ⇒
  /// `EditViewStats.autoWrapped` 永远是 0 ⇒ 状态栏那条「自动包裹 N 处 · 查看清单 ›」
  /// **永远不出现** ⇒ 「查看清单 → 跳转并高亮」没有任何入口（T-A 只见过空态）。
  ///
  /// 调用时机：`loadDocument` 之后（`docEpoch` 变化会清零一次，所以必须**之后**盖）。
  void noteExternalWrap(int n, {List<MathSpan> spans = const <MathSpan>[]}) {
    if (n <= 0) return;
    _autoWrapped = n;
    _autoWrappedSpans = spans;
    if (mounted) _emitStats();
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
  ///
  /// ⏳ 2026-10-24（批 13）**记账**：这一条应当改成"**同一个容器里**"——
  /// 现在它看整段 tex，于是 `x^{|2}`（光标在脚本内容开头）会误判成"有基座"，
  /// 插进去得到 `x^{^{}2}`（没有基座的 `^{}`）⇒ 公式不完整。
  /// 但光改这里不够：`planInsert` 的 `neutralPoint` 会把落点**从基座后面挪进脚本内部**，
  /// 所以判据必须在**挪完之后**再问一次 —— 那是"插入落点"那一批的活，见台账 §14.7 批 13。
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

  /// ★★ 2026-10-19（U6）：**设置**当前行的块类型（顶栏「块类型」下拉用）。
  ///
  /// 与 [insertBlockOp] 的区别只有一条：**不切换**。选「标题 2」就当标题 2；
  /// 已经是标题 2 就什么都不做（`planLineMarkerSet` 返回 null）。
  /// 落盘仍是**一次区间替换** ⇒ 一步撤销。
  void setLineMarker(String desired) {
    _breakUndoGroup();
    final BlockOpResult? r = planLineMarkerSet(_buf.buf, _buf.caret, desired);
    if (r == null || r.isNoop) return;
    final String out = applyBlockOpTo(_buf.buf, r);
    final int caret = r.caret.clamp(0, out.length);
    _mutate(() {
      _buf.replace(0, _buf.length, out);
      _buf.setCaret(caret);
    });
  }

  /// ★★ 2026-10-20（接缝带口径）：**删除光标所在的"两页之间的缝"**
  /// （分页符行 + 上下连续空行 ⇒ 换成一个空行；文首/文末那一侧没有正文就抹干净）。
  void removePageBreakAtCaret() {
    _breakUndoGroup();
    final BlockOpResult? r = planRemoveSeam(_buf.buf, _buf.caret);
    if (r == null || r.isNoop) return;
    final String out = applyBlockOpTo(_buf.buf, r);
    final int caret = r.caret.clamp(0, out.length);
    _mutate(() {
      _buf.replace(0, _buf.length, out);
      _buf.setCaret(caret);
    });
  }

  /// 测试用：累计导出次数（转发给 DocView，证明"导出走过隐藏这一步"）
  @visibleForTesting
  int get captureHideCountForTest {
    final State<StatefulWidget>? st = _docKey.currentState;
    return st is DocViewState ? st.captureHideCountForTest : 0;
  }

  /// 测试用：导出期间是否处于"隐藏光标"状态（转发给 DocView）
  @visibleForTesting
  bool get hidingForCaptureForTest {
    final State<StatefulWidget>? st = _docKey.currentState;
    return st is DocViewState && st.hidingForCaptureForTest;
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

  /// **行内公式顶层打汉字 / 全角标点 ⇒ 拆段，字落文本层**（批 18，2026-10-24 用户拍板）。
  ///
  /// 规则与自检全在 `lang/break_split.dart`（纯函数、可全域断言）：这里只负责接线，
  /// 并且**一次 `replace` 写完** ⇒ 一步撤销（与"Enter 断栅栏"同一套）。
  ///
  /// 返回 true = 已经处理掉（调用方立刻 return，不再走自动展开/插入守门人）；
  /// 返回 false = 不归这条管（结构槽里 / 行间块 / 边界不拆的情形 / 混合载荷）。
  bool _splitInlineMathOnBreakChar(String raw) {
    if (!isAllBreakChars(raw)) return false;
    final BreakSplit? plan = planBreakSplit(
      doc: _buf.buf,
      caret: _buf.caret,
      selStart: _buf.hasSelection ? _buf.selectionStart : _buf.caret,
      selEnd: _buf.hasSelection ? _buf.selectionEnd : _buf.caret,
      payload: raw,
    );
    if (plan == null) return false;
    _mutate(() => _buf.replace(plan.from, plan.to, plan.text));
    _buf.setCaret(plan.caret);
    _pokeBlink();
    return true;
  }

  /// **右键改尺寸**（PC-5）：对多行环境（矩阵 / 行列式 / 分段函数 / 对齐推导）生效。
  ///
  /// 流程：定位数学段 ⇒ 认环境族与当前行列 ⇒ 弹面板（带当前值）⇒ `resizeEnvironment` 就地重写。
  /// 语义：既有内容左上对齐保留；缩小的内容进**一次撤销**（`_mutate` 记一步）。
  ///
  /// ★★ 2026-10-23（批 2 · E1）：`cases` / `aligned` 只有**行数**一个自由度 ⇒
  ///   面板只给一栏（标签「段数」/「行数」），不带括号选择、预览不接 `× 数字`。
  Future<void> _resizeEnvAt(int offset) async {
    if (!_alive) return;
    final MathRegion? r = mathRegionAt(_buf.buf, offset);
    if (r == null) return;
    final EnvStyle? style = envStyleOf(r.tex);
    if (style == null) return; // 不是多行环境 ⇒ 右键不做事
    final bool det = style == EnvStyle.det;
    final bool rowsOnly = style == EnvStyle.cases || style == EnvStyle.aligned;
    final List<List<String>> cells = splitEnvCells(_envBody(r.tex, style));
    final int rows = cells.isEmpty ? 2 : cells.length;
    final int cols = cells.isEmpty ? 2 : cells.first.length;
    // ★★ 2026-10-24（D3 续）：**列数的下限只有矩阵需要**（矩阵面板要显示「列数」一栏）。
    //   对 `cases` / `aligned`（只有行数一栏）来说，列数就是**文档里现在那个值** ——
    //   以前一刀切 `cols < 2 ? 2 : cols`，把**单列分段**（乙口径的 `\begin{cases}\\`）
    //   当成两列 ⇒ 一扩增段数，**每一行末尾就被塞进一个 `&`**
    //   ⇒ 用户实测："2 段确实没有第二列，但我扩增之后每一行就冒出来第二个位点了"。
    final int colsForDialog = rowsOnly ? (cols < 1 ? 1 : cols) : (cols < 2 ? 2 : cols);
    final EnvSizeChoice? choice = await showEnvSizeDialog(
      context,
      style: style,
      rows: rows < 1 ? 2 : rows,
      cols: colsForDialog,
      determinant: det,
      rowsOnly: rowsOnly,
      rowsLabel: style == EnvStyle.cases ? '段数' : '行数',
      unit: style == EnvStyle.cases ? '段' : '行',
      title: switch (style) {
        EnvStyle.det => '行列式',
        EnvStyle.cases => '分段函数',
        EnvStyle.aligned => '对齐推导',
        _ => '矩阵',
      },
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
      EnvStyle.cases => 'cases',
      EnvStyle.aligned => 'aligned',
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
    _pasteNote = null;
    if (mounted) _emitStats();
  }

  /// 记一条"粘贴时替你动过手脚"的说明（下一次编辑自动清掉）
  void _note(String? s) {
    _pasteNote = s;
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
        final ClipboardSlice sl = _selectionSlice;
        if (sl.text.isNotEmpty) {
          Clipboard.setData(ClipboardData(text: sl.text));
        }
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyX) {
        final ClipboardSlice sl = _selectionSlice;
        if (sl.text.isNotEmpty) {
          Clipboard.setData(ClipboardData(text: sl.text));
          // ★ 剪切删的是**切片对应的源区间**（不是原选区）—— 否则公式里会留下半截 `$`
          _deleteRange(sl.start, sl.end);
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
      _commitText(shift ? '  \n' : _enterPayload());
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
    // ★★★ 2026-10-24（用户实测"拖选删掉已有分段 ⇒ 显示公式不完整"）：
    //   选区跨进数学段却只删了一半 ⇒ `\begin{cases}` 留一半、`\end{cases}` 被删掉
    //   ⇒ 引擎解析失败 ⇒ 页面上红字 `[公式不完整]`。
    //   ⇒ 删之前先把区间**扩到自洽边界**（与复制/剪切同一套规则 `clipboardSlice`）：
    //     · 端点落在某个 `$…$` / `$$…$$` **内部** ⇒ 扩到那一段的边界；
    //     · 整段都在公式内部 ⇒ 不动（照旧删内容）。
    final ClipboardSlice sl = clipboardSlice(_buf.buf, from, to);
    final SmartEdit ed = reclaimEmptiedMath(
        _buf.buf, SmartEdit.remove(sl.start, sl.end, sl.start));
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
    // ★★ 2026-10-20（F2）：**同一实例整篇换掉**（新建 / 打开）也算"新的一次编辑会话"。
    if (_buf.docEpoch != _docEpoch) {
      _docEpoch = _buf.docEpoch;
      _edits = 0;
      _autoWrapped = 0;
      _autoWrappedSpans = const <MathSpan>[];
    }
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
      pasteNote: _pasteNote,
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

  /// 指针**按下**落在某个偏移上（DocView 命中后回吐）。
  ///
  /// ★★ 2026-10-21（L10）：行内公式上**一次按下会报两次**（文本层粗落点 / 公式层精确落点），
  /// 而公式层那条**晚于**父层 `Listener` 才到（`onTapDown` 要等手势竞技场结算）。
  /// ⇒ 第一次上报做**连击计数**（每次物理按下只数一次），落点由 [_applyClick] 应用；
  /// 后续上报**只重放一次落点应用**（用更精确的偏移），不重新计数。
  void _onTapReport(int offset, Offset pos, TapSource source) {
    focusInput(); // 必须在用户手势里拿焦点，浏览器才肯把 IME 接上

    if (_tapHandledThisPress) {
      // 同一次按下的后续上报：**只有优先级更高**的才覆盖落点（计数一律不动）
      //   band（页边物理边界）＞ math（字形命中）＞ text（单元宿主的粗落点）
      if (source.priority > _tapAppliedPriority) {
        _tapAppliedPriority = source.priority;
        _applyClick(offset);
      }
      return;
    }
    _tapHandledThisPress = true;
    _tapAppliedPriority = source.priority;
    _pressHit = true;
    _pokeBlink();
    // ★★ 2026-10-19（L4 收尾）：连击的判据必须用**这一按**的位置。
    //   以前读 `_pressAt` —— 那是父层 `Listener.onPointerDown` 写的，而父层在**子层之后**才跑
    //   ⇒ 此处拿到的是**上一按**的位置 ⇒ 实测"双击永远只算单击、三击被算成双击"。
    final DateTime now = DateTime.now();
    final bool sameSpot =
        _lastClickPos != null && (pos - _lastClickPos!).distance < 6;
    final bool quick = _lastClickAt != null &&
        now.difference(_lastClickAt!) < const Duration(milliseconds: 400);
    final bool combo = sameSpot && quick;
    _clickCount = combo ? (_clickCount >= 3 ? 1 : _clickCount + 1) : 1;
    _lastClickAt = now;
    _lastClickPos = pos;

    // ★ 先决定"旧选区收不收"：连击要选单位 / Shift 扩展时**让开**
    final bool shift = HardwareKeyboard.instance.isShiftPressed;
    final bool willSelectUnit = !shift && _clickCount >= 2;
    if (!shift && !willSelectUnit && _buf.hasSelection) {
      _buf.setCaret(_buf.caret);
    }
    _applyClick(offset);
  }

  /// 把"这一击"落到文档上（**同一次按下可能被调用多次**：公式层会拿更精确的偏移重放一次）。
  void _applyClick(int offset) {
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
    // ★ L10：按下期间的去重标记到此结束（下一次按下重新计）
    _tapHandledThisPress = false;
    _tapAppliedPriority = -1;
  }
  /// 当前选区的**自洽片段**（没有选区 ⇒ 空）。
  ///
  /// ★★ 2026-10-23（批 1 · A1/A2）：原来直接 `substring(selStart, selEnd)` ——
  ///   复制行内公式里的一个分式，得到的是 `\frac{…}{…}$`（**缺开头 `$`、多结尾 `$`**，用户实测）。
  ///   现在走 `clipboardSlice`：两端都在同一个公式内 ⇒ 替用户**补一对 `$…$`**；
  ///   只有一端在公式内 ⇒ 把那一端扩到段边界。判据与「粘贴侧」共用同一套语境表
  ///   （`notes\design\剪贴板与跨语境粘贴.md`）。
  ClipboardSlice get _selectionSlice => _buf.hasSelection
      ? clipboardSlice(_buf.buf, _buf.selectionStart, _buf.selectionEnd)
      : const ClipboardSlice(start: 0, end: 0, text: '');

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
  ///
  /// ★★ 2026-10-23（批 1 · 跨语境粘贴）：先问"**粘到哪**"（`paste_context.decidePaste`）：
  ///   · 目标在**文字流**里 ⇒ 老路（智能包裹）；
  ///   · 目标在**数学里**（行内 / 行间 / 任何结构槽）⇒ 剥掉外层定界符、只插 tex，**不再跑包裹**
  ///     （否则会在 `$…$` 里再包出一层 `$…$`）；
  ///   · 多行进**行间块** ⇒ 整块内容替换；多行进**行内公式** ⇒ 提升成新块放到本行之后。
  @visibleForTesting
  void pasteText(String rawText) {
    // ★★ 2026-10-23（批 2）：粘贴载荷先把 CRLF 归一成 LF —— 否则从记事本/AI 网页粘进来的
    //   每行都带 `\r`，整行语法（`$$` / `---` / 标题 / 列表 / 分页符）会静默失效。
    final String raw = normalizeNewlines(rawText);
    final int selStart = _buf.hasSelection ? _buf.selectionStart : _buf.caret;
    final int selEnd = _buf.hasSelection ? _buf.selectionEnd : _buf.caret;
    final PasteDecision d = decidePaste(
      doc: _buf.buf,
      caret: _buf.caret,
      selStart: selStart,
      selEnd: selEnd,
      payload: raw,
    );
    switch (d.apply) {
      case PasteApply.asIs:
        final SmartWrapPlan plan = planSmartWrap(raw);
        final String text = plan.isEmpty ? raw : applySmartWrap(raw, plan);
        _commitText(text, autoWrapped: plan.runs.length);
        return;
      case PasteApply.mathTex:
        // 已经是 tex（或用户就是想插文字）⇒ 直接走插入守门人，不包裹
        _commitText(d.payload);
        return;
      case PasteApply.pushOut:
        _breakUndoGroup();
        _buf.setCaret(d.at!.clamp(0, _buf.length));
        _commitText(d.payload);
        _note(d.note);
        return;
      case PasteApply.replaceBlock:
        _breakUndoGroup();
        _mutate(() {
          _buf.replace(d.replaceFrom!, d.replaceTo!, d.payload);
          _buf.setCaret(d.at!.clamp(0, _buf.length));
        });
        _note(d.note);
        return;
      case PasteApply.promoteBlock:
        _breakUndoGroup();
        // 围栏必须独占一行 ⇒ 前后各补行边界；插在**本行之后**，不劈开原公式
        final String block = '\n\n\$\$\n${d.payload}\n\$\$';
        final int at = d.at!.clamp(0, _buf.length);
        _mutate(() {
          _buf.replace(at, at, block);
          _buf.setCaret((at + block.length).clamp(0, _buf.length));
        });
        _note(d.note);
        return;
    }
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
              _pressAt = e.position;
              _dragging = false;
              // ★★ 2026-10-21（L10）：命中单元的落点（含"收起旧选区"）由 [_commitPress] 负责；
              //   这里只管**没命中任何单元**的情形（页边 / 块间空隙）⇒ 老行为：点空白也收起选区。
              //   ★ 判据用 `_pressHit`（子层上报时置 true，`_endDrag` 复位）。
              if (!_pressHit &&
                  !HardwareKeyboard.instance.isShiftPressed &&
                  _buf.hasSelection) {
                _buf.setCaret(_buf.caret);
              }
            },
            onPointerMove: (PointerMoveEvent e) => _onDragMove(e.position),
            onPointerUp: (PointerUpEvent e) => _endDrag(e.position),
            onPointerCancel: (_) => _endDrag(null),
            child: DocView(
              key: _docKey,
              buffer: widget.buffer,
              settings: widget.settings,
              onTapOffset: _onTapReport,
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

