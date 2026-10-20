// 数语引擎 · 行内投影：把 L0 的一段文本切成「文字段 / 数学段」
//
// 规格：notes/design/数学语法范围.md §一；架构：notes/design/技术选型与风险.md 4.0
// **纯 Dart，不依赖 Flutter** —— 分段规则可以直接被单测钉死。

/// 一个投影分段。`start` 是**相对 source 的偏移**。
///
/// ★★ **三类**（2026-10-17 加第三类）：文字段 / **行内**数学段 / **行间**数学段。
///
/// 为什么要认行间：`$$\nx=\frac{a}{b}\n$$` 这种输入被原先的实现切成
/// `[Text(""), Math(""), Text("\nx=\frac{a}{b}\n"), Math("")]` —— **LaTeX 源码被当成正文**，
/// 于是 `caretPlacement` 对块内每一格都给出**错误归属**。
/// 块模型本来就不把行间块交给行内投影（各走各的），但"**喂错了会静默给出错误答案**"
/// 是个陷阱（《位点》§11.25 附带 2 记的账）⇒ 现在明明白白给它一类分段。
class ProjectionSegment {
  const ProjectionSegment._(
    this.start,
    this.isMath,
    this.isDisplayMath,
    this.text,
    this.tex, {
    this.isEmphasis = false,
  });

  factory ProjectionSegment.text(int start, String text) =>
      ProjectionSegment._(start, false, false, text, '');

  factory ProjectionSegment.math(int start, String tex) =>
      ProjectionSegment._(start, true, false, '', tex);

  /// ★★ 2026-10-20（用户拍板方案 B）：**行内强调段** `**…**`。
  ///
  /// [start] 指向**第一个正文字符**（与数学段"指向 tex[0]"同一口径）：
  /// 于是开标记 `**` 在 `start-2`、闭标记在 `end..end+2`，两端像数学段一样**由段自己隐藏**。
  /// 为什么不继续在渲染层"把星号缩到看不见"：那样光标切分文本时会把一对星号**劈开**
  /// （用户实测：点标题左右两侧，星号就被显示出来、还随光标闪动）——
  /// 投影层认领之后，光标只能在段内移动，**结构上**不可能劈开。
  factory ProjectionSegment.emphasis(int start, String text) =>
      ProjectionSegment._(start, false, false, text, '', isEmphasis: true);

  /// 行间块（`$$…$$`）：[start] 指向**开围栏之后**那一格，[tex] 是围栏**之内**的原文。
  factory ProjectionSegment.displayMath(int start, String tex) =>
      ProjectionSegment._(start, true, true, '', tex);

  /// 在 source 内的起始偏移。
  /// 数学段的 start 指向**定界符之后**的第一个字符（即 `tex[0]`）。
  final int start;

  final bool isMath;

  /// 是不是**行间**块（`$$…$$`，围栏连自己一起被这一段落覆盖）
  final bool isDisplayMath;

  /// 文字段的内容（数学段为空串）
  final String text;

  /// 数学段的 tex，**不含定界符**（文字段为空串）
  final String tex;

  /// 是不是**行内强调段**（`**…**`；[text] 只有正文，两个标记不在这段里）
  final bool isEmphasis;

  int get length => isMath ? tex.length : text.length;

  /// 在 source 内的结束偏移（不含）。
  /// 文字段 = 最后一个字符之后；数学段 = 闭合定界符所在的位置。
  int get end => start + length;

  @override
  String toString() => isMath
      ? '${isDisplayMath ? 'DisplayMath' : 'Math'}($start..$end, "$tex")'
      : (isEmphasis
          ? 'Emphasis($start..$end, "$text")'
          : 'Text($start..$end, "$text")');
}

