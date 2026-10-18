// 数语引擎 · **面板插入语义**（S4-b）：符号/模板 → 一次编辑写进缓冲区
//
// 用户 2026-10-17 确认过的口径（《界面与布局.md》§7）：
//   ① 光标**在数学段里**（含紧邻 ±1 格）⇒ **并入那一段**（`$x$` 后点 `+` ⇒ `$x+$`），不新建第二个 `$…$`；
//   ② 光标在**纯文字**里 ⇒ **自动建壳**：插入 `$<tex>$`（"用户不写编码" = 编辑器替用户写）；
//   ③ 有选区 ⇒ **替换选区**（选区里已有数学段就替换成 tex、不重复包）。
// 不管哪一条，都是**一次区间替换** ⇒ 一步撤销。
//
// ★ 走 `insert_guard.planInsert`，**不绕过守门人**（行边界 ③④⑤、粘合处挪位 ② 全都照旧）。
//
// **纯 Dart**（只依赖核心/渲染层的纯函数），可单测。

import '../render/insert_guard.dart';
import '../render/math_nav.dart';

/// 插入时做的三选一（诊断与守卫用）
enum SymbolInsertMode { mergeIntoMath, wrapNewInlineMath, replaceSelection }

class SymbolInsertResult {
  const SymbolInsertResult({
    required this.doc,
    required this.caret,
    required this.mode,
    required this.wrapped,
    required this.inserted,
  });

  /// 新文档（整份替换进 `DocBuffer` = 一次编辑）
  final String doc;

  /// 新光标（模板 = 第一个空槽里；符号 = 插入内容之后）
  final int caret;

  final SymbolInsertMode mode;

  /// 是否替用户补了 `$…$`（状态栏"自动包裹 N 处"要报它）
  final bool wrapped;

  /// 真正写进缓冲区的文本（含壳 / 补的行边界；诊断用）
  final String inserted;

  @override
  String toString() => 'SymbolInsert(${mode.name}, wrapped=$wrapped, '
      'caret=$caret, inserted="${inserted.replaceAll('\n', r'\n')}")';
}

/// 建壳：行内 `$…$` / 行间 `$$\n…\n$$`（围栏必须**独占一行**，否则不是围栏）。
///
/// ★ 行间的前缀固定 3 个字符（`$$\n`）—— 光标定位要按它算（见 `shellPrefix`）。
String _shell(String tex, {required bool display}) =>
    display ? '\$\$\n$tex\n\$\$' : '\$$tex\$';

/// tex 里**第一个空槽**的偏移（空槽 = 一对空的 `{}` 或 `[]`）。///
/// ★ 为什么不用位点表的第一个位点：位点表包含"tex 之前/之后"这类**边界位点**，
///   而这里要的是"**空槽内部**的第一个落点"（模板插入后光标就该停在那个空格里）。
///   判据就是源码里的空组 —— 与 `slot_marks` 认空槽的口径一致（空 `{}` / 空 `[]`）。
int firstSlotOffset(String tex) {
  // ★★ 2026-10-18 多行环境（`\begin{aligned}…\end{aligned}` / `cases` …）：
  //   光标落进**第一格** = `\begin{env}` 之后、第一个 `&` 之前。
  //   为什么必须这样（用户实测）：原来环境里**没有 `{}` / `[]`**，于是 `firstSlotOffset`
  //   返回 `tex.length`（末尾）⇒ 人一打字就打在 `&` **右边**，而 `&` 后面那一列是**左对齐**的，
  //   于是 `=` 被内容推右、两行的等号立刻错位（`\begin{aligned}&a=b\\&=\end{aligned}`）。
  //   写推导的自然顺序是"左边 → `=` → 右边"，所以先落第一格。
  final int begin = tex.indexOf(r'\begin{');
  if (begin >= 0) {
    final int brace = tex.indexOf('}', begin);
    if (brace > 0) return brace + 1;
  }
  final int a = tex.indexOf('{}');
  final int b = tex.indexOf('[]');
  if (a < 0 && b < 0) return tex.length;
  if (a < 0) return b + 1;
  if (b < 0) return a + 1;
  return (a < b ? a : b) + 1;
}

