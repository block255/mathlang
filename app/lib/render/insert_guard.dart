// 数语引擎 · 插入侧守门人（2026-10-15）
//
// ============================ 为什么需要它 ============================
// 2026-10-15 用户实测：「点分式内 → 右箭头到数学区外行末 → 按 Enter → **分式被直接拆出编码**」。
// 探针把根因钉死了（`文字。$\frac{a}{b}$`，Enter 走平台真身 `performAction(newline)`）：
//
//   偏移：文0 字1 。2 $3 \4f5r6a7c8 {9a10}11{12b13}14 $15 ⏎16
//   · 14 = 分母内容末尾          Enter → 公式完好 ✓
//   · **15 = tex 末尾 = 闭合 `$` 那一格**（"还在公式里"）
//                                 Enter → `文字。$\frac{a}{b}` ⏎⏎ `$` → **劈断，退化成源码** ✗
//   · 16 = closeEnd（"在公式之后"）Enter → 公式完好 ✓
//
// ★ 关键在于 **15 与 16 在屏幕上是同一个位置**（`$` 不可见）——
//   所以"按 `→` 到行末再回车"极易停在 15，一按 Enter 就把 `$` 配成单数。
//
// ★★ 根因的**一般形式**：`EditView` 把文本**无条件**插到 `_buf.caret`，
//   而 caret 可以合法地落在数学段**内部**（槽里 / 原子之间 / tex 末尾）。
//   块级换行会破坏"行内公式不跨行、行间公式的 tex 里不出现空行"这两条结构不变量 ——
//   而**插入这一侧从来没有守门人**：设计稿 §4.0 的"永不留下半个坏公式"
//   只做在**删除**上（`smart_delete.dart`），插入侧是裸的。
//
// ============================ 规则（两条） ============================
// ① **在数学段内部插入含 `\n` 的文本 → 落点推到最后 `closeEnd`（公式之后）。**
//
// 为什么这样分：
//   · **行内**公式不能跨行（`projectInline` 是按行做的）→ 任何 `\n` 都会劈断定界符
//   · **行间**公式的 tex 里出现**空行**在 TeX 里是 `\par`（数学模式直接报错）
//   · 而**非换行**的插入**照样进公式**（在末尾打字 = 继续这段数学）——
//     这一点很重要：`$x^2$` 的光标停在 tex 末尾时打 `+1`，得到的是数学里的 `x^2+1` ✓
//
// ② ★★ **插在"语法粘合处"要挪位**（2026-10-17 加，与 `caret_sites.neutralPoint` 同一条规则）：
//    插入物与注入的光标锚点**一样**会顶掉 `^`/`_` 的结合 —— 探针实测 `\sum|^…` 打进一个字符，
//    上下限就掉到右边；`a_|i` 打进一个字符，`i` 变成普通字号（用户原话"i 被放大了"）。
//    ⇒ 落点按 `neutralPoint` 挪到**结构内部**（必要时先给裸参数补花括号，见 [InsertPlan.wrapBareArg]）。
//    ★ 这一条保证"**光标画在哪 = 打字插在哪**"。
//
// ⚠️ **已知代价（诚实记账）**：**在行间公式块内部没法再插空行** →
//    多行公式（`aligned` / `cases`）暂时写不出来。那需要先定"公式块内换行"的键位语义
//    （例如块内 `Enter` = 单个 `\n`、`Ctrl+Enter` = 断块），已记入待办（S4/S5）。
//    注意"单个 `\n`"仍然放行（`Shift+Enter` 的 `  \n` 在行间公式里是合法的），
//    被挡的只有**会产生空行**的那种。
//
// **纯 Dart，不依赖 Flutter。**

import '../core/block.dart';
import 'caret_sites.dart';
import 'math_nav.dart';

