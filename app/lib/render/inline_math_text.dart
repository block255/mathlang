// 数语引擎 · 行内混排投影 Widget
//
// 这是 4.0 架构的渲染侧落地：**文字走 Flutter 的文字排版，`$...$` 走 Math.tex，
// 两者同行基线对齐、并一起参与折行**。
//
// 为什么用 `Text.rich` + `WidgetSpan`：
//   `WidgetSpan` 对行内排版器是一个**原子盒子** → 数学不会被从中间拆到两行，
//   而"自动换行 + 基线对齐"这两件事**免费**由 Flutter 的行内排版器完成（S2-2 实测验证）。

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../lang/env_table.dart';
import 'caret_ownership.dart';
import 'caret_sites.dart';
import 'empty_math_mark.dart';
import 'math_caret.dart';
import 'math_nav.dart';
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
    this.slotCaretOffset,
    this.composingText = '',
    this.textStyle,
    this.mathFontSize = 16,
    this.align = MathAlignMode.baseline,
    this.mathKeys,
    this.onMathTap,
    this.onMathLayout,
    this.onMathRightClick,
    this.caretWidth = 1.5,
    this.caretColor,
    this.selStart,
    this.selEnd,
    this.showEditingAids = true,
  });

  /// **选区**（⑤ 高亮）：`source` 内的区间 `[selStart, selEnd)`；`null` = 这段没被选中。
  ///
  /// ★ 用 `source` 的下标（不是绝对偏移）—— 调用方已经减过 `baseOffset`。
  final int? selStart;
  final int? selEnd;

  /// ★★ 2026-10-20（T-C 实测 F16）：**要不要画编辑辅助**（空槽虚线框 / 光标竖条 / 选区底块）。
  ///
  /// 导出 PDF / 图片集时传 `false` —— 那些框是**编辑态的可视化**，
  /// 实测它会**被画进导出的纸面里**（一个空的行间公式 ⇒ 纸面上出现一个虚线小方框）。
  final bool showEditingAids;

  /// L0 里的这一段（一行或一段；`$...$` 由它自己投影）
  final String source;

  /// `source[0]` 在文档 L0 里的**绝对偏移**
  final int baseOffset;

  /// 文档绝对光标偏移（`null` = 不画光标）
  final int? caretOffset;

  /// **光标逻辑位置**（用来决定"注不注空槽垫子"）。
  ///
  /// ★★ 与 [caretOffset] 的唯一区别：它**不受光标闪烁相位、不受选区影响**。
  ///   为什么必须分开：空槽垫子是"注进 TeX 的字形"，**会改版面宽度**；
  ///   若它跟着闪烁灭/亮走，整段每秒重排两次 ⇒ 用户看到的"虚线框若隐若现 + 排版闪动"
  ///   （2026-10-18 用户实测，根因就是 `_caretAbsFor` 在闪烁灭时返回 null）。
  ///   ⇒ 位置归位置（本字段），可见性归可见性（[caretOffset]）。
  final int? slotCaretOffset;

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

  /// ★★★ 2026-11-01（反馈 19 续 · 拖选）：每次布局时把「这一段的 key + **渲染 tex**」登记出去。
  ///   拖选走的是页面级几何（DocView.offsetAtGlobal），它拿不到段内坐标；
  ///   有了这张登记表，拖选就能与点击**共用一个命中函数**（hitTestMathTex）。
  final void Function(int absStart, GlobalKey key, String renderTex)? onMathLayout;
  /// ★★ 2026-10-18 晚（用户实测「行内矩阵右键一点反应没有」）：
  /// 行内公式上**右键**时回调，参数是**这段公式在文档里的绝对起点**
  /// （`_resizeEnvAt` 只要知道"落在哪一段里"就能认出环境族与当前行列）。
  final void Function(int absOffset)? onMathRightClick;

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

    // ★★ 注入垫子用的**逻辑**位置（不看闪烁、不看选区）——见 [slotCaretOffset] 的说明
    final int? slotRel = widget.slotCaretOffset == null
        ? null
        : widget.slotCaretOffset! - widget.baseOffset;
    final CaretPlacement? slotPl =
        slotRel == null ? null : caretPlacement(widget.source, slotRel);

    // 清掉已经不存在的公式 key（源码变了之后旧 key 会残留）
    if (widget.mathKeys == null) {
      final live = <int>{
        for (final s in segs)
          if (s.isMath) widget.baseOffset + s.start,
      };
      _internalKeys.removeWhere((k, _) => !live.contains(k));
    }

    // ★★ 2026-10-24（批 28）：**空的一段也要看得见光标**。
    //
    // 实测（用户作业文档结尾 `---\n\n### \n\n`）：空标题块（`### ` 后面没字）的渲染文本是 `''`
    // ⇒ 下面那条 `for (segs)` 一个 span 都不产出 ⇒ 光标落在这一行时**一根竖条都不画**：
    //   探针逐偏移扫出来 30–34 全是死区（用户读成"光标消失"、那一段空隙读成"多了一个空行"）。
    //
    // 口径：空文本只有一个位置 ⇒ 光标只要在本单元里就画在行首。
    //   ★ 用**普通空格**当"占位字符"（必须有一个 span，否则这一行没有行高）：
    //     实测空的 `Text.rich` 比"有一个字"的行**矮 7px**（空 `### ` 25.4 vs 有字 32.4）
    //     ⇒ 空标题里打出第一个字时整块会突然长高、页面跳一下。空格正好把行高补回 32.4。
    //   ★ 不用 `\u200B`（零宽空格）：版面一样，但它在某些字体里缺字形 ⇒ 可能渲染成豆腐块。
    // ★★★ 2026-11-10（反馈 ④）：**光标条退出字符流**。
    //
    // 旧做法：把竖条当 `WidgetSpan` 插在光标那一格（0 宽占位，见已删的 `_caretBar`）。
    //   当时的判断是"0 宽 = 不参与排版"，实测证明**只对了一半**：
    //   WidgetSpan 会往段落字符流里塞一个 **U+FFFC**，而它是行内断行类别 ID ——
    //   **那个位置本身就是一个断行机会**，与宽度、高度都无关。
    //
    // 实测（真字体 Segoe UI、正文栏宽 657.7、字号 22）：
    //   光标落在 `different` 的 `d` 与 `i` 之间 ⇒ 同一段从 **2 行变 3 行**；
    //   光标一亮一灭，整段就在 2/3 行之间来回 ⇒ 用户看到"排版闪烁、`d` 一会儿在上行末"。
    //
    // ⇒ 竖条改成**段落之外的兄弟**（[`_TextCaretBox`]）：位置由段落自己的
    //   `RenderParagraph.getOffsetForCaret` 给出，**排版只算一次**；
    //   闪烁 / 选区 / 导出只影响"画不画它"，不影响任何排版输入。
    if (widget.source.isEmpty) {
      final bool here = rel != null && rel <= 0;
      return _wrapWithCaret(
        Text.rich(TextSpan(style: widget.textStyle, children: <InlineSpan>[
          const TextSpan(text: ' '),
        ])),
        caretPara: here ? 0 : null,
      );
    }

    // 段落字符流里的下标（数学段在段落里只占一格 U+FFFC）—— 用来给竖条定位
    int paraLen = 0;
    int? caretPara;
    for (var i = 0; i < segs.length; i++) {
      final ProjectionSegment s = segs[i];
      if (s.isMath) {
        children.add(_mathSpan(s, i, pl, slotPl));
        // 光标在这个行内公式里 → 组合串接在公式**之后**（拼音不是数学源码，塞进 `$...$` 会破坏渲染）
        // ★★★ 2026-11-01（反馈 1 · R9）：组合串**不许跟着光标闪烁灭**。
        //   闪烁只影响"画不画光标条"，不影响"组合串在哪儿"——
        //   与 2026-10-18 给空槽垫子开的药方同一条（`slotCaretOffset` 不跟闪烁）。
        //   实测病灶：`pl` 在闪烁灭时为 null ⇒ 这一段整条分支塌掉 ⇒ 拼音每 530 ms 消失一次。
        if (widget.composingText.isNotEmpty &&
            (caretOwnedBy(pl, i, isMath: true) ||
                caretOwnedBy(slotPl, i, isMath: true))) {
          children.add(_composingSpan());
        }
        paraLen += 1;
        continue;
      }
      // ★ 光标在本段文字里 ⇒ 记下它在**段落字符流**里的下标（竖条按这个位置画）
      if (caretOwnedBy(pl, i, isMath: false)) {
        caretPara = paraLen + pl!.localRel.clamp(0, s.text.length);
      }
      if (s.isEmphasis) {
        children.addAll(_emphasisSpansWithCaret(s, i, pl));
      } else {
        children.addAll(_textSpansWithCaret(s, i, pl, slotPl));
      }
      paraLen += s.text.length;
    }

    return _wrapWithCaret(
      Text.rich(TextSpan(style: widget.textStyle, children: children)),
      caretPara: caretPara,
    );
  }

  /// 把"正文 + 竖条"包成一层：**竖条是段落的兄弟，不在字符流里**（见 [build] 里的长注释）。
  ///
  /// [caretPara] 是光标在段落字符流里的下标（null ⇒ 这次不画：闪烁灭 / 有选区 / 导出中）。
  Widget _wrapWithCaret(Widget text, {required int? caretPara}) {
    if (caretPara == null || !widget.showEditingAids) return text;
    final double h = textCaretHeight(_textFontSize);
    // ignore: avoid_print
    print('[CARET-DIAG] fs=$_textFontSize styleH=${widget.textStyle?.height} '
        'lineBox=$_lineBoxHeight barH=$h idx=$caretPara');
    return _TextCaretBox(
      caretIndex: caretPara,
      barWidth: widget.caretWidth,
      barHeight: h,
      lineBoxHeight: _lineBoxHeight,
      children: <Widget>[
        text,
        Container(
          width: widget.caretWidth,
          height: h,
          // ★ 必须与数学侧的光标同色（数学侧靠 `\textcolor` 注入，见 caret_sites.dart）
          color: widget.caretColor ?? const Color(kCaretColorValue),
        ),
      ],
    );
  }

  /// 文字段：把光标条 + 组合串切开插进去（光标在数学段里时走注入，见 [_mathSpan]）
  List<InlineSpan> _textSpansWithCaret(
    ProjectionSegment s,
    int i,
    CaretPlacement? pl,
    CaretPlacement? slotPl,
  ) {
    // ★★★ 2026-11-01（反馈 1 · R9）：**组合串与光标条分开判**。
    //   光标条看 `pl`（跟闪烁）；组合串看 `pl ?? slotPl`（不跟闪烁、不跟选区）。
    final bool here = caretOwnedBy(pl, i, isMath: false);
    final bool composingHere = widget.composingText.isNotEmpty &&
        (here || caretOwnedBy(slotPl, i, isMath: false));
    if (!here && !composingHere) {
      // ★ 绝对偏移口径（2026-10-20 修复拖选高亮错位）
      return _runs(s.text, s.start);
    }
    final CaretPlacement cpl = here ? pl! : slotPl!;
    final int r = cpl.localRel.clamp(0, s.text.length);
    // ★ `widget.selStart/selEnd` 是**本单元源坐标里的相对偏移**（`DocView._localSelFor` 算的），
    //   所以这里必须传段内相对的 `s.start`（2026-10-20 曾误改成绝对偏移，导致中文不高亮）。
    final int abs0 = s.start;
    // ★★★ 2026-11-10（反馈 ④）：这里**不再插光标条**（竖条由 `_wrapWithCaret` 叠在外面）。
    //   组合串仍要插在这里 —— 它是**内容**（输入法预览），必须参与排版。
    return <InlineSpan>[
      ..._runs(s.text.substring(0, r), abs0),
      // ★ 插入点在正文中间：光标不动、拼音向右展开，后面的字被真的推开
      if (composingHere) _composingSpan(),
      ..._runs(s.text.substring(r), abs0 + r),
    ];
  }

  /// 把一段**纯文字**按选区切成「有底 / 无底」若干 `TextSpan`（⑤ 高亮）。
  ///
  /// [srcStart] 是这段文字第一个字符在**本 widget 的 `source`** 里的下标
  /// （文字段的渲染文本与源码是按 1:1 对应的，公式段才会被剥掉 `$`）。
  List<InlineSpan> _runs(String txt, int srcStart) {
    if (txt.isEmpty) return const <InlineSpan>[];
    final int? a = widget.selStart;
    final int? b = widget.selEnd;
    if (a == null || b == null || b <= a) return <InlineSpan>[TextSpan(text: txt)];
    final int from = (a - srcStart).clamp(0, txt.length);
    final int to = (b - srcStart).clamp(0, txt.length);
    if (to <= from) return <InlineSpan>[TextSpan(text: txt)];
    final TextStyle sel = TextStyle(backgroundColor: const Color(kSelectionColorValue));
    return <InlineSpan>[
      if (from > 0) TextSpan(text: txt.substring(0, from)),
      TextSpan(text: txt.substring(from, to), style: sel),
      if (to < txt.length) TextSpan(text: txt.substring(to)),
    ];
  }

  /// ★★ 2026-10-20（方案 B）：**强调段**（`**…**`）—— 正文按粗体画，两个标记不画。
  ///
  /// 标记由**投影层**认领（`ProjectionSegment.emphasis`），这里只管正文：
  /// 于是光标切分也只会在**正文**里切，永远劈不到星号（这就是方案 B 的收益）。
  List<InlineSpan> _emphasisSpansWithCaret(
    ProjectionSegment s,
    int i,
    CaretPlacement? pl,
  ) {
    const TextStyle bold = TextStyle(fontWeight: FontWeight.bold);
    // ★★ 2026-10-20（用户实测：拖选时「不成立。」三个字没高亮）：
    //   `widget.selStart/selEnd` 是**本单元源坐标里的相对偏移**（`DocView._localSelFor` 算的），
    //   所以这里和 `_runs` 一样必须用段内相对的 `s.start`，**不能**再加 `baseOffset`
    //   （加了就整段错位，正好漏掉粗体那一截）。
    final int abs0 = s.start;
    final String txt = s.text;
    // 选区（绝对偏移 → 段内正文偏移；两端标记不算正文）
    final int? sa = widget.selStart;
    final int? sb = widget.selEnd;
    final int selFrom =
        (sa == null || sb == null || sb <= sa) ? 0 : (sa - abs0).clamp(0, txt.length);
    final int selTo =
        (sa == null || sb == null || sb <= sa) ? 0 : (sb - abs0).clamp(0, txt.length);
    final TextStyle selStyle = const TextStyle(
        backgroundColor: Color(kSelectionColorValue),
        fontWeight: FontWeight.bold);

    /// 把正文 [from, to) 画出来（粗体 + 视情况铺选区底色）
    List<InlineSpan> body(int from, int to) {
      if (to <= from) return const <InlineSpan>[];
      final List<InlineSpan> out = <InlineSpan>[];
      final int a = from < selFrom ? selFrom.clamp(from, to) : from;
      final int b = to > selTo ? selTo.clamp(from, to) : to;
      if (b > a) {
        if (a > from) out.add(TextSpan(text: txt.substring(from, a), style: bold));
        out.add(TextSpan(text: txt.substring(a, b), style: selStyle));
        if (b < to) out.add(TextSpan(text: txt.substring(b, to), style: bold));
      } else {
        out.add(TextSpan(text: txt.substring(from, to), style: bold));
      }
      return out;
    }

    if (!caretOwnedBy(pl, i, isMath: false)) {
      return body(0, txt.length);
    }
    final int r = pl!.localRel.clamp(0, txt.length);
    // ★★★ 2026-11-10（反馈 ④）：不再插光标条（竖条由 `_wrapWithCaret` 叠在外面）
    return <InlineSpan>[
      ...body(0, r),
      if (widget.composingText.isNotEmpty) _composingSpan(),
      ...body(r, txt.length),
    ];
  }
  /// 把本 widget 的 `source` 选区换算成**这个公式段**的 tex 相对区间。
  ///
  /// `$tex$` 的内容从 `s.start + 1` 开始；选区碰到 `$` 就算"到边"。
  /// 与本段无交集 ⇒ `null`。
  ({int from, int to})? _texSelection(ProjectionSegment s, int texLen) {
    final int? a = widget.selStart;
    final int? b = widget.selEnd;
    if (a == null || b == null || b <= a) return null;
    // ★ `ProjectionSegment.start` 是**tex 的第一个字符**（不含两端 `$`）——
    //   依据：点击行内公式时 `cb(renderBase + seg.start + texRel)`（见 doc_view `_onMathTap`）。
    final int segEnd = s.start + texLen + 1; // 含收尾 `$`
    if (b <= s.start || a >= segEnd) return null;
    final int from = (a - s.start).clamp(0, texLen);
    final int to = (b - s.start).clamp(0, texLen);
    if (to <= from) return null;
    return (from: from, to: to);
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

  InlineSpan _mathSpan(ProjectionSegment s, int i, CaretPlacement? pl,
      CaretPlacement? slotPl) {
    final absStart = widget.baseOffset + s.start;
    final bool caretHere = caretOwnedBy(pl, i, isMath: true);
    // ★ 垫子看**逻辑**位置（闪烁/选区不影响），竖条看**视觉**位置
    final bool slotHere = caretOwnedBy(slotPl, i, isMath: true);

    final key = _keys.putIfAbsent(absStart, () => GlobalKey());
    final bool baseline = widget.align == MathAlignMode.baseline;
    final onTap = widget.onMathTap;

    // ★★ §6.1.1（2026-10-18）：**空公式必须看得见**。
    //   `$ $`（在公式里把内容删光的产物，§4.6）渲染出来是**零尺寸** ⇒ 既看不见也点不到，
    //   只能靠"再按一次退格"清掉（用户实测"按了没反应"）。
    //   ⇒ 空壳不走 Math 渲染，改画一个 1px 淡虚线小框（`EmptyMathMark`）；
    //   点它就落进公式里（`doc_view._onMathTap` 对空 tex 直接给 contentStart）。
    //   ★ 它占"一个正文汉字宽"（与空槽同一口径），高度取**当地那一行** —— 与光标同一标准。
    if (s.tex.trim().isEmpty) {
      final Widget mark = EmptyMathMark(
        width: widget.mathFontSize * 1.2,
        height: textCaretHeight(_textFontSize),
        showCaret: caretHere,
        // ★ F16：导出抓图时不画这个虚线小框
        showEditingAids: widget.showEditingAids,
      );
      return WidgetSpan(
        alignment: baseline
            ? PlaceholderAlignment.baseline
            : PlaceholderAlignment.middle,
        baseline: baseline ? TextBaseline.alphabetic : null,
        child: onTap == null
            ? mark
            : Listener(
                // ★★ 2026-10-21（L10）：改用**原始 pointer down**，不用 `GestureDetector.onTapDown`。
                //   理由（实测）：`onTapDown` 要等**手势竞技场结算**（滚动器也在场）——
                //   有时要到**抬手**才回调 ⇒ 落点上报会落在"本次按下结束之后"，
                //   被上层当成**新的一按**（连击计数翻倍、选区乱掉）。
                //   `Listener` 不参加竞技场 ⇒ 一定在按下那一帧、且在祖先之前回调。
                onPointerDown: (PointerDownEvent e) =>
                    onTap(s, s.tex, e.position, key),
                child: MouseRegion(
                  cursor: SystemMouseCursors.text,
                  child: mark,
                ),
              ),
      );
    }

    // ★★ 注入链的**唯一入口**（`slot_marks.renderMathTex`）：先注空槽占位，再按需注光标。
    //   ★ `caretHere == false` 时**也要注占位** —— 空槽必须一直看得见。
    //     2026-10-15 用户实测：粘贴 `$\frac{}{}$` 后光标停在**闭合 `$` 之后那一格**，
    //     原先"不在这段里就什么都不注入" → 空分数退化成 3.4 × 10.3 px 细线 → 看着像"消失了"。
    //   ★ 注入点仍走**位点吸附**（`caret_sites.dart` 的 `injectCursor`）——
    //     旧的 `snapCaretInTex` 只防"切开命令名"，会把光标留在 `}{` 这类语法夹缝里。
    final String tex = renderMathTex(
      s.tex,
      caretRel: slotHere ? slotPl!.localRel : -1,
      showCursor: caretHere,
      // ★★ 2026-10-24（批 4 · C1）：**行内**分式加大（`\frac` → `\dfrac`）。
      //   行间块（`doc_view` 那条）不传 ⇒ 保持 display 尺寸（它本来就是全尺寸）。
      inlineFractions: true,
    );
    // ★★★ 2026-11-01（反馈 19 续 · 拖选）：**把"这一段公式的 key 与渲染 tex"登记出去**。
    //   为什么：拖选走的是页面级几何（`DocView.offsetAtGlobal`），而它对文字段只有
    //   "段落排版器"一条路 —— 段落里行内公式是被**整段删掉**的（`_plainTextOf`），
    //   所以点在公式里只能吸到公式边界（实测：点 `D` 得到偏移 1 = `$`）。
    //   有了这张登记表，拖选就能像点击一样走 `hitTestMathTex`。
    widget.onMathLayout?.call(absStart, key, tex);

    // ★★ ⑤ 选区：`source` 里公式段是 `$tex$` ⇒ 内容从 `s.start + 1` 开始
    final ({int from, int to})? sel = _texSelection(s, s.tex.length);
    // ★★ 层级（§11.27）：光标落在**两端多认领的那两格**上时，这一格**视觉上属于文本层**
    //   ⇒ 交给 `MathWithCaret` 按文本层标准画（与"文字后面的光标"地位等同）。
    final CaretEdge edge = caretHere ? (pl?.edge ?? CaretEdge.none) : CaretEdge.none;

    // ★★ U3（2026-10-21）：光标所在的**槽层深**（0 = 主行）—— 由位点表给，不靠几何猜。
    //   只在本段确实画/占光标时才算（只算这一段，成本可忽略）。
    int caretDepth = 0;
    // ★★ 批 16（2026-10-24 用户拍板"变矮"）：脚本槽（`^` / `_` 的内容）⇒ 竖条单独缩
    bool caretScript = false;
    // ★★ 2026-11-03 晚：光标在**哪一格**（行内矩阵也要画格框；见 `math_caret.caretCell`）。
    //   必须由**偏移**定，不能拿像素猜 —— `a&b` 的左格末尾与右格开头是同一像素。
    ({int r, int c, int envIx})? caretCell;
    if (caretHere || slotHere) {
      final int? rel = caretHere ? pl?.localRel : slotPl?.localRel;
      if (rel != null) {
        final CaretSite site = buildCaretSites(s.tex).snap(rel);
        // ★ 反馈 8：粘合位点按脚本档画（画/插同源，见 `caretVisualLevel`）
        final ({int depth, bool script}) lv = caretVisualLevel(site);
        caretDepth = lv.depth;
        caretScript = lv.script;
        if (s.tex.contains(r'\begin{')) caretCell = cellAtOffset(s.tex, rel);
      }
    }

    return WidgetSpan(
      alignment: baseline
          ? PlaceholderAlignment.baseline
          : PlaceholderAlignment.middle,
      baseline: baseline ? TextBaseline.alphabetic : null,
      child: onTap == null && widget.onMathRightClick == null
          ? _mathWidget(key, tex,
              caretHere: caretHere,
              edge: edge,
              sel: sel,
              caretDepth: caretDepth,
              caretCell: caretCell,
              caretScript: caretScript)
          : GestureDetector(
              // ★ 右键：行内公式也要能"改尺寸"（只有多行环境会被接住）。
              //   `opaque` 是为了**公式内部的空白**也归它（与行间那块同一口径）。
              behavior: HitTestBehavior.opaque,
              onSecondaryTapDown: widget.onMathRightClick == null
                  ? null
                  : (TapDownDetails _) => widget
                      .onMathRightClick!(widget.baseOffset + s.start),
              // ★★ L10（2026-10-21）：左键走**原始 pointer down**（理由见上面空公式分支的注释）
              child: Listener(
                onPointerDown: onTap == null
                    ? null
                    : (PointerDownEvent e) => onTap(s, tex, e.position, key),
                child: MouseRegion(
                  cursor: SystemMouseCursors.text,
                  child:
                      _mathWidget(key, tex,
                          caretHere: caretHere,
                          edge: edge,
                          sel: sel,
                          caretDepth: caretDepth,
                          caretCell: caretCell,
                          caretScript: caretScript),
                ),
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
  Widget _mathWidget(GlobalKey key, String tex,
          {bool caretHere = false,
          CaretEdge edge = CaretEdge.none,
          int caretDepth = 0,
          bool caretScript = false,
          ({int r, int c, int envIx})? caretCell,
          ({int from, int to})? sel}) =>
      MathWithCaret(
        tex: tex,
        selFrom: sel?.from,
        selTo: sel?.to,
        showCaret: caretHere,
        caretEdge: edge,
        caretDepth: caretDepth, // ★ U3：0 = 主行 ⇒ 竖条按文本层标准画高
        // ★★ 2026-11-03 晚：光标在哪一格（行内矩阵的格框；按偏移算，不拿像素猜）
        caretCell: caretCell,
        // ★ 批 16：脚本槽（上标/下标内容）⇒ 竖条明显更矮（用户拍板）
        caretScript: caretScript,
        // ★ F16：导出抓图时不画任何编辑辅助
        showEditingAids: widget.showEditingAids,
        // ★ 文本层字号（"公式前后那两格"按它画，与文字后面的光标地位等同）
        textFontSize: _textFontSize,
        mathKey: key,
        fontSize: widget.mathFontSize,
        onErrorFallback: (e) => Tooltip(
          message: e.messageWithType,
          child: const Text(
            '［公式不完整］',
            style: TextStyle(color: Color(0xFFB08968), fontSize: 13),
          ),
        ),
      );

  /// 本行的**文本字号**（文本侧光标与"公式前后那两格"都用它当文本层标准）
  double get _textFontSize => widget.textStyle?.fontSize ?? widget.mathFontSize;

  /// 行盒高度 = 字号 × 行距（`TextStyle.height`）。
  ///
  /// 只用来把竖条**垂直居中**（旧实现靠 `PlaceholderAlignment.middle`，效果相同）。
  /// 没设 `height` 时退回 1.2（Flutter 缺省行距的量级）—— 目前所有调用方都设了。
  double get _lineBoxHeight => _textFontSize * (widget.textStyle?.height ?? 1.2);
}

/// **正文 + 竖条**：竖条是段落的**兄弟**，不在字符流里。
///
/// 为什么必须分开（2026-11-10 反馈 ④ 的实测）：
///   · 竖条原来是一个 0 宽的 `WidgetSpan` —— 0 宽只保证"不占宽度"，
///     但 WidgetSpan 会在段落字符流里留下一个 **U+FFFC**，那是行内断行类别 ID，
///     **本身就是一个断行机会**：光标落在 `d`/`i` 之间时，整段会从 2 行变 3 行，
///     光标一灭又变回 2 行 ⇒ 用户看到"排版闪烁 + 字在行首/行末之间跳"。
///   · 现在竖条完全不进字符流：位置在 layout 阶段用段落自己的
///     `getOffsetForCaret` 算出来（与旧的 0 宽占位位置**逐像素一致**，见 2026-11-10 标定：
///     旧竖条 `Rect.fromLTRB(0.1, 3.4, 1.6, 23.4)` == `getOffsetForCaret(0, Rect.zero)`）。
class _TextCaretBox extends MultiChildRenderObjectWidget {
  const _TextCaretBox({
    required this.caretIndex,
    required this.barWidth,
    required this.barHeight,
    required this.lineBoxHeight,
    required super.children,
  });

  /// 光标在**段落字符流**里的下标（数学段在段落里只占一格）
  final int caretIndex;
  final double barWidth;
  final double barHeight;

  /// 行盒高度（字号 × 行距）。旧实现用 `PlaceholderAlignment.middle` 把竖条**垂直居中**在行盒里，
  /// 新的叠层必须自己算这一下：`dy += (行盒 − 竖条高) / 2`。
  /// 标定（2026-11-10）：正文 16 / 行距 1.7 ⇒ 行盒 27.2、竖条 20 ⇒ 内缩 3.6，
  /// 与旧竖条的 `Rect` 逐像素一致（旧 3.4 == 新 `getOffsetForCaret().dy(=−0.2) + 3.6`）。
  final double lineBoxHeight;

  @override
  _RenderTextCaretBox createRenderObject(BuildContext context) => _RenderTextCaretBox(
        caretIndex: caretIndex,
        barWidth: barWidth,
        barHeight: barHeight,
        lineBoxHeight: lineBoxHeight,
      );

  @override
  void updateRenderObject(BuildContext context, _RenderTextCaretBox renderObject) {
    renderObject
      ..caretIndex = caretIndex
      ..barWidth = barWidth
      ..barHeight = barHeight
      ..lineBoxHeight = lineBoxHeight;
  }
}

class _RenderTextCaretBox extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, MultiChildLayoutParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, MultiChildLayoutParentData> {
  _RenderTextCaretBox({
    required this._caretIndex,
    required this._barWidth,
    required this._barHeight,
    required this._lineBoxHeight,
  });

  int _caretIndex;
  set caretIndex(int v) {
    if (v == _caretIndex) return;
    _caretIndex = v;
    markNeedsLayout();
  }

  double _barWidth;
  set barWidth(double v) {
    if (v == _barWidth) return;
    _barWidth = v;
    markNeedsLayout();
  }

  double _barHeight;
  set barHeight(double v) {
    if (v == _barHeight) return;
    _barHeight = v;
    markNeedsLayout();
  }

  double _lineBoxHeight;
  set lineBoxHeight(double v) {
    if (v == _lineBoxHeight) return;
    _lineBoxHeight = v;
    markNeedsLayout();
  }

  RenderBox? get _text => firstChild;

  RenderBox? get _bar {
    final RenderBox? t = firstChild;
    return t == null ? null : childAfter(t);
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! MultiChildLayoutParentData) {
      child.parentData = MultiChildLayoutParentData();
    }
  }

  @override
  void performLayout() {
    final RenderBox? text = _text;
    if (text == null) {
      size = constraints.smallest;
      return;
    }
    // 段落按**原样**的约束排版（与"没有竖条"时完全相同）
    text.layout(
      BoxConstraints(maxWidth: constraints.maxWidth),
      parentUsesSize: true,
    );
    size = constraints.constrain(text.size);

    final RenderBox? bar = _bar;
    if (bar == null) return;
    bar.layout(
      BoxConstraints.tight(Size(_barWidth, _barHeight)),
      parentUsesSize: true,
    );
    Offset at = Offset.zero;
    if (text is RenderParagraph) {
      final int len = text.text.toPlainText().length;
      final int idx = _caretIndex.clamp(0, len);
      at = text.getOffsetForCaret(TextPosition(offset: idx), Rect.zero);
      // ★★★ 2026-11-10 晚（用户实测回归）：**软换行边界上的光标要落在上一行行末**。
      //   offset 正好落在"第 1 行末 / 第 2 行首"这个边界时，默认（downstream）取到的是
      //   **下一行行首**；旧实现（竖条是文字流里的占位）落在**上一行行末**。
      //   实测（宽 657.6、边界 offset=37）：downstream=(0.1, 26.8) / upstream=(601.4, −0.2)。
      //   ⇒ 只要 upstream 的行更靠上，就用 upstream（= 恢复旧表现）。
      //   ★ 顺带解决"段落末尾那个位置 Skia 给的 y 偏低 4.1px"（那种情形 upstream 也更靠上）。
      if (idx > 0) {
        final Offset up = text.getOffsetForCaret(
          TextPosition(offset: idx, affinity: TextAffinity.upstream),
          Rect.zero,
        );
        if (up.dy < at.dy - 0.5) at = up;
      }
      // ★ 垂直居中在行盒里（旧实现是 `PlaceholderAlignment.middle` 的等价物）。
      //   ★★ 行盒高度**必须问段落自己**（`getFullHeightForCaret`）：这一行里可能插着
      //   行内公式，行盒会被公式撑高 —— 用"字号 × 行距"估出来的值会让竖条低 5.8 px
      //   （`caret_line_center_test` ② 当场红：公式侧 109.1 vs 文字侧 114.9）。
      // ★ 垂直位置：与数学侧**同一把尺子**（2026-11-01 定的「行盒中心」；
      //   单行段 = 段落盒中心 —— 见 `caret_line_center_test` ②）。
      //   为什么不能只用 `getOffsetForCaret` 的 y：它给的是**字形盒顶**（基线 − ascent），
      //   当这一行里插着更高的行内公式时，字形盒顶会落在行盒中间（实测 6.99 vs 行盒顶 0），
      //   直接加内缩会让竖条低 2~6 px。所以：
      //   · **单行段** ⇒ 直接按段落盒中心放（和数学侧那条判据同一个式子）；
      //   · **多行段**（软换行）⇒ 按"字形盒顶 + (行高 − 竖条高)/2"放（行内公式很少见）。
      final double paraH = text.size.height;
      final double line0H =
          text.getFullHeightForCaret(const TextPosition(offset: 0));
      final bool singleLine = line0H > 0 && (paraH - line0H).abs() < 1.0;
      double barTop;
      if (singleLine) {
        barTop = (paraH - _barHeight) / 2;
      } else {
        final double boxH = line0H > 0 ? line0H : _lineBoxHeight;
        final double inset = (boxH - _barHeight) / 2;
        barTop = at.dy + (inset > 0 ? inset : 0);
      }
      at = Offset(at.dx, barTop);
    }
    (bar.parentData! as MultiChildLayoutParentData).offset = at;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
