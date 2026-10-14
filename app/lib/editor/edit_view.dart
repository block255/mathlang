// 数语引擎 · 编辑面（S3-2）
//
// 架构（由 S3-1b 的实测确定，见 notes/design/位点与结构导航.md §11.6 / §11.7）：
//
//   ① 渲染层：DocView（我们自己的 A4 分页视图）—— 唯一给用户看的东西
//   ② 输入设备：一个**透明的镜像输入框**，内容是缓冲区的全文（含 `$...$` 与 LaTeX 源码）
//        · 它不吃指针（IgnorePointer）→ 点击落在渲染层上
//        · 它只负责把平台（含 IME）的输入交给我们 → `diffPlatformText` → 一次编辑进缓冲区
//        · ★ 组合中间态（打拼音时）**一个字都不写进缓冲区**（§11.7）
//   ③ 提交规则：挂在镜像框上的 `TextInputFormatter` 链（本文件先做「Enter → 新块」）
//
// ★ 为什么不让镜像框自己当编辑器：那样用户就会看见 `\frac{}{}` 的源码 —— 违背原则 2。
//   镜像框永远是**透明**的，用户看到的只有 ①。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/doc_buffer.dart';
import '../core/doc_settings.dart';
import 'doc_view.dart';
import 'platform_text_diff.dart';

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
/// 为什么放在 **formatter** 里而不是 `onKeyEvent`：formatter 运行在平台文本管道里、
/// 紧挨"输入设备"，不需要和 `EditableText` 抢按键（抢不过：它的 `Shortcuts` 更靠近焦点）；
/// 而且 `formatEditUpdate` 是**纯函数**，可以直接单测。
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
  final FocusNode _mirrorFocus = FocusNode(debugLabel: 'edit-mirror');
  final TextEditingController _mirror = TextEditingController();

  /// 正在"由镜像写进缓冲区"→ 不要再把缓冲区回写镜像（否则光标被重置）
  bool _fromMirror = false;

  bool _composing = false;
  String _composingText = '';
  int _edits = 0;
  EditViewStats? _lastStats;

  /// 光标所在行的盒子（DocView 局部坐标 = 本 Stack 局部坐标，因为 DocView 是 Stack 的非定位子项）
  Rect? _caretRect;

  /// 镜像框实际使用的矩形：光标未知时给兜底值（见 build 里的注释）
  Rect get _mirrorBox =>
      _caretRect == null
          ? const Rect.fromLTWH(0, 0, 240, 24)
          : Rect.fromLTWH(
              _caretRect!.left,
              _caretRect!.top,
              _caretRect!.width,
              _caretRect!.height * 1.3, // 略高一档：给输入法候选窗留点余地
            );

  DocBuffer get _buf => widget.buffer;

  @override
  void initState() {
    super.initState();
    _syncMirrorFromBuffer();
    _buf.addListener(_onBufferChanged);
    _mirror.addListener(_onMirrorChanged);
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
      _syncMirrorFromBuffer();
    }
  }

  @override
  void dispose() {
    _buf.removeListener(_onBufferChanged);
    _mirror.removeListener(_onMirrorChanged);
    _mirror.dispose();
    _mirrorFocus.dispose();
    super.dispose();
  }

  // ---------------- 缓冲区 ⇄ 镜像 ----------------

  void _syncMirrorFromBuffer() {
    final int caret = _buf.caret.clamp(0, _buf.length);
    _mirror.value = TextEditingValue(
      text: _buf.buf,
      selection: TextSelection.collapsed(offset: caret),
    );
  }

  void _onBufferChanged() {
    if (_fromMirror) return; // 镜像自己造成的改动：不要回写（回写会把平台光标重置）
    if (!_composing) _syncMirrorFromBuffer();
    _emitStats();
    if (mounted) setState(() {});
  }

  /// ★ 镜像 → 缓冲区。**两件事都要管**：
  ///   · **文本**变了 → 一次 `diffPlatformText` 落进缓冲区（组合中不落，见 §11.7）
  ///   · **只有选区 / 光标**变了（方向键、`Home`/`End`、`Shift+`选择）→ 只同步光标，**不产生编辑**
  ///
  /// ⚠️ 漏掉第二条的表现就是"**方向键按了没反应**"：方向键只改选区、不改文本，
  /// 若只在文本变化时才回写缓冲区，光标就永远不动。
  void _onMirrorChanged() {
    final TextEditingValue v = _mirror.value;
    final TextRange c = v.composing;
    final bool composing = c.isValid && !c.isCollapsed;
    final PlatformEdit? e =
        composing ? null : diffPlatformText(_buf.buf, v.text);

    _composing = composing;
    _composingText = composing ? v.text.substring(c.start, c.end) : '';

    _fromMirror = true;
    if (e != null) {
      _edits++;
      _buf.replace(e.start, e.end, e.inserted);
    }
    if (v.selection.isValid) {
      final int a = v.selection.baseOffset;
      final int b = v.selection.extentOffset;
      if (_buf.anchor != a || _buf.caret != b) {
        _buf.setSelection(a, b);
      }
    }
    _fromMirror = false;

    _emitStats();
    if (mounted) setState(() {});
  }

  void _emitStats() {
    final EditViewStats s = EditViewStats(
      length: _buf.length,
      caret: _buf.caret,
      edits: _edits,
      composing: _composing,
      composingText: _composingText,
    );
    if (_lastStats == s) return;
    _lastStats = s;
    widget.onStats?.call(s);
  }

  /// 让输入设备拿到焦点（必须由**用户手势**触发，浏览器才肯把 IME 接上）
  void focusInput() {
    if (!_mirrorFocus.hasFocus) _mirrorFocus.requestFocus();
  }

  int get edits => _edits;
  bool get isComposing => _composing;
  String get composingText => _composingText;

  @override
  Widget build(BuildContext context) {
    return Stack(
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
            // ★ 镜像框跟着光标走：位置/宽度/字号与文档那一行对齐，
            //   这样浏览器才会把中文候选框画在光标附近（见 DocView.onCaretRect 的注释）
            onCaretRect: (Rect? r) {
              if (r == _caretRect) return;
              setState(() => _caretRect = r);
            },
          ),
        ),

        // ② 输入设备：透明、不吃指针；**贴着光标那一行**
        //    还不知道光标在哪（首帧）时用一个兜底小矩形 —— 镜像框必须始终挂着，
        //    否则焦点与平台的文本输入管道会断。
        Positioned(
          left: _mirrorBox.left,
          top: _mirrorBox.top,
          width: _mirrorBox.width,
          height: _mirrorBox.height,
          child: IgnorePointer(
            child: Theme(
              data: Theme.of(context).copyWith(
                textSelectionTheme: const TextSelectionThemeData(
                  cursorColor: Colors.transparent,
                  selectionColor: Colors.transparent,
                  selectionHandleColor: Colors.transparent,
                ),
              ),
              child: TextField(
                controller: _mirror,
                focusNode: _mirrorFocus,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                inputFormatters: widget.inputFormatters,
                showCursor: false,
                // 键盘选区（`Shift+方向键`）要能用；鼠标选区被 IgnorePointer 挡在外面
                enableInteractiveSelection: true,
                // ★ 字号必须与正文一致：镜像框内部排版越接近文档，候选框位置越准
                style: TextStyle(
                  color: Colors.transparent,
                  fontSize: widget.settings.bodyFontSize,
                ),
                cursorColor: Colors.transparent,
                decoration: const InputDecoration.collapsed(hintText: ''),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