/// 把一段 L0 文本投影成「文字段 / 行内数学段 / 行间数学段」序列。
///
/// 规则：
///   · **行间块** `$$…$$` → 一个 [ProjectionSegment.displayMath]（见 [displayFenceEnd]）
///   · `$...$` → 行内数学段（tex 不含定界符）
///   · **未闭合的 `$`** → 余下全部当普通文字（打字过程中它是常态，不能报错）
///   · 数学区段内的 `_ * \` 归数学，不做 md 解析
///
/// **S2 已知缺口**（后续阶段补）：`\$` 转义、`\(...\)` 兼容写法、行内代码里的 `$` 不解析。
///
/// ★★ **边界（2026-10-17 写进代码）**：行内投影只负责**一行之内**的东西。
/// 行间块由**块模型**认领（`BlockType.math` 的单元自己拿 `renderBase`/`renderLength`），
/// 本函数对它的职责只有一条：**喂进来也不会把 LaTeX 当正文**。
List<ProjectionSegment> projectInline(String source) {
  final out = <ProjectionSegment>[];
  var i = 0;
  var textStart = 0;

  void flushText(int end) {
    if (end > textStart) {
      out.add(ProjectionSegment.text(textStart, source.substring(textStart, end)));
    }
  }

  while (i < source.length) {
    final String ch = source[i];
    // ① 行间围栏（`$$` 独占行首、且有闭合）—— 整块当一个 displayMath 段
    if (ch == r'$') {
      final int? fenceEnd = displayFenceEnd(source, i);
      if (fenceEnd != null) {
        flushText(i);
        out.add(ProjectionSegment.displayMath(
          i + 2,
          source.substring(i + 2, fenceEnd - 2),
        ));
        i = fenceEnd;
        textStart = i;
        continue;
      }
      // ② 行内 `$…$`
      final int close = source.indexOf(r'$', i + 1);
      if (close < 0) break; // 未闭合 → 余下全是文字
      flushText(i);
      out.add(ProjectionSegment.math(i + 1, source.substring(i + 1, close)));
      i = close + 1;
      textStart = i;
      continue;
    }
    // ①.5 **行内强调** `**…**`（用户 2026-10-20 拍板方案 B：投影层独立段）
    //   成对才算（`**` 之间至少一个字）；落单的星号原样当文字。
    if (ch == '*' && i + 1 < source.length && source[i + 1] == '*') {
      final int emphClose = source.indexOf('**', i + 2);
      if (emphClose > i + 2) {
        flushText(i);
        out.add(ProjectionSegment.emphasis(
          i + 2,
          source.substring(i + 2, emphClose),
        ));
        i = emphClose + 2;
        textStart = i;
        continue;
      }
    }
    i++;
  }
  flushText(source.length);
  return out;
}
/// 若 [at] 处是**行间围栏**的开头，返回"覆盖整个块之后"的偏移（= 闭合 `$$` 之后）；
/// 不是围栏（或**未闭合**）返回 null。
///
/// 判据与块模型**同一套**（`BlockMarkers.isMathFence`）：
/// 行首（前导 ≤3 空格）的 `$$`，且
///   · **同行闭合**（`$$x=1$$`），或
///   · 下文某个**行首的 `$$`** 收尾（`$$\n…\n$$`）。
///
/// ★ **未闭合时返回 null**（而不是"吞到文末"）：`$$ x` 这种"空壳公式 + 后续内容"
///   按块模型是**普通段落**（§11.22 收紧过判据），它那里的 `$$` 要按**空的行内公式**渲染。
///   真正的"未闭合行间块"（`$$\n…` 到文末）由**块模型**当整块吃掉，轮不到行内投影。
int? displayFenceEnd(String source, int at) {
  if (at + 1 >= source.length || source[at + 1] != r'$') return null;
  // 必须在行首（允许最多 3 个前导空格，与块模型一致）
  var k = at - 1;
  var spaces = 0;
  while (k >= 0 && source[k] == ' ' && spaces <= 3) {
    k--;
    spaces++;
  }
  if (spaces > 3) return null;
  if (k >= 0 && source[k] != '\n') return null;

  final int lineEndRaw = source.indexOf('\n', at);
  final int lineEnd = lineEndRaw < 0 ? source.length : lineEndRaw;

  // ① 同行闭合
  final int same = source.indexOf(r'$$', at + 2);
  if (same >= 0 && same + 2 <= lineEnd) return same + 2;
  // ② 跨行：找下一行行首的 `$$`
  var j = lineEnd + 1;
  while (j < source.length) {
    var m = j;
    var sp = 0;
    while (m < source.length && source[m] == ' ' && sp <= 3) {
      m++;
      sp++;
    }
    if (sp <= 3 &&
        m + 1 < source.length &&
        source[m] == r'$' &&
        source[m + 1] == r'$') {
      return m + 2;
    }
    final int nl = source.indexOf('\n', j);
    if (nl < 0) break;
    j = nl + 1;
  }
  return null;
}

