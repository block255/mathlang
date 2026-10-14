// 数语引擎 · 行内混排投影 Widget
//
// 这是 4.0 架构的渲染侧落地：**文字走 Flutter 的文字排版，`$...$` 走 Math.tex，
// 两者同行基线对齐、并一起参与折行**。
//
// 为什么用 `Text.rich` + `WidgetSpan`：
//   `WidgetSpan` 对行内排版器是一个**原子盒子** → 数学不会被从中间拆到两行，
//   而"自动换行 + 基线对齐"这两件事**免费**由 Flutter 的行内排版器完成（S2-2 实测验证）。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import 'caret_sites.dart';
import 'projection.dart';
/// 行内公式与正文的对齐方式。
/// S1 定稿：**默认 `baseline`**（排版上正确的语义），保留 `middle` 作为回退。
enum MathAlignMode {
  baseline,
  middle,
}

/// 把一段 L0 文本渲染成「文字 + 行内数学」混排的段落。
class InlineMathText extends StatefulWidget {
  const InlineMathText({
    super.key,
    required this.source,
    this.baseOffset = 0,
    this.caretOffset,
    this.textStyle,
    this.mathFontSize = 16,
    this.align = MathAlignMode.baseline,
    this.mathKeys,
    this.onMathTap,
    this.caretWidth = 1.5,
    this.caretColor,
  });

  /// L0 里的这一段（一行或一段；`$...$` 由它自己投影）
  final String source;

  /// `source[0]` 在文档 L0 里的**绝对偏移**
  final int baseOffset;

  /// 文档绝对光标偏移（`null` = 不画光标）
  final int? caretOffset;

  final TextStyle? textStyle;
  final double mathFontSize;
  final MathAlignMode align;

  /// 段起始绝对偏移 → GlobalKey（调用方持有；不传则内部自建）。
  /// 用于事后取 Math 的渲染根盒做命中测试与测量。
  final Map<int, GlobalKey>? mathKeys;

  /// 点中某个行内公式时回调（带该公式的渲染根盒 key）
  final void Function(ProjectionSegment seg, Offset globalPos, GlobalKey key)?
      onMathTap;

  final double caretWidth;
  final Color? caretColor;

  @override
  State<InlineMathText> createState() => _InlineMathTextState();
}

class _InlineMathTextState extends State<InlineMathText> {
  final Map<int, GlobalKey> _internalKeys = <int, GlobalKey>{};

  Map<int, GlobalKey> get _keys => widget.mathKeys ?? _internalKeys;

  @override
  Widget build(BuildContext context) {
    final segs = projectInline(widget.source);
    final children = <InlineSpan>[];

    // 清掉已经不存在的公式 key（源码变了之后旧 key 会残留）
    if (widget.mathKeys == null) {
      final live = <int>{
        for (final s in segs)
          if (s.isMath) widget.baseOffset + s.start,
      };
      _internalKeys.removeWhere((k, _) => !live.contains(k));
    }

    for (final s in segs) {
      if (s.isMath) {
        children.add(_mathSpan(s));
        continue;
      }
      children.addAll(_textSpansWithCaret(s));
    }

    return Text.rich(
      TextSpan(style: widget.textStyle, children: children),
    );
  }

  /// 文字段：把光标条切开插进去（光标在数学段里时走 `\cursor{}`，见 [_mathSpan]）
  List<InlineSpan> _textSpansWithCaret(ProjectionSegment s) {
    final absStart = widget.baseOffset + s.start;
    final absEnd = widget.baseOffset + s.end;
    final int? c = widget.caretOffset;
    if (c == null || c < absStart || c > absEnd) {
      return <InlineSpan>[TextSpan(text: s.text)];
    }
    final rel = c - absStart;
    return <InlineSpan>[
      TextSpan(text: s.text.substring(0, rel)),
      _caretBar(),
      TextSpan(text: s.text.substring(rel)),
    ];
  }

  InlineSpan _mathSpan(ProjectionSegment s) {
    final absStart = widget.baseOffset + s.start;
    final absEnd = widget.baseOffset + s.end;
    var tex = s.tex;

    // 光标在数学段里 → 注入引擎内置的 `\cursor{}`（默认已注册）。
    // ★ S3-1：注入点走**位点吸附**（caret_sites.dart），不再用旧的 snapCaretInTex ——
    //   后者只防"切开命令名"，会把光标留在 `}{` 这类语法夹缝里，注入后公式渲染是错的。
    final int? c = widget.caretOffset;
    if (c != null && c >= absStart && c <= absEnd) {
      tex = injectCursor(tex, c - absStart).tex;
    }

    final key = _keys.putIfAbsent(absStart, () => GlobalKey());
    final bool baseline = widget.align == MathAlignMode.baseline;
    final onTap = widget.onMathTap;

    return WidgetSpan(
      alignment: baseline
          ? PlaceholderAlignment.baseline
          : PlaceholderAlignment.middle,
      baseline: baseline ? TextBaseline.alphabetic : null,
      child: onTap == null
          ? _mathWidget(key, tex)
          : GestureDetector(
              onTapDown: (d) => onTap(s, d.globalPosition, key),
              child: MouseRegion(
                cursor: SystemMouseCursors.text,
                child: _mathWidget(key, tex),
              ),
            ),
    );
  }

  Widget _mathWidget(GlobalKey key, String tex) => Math.tex(
        key: key,
        tex,
        mathStyle: MathStyle.text,
        textStyle: TextStyle(fontSize: widget.mathFontSize),
        onErrorFallback: (e) => Text(
          '❌ ${e.messageWithType}',
          style: const TextStyle(color: Colors.red, fontSize: 13),
        ),
      );

  /// ★ 光标必须**零宽**。
  ///
  /// `WidgetSpan` 是参与行内排版的：1.5 px 的宽度足以在行尾临界处把词挤到下一行 →
  /// **行高变 → 分页跟着动 → 页边界随光标位置抖动**（用户会看到页码乱跳）。
  /// 这里用「0 宽占位 + `OverflowBox` 溢出绘制」：布局上不存在，视觉上照旧。
  /// 高度保持不变（仍参与行高计算），所以"渲染即测量"的结论不受影响。
  InlineSpan _caretBar() => WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: SizedBox(
          width: 0,
          height: widget.mathFontSize * 1.25,
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            minWidth: 0,
            maxWidth: widget.caretWidth * 4,
            child: Container(
              width: widget.caretWidth,
              height: widget.mathFontSize * 1.25,
              // ★ 必须与数学侧的光标同色（数学侧靠 `\textcolor` 注入，见 caret_sites.dart）
              color: widget.caretColor ?? const Color(kCaretColorValue),
            ),
          ),
        ),
      );
}
