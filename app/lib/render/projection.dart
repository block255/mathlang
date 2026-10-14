// 数语引擎 · 行内投影：把 L0 的一段文本切成「文字段 / 数学段」
//
// 规格：notes/design/数学语法范围.md §一；架构：notes/design/技术选型与风险.md 4.0
// **纯 Dart，不依赖 Flutter** —— 分段规则可以直接被单测钉死。

/// 一个投影分段。`start` 是**相对 source 的偏移**。
class ProjectionSegment {
  const ProjectionSegment._(this.start, this.isMath, this.text, this.tex);

  factory ProjectionSegment.text(int start, String text) =>
      ProjectionSegment._(start, false, text, '');

  factory ProjectionSegment.math(int start, String tex) =>
      ProjectionSegment._(start, true, '', tex);

  /// 在 source 内的起始偏移。
  /// 数学段的 start 指向 `$` **之后**的第一个字符（即 `tex[0]`）。
  final int start;

  final bool isMath;

  /// 文字段的内容（数学段为空串）
  final String text;

  /// 数学段的 tex，**不含定界符**（文字段为空串）
  final String tex;

  int get length => isMath ? tex.length : text.length;

  /// 在 source 内的结束偏移（不含）。
  /// 文字段 = 最后一个字符之后；数学段 = 闭合 `$` 所在的位置。
  int get end => start + length;

  @override
  String toString() =>
      isMath ? 'Math($start..$end, "$tex")' : 'Text($start..$end, "$text")';
}

/// 把一段 L0 文本投影成「文字段 / 数学段」序列。
///
/// 规则：
///   · `$...$` → 数学段（tex 不含定界符）
///   · **未闭合的 `$`** → 余下全部当普通文字（打字过程中它是常态，不能报错）
///   · 数学区段内的 `_ * \` 归数学，不做 md 解析
///
/// **S2 已知缺口**（后续阶段补）：`\$` 转义、`\(...\)` 兼容写法、行内代码里的 `$` 不解析。
List<ProjectionSegment> projectInline(String source) {
  final out = <ProjectionSegment>[];
  var i = 0;
  var textStart = 0;
  while (i < source.length) {
    if (source[i] != r'$') {
      i++;
      continue;
    }
    final close = source.indexOf(r'$', i + 1);
    if (close < 0) break; // 未闭合 → 余下全是文字
    if (i > textStart) {
      out.add(ProjectionSegment.text(textStart, source.substring(textStart, i)));
    }
    out.add(ProjectionSegment.math(i + 1, source.substring(i + 1, close)));
    i = close + 1;
    textStart = i;
  }
  if (textStart < source.length) {
    out.add(ProjectionSegment.text(textStart, source.substring(textStart)));
  }
  return out;
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