/// ★★ 规则 ④ 的产物：**载荷边界要补的换行**（见 [planInsert] 的说明）。
///
/// 为什么需要它：块模型是**按行**的 —— `$$` 必须**独占一行**才是行间公式（`BlockMarkers.isMathFence`）。
/// 粘贴一段多行文本时，如果载荷的首行/尾行是"整行语法"（`$$`、```` ``` ````、`#` 标题、列表标记、
/// 分页符），而插入点又**不在行边界**上，那两行会与用户原有的文字粘成一行 ⇒ 围栏失效 ⇒
/// 扫描时吞到下一个 `$$` ⇒ tex 里出现 `$` ⇒ `Parser Error: Can't use function '$' in math mode`
/// （2026-10-17 探针：1840 组里坏 777 组，其中行边界上也坏 113 组）。
///
/// **口径（用户 2026-10-17 拍板 = 「D 保守」）**：**只在会破坏整行语法时补**。
/// 在句子中间粘两行纯文字 → 保持"原样进门"（首行仍拼在句子上，不报错）；
/// 粘的是带 `$$` 的答案 → 自动自成一段。**绝不**无条件给每次多行粘贴加空行。
class InsertPadding {
  const InsertPadding({this.prefixNewline = false, this.suffixNewline = false});

  const InsertPadding.none()
      : prefixNewline = false,
        suffixNewline = false;

  /// 载荷**前面**要先补一个 `\n`（否则载荷首行会粘在插入点所在行的前半句后面）
  final bool prefixNewline;

  /// 载荷**后面**要先补一个 `\n`（否则载荷尾行会粘在插入点所在行的后半句前面）
  final bool suffixNewline;

  bool get any => prefixNewline || suffixNewline;

  /// 真正写进缓冲区的文本（补行边界；**仍是同一次编辑 ⇒ 一步撤销**）
  String wrap(String text) =>
      '${prefixNewline ? '\n' : ''}$text${suffixNewline ? '\n' : ''}';

  @override
  String toString() => any
      ? 'InsertPadding(${prefixNewline ? '前补\\n' : ''}'
          '${suffixNewline ? '${prefixNewline ? ' + ' : ''}后补\\n' : ''})'
      : 'InsertPadding(无)';
}

/// 一次插入的落点计划。
class InsertPlan {
  const InsertPlan(
    this.offset, {
    required this.moved,
    this.why,
    this.wrapBareArg,
    this.padding = const InsertPadding.none(),
  });

  const InsertPlan.keep(int offset)
      : this(offset, moved: false, why: null, wrapBareArg: null);

  /// 最终落点（没被调整时 = 原样）。★ 若 [wrapBareArg] 非空，这是**补完花括号之后**的偏移。
  final int offset;

  /// 落点是否被推出过（测试与探针都靠它）
  final bool moved;

  /// 为什么推（`null` = 没推）；给人读的
  final String? why;

  /// ★ 插入前要先把这段**裸参数**包上花括号（源坐标；`null` = 不用）。
  ///
  /// 为什么需要它：`a_i` 里"脚本参数"没花括号 ⇒ 往 `i` 前面插东西，插入物会**变成**那个参数
  /// （`a_xi` ⇒ `i` 掉成普通字符）。补上花括号后语义完全不变，插入物就落在参数**内部**了。
  final ({int start, int end})? wrapBareArg;

  /// ★ 载荷边界要补的换行（规则 ④；`const InsertPadding.none()` = 不补）
  final InsertPadding padding;

  /// 真正要写进缓冲区的文本（把 [padding] 应用到原文上）
  String padText(String text) => padding.wrap(text);

  @override
  String toString() => moved
      ? 'InsertPlan(→$offset, $why${wrapBareArg == null ? '' : '，补括号 $wrapBareArg'}'
          '${padding.any ? '，$padding' : ''})'
      : 'InsertPlan(保持 $offset${padding.any ? '，$padding' : ''})';
}

/// 把一次插入的落点调到"不会破坏结构不变量"的地方。
///
/// 四条规则（①② 是既有，③④ 是 2026-10-17 S4-a 的 A1 补的）：
///   ① 块级换行不许落在数学段内部；
///   ② 非换行插入不许顶掉 `^`/`_` 的结合（落点按 `neutralPoint` 挪）；
///   ③ ★ **围栏行不是多行载荷的合法落点**（`$$` 后面、换行之前那一格也不行）；
///   ④ ★ **载荷的首/尾行是"整行语法"时，把它的边界补成行边界**（见 [InsertPadding]）。
///
/// ★ **不要**在这里顺手拦"插入一个 `$`" —— 那正是用户**新建公式**的路径（打 `$` 开始一段数学），
///   拦了就没法用了。
InsertPlan planInsert(String source, int offset, String text) {
  final InsertPlan core = _planCore(source, offset.clamp(0, source.length), text);
  return _settle(source, core, text);
}