/// 把 [tex] 插到光标处（或替换选区），返回新文档与新光标。
///
/// [display] = 插成**行间公式段**（`$$\n<tex>\n$$`，围栏独占一行）。
/// ★ 2026-10-18：`行间` 与 `行内` 是**两种排版意图**，混不进去 ⇒
///   display 请求**不并入**已有的行内公式；而载荷里带 `\n` 走 `insert_guard` 规则 ①，
///   会被**推出**行内公式（推到 `closeEnd` 之后），所以不会把 `$…$` 劈开。
SymbolInsertResult applySymbolInsert({
  required String doc,
  required int caret,
  required int selStart,
  required int selEnd,
  required String tex,
  required bool template,
  bool display = false,
}) {
  final int c = caret.clamp(0, doc.length);
  final int s = selStart.clamp(0, doc.length);
  final int e = selEnd.clamp(0, doc.length);

  SymbolInsertMode mode;
  String text;
  bool wrapped;
  int? mergeAt;

  if (e > s) {
    // ③ 替换选区
    mode = SymbolInsertMode.replaceSelection;
    wrapped = display || !_touchesMath(doc, s, e);
    text = wrapped ? _shell(tex, display: display) : tex;
  } else if (!display && _mergeRegion(doc, c) != null) {
    // ① 并入数学段（★ 落点要**挪进段内**：段边界那一格在 `mathRegionAt` 里算"段外"）
    mode = SymbolInsertMode.mergeIntoMath;
    wrapped = false;
    text = tex;
    mergeAt = _mergeRegion(doc, c)!.at;
  } else {
    // ② 在文字里 ⇒ 自动建壳（display ⇒ 建的是**行间**的壳）
    mode = SymbolInsertMode.wrapNewInlineMath;
    wrapped = true;
    text = _shell(tex, display: display);
  }

  // ★ 走同一条守门人链（含行边界 ③④⑤、粘合处挪位 ②、裸参数补花括号）
  int at0 = e > s ? s : (mergeAt ?? c);
  // ★★ 2026-10-17（用户手验抓到的真缺陷）：**落点必须在"参数安全位"**。
  //   两个坑（全域扫 146/804 个落点会产出**解析失败**的文档）：
  //     ① 落在**控制词中间**：`\f|rac` 里插 `\forall` ⇒ `\f\forallrac`（命令当场散架）；
  //     ② 与**字母粘连**：`\forall` + `x^2` ⇒ `\forallx^2`（TeX 只按字母读词 ⇒ 未知命令）。
  //   ⇒ ① 挪到控制词**之前**（`\frac` 在视觉上是一个原子，"插在它前面"才有意义）；
  //     ② 两边都补一个空格（TeX 里空格只是分隔符，不占版面）。
  if (e == s) at0 = _intoArgGroupIfAfterCommand(doc, _safeMathOffset(doc, at0));
  // 两趟：`planInsert` 自己也会挪落点（粘合处规则 ②）⇒ 分隔符必须按**最终落点**判邻居。
  InsertPlan plan = planInsert(doc, at0, text);
  if (plan.offset != at0) at0 = plan.offset;
  final ({String text, int prefix}) safe =
      _withCommandSeparators(doc, at0, text);
  text = safe.text;
  final int sepPrefix = safe.prefix;
  if (plan.offset != at0) plan = planInsert(doc, at0, text);
  var d = doc;
  if (plan.wrapBareArg != null) {
    final ({int start, int end}) w = plan.wrapBareArg!;
    d = d.replaceRange(w.start, w.end, '{${d.substring(w.start, w.end)}}');
  }
  final String payload = plan.padText(text);
  final int at = plan.offset.clamp(0, d.length);
  final int delEnd = (e > s) ? (e + (d.length - doc.length)).clamp(at, d.length) : at;
  final String newDoc = d.replaceRange(at, delEnd, payload);

  // 新光标：模板 ⇒ 第一个空槽；符号 ⇒ 插入内容之后
  final int padPrefix = plan.padding.prefixNewline ? 1 : 0;
  // ★ 行间壳的前缀是 `$$\n`（3 个字符），行内壳是 `$`（1 个）
  final int shellPrefix = wrapped ? (display ? 3 : 1) : 0;
  final int texStart = at + padPrefix + shellPrefix + sepPrefix;
  final int caretOut = template
      ? (texStart + firstSlotOffset(tex)).clamp(0, newDoc.length)
      : (at + payload.length).clamp(0, newDoc.length);

  return SymbolInsertResult(
    doc: newDoc,
    caret: caretOut,
    mode: mode,
    wrapped: wrapped,
    inserted: payload,
  );
}