bool isAsciiLetter(int c) =>
    (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

/// 「**段落坐标 → 源坐标**」映射表（S3-2 点屏幕定位用）。
///
/// 为什么需要这张表：`InlineMathText` 用 `Text.rich` + `WidgetSpan`，
/// 而**每个行内公式在段落里只占 1 个码元**（`U+FFFC` 对象替换符），
/// 在源里却是 `$...$` 好几个字符 —— 所以 `RenderParagraph.getPositionForOffset()`
/// 给出的偏移是**段落坐标**，直接当源偏移用会整体偏掉。
///
/// ★ [caretInText]：光标落在本段**文字段**里时，传入它的相对偏移。
/// **必须传**，否则映射会整体偏 1 —— 因为**零宽光标条也是 `WidgetSpan`，
/// 在段落里照样占 1 个码元**（它只是不占宽度）。用户实测的"点哪儿都没规律"就是这个：
/// 偏移量取决于光标当时在哪儿（详见《位点与结构导航.md》）。
/// 光标落在**数学段**里时传 `null`：那时光标是注进 tex 的 `\cursor{}`，不产生额外码元。
///
/// 返回长度 = 段落码元数 + 1；`表[i]` = 段落光标在第 i 位时对应的**源偏移**。
/// 约定：`表[0]` = 源起点；数学段占位符那一格 → 该段**之后**的源偏移（闭合 `$` 再 +1）。
List<int> paragraphIndexMap(String source, {int? caretInText}) {
  final List<int> out = <int>[0];
  for (final ProjectionSegment s in projectInline(source)) {
    if (s.isMath) {
      out.add(s.end + 1); // 占位符那一格 → 整段 `$...$` 之后
    } else {
      for (var k = 0; k < s.text.length; k++) {
        out.add(s.start + k + 1);
      }
    }
  }
  if (caretInText != null) {
    final int p = out.indexOf(caretInText);
    if (p >= 0) out.insert(p, caretInText); // 光标条那一格：不前进
  }
  return out;
}

/// 光标在**段落坐标**里的下标（= 渲染出来的 `Text.rich` 里，光标条那个占位符在第几格）。
///
/// ★ 用途（S3-2）：把光标的**像素位置**问出来（`RenderParagraph.getOffsetForCaret`），
/// 好让隐藏的镜像输入框跟过去 —— Web 上**中文输入法的候选框是画在 DOM 输入框那儿的**，
/// 镜像框不跟手，候选框就会出现在错误的屏幕位置。
///
/// [caretRel] 是光标在渲染文本里的相对偏移。**只有落在文字段里**才返回非 null：
/// 落在数学段里时光标是注进 tex 的 `\cursor{}`，不产生额外码元（那时用数学段的占位盒定位）。
int? caretParagraphOffset(String source, int caretRel) {
  var units = 0;
  for (final ProjectionSegment s in projectInline(source)) {
    if (s.isMath) {
      units += 1; // 数学段在段落里占 1 格
      continue;
    }
    if (caretRel >= s.start && caretRel <= s.end) {
      return units + (caretRel - s.start);
    }
    units += s.text.length;
  }
  return null;
}

/// 光标所在**数学段**在段落坐标里的下标（不在数学段里则 null）
int? mathPlaceholderAt(String source, int caretRel, {int slack = 1}) {
  var units = 0;
  for (final ProjectionSegment s in projectInline(source)) {
    if (s.isMath) {
      if (caretRel >= s.start - slack && caretRel <= s.end + slack) return units;
      units += 1;
      continue;
    }
    units += s.text.length;
  }
  return null;
}

// 说明：S1 时代这里有一个 `snapCaretInTex()`（只防"把命令名切开"的轻量吸附）。
// S3-1 之后注入光标一律走 `caret_sites.dart` 的位点表 + `injectCursor()`（它连 `}{` 这类
// 语法夹缝、以及 `\text{}` 内的文本模式都处理了），旧函数已**删除**，避免两套吸附规则并存。