/// 规则 ①ⓞ② 的落点计算（不含 ③④ 的行边界处理）。
InsertPlan _planCore(String source, int o, String text) {
  final MathRegion? r = mathRegionAt(source, o);
  final bool hasDelim = text.contains(r'$');
  final bool nl = text.contains('\n');

  if (r != null) {
    // ★★ 规则 ⓞ：**插入点落在定界符的字符之间 ⇒ 先挪出去**（2026-10-17，全域守卫抓出）。
    //   `$$|$` 里插任何字符都会把 `$$` 配成两个单 `$` ⇒ 公式退化成源码。
    if (o < r.contentStart) {
      return InsertPlan(
        (nl || hasDelim) ? r.closeEnd : r.contentStart,
        moved: true,
        why: '插入点落在**开头定界符**里（会把 `\$` 配成单数）⇒ 挪进公式',
      );
    }
    if (o > r.contentEnd) {
      // ★ 围栏里 / 围栏**行末**都没有"公式之外"的位置（那一行末尾塞字符就不再是围栏）
      //   ⇒ 非换行、且**不带定界符**的文本落进公式内部；否则落块之后。
      return InsertPlan(
        (nl || hasDelim) ? r.closeEnd : r.contentEnd,
        moved: true,
        why: '插入点落在**结尾定界符**（或围栏行末）上 ⇒ 普通插入落进公式、'
            '含换行/`\$` 的落块之后',
      );
    }
    // ★★ 规则 ①b（2026-10-17 新）：**载荷自带 `$` ⇒ 一律推出 tex**。
    //   否则粘进去就是"公式里出现定界符"⇒ 整段退化（用户实测的 Parser Error 同一个源头）。
    //   ★ 只对**多字符**载荷生效：用户**打一个 `$`**（想新建/续写公式）仍按老行为留在原位 ——
    //     "打一半的公式"是编辑中间态，不是粘贴，不该被搬走（否则 `$x$` 里打 `$` 会变成 `$x$$`）。
    if (hasDelim && text.length > 1) {
      return InsertPlan(
        r.closeEnd,
        moved: true,
        why: '载荷自带 `\$` ⇒ 不能插进公式内部（会与既有定界符配乱）',
      );
    }
  }

  if (!text.contains('\n')) {
    // ★★ 规则 ②：非换行插入也要过"结构中性"这一关（2026-10-17）
    final InsertPlan? neutral = _neutralInsert(source, o);
    if (neutral != null) return neutral;
    return InsertPlan.keep(o);
  }

  if (r == null) return InsertPlan.keep(o); // 不在数学段里 → 正常断块

  // ★★ 规则 ①：**单行闭合的 `$$…$$` 一个换行都不许收**（收了就不再是"同行闭合"⇒ 退化）
  final bool multiLineFence =
      source.substring(r.openStart, r.contentStart).contains('\n');
  // 行间公式块（多行围栏）：只有"会产生空行"的才破（单个 `\n` 在 TeX 里合法，`aligned` 要用）
  if (r.isDisplay && multiLineFence && !_introducesBlankLine(source, o, text)) {
    return InsertPlan.keep(o);
  }

  return InsertPlan(
    r.closeEnd,
    moved: true,
    why: !r.isDisplay
        ? '行内公式不能跨行'
        : (!multiLineFence
            ? '单行闭合的 `\$\$…\$\$` 不能收换行（会退化成源码）'
            : '块级换行不能落在行间公式的 tex 里（TeX 空行 = \\par）'),
  );
}