/// 光标是否"在数学段里或紧贴它的边界"；是则返回 **并入时的落点**。
///
/// ★ 落点必须**挪进段内**：段边界那一格（`closeEnd` / `openStart`）在 `mathRegionAt` 里算"段外"，
///   直接按原光标插会插到 `$` 外面（实测：`$x$` 后点 `+` 变成 `$x$+` 而不是 `$x+$`）。
({MathRegion region, int at})? _mergeRegion(String doc, int caret) {
  final MathRegion? here = mathRegionAt(doc, caret);
  if (here != null) return (region: here, at: caret);
  // 紧贴左边：`$x$|` ⇒ 落进段内末尾
  if (caret > 0) {
    final MathRegion? left = mathRegionAt(doc, caret - 1);
    if (left != null && left.closeEnd == caret) {
      return (region: left, at: left.contentEnd);
    }
  }
  // 紧贴右边：`|$x$` ⇒ 落进段内开头
  final MathRegion? right =
      caret < doc.length ? mathRegionAt(doc, caret + 1) : null;
  if (right != null && right.openStart == caret) {
    return (region: right, at: right.contentStart);
  }
  return null;
}

/// 选区内是否"碰到"数学段（有任何一段与选区相交 ⇒ 不重复包壳）
bool _touchesMath(String doc, int from, int to) {
  for (var o = from; o <= to; o++) {
    if (mathRegionAt(doc, o) != null) return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// 落点的"参数安全"两条（2026-10-17，用户手验后全域扫出来的）
// ---------------------------------------------------------------------------

bool _isLetter(String ch) {
  final int c = ch.codeUnitAt(0);
  return (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
}

/// 包含 [at] 的那个**控制词**（`\frac` 的 `[反斜杠, 词尾)`）；不在控制词里返回 `null`。
///
/// 判据：`at` 两侧的字母串 + 串前必须是 `\`。注意 `at` 可以正好等于词首/词尾
/// （那两个位置是**合法**落点，本函数照样返回区间，由调用方判"是不是真落在中间"）。
({int start, int end})? controlWordSpanAt(String doc, int at) {
  final int o = at.clamp(0, doc.length);
  var s = o, e = o;
  while (s > 0 && _isLetter(doc[s - 1])) {
    s--;
  }
  while (e < doc.length && _isLetter(doc[e])) {
    e++;
  }
  if (s == e) return null;
  if (s == 0 || doc[s - 1] != r'\') return null;
  return (start: s - 1, end: e);
}

/// 把落在**控制词中间**的落点挪到那个控制词**之前**。
int _safeMathOffset(String doc, int at) {
  final ({int start, int end})? span = controlWordSpanAt(doc, at);
  if (span == null) return at;
  if (at <= span.start || at >= span.end) return at; // 词前 / 词后都是合法位
  return span.start;
}

/// ★★ 第三个坑：落点**紧贴控制词之后、而下一个字符正好是 `{`**。
///
/// 例：`\frac|-b \pm …` 插模板 ⇒ `\frac\frac{}{}{-b…}` —— 老的 `\frac` 会把**新模板**
/// 当成自己的第一个参数，于是多出一个 `{}` ⇒ 整段解析失败（实测可达、也实测红）。
/// 处置：把落点**挪进那个 `{` 里面**（= 那个参数的开头）⇒ `\frac{\frac{}{}}{-b…}`，
/// 语义上正好是"把模板放进分子的位置"，与用户点在那儿的心智一致。
int _intoArgGroupIfAfterCommand(String doc, int at) {
  if (at <= 0 || at >= doc.length) return at;
  if (doc[at] != '{') return at;
  final ({int start, int end})? span = controlWordSpanAt(doc, at);
  // ① 紧贴"命令名 + `{`"（`\frac|{-b…` / `\sqrt|{…`）
  if (span != null && at == span.end) return at + 1;
  // ② 紧贴"上一个参数的 `}` + 下一个参数的 `{`"（`…}|{2a}`）——同样是"新模板会被外层命令
  //    当成参数吃掉"的情形。挪进下一个参数的开头，语义上也最接近用户点的位置。
  if (doc[at - 1] == '}') return at + 1;
  return at;
}

/// 载荷与相邻字母之间补**空格分隔符**（TeX 里空格只是分隔，不占版面）。
///
/// 返回 `(text, prefix)`：`prefix` = 前面补了几个字符（光标定位要用）。
({String text, int prefix}) _withCommandSeparators(
    String doc, int at, String text) {
  if (text.isEmpty) return (text: text, prefix: 0);
  var out = text;
  var prefix = 0;
  final bool startLetter = _isLetter(text[0]);
  final bool endLetter = _isLetter(text[text.length - 1]);
  if (startLetter && at > 0 && _isLetter(doc[at - 1])) {
    out = ' $out';
    prefix = 1;
  }
  if (endLetter && at < doc.length && _isLetter(doc[at])) {
    out = '$out ';
  }
  return (text: out, prefix: prefix);
}
