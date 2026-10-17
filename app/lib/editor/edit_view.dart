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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/block.dart';
import '../core/doc_buffer.dart';
import '../core/doc_settings.dart';
import '../render/caret_sites.dart' show kCaretColorValue;
import '../render/insert_guard.dart';
import '../render/math_nav.dart';
import '../render/normalize.dart';
import '../render/smart_delete.dart';
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
  });

  final int length;
  final int caret;

  /// 已写进缓冲区的编辑次数（组合中间态**不计**）
  final int edits;
  final bool composing;
  final String composingText;

  @override
  bool operator ==(Object other) =>
      other is EditViewStats &&
      other.length == length &&
      other.caret == caret &&
      other.edits == edits &&
      other.composing == composing &&
      other.composingText == composingText;

  @override
  int get hashCode => Object.hash(length, caret, edits, composing, composingText);

  @override
  String toString() => '$length 字符 · 光标 $caret · $edits 次编辑'
      '${composing ? ' · 组合中「$composingText」' : ''}';
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
    this.inputFormatters = const <TextInputFormatter>[
      NewBlockOnEnterFormatter(),
    ],
  });

  final DocBuffer buffer;
  final DocSettings settings;
  final void Function(EditViewStats stats)? onStats;
  final List<TextInputFormatter> inputFormatters;

  @override
  State<EditView> createState() => EditViewState();
}

class EditViewState extends State<EditView> {
  final FocusNode _focus = FocusNode(debugLabel: 'edit-input');
  late final TextInputSurfaceController _input =
      TextInputSurfaceController(focusNode: _focus);

  /// 光标所在行的盒子（**DocView 局部坐标**）—— 给输入面定位 + 画组合中间态
  Rect? _caretRect;

  int _edits = 0;
  EditViewStats? _lastStats;

  /// `false` = 已经开始 dispose（此时一律不再 setState —— `mounted` 在 dispose 期间仍为 true）
  bool _alive = true;

  DocBuffer get _buf => widget.buffer;

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
  void _commitText(String text) {
    if (text.isEmpty) return;
    // ★★ 插入侧守门人（`render/insert_guard.dart`）：
    //   ① **块级换行不许落在数学段内部**（用户实测的路径：点进分式 → `→` 到行末
    //      （其实停在"闭合 `$` 之前那一格"）→ `Enter` → `$` 被配成单数 → **整行退化成源码**）。
    //   ② ★ 2026-10-17 加：**插在语法粘合处要挪位**（`\sum` 与它的上下限之间、裸参数里）——
    //      插入物会顶掉 `^`/`_` 的结合，版面当场变（用户实测"点 ∑ 就散架"）。
    //      ⇒ 与光标注入**同一条规则**（`caret_sites.neutralPoint`），保证"画在哪 = 插在哪"。
    //   ★ 只调整**落点**，不吞内容：非换行的插入照样进公式
    final InsertPlan plan = planInsert(_buf.buf, _buf.caret, text);
    _mutate(() {
      final ({int start, int end})? wrap = plan.wrapBareArg;
      if (wrap != null) {
        // 先把裸参数包上花括号（语义完全不变），落点就是"参数内容开头"
        final String arg = _buf.buf.substring(wrap.start, wrap.end);
        _buf.replace(wrap.start, wrap.end, '{$arg}');
      }
      if (_buf.caret != plan.offset) _buf.setCaret(plan.offset);
      _buf.insertText(text);
    });
  }

  /// 跑一次可能改缓冲区的操作，**只在真的改动了**的时候记一次编辑。
  ///
  /// 两条通道（文本 / 命令键）都走这里，所以 `EditViewStats.edits` 的含义是
  /// "缓冲区实际被改了几次" —— 纯光标移动不算，落到边界上的删除也不算。
  ///
  /// ⚠️ `op()` 内部会 notify（→ 上报统计），那一次上报读到的还是**旧计数**，
  /// 所以这里改完必须**补一次上报**，否则统计永远慢一拍。
  void _mutate(void Function() op) {
    final String before = _buf.buf;
    op();
    if (identical(before, _buf.buf)) return;
    _edits++;
    if (mounted) _emitStats();
  }

  // ---------------- 焦点 / 输入通道 ----------------

  void _onFocusChanged() {
    if (_focus.hasFocus) {
      _input.ensureAttached();
    } else {
      // ★ **提交点**（§七）：失焦时把光标所在的数学段 normalize 一遍。
      //   绝不在逐击键时回收 —— 否则用户删到一半，结构就被自动撤走了。
      _normalizeOnCommit();
      _input.detach();
    }
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
    if (kb.isControlPressed || kb.isMetaPressed) {
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
      return KeyEventResult.ignored; // 其余 Ctrl 组合键留给后面（全选等）
    }
    if (kb.isAltPressed) return KeyEventResult.ignored;

    if (k == LogicalKeyboardKey.backspace) {
      _applyEdit(smartEditAt(_buf.buf, _buf.caret, forward: false));
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.delete) {
      _applyEdit(smartEditAt(_buf.buf, _buf.caret, forward: true));
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
    if (k == LogicalKeyboardKey.tab) {
      final int? to = tabStopAt(_buf.buf, _buf.caret, forward: !shift);
      if (to == null) return KeyEventResult.ignored;
      _buf.setCaret(to);
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
    // `Enter` **不在这里处理**：它走文本通道（textarea 自己插 `\n` → formatter 变成 `\n\n`）。
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
      _mutate(() => _buf.replace(e.from!, e.to!, ''));
      // `replace` 会把光标放到删除点之后；跨越删除后要落回起点（用户感知是"删掉那一个符号"）
      if (_buf.caret != e.caret) _buf.setCaret(e.caret);
    } else {
      _buf.setCaret(e.caret);
    }
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
            onPointerDown: (_) => focusInput(),
            child: DocView(
              buffer: widget.buffer,
              settings: widget.settings,
              onTapOffset: (int offset) {
                focusInput(); // 必须在用户手势里拿焦点，浏览器才肯把 IME 接上
                _buf.setCaret(offset);
              },
              onCaretRect: _onCaretRect,
              // ★ 组合串接进排版 → 后面的字被真的推开（只在文字类单元里；公式块见 _caretInMathBlock）
              composingText: _caretInMathBlock ? '' : _input.composingText,
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