/// 规则 ③（围栏行不可落）与 ④⑤（载荷边界补行边界）。
InsertPlan _settle(String src, InsertPlan p, String text) {
  int at = p.offset.clamp(0, src.length);
  bool moved = p.moved;
  String? why = p.why;

  // ★★ 规则 ③：落点所在的行如果是**围栏行**（`$$` / ```` ``` ````），多行载荷会把那一行撑长
  //   ⇒ 围栏不再成立 ⇒ 后续整段被当成一个数学块（tex 里出现 `$`）。
  //   ★ 只在"多行载荷 + 首行有内容"时搬（`'\n\n'`、`'  \n'` 这类以空白/换行开头的载荷不会撑长围栏行
  //     —— `$$  ⏎` 的 `trimRight()` 仍是 `$$`，所以那两种既有行为**一个字都不变**）。
  if (text.contains('\n')) {
    final String firstLine = text.substring(0, text.indexOf('\n'));
    if (firstLine.trim().isNotEmpty &&
        at > 0 &&
        src[at - 1] != '\n' &&
        _isFenceLineAt(src, at)) {
      final int after = _afterLine(src, at);
      if (after != at) {
        at = after;
        moved = true;
        why = '多行载荷落在围栏行里（会把「整行 `\$\$`」撑坏）⇒ 挪到围栏行之后';
      }
    }
  }

  // ★★ 规则 ④⑤：把载荷边界补成行边界（口径 =「D 保守」，用户 2026-10-17 拍板）
  final InsertPadding pad = padForRange(src, at, at, text);
  if (pad.any) {
    moved = true;
    why = '${why ?? '载荷边界会造出坏行（整行语法/围栏行/`\$` 粘连）'}'
        ' ⇒ 补行边界，否则会和同行文字粘成一行';
  }
  return InsertPlan(
    at,
    moved: moved,
    why: why,
    wrapBareArg: p.wrapBareArg,
    padding: pad,
  );
}

/// 区间 [start, end) 被一段多行文本替换时，载荷边界要不要补 `\n`（规则 ④⑤ 的**唯一**判据）。
///
/// 用在两处：**插入**（`start == end ==` 落点）与**选区替换**（`EditView._commitText`）。
/// 判据只看"这个边界会不会造出一个坏行"——**不**看插入点周围长什么样，
/// 这样"在句子中间粘两行纯文字"仍然原样进门（用户拍板的 D 口径）：
///
///   · **④ 整行语法**：载荷的首行/尾行是 `$$`、```` ``` ````、标题、列表、分页符
///     ⇒ 与同行文字粘在一起就不再是那个语法了；
///   · **④′ 围栏行**：载荷尾行会与**后面那一行**粘成一行，而后面那一行是围栏行
///     （典型：光标停在行首、下一行是 `$$`）⇒ 那一行的围栏会被 payload 的尾行「吃掉」；
///   · **⑤ 定界符粘连**：载荷的边缘是 `$`、紧邻处也是 `$`（`$$x=1$$` 紧贴一个 `$$`）
///     ⇒ 粘成 `$$$$` / `$$$`，配法当场就变了。
InsertPadding padForRange(String src, int start, int end, String text) {
  final bool risky =
      (text.contains('\n') || text.contains(r'$')) && text.length > 2;
  if (!risky) return const InsertPadding.none();
  final int s = start.clamp(0, src.length);
  final int e = end.clamp(s, src.length);
  final int firstNl = text.indexOf('\n');
  final String firstLine = firstNl < 0 ? text : text.substring(0, firstNl);
  final String lastLine = text.substring(text.lastIndexOf('\n') + 1);
  final bool leftDollar = s > 0 && src[s - 1] == r'$';
  final bool rightDollar = e < src.length && src[e] == r'$';
  final bool prefix = s > 0 &&
      src[s - 1] != '\n' &&
      !text.startsWith('\n') &&
      ((leftDollar && text.startsWith(r'$')) || _isBlockSyntaxLine(firstLine));
  // ★★ 规则 ⑥（2026-10-17 b2-② 手验抓到的真缺陷）：**落点正好在"整行语法行"的行首**。
  //   例：`# 例 1 一元二次方程` 的光标在 0 ⇒ 插 `$\frac{}{}$` 会粘成
  //   `$\frac{}{}$# 例 1 …` ⇒ `#` 不再在行首 ⇒ **整行标题退化成正文**（用户实测截图）。
  //   判据只多一句"右边这个位置就是某行行首，且那一行是整行语法"。
  final bool atSyntaxLineStart = (e == 0 || src[e - 1] == '\n') &&
      _isBlockSyntaxLine(_nextLineAt(src, e));
  final bool suffix = e < src.length &&
      src[e] != '\n' &&
      !text.endsWith('\n') &&
      ((rightDollar && text.endsWith(r'$')) ||
          _isBlockSyntaxLine(lastLine) ||
          _isFenceLine(_nextLineAt(src, e)) ||
          atSyntaxLineStart);
  return InsertPadding(prefixNewline: prefix, suffixNewline: suffix);
}

