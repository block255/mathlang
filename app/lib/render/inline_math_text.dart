// 数语引擎 · 行内混排投影 Widget
//
// 这是 4.0 架构的渲染侧落地：**文字走 Flutter 的文字排版，`$...$` 走 Math.tex，
// 两者同行基线对齐、并一起参与折行**。
//
// 为什么用 `Text.rich` + `WidgetSpan`：
//   `WidgetSpan` 对行内排版器是一个**原子盒子** → 数学不会被从中间拆到两行，
//   而"自动换行 + 基线对齐"这两件事**免费**由 Flutter 的行内排版器完成（S2-2 实测验证）。

import 'package:flutter/material.dart';

import 'caret_ownership.dart';
import 'caret_sites.dart';
import 'math_caret.dart';
import 'projection.dart';
import 'slot_marks.dart';
/// ★★ §6.5 **公式范围可见** —— ⚠️ **2026-10-15 晚撤掉了"整段淡色底"那一版**。
///
/// 撤掉的理由（用户一眼指出，比我自己想得准）：
/// **给整段公式刷一层底色，等于把"渲染提示"画成了"一个对象"** ——
/// `$\frac{a}{b}=\sqrt{2}$` 在用户眼里是**三个对象**（分式 / `=` / 根号），
/// 而一整块底色在说"这是**一整个**东西" ⇒ 那正是**公式块**的观感
/// （也正是本仓过闸表 §7.2 里那条"公式有专用底色 = 症状"）。
///
/// §6.5 的**动机仍然成立**（定界符不可见 ⇒ 里 / 外画在同一根像素上；W1 点不到末尾分式外面），
/// 但**手段**要选"像文本装饰 / 只在边界"的，不要选"像卡片 / 覆盖整段"的。
/// 现在**什么都不常显**；真要再做边界提示，按 §六 维护约定第 6 条先过一遍过闸表。
const Color kMathRangeColor = Color(0x261E88E5); // ⚠️ 已停用，保留常量备查

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
    this.composingText = '',
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

  /// ★ 组合中间态文本（拼音串）：**只进排版，不进缓冲区**。
  ///
  /// 为什么要接进排版而不是叠画（2026-10-14 用户实测提出）：叠画不会让后面的字让位，
  /// 拼音会**盖住**后文。接进排版后后面的字真的被推开、超出行宽还会折行 —— 与真人编辑器的观感一致。
  ///
  /// 插入点就是 [caretOffset]：光标条在前、拼音紧随其后（插入点不动，拼音向右展开）。
  final String composingText;

  final TextStyle? textStyle;
  final double mathFontSize;
  final MathAlignMode align;

  /// 段起始绝对偏移 → GlobalKey（调用方持有；不传则内部自建）。
  /// 用于事后取 Math 的渲染根盒做命中测试与测量。
  final Map<int, GlobalKey>? mathKeys;

  /// 点中某个行内公式时回调。
  ///
  /// ★ 第二个参数是**渲染这个公式时用的 tex**（含空槽占位与光标注入）——
  ///   点击定位必须用它去命中，否则"叶盒数 vs 原子数"对不上（详见 `injection_map.dart`）。
  final void Function(ProjectionSegment seg, String renderTex, Offset globalPos,
      GlobalKey key)? onMathTap;

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

    // ★★ 光标归属**只在这里问一次**，后续两个分支都拿这个结果用。
    //   唯一判据在 `caret_ownership.dart`（那里记着"四份判据漏掉一个偏移"的事故）。
    final int? rel = widget.caretOffset == null
        ? null
        : widget.caretOffset! - widget.baseOffset;
    final CaretPlacement? pl =
        rel == null ? null : caretPlacement(widget.source, rel);

    // 清掉已经不存在的公式 key（源码变了之后旧 key 会残留）
    if (widget.mathKeys == null) {
      final live = <int>{
        for (final s in segs)
          if (s.isMath) widget.baseOffset + s.start,
      };
      _internalKeys.removeWhere((k, _) => !live.contains(k));
    }

    for (var i = 0; i < segs.length; i++) {
      final ProjectionSegment s = segs[i];
      if (s.isMath) {
        children.add(_mathSpan(s, i, pl));
        // 光标在这个行内公式里 → 组合串接在公式**之后**（拼音不是数学源码，塞进 `$...$` 会破坏渲染）
        if (caretOwnedBy(pl, i, isMath: true) &&
            widget.composingText.isNotEmpty) {
          children.add(_composingSpan());
        }
        continue;
      }
      children.addAll(_textSpansWithCaret(s, i, pl));
    }

    return Text.rich(
      TextSpan(style: widget.textStyle, children: children),
    );
  }

  /// 文字段：把光标条 + 组合串切开插进去（光标在数学段里时走注入，见 [_mathSpan]）
  List<InlineSpan> _textSpansWithCaret(
    ProjectionSegment s,
    int i,
    CaretPlacement? pl,
  ) {
    if (!caretOwnedBy(pl, i, isMath: false)) {
      return <InlineSpan>[TextSpan(text: s.text)];
    }
    final int r = pl!.localRel.clamp(0, s.text.length);
    return <InlineSpan>[
      TextSpan(text: s.text.substring(0, r)),
      _caretBar(),
      // ★ 插入点在光标条之后：光标不动、拼音向右展开，后面的字被真的推开
      if (widget.composingText.isNotEmpty) _composingSpan(),
      TextSpan(text: s.text.substring(r)),
    ];
  }

  /// 组合中间态（未提交）的观感：正常字色 + **蓝色下划线** —— 与已提交的正文区分开
  InlineSpan _composingSpan() => TextSpan(
        text: widget.composingText,
        style: const TextStyle(
          color: Color(0xFF1F2937),
          decoration: TextDecoration.underline,
          decorationColor: Color(kCaretColorValue),
          decorationThickness: 2,
        ),
      );

  InlineSpan _mathSpan(ProjectionSegment s, int i, CaretPlacement? pl) {
    final absStart = widget.baseOffset + s.start;
    final bool caretHere = caretOwnedBy(pl, i, isMath: true);

    // ★★ 注入链的**唯一入口**（`slot_marks.renderMathTex`）：先注空槽占位，再按需注光标。
    //   ★ `caretHere == false` 时**也要注占位** —— 空槽必须一直看得见。
    //     2026-10-15 用户实测：粘贴 `$\frac{}{}$` 后光标停在**闭合 `$` 之后那一格**，
    //     原先"不在这段里就什么都不注入" → 空分数退化成 3.4 × 10.3 px 细线 → 看着像"消失了"。
    //   ★ 注入点仍走**位点吸附**（`caret_sites.dart` 的 `injectCursor`）——
    //     旧的 `snapCaretInTex` 只防"切开命令名"，会把光标留在 `}{` 这类语法夹缝里。
    final String tex =
        renderMathTex(s.tex, caretRel: caretHere ? pl!.localRel : -1);

    final key = _keys.putIfAbsent(absStart, () => GlobalKey());
    final bool baseline = widget.align == MathAlignMode.baseline;
    final onTap = widget.onMathTap;

    return WidgetSpan(
      alignment: baseline
          ? PlaceholderAlignment.baseline
          : PlaceholderAlignment.middle,
      baseline: baseline ? TextBaseline.alphabetic : null,
      child: onTap == null
          ? _mathWidget(key, tex, caretHere: caretHere)
          : GestureDetector(
              onTapDown: (d) => onTap(s, tex, d.globalPosition, key),
              child: MouseRegion(
                cursor: SystemMouseCursors.text,
                child: _mathWidget(key, tex, caretHere: caretHere),
              ),
            ),
    );
  }

  /// ⚠️ **这里曾经给整段刷一层淡色底（§6.5 旧版）—— 2026-10-15 晚撤掉了**：
  /// 那等于把"渲染提示"画成"一个对象"（用户指出 `$\frac{a}{b}=\sqrt{2}$` 是**三个对象**）。
  /// 详见文件头 `kMathRangeColor` 的注释与《编辑地基与手感》§六 维护约定第 6 条。
  ///
  /// ★★ 2026-10-15 晚：光标改成 **零尺寸锚点 + 自绘竖条**（`MathWithCaret`）——
  ///   以前注入的引擎 `\cursor{}` 会**参与排版**（把公式盒子撑高/撑宽 ⇒ accent "跳"）。
  Widget _mathWidget(GlobalKey key, String tex, {bool caretHere = false}) =>
      MathWithCaret(
        tex: tex,
        showCaret: caretHere,
        mathKey: key,
        fontSize: widget.mathFontSize,
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