/// 这一行是不是"整行语法"（块的起点/边界）——`$$` 围栏、```` ``` ````、标题、列表、分页符。
///
/// ★ 判据全部借 [BlockMarkers]，与块模型**同一套**（改判据不许在这里另写一份）。
bool _isBlockSyntaxLine(String line) {
  final String l = line.trimLeft();
  if (l.isEmpty) return false;
  return BlockMarkers.isMathFence(l) ||
      BlockMarkers.isFence(l) ||
      BlockMarkers.headingLevel(l) > 0 ||
      BlockMarkers.listMarker(l) != null ||
      BlockMarkers.isPageBreak(l);
}

bool _isFenceLine(String line) =>
    BlockMarkers.isMathFence(line) || BlockMarkers.isFence(line);

/// 位置 [o] 之后那一行（`o` 之后的第一个 `\n` 之前）；文末返回空串。
String _nextLineAt(String src, int o) {
  if (o >= src.length) return '';
  int b = src.indexOf('\n', o);
  if (b < 0) b = src.length;
  return src.substring(o, b);
}

/// 位置 [o]（字符之间的缝）所在的那一行；取 `o-1` 所在行 ⇒ `o` 在行末时也算"这一行"。
String _lineAt(String src, int o) {
  final int a = o <= 0 ? 0 : src.lastIndexOf('\n', o - 1) + 1;
  int b = src.indexOf('\n', a);
  if (b < 0) b = src.length;
  return src.substring(a, b);
}

bool _isFenceLineAt(String src, int o) => _isFenceLine(_lineAt(src, o));

/// 把位置推到**下一行行首**（`o` 后面没有换行 = 文末 ⇒ 原样返回）。
int _afterLine(String src, int o) {
  final int i = src.indexOf('\n', o.clamp(0, src.length));
  return i < 0 ? o.clamp(0, src.length) : i + 1;
}

/// 插入点落在语法粘合处时，按 [neutralPoint] 给出的**中性落点**做计划；不需要调整返回 null。
InsertPlan? _neutralInsert(String source, int o) {
  final MathRegion? r = mathRegionAt(source, o);
  if (r == null) return null;
  final int rel = o - r.contentStart;
  if (rel < 0 || rel > r.tex.length) return null;
  final NeutralPoint np = neutralPoint(r.tex, rel);
  if (np.wrap == null && np.at == rel) return null;
  final ({int start, int end})? wrap = np.wrap == null
      ? null
      : (start: r.contentStart + np.wrap!.start, end: r.contentStart + np.wrap!.end);
  return InsertPlan(
    r.contentStart + np.at,
    moved: true,
    why: wrap == null
        ? '插入点紧跟 ^/_（注入物会顶掉结合关系）⇒ 挪进脚本内部'
        : '插入点在裸参数里（插入物会顶掉这个参数）⇒ 先补花括号再插进内部',
    wrapBareArg: wrap,
  );
}

/// 这次插入会不会在公式块里造出**空行**（TeX 里 = `\par`，数学模式会报错）。
bool _introducesBlankLine(String source, int o, String text) {
  if (text.contains('\n\n')) return true;
  if (!text.contains('\n')) return false;
  // 插入点紧邻已有的 `\n` → 拼起来就是一个空行
  final bool prevNl = o > 0 && source[o - 1] == '\n';
  final bool nextNl = o < source.length && source[o] == '\n';
  return prevNl || nextNl;
}
