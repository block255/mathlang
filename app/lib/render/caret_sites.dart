// 数语引擎 · 位点表（S3 地基）
//
// 规格：notes/design/位点与结构导航.md（§一 概念正名 / §二 位点表 / §2.4 三条性质）
//
// ★ 为什么要自己建：引擎的 `caretPositions` / `GreenNode.range` 是**渲染空间的编辑坐标**
//   （只覆盖渲染出来的原子，不含 `\frac{}` / `^` / `_` 等命令与结构字符），
//   实测 `\frac{a}{b}=\sqrt{2}` 给出 `[2,3)[4,5)[6,7)[8,9)` —— **根本不是源码下标**。
//   见 notes/design/技术选型与风险.md 9.8。
//
// 四个概念（不许混）：
//   offset 偏移  = L0 字符串下标（唯一真相，光标就是一个整数）
//   atom   原子  = 看得见的最小单位（`\alpha` 一个；`\frac` / `{` / `^` 都不是）
//   slot   槽    = 结构命令的一个参数位（`\frac{□}{□}` 两个）—— **位点的分组容器**
//   site   位点  = tex 里一个**合法**的光标插入位置；位点表是**有序扁平表**
//
// ★ 位点 ≠ 每个字节：`\frac{a}{b}` 里 `7`（分子后）与 `9`（分母前）是位点，
//   而 `8`（`}{` 之间）**不是** —— 往那儿插字符会得到 `\frac{a}x{b}`，语法直接坏掉。
//
// **纯 Dart，不依赖 Flutter。**

import 'visible_atoms.dart';

/// 槽路径上的一步：`\frac` 的第 0 个参数 = `SlotStep('frac', 0)`。
/// 上标 / 下标 / `\sqrt` 的可选参数用特殊 `argIndex`；多行环境带行列。
class SlotStep {
  const SlotStep(this.command, this.argIndex, {this.row, this.col});

  final String command;

  /// 参数序号；`-1` = 可选参数（`\sqrt[3]{x}` 的 `[3]`）
  final int argIndex;

  /// 多行环境才有：第几行 / 第几列（0-based）
  final int? row;
  final int? col;

  String get label => row == null
      ? '$command${argIndex < 0 ? "[opt]" : "#$argIndex"}'
      : '$command#$argIndex@$row,$col';

  @override
  String toString() => label;
}

/// 一个位点：`offset` 是**相对该段 tex** 的源偏移。
class CaretSite {
  const CaretSite(this.offset, this.path, this.indexInSlot, {this.glue = false});

  final int offset;

  /// 从主行到该位点所在槽的路径；**空 = 主行**（不在任何结构内）
  final List<SlotStep> path;

  /// 它在所属内容列表里的序号（0 = 槽首，items.length = 槽末）
  final int indexInSlot;

  /// ★★ 是不是**语法粘合处**（2026-10-17）：基座与它自己的 `^`/`_` 之间、
  /// 同一基座两个脚本之间、裸参数的内容开头。
  ///
  /// 这些位置**插入非法**（插入物会顶掉结合关系），所以注入被挪进脚本内容开头
  /// ⇒ 视觉上与"脚本的第一个位点"同一根像素 ⇒ **方向键要跳过它们**（否则像"没反应"）。
  /// 但**位点本身保留**：点击与吸附需要它（删了会让"点基座右半"吸附倒退）。
  final bool glue;

  bool get isMain => path.isEmpty;

  @override
  String toString() => 'site@$offset'
      '${path.isEmpty ? "（主行）" : "（${path.map((SlotStep s) => s.label).join(" › ")}）"}'
      '${glue ? "·粘合" : ""}';
}

/// 一个槽（参数位）在源码里的区间。
class SlotSpan {
  const SlotSpan(this.path, this.start, this.end);

  final List<SlotStep> path;

  /// 槽的**内容区间** `[start, end)`（不含 `{` `}` 本身；空槽时 `start == end`）
  final int start;
  final int end;

  bool get isEmpty => start >= end;

  @override
  String toString() =>
      '${path.map((SlotStep s) => s.label).join(" › ")}[$start,$end)${isEmpty ? " 空" : ""}';
}

/// 一个内容项（渲染出来的一"块"东西）：一段连续语法（原子 / 命令 / 结构 / 裸组）。
///
/// ★ 它是 §4.0 通则「与光标**同层**的、紧邻的那一个渲染对象」的**唯一判据来源**。
/// `command` 为空 = 裸花括号组或单字符（**透明**：渲染出来就是它自己 / 它的内容）；
/// 结构命令（`\frac` / `\sqrt` / 上下标 / 环境…）见 `smart_delete.dart` 的 `kOpaqueCommands`。
class TexItem {
  const TexItem(this.start, this.end, {this.command, required this.hasSlots});

  /// tex 里的区间 `[start, end)`；结构含它自己的收尾 `}`
  final int start;
  final int end;

  /// 结构 / 命令名（`^` / `_` 就是 `'^'` / `'_'`；裸组与单字符为 `null`）
  final String? command;

  /// 是否自带参数区域（结构 / 命令带参数 / 上下标）
  final bool hasSlots;

  @override
  String toString() =>
      'TexItem[$start,$end)${command == null ? "" : " \\$command"}${hasSlots ? " 结构" : ""}';
}

/// 一个**内容区域**（主行 / 某个槽内部 / 裸花括号组 / 环境的一格）—— "层"的载体。
///
/// `path` 空 = 主行**或裸组**（裸组**不产生层级**，见 §2.2）；
/// 非空 = 某个槽内部。同一区域里的 [items] 是**同层**的兄弟。
class TexRegion {
  const TexRegion(this.start, this.end, this.path, this.items,
      {required this.isSlot});

  /// 内容的可插入区间 `[start, end)`；空区域时 `start == end`
  final int start;
  final int end;

  final List<SlotStep> path;
  final List<TexItem> items;
  final bool isSlot;

  @override
  String toString() => 'TexRegion[$start,$end)'
      '${isSlot ? " 槽(${path.map((SlotStep s) => s.label).join(" › ")})" : " 主行/裸组"}'
      ' items=${items.length}';
}

/// 位点表。
class CaretSiteTable {
  CaretSiteTable._(
    this.tex,
    this.sites,
    this.slots,
    this.degraded,
    this.degradeReason,
    this.regions,
  );

  final String tex;

  /// **按 offset 升序、无重复**的位点表
  final List<CaretSite> sites;

  /// 全部槽（供 S3-3 邻接表使用）
  final List<SlotSpan> slots;

  /// ★ **内容区域表**：每个区域带着它**同层的兄弟项**（§4.0 通则的判据来源）。
  /// 降级位点表里为空（降级时删除退化为字节级，不用层级）。
  final List<TexRegion> regions;

  /// 是否退化为「纯字符级位点表」（配对失败时；见设计稿 §2.3）
  final bool degraded;

  final String? degradeReason;

  List<int> get offsets => <int>[for (final CaretSite s in sites) s.offset];

  int get length => sites.length;

  /// 精确查（不是位点则 null）
  CaretSite? at(int offset) {
    for (final CaretSite s in sites) {
      if (s.offset == offset) return s;
    }
    return null;
  }

  bool isSite(int offset) => at(offset) != null;

  /// 位点序下标（精确命中，否则 -1）
  int indexOf(int offset) {
    for (var k = 0; k < sites.length; k++) {
      if (sites[k].offset == offset) return k;
    }
    return -1;
  }

  /// 吸附：取**最近的合法位点**；左右等距时取**左**（与文本编辑器一致）。
  ///
  /// ★ 性质 P3：返回值必然 ∈ 位点表。
  CaretSite snap(int offset) {
    if (sites.isEmpty) {
      return CaretSite(offset.clamp(0, tex.length), const <SlotStep>[], 0);
    }
    CaretSite best = sites.first;
    var bestD = (best.offset - offset).abs();
    for (final CaretSite s in sites.skip(1)) {
      final int d = (s.offset - offset).abs();
      if (d < bestD) {
        best = s;
        bestD = d;
      }
    }
    return best;
  }

  CaretSite? nextOf(int index) =>
      (index + 1 >= 0 && index + 1 < sites.length) ? sites[index + 1] : null;

  CaretSite? prevOf(int index) =>
      (index - 1 >= 0 && index - 1 < sites.length) ? sites[index - 1] : null;

  @override
  String toString() =>
      'CaretSiteTable(${tex.length} 字符, ${sites.length} 位点, ${slots.length} 槽'
      '${degraded ? "，已降级：$degradeReason" : ""})';
}

// ---------------------------------------------------------------------------
// 构造
// ---------------------------------------------------------------------------

/// 一条结构命令的参数规格。
class _ArgSpec {
  const _ArgSpec(this.args, {this.optional = false});
  final int args;
  final bool optional;
}

/// ★ **只给真正影响导航的结构建槽**：分式族 / 根号（含可选次数）/ 上下标 / 多行环境。
/// 其余结构命令（`\overline` `\text` `\left` …）按**透明**处理 —— 不消费参数、花括号直接透传，
/// 与 `visible_atoms` 的既有行为一致；避免写一份巨大的 KaTeX 规格表（S3 范围外，S5 再细化）。
const Map<String, _ArgSpec> _kArgSpec = <String, _ArgSpec>{
  'frac': _ArgSpec(2),
  'dfrac': _ArgSpec(2),
  'tfrac': _ArgSpec(2),
  'binom': _ArgSpec(2),
  'sqrt': _ArgSpec(1, optional: true),
};

/// ★ 这些命令的**前 N 个参数不是内容**（颜色名 / 尺寸 / 间距）——整段跳过：
/// **不建槽、不建内容项**，因而也不会在里面产生位点。
///
/// ★★ 为什么必须有这条（2026-10-17 配对探针撞出来的**既有缺陷**）：
/// 注入链往 tex 里塞的是 `\textcolor{#FFFFFF}{M\rule{0.3em}{0pt}}` 与 `\rule{3pt}{0pt}`，
/// 而本解析器原来对 `\rule` 走"命令 + 第一个 `{...}` 合成一个内容项、第二个 `{...}` 当裸组"，
/// 于是渲染 tex 的区域表里出现 **两个 `path` 为空的区域**、还有一个范围算错的内容项 ——
/// `renderOrderAtoms` 因此把重排整份放弃（`\sum` 的上下限一直没被重排、尾垫原子被排到末尾）。
/// 换句话说：**注入物污染了"源码结构"的判据**，这正是本仓最怕的那一类自干扰。
///
/// 与 `visible_atoms.kNonRenderedArgCount`（那份管**原子**）是同一张表的两个视角。
const Map<String, int> _kSkipArgs = <String, int>{
  'rule': 2, // \rule{宽}{高}
  'textcolor': 1, // \textcolor{颜色}{内容} —— 内容是**后面的那个组**，照常当内容
  'color': 1, // \color{颜色}
  'hspace': 1, 'hskip': 1, 'kern': 1, 'mspace': 1, 'vspace': 1, 'vskip': 1,
};

/// ★ 这些命令**要与紧跟其后的分隔符一起看**（`\left(`、`\right)`、`\big|`）——
/// 它们与分隔符之间的位置是**语法夹缝**，不是位点（否则往那儿插字符会得到 `\left+(`，解析直接坏）。
const Set<String> _kDelimCommands = <String>{
  'left', 'right', 'middle',
  'big', 'Big', 'bigg', 'Bigg',
  'bigl', 'bigr', 'Bigl', 'Bigr', 'biggl', 'biggr', 'Biggl', 'Biggr',
};

/// 建位点表。**纯函数**：同一 tex 永远给同一张表。
CaretSiteTable buildCaretSites(String tex) => _Parser(tex).build();

/// 光标颜色（**文本侧与数学侧必须一致**）。
///
/// 数学侧只能靠 `\textcolor{...}` 注入 —— 引擎的 `\cursor{}` 用的是**当前公式的颜色**
/// （`cursor_node.dart:17` → `color: options.color`），而我们给公式传的是黑色文字色，
/// 所以裸注入 `\cursor{}` 会得到一根**黑光标**，和文本侧的蓝光标不一致（用户实测发现）。
const int kCaretColorValue = 0xFF1E88E5;

/// 给 `\textcolor` 用的十六进制写法。**由 [kCaretColorValue] 推出**，避免两处写死不一致。
final String kCaretTexColor =
    '#${(kCaretColorValue & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// **光标锚点**（`injectCursor` 插进 tex 的那一段）—— ★★ **零宽零高**。
///
/// 2026-10-15 晚改：以前这里注入的是引擎自带的 `\cursor{}`（1.5 × 14 px 的实心竖条），
/// 它**真的参与排版** ⇒ 光标一进公式就把盒子撑高/撑宽，accent 那类装饰不跟着走
/// ⇒ 用户看到的"跟上标跳起来了一样"（实测数据见 `math_caret.dart` 头部的表）。
///
/// 现在这里只放一个 **`\rule{0pt}{0pt}`**：
/// · **一个像素的版面都不占**（实测：Math 盒与不注光标时**完全相同**，连叶盒位置都逐个一样）；
/// · 它的**位置就是光标位置**，而且它就是**那一行的基线**（实测）⇒ 交给
///   [MathWithCaret] 帧末读出坐标、把竖条自绘上去（高度与文本侧一致）。
/// · 词法上 `\rule` 是结构命令 ⇒ **0 个可见原子**；渲染上是 0×0 的 `_RenderColoredBox`
///   ⇒ 被 `leaf_boxes` 的宽度下限滤掉 ⇒ 命中测试的「叶盒数 == 原子数」不受影响 ✓
///
/// ★ 仍然包在 `\textcolor{...}` 里（**虽然颜色已经不重要**，因为它不可见）：
///   注入点紧跟 `^` / `_` 时，**裸** `\rule` 会被当成**上标的参数**（把后面的字符挤到主行）
///   —— `\textcolor` 自带一个组，脚本绑在组上 ⇒ 安全（这是 2026-10-14 实测的坑）。
final String kCursorTex = '\\textcolor{$kCaretTexColor}{\\rule{0pt}{0pt}}';

/// **`\text{}` 被拆开时**插入的那一段：`}`（收掉前半） + 光标 + `\text{`（起后半）。
final String kCursorSplitTex = '}$kCursorTex\\text{';

/// 「把光标画进数学内部」的结果。
class CursorInjection {
  const CursorInjection(this.tex, this.offset);

  /// 注入光标之后的 tex（**只用于渲染**，绝不写回缓冲区）
  final String tex;

  /// 实际注入点（**已做位点吸附**，相对该段 tex）
  final int offset;

  @override
  String toString() => 'CursorInjection(@$offset)';
}

/// ★★ **结构中性**的注入点（2026-10-17 用户实测抓出，见 [neutralPoint]）。
class NeutralPoint {
  const NeutralPoint(this.tex, this.at, this.wrap);

  /// 改写后的 tex（**可能已给裸参数补上花括号**；语义不变）
  final String tex;

  /// 注入 / 插入偏移（相对 [tex]）
  final int at;

  /// 源侧要做的"给裸参数补花括号"编辑：`(start, end)` 是**原 tex** 里的裸参数区间。
  /// `null` = 不需要补。
  final ({int start, int end})? wrap;

  @override
  String toString() => 'NeutralPoint(@$at${wrap == null ? '' : ' wrap=$wrap'})';
}

/// ★★ **注入物绝不许改变语法结合**（2026-10-17，用户实测：点 `\sum` 的几格，版面整个变了）。
///
/// 探针（`\sum_{i=1}^{n}a_i`，display，Math 盒基准 **48.6 × 58.6**）：
///
/// | 位点 | 就地注入得到的 tex | Math 盒 | 后果 |
/// |---|---|---|---|
/// | 4（`\sum` 之后 = 它的上下限之前） | `\sum␣_{i=1}^{n}a_i` | **72.3 × 32.0** | 上下限**掉到右边**（"∑ 缩成一行"） |
/// | 10（下限 `}` 之后 = 上限 `^` 之前） | `\sum_{i=1}␣^{n}a_i` | **58.0 × 46.6** | 上限掉到右边 |
/// | 16（`a_i` 的裸参数之前） | `a_␣i` | 50.7 × 58.6 | `i` 变成**普通字号**（"i 被放大了"） |
///
/// ★ 根因一句话：**`^`/`_` 绑在"紧挨它前面的那个节点"上**。注入的 `\textcolor{...}{...}`
///   自带一个组 ⇒ 它一旦插在"算子 / 极限 / 裸参数"与 `^`/`_` 之间，脚本就**改绑到组上**。
///   零尺寸只保证"不占版面"，**不保证"不改变结合"** —— 这是 2026-10-15 那次"光标不参与排版"
///   只解决了一半的原因（当时只在 `x^2` 这种看得不太出来的地方验证过）。
///
/// 规则（三条，**只挪注入点，不改任何语义**）：
///   ① 位点之后紧跟 `^`/`_` ⇒ 注入进**那个脚本的内容开头**（`\sum_{␣i=1}`）；
///   ② 位点紧跟在 `^`/`_` 之后（裸参数起点）⇒ 先**给这个裸参数补花括号**，再注入到内容开头
///      （`a_␣i` → `a_{␣i}`）；
///   ③ 其它位点 ⇒ 就地注入（零尺寸锚点本来就是版面上不存在的）。
///   ★ 三种情形下"**光标画在哪**"与"**打字会插在哪**"都保持一致（插入侧走同一条规则，
///     见 `insert_guard.planInsert`）。
NeutralPoint neutralPoint(String tex, int rel) {
  final int r = rel.clamp(0, tex.length);

  // ① 位点之后紧跟 `^` / `_`
  var k = r;
  while (k < tex.length && tex[k] == ' ') {
    k++;
  }
  if (k < tex.length && (tex[k] == '^' || tex[k] == '_')) {
    var a = k + 1;
    while (a < tex.length && tex[a] == ' ') {
      a++;
    }
    if (a < tex.length && tex[a] == '{') {
      final int at = a + 1;
      return NeutralPoint(tex, at, null);
    }
    final int end = _bareArgEnd(tex, a);
    final String wrapped =
        '${tex.substring(0, a)}{${tex.substring(a, end)}}${tex.substring(end)}';
    return NeutralPoint(wrapped, a + 1, (start: a, end: end));
  }

  // ② 位点紧跟在 `^` / `_` 之后（**裸参数**的起点）
  var p = r - 1;
  while (p >= 0 && tex[p] == ' ') {
    p--;
  }
  if (p >= 0 &&
      (tex[p] == '^' || tex[p] == '_') &&
      r < tex.length &&
      tex[r] != '{') {
    final int end = _bareArgEnd(tex, r);
    final String wrapped =
        '${tex.substring(0, r)}{${tex.substring(r, end)}}${tex.substring(end)}';
    return NeutralPoint(wrapped, r + 1, (start: r, end: end));
  }

  // ③ 就地
  return NeutralPoint(tex, r, null);
}

/// 裸参数（一个原子）的结束位置：`{...}` / `\cmd` / 单字符
int _bareArgEnd(String tex, int at) {
  if (at >= tex.length) return at;
  if (tex[at] == '{') {
    final int c = _matchBrace(tex, at);
    return c < 0 ? tex.length : c + 1;
  }
  if (tex[at] == r'\') {
    var j = at + 1;
    while (j < tex.length && _isLetter(tex.codeUnitAt(j))) {
      j++;
    }
    return j <= at + 1 ? at + 1 : j;
  }
  return at + 1;
}

/// 把「光标」注入到 tex 里，**注入点先做位点吸附**。
///
/// ★ 这是"光标画进数学内部"的唯一入口（`InlineMathText` 与实验页都走它）。
///
/// 两个坑都在这一行里解决（都是实测出来的）：
/// 1. **注入点必须在合法位点上**。S1 时代的 `snapCaretInTex`（已删）只防"切开命令名"，
///    会把光标留在 `}{` 这类语法夹缝里 —— `\frac{a}{b}` 的偏移 8 会注入成 `\frac{a}\cursor{}{b}`，
///    `\frac` 的第二个参数被 `\cursor` 顶替，**分母被挤到主行**。位点吸附后落到 7 ✓。
/// 2. ★★ **注入物必须结构中性**（见 [neutralPoint]）—— 2026-10-17 前的做法只管住了"尺寸为零"，
///    没管住"不改变结合"：插在 `\sum` 与它的上下限之间，上下限就掉到右边去了（用户实测截图）。
/// 3. ★ **必须包在 `\textcolor{...}{...}` 里**，不能裸注入：`\textcolor` 自带一个组，
///    顺带把光标染成与文本侧**同一个颜色**（见 [kCaretColorValue]）。
CursorInjection injectCursor(String tex, int relOffset) {
  final int rel = buildCaretSites(tex).snap(relOffset).offset;
  final String cursor = kCursorTex; // ★ 零尺寸锚点（见它的注释）
  final _TextGroup? g = _textGroupAt(tex, rel);

  // 一般情况：先算"结构中性"的注入点，再把锚点塞进去
  if (g == null) {
    final NeutralPoint np = neutralPoint(tex, rel);
    final int at = np.at;
    return CursorInjection(
      '${np.tex.substring(0, at)}$cursor${np.tex.substring(at)}',
      at,
    );
  }

  // ★ 文本模式内：`\cursor` **不被接受**（实测 `\text{\cursor{}中文}` 等 6 种写法全部 ParseException）。
  //   做法：把这个 `\text{...}` **拆成两半**，光标落在两半之间（那里是数学模式）——
  //   `\text{中}\textcolor{...}{\rule{0pt}{0pt}}\text{文}`，实测可解析、锚点就在「中」「文」之间。
  final String before = tex.substring(g.contentStart, rel);
  final String after = tex.substring(rel, g.contentEnd);
  final StringBuffer sb = StringBuffer()..write(tex.substring(0, g.groupStart));
  if (before.isNotEmpty) sb.write('\\text{$before}');
  sb.write(cursor);
  if (after.isNotEmpty) sb.write('\\text{$after}');
  if (g.next < tex.length) sb.write(tex.substring(g.next)); // 收尾的 `}`
  return CursorInjection(sb.toString(), rel);
}

/// 一个 `\text{...}` 组的位置信息
class _TextGroup {
  const _TextGroup(this.groupStart, this.contentStart, this.contentEnd, this.next);
  final int groupStart; // `\text` 的反斜杠
  final int contentStart; // `{` 之后
  final int contentEnd; // `}` 的位置（未闭合 = tex.length）
  final int next; // 闭合 `}` 之后（未闭合 = tex.length）
}

/// 偏移是否落在某个 `\text{...}` 的内容里
_TextGroup? _textGroupAt(String tex, int offset) {
  var i = 0;
  while (i + 5 <= tex.length) {
    if (!tex.startsWith(r'\text', i)) {
      i++;
      continue;
    }
    final int after = i + 5;
    if (after < tex.length && _isLetter(tex.codeUnitAt(after))) {
      i = after; // `\textrm` / `\textstyle` 之类，不是 `\text{`
      continue;
    }
    var k = after;
    while (k < tex.length && tex[k] == ' ') {
      k++;
    }
    if (k >= tex.length || tex[k] != '{') {
      i = after;
      continue;
    }
    final int close = _matchBrace(tex, k);
    final int contentStart = k + 1;
    final int contentEnd = close < 0 ? tex.length : close;
    if (offset >= contentStart && offset <= contentEnd) {
      return _TextGroup(
        i,
        contentStart,
        contentEnd,
        close < 0 ? tex.length : close + 1,
      );
    }
    i = close < 0 ? tex.length : close + 1;
  }
  return null;
}

/// 返回与 `tex[open]`（必须是 `{`）配对的 `}` 的下标；找不到返回 -1
int _matchBrace(String tex, int open) {
  var depth = 0;
  for (var i = open; i < tex.length; i++) {
    if (tex[i] == '{') {
      depth++;
    } else if (tex[i] == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

/// 降级位点表：只用「可见原子边界 + 首尾」（纯字符级导航）。
CaretSiteTable _buildDegraded(String tex, String reason) {
  final Set<int> offs = <int>{0, tex.length};
  for (final VisibleAtom a in lexVisibleAtoms(tex)) {
    offs.add(a.start);
    offs.add(a.end);
  }
  final List<int> sorted = offs.toList()..sort();
  return CaretSiteTable._(
    tex,
    <CaretSite>[
      for (var k = 0; k < sorted.length; k++)
        CaretSite(sorted[k], const <SlotStep>[], k),
    ],
    const <SlotSpan>[],
    true,
    reason,
    const <TexRegion>[],
  );
}

// ---------------------------------------------------------------------------
// 词法
// ---------------------------------------------------------------------------

enum _K { cmd, lbrace, rbrace, sup, sub, amp, rowBreak, ch }

class _Tok {
  _Tok(this.kind, this.start, this.end, [this.name = '']);
  final _K kind;
  final int start;
  final int end;
  final String name; // 仅 cmd（不含反斜杠）
}

bool _isLetter(int c) => (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

List<_Tok> _tokenize(String tex) {
  final List<_Tok> out = <_Tok>[];
  var i = 0;
  while (i < tex.length) {
    final String c = tex[i];
    if (c == r'\') {
      if (i + 1 < tex.length && tex[i + 1] == r'\') {
        out.add(_Tok(_K.rowBreak, i, i + 2)); // `\\` 行分隔
        i += 2;
        continue;
      }
      if (i + 1 < tex.length && _isLetter(tex.codeUnitAt(i + 1))) {
        var j = i + 1;
        while (j < tex.length && _isLetter(tex.codeUnitAt(j))) {
          j++;
        }
        out.add(_Tok(_K.cmd, i, j, tex.substring(i + 1, j)));
        i = j;
        continue;
      }
      if (i + 1 < tex.length) {
        out.add(_Tok(_K.ch, i, i + 2)); // `\{` `\,` 等转义：算一个可见字符
        i += 2;
        continue;
      }
      i++; // 孤立反斜杠：跳过
      continue;
    }
    switch (c) {
      case '{':
        out.add(_Tok(_K.lbrace, i, i + 1));
      case '}':
        out.add(_Tok(_K.rbrace, i, i + 1));
      case '^':
        out.add(_Tok(_K.sup, i, i + 1));
      case '_':
        out.add(_Tok(_K.sub, i, i + 1));
      case '&':
        out.add(_Tok(_K.amp, i, i + 1));
      case ' ':
      case '\n':
      case '\t':
        break; // 空白既不产出内容、也不产出位点
      default:
        out.add(_Tok(_K.ch, i, i + 1));
    }
    i++;
  }
  return out;
}

// ---------------------------------------------------------------------------
// 语法：内容项 / 内容列表
// ---------------------------------------------------------------------------

/// 一个内容项（渲染出来的一"块"东西），可自带子槽。
class _Item {
  _Item(this.start, this.end, [this.slots = const <_Region>[], this.cmd]);
  final int start;
  final int end;
  final List<_Region> slots;

  /// 结构 / 命令名（`^` / `_` 就是它们自己；裸组与单字符为 `null`）—— 供"可见对象"判定用
  final String? cmd;
}

/// 一个**内容列表**（主行 / 某槽内部 / 环境的一格）。
class _Region {
  _Region(
    this.start,
    this.end,
    this.path,
    this.items, {
    this.isSlot = false,
    this.isBareArg = false,
  });

  /// 内容的可插入区间 `[start, end)`；空槽时 `start == end`
  final int start;
  final int end;
  final List<SlotStep> path;
  final List<_Item> items;

  /// 是否是"导航意义上的槽"（命令参数 / 上下标 / 环境格）。
  /// 裸花括号组 `{...}` 也是区域，但**不算槽**（不产生层级，只是括起来）。
  final bool isSlot;

  /// ★ **裸参数**槽（`a_i` 的 `i`、`x^2` 的 `2`、`\frac12` 的 `2`）：
  /// 它的"内容开头"**不是位点** —— 往那儿插东西，插入物会**变成**那个参数
  /// （`a_|i` 打一个字符 ⇒ `i` 掉成普通字号）。要进这个参数，先打字（会自动补花括号）。
  final bool isBareArg;
}

class _Parser {
  _Parser(this.tex) : _toks = _tokenize(tex);

  final String tex;
  final List<_Tok> _toks;
  int _i = 0;

  bool _degraded = false;
  String? _degradeReason;
  final List<_Region> _slots = <_Region>[];

  /// 所有"粘合处"的偏移（见 [CaretSite.glue]）
  final Set<int> _glueOffsets = <int>{};

  // ---------- 入口 ----------

  CaretSiteTable build() {
    final List<_Item> items = _parseItems((_) => false);
    if (_degraded) return _buildDegraded(tex, _degradeReason ?? '配对失败');
    final _Region root = _Region(0, tex.length, const <SlotStep>[], items);
    final List<CaretSite> raw = <CaretSite>[];
    _emit(root, raw);
    final List<TexRegion> regions = <TexRegion>[];
    _collectRegions(root, regions);
    final List<SlotSpan> slots = _withFullPaths(<SlotSpan>[
      for (final _Region r in _slots) SlotSpan(r.path, r.start, r.end),
    ]);
    return CaretSiteTable._(
      tex,
      _dedupe(<CaretSite>[
        for (final CaretSite s in raw)
          CaretSite(
            s.offset,
            _fullPathAt(slots, s),
            s.indexInSlot,
            // ★ "粘合处"是**这个偏移**的性质，不是某一次发射的性质 ——
            //   `_dedupe` 只按 offset 去重，所以这里按偏移统一补上（否则标记会丢）。
            glue: s.glue || _glueOffsets.contains(s.offset),
          ),
      ]),
      List<SlotSpan>.unmodifiable(slots),
      false,
      null,
      List<TexRegion>.unmodifiable(regions),
    );
  }

  /// 导出「内容区域 → 同层内容项」的层级表（§4.0 通则的唯一判据）。
  void _collectRegions(_Region r, List<TexRegion> out) {
    out.add(TexRegion(
      r.start,
      r.end,
      r.path,
      <TexItem>[
        for (final _Item it in r.items)
          TexItem(it.start, it.end, command: it.cmd, hasSlots: it.slots.isNotEmpty),
      ],
      isSlot: r.isSlot,
    ));
    for (final _Item it in r.items) {
      for (final _Region s in it.slots) {
        _collectRegions(s, out);
      }
    }
  }

  /// 把「单步路径」补成**从根到该槽的完整链**。
  ///
  /// ★ 为什么需要（2026-10-14 S3-3 实测发现）：解析器建槽时只记了"我是谁的哪个参数"
  /// （`SlotStep('frac', 0)`），**没把祖先拼进去** → 同一公式里
  /// `\frac{a}{b}+\frac{c}{d}` 的两个分子路径**完全一样**，槽序与竖直邻接就分不开了。
  ///
  /// 槽区间天然是**嵌套包含**的（子槽的 `[start,end]` 一定被父槽含住），
  /// 所以按包含关系补父链既简单又不会错：祖先 = 严格包含我的那些槽，外层在前。
  List<SlotSpan> _withFullPaths(List<SlotSpan> spans) {
    final List<SlotSpan> out = <SlotSpan>[];
    for (final SlotSpan s in spans) {
      final List<SlotSpan> ancestors = <SlotSpan>[
        for (final SlotSpan o in spans)
          if (_sameArgs(o, s) == false && _contains(o, s)) o,
      ]..sort((SlotSpan a, SlotSpan b) => a.start.compareTo(b.start));
      out.add(SlotSpan(
        <SlotStep>[
          for (final SlotSpan a in ancestors) a.path.last,
          s.path.last,
        ],
        s.start,
        s.end,
      ));
    }
    return out;
  }

  bool _contains(SlotSpan outer, SlotSpan inner) =>
      outer.start <= inner.start &&
      outer.end >= inner.end &&
      (outer.start < inner.start || outer.end > inner.end);

  bool _sameArgs(SlotSpan a, SlotSpan b) =>
      a.start == b.start && a.end == b.end && a.path.last == b.path.last;

  /// 某个位点的完整槽路径 = **含住它的最内层槽**的路径（不含任何槽 → 主路径 `[]`）
  List<SlotStep> _fullPathAt(List<SlotSpan> slots, CaretSite s) {
    SlotSpan? best;
    for (final SlotSpan sp in slots) {
      if (s.offset < sp.start || s.offset > sp.end) continue;
      if (best == null || sp.path.length > best.path.length) best = sp;
    }
    return best?.path ?? s.path;
  }

  /// 按 offset 升序；同 offset **保留路径更深的那一个**（更具体的那层语义）。
  ///
  /// 例：`a{}b` 的 offset 2 既是「空槽内部」又是「组与 b 之间」——
  /// tex 里往 2 插字符得到的正是 `a{x}b`（进了空槽），所以深路径才是对的。
  List<CaretSite> _dedupe(List<CaretSite> raw) {
    raw.sort((CaretSite a, CaretSite b) {
      final int c = a.offset.compareTo(b.offset);
      if (c != 0) return c;
      return b.path.length.compareTo(a.path.length);
    });
    final List<CaretSite> out = <CaretSite>[];
    for (final CaretSite s in raw) {
      if (out.isNotEmpty && out.last.offset == s.offset) continue;
      out.add(s);
    }
    return List<CaretSite>.unmodifiable(out);
  }

  /// 位点发射：区域两端 + 每个内容项的两端；空区域只有一个位点。
  ///
  /// ★★ 2026-10-17：**"插入非法的粘合处"不再产生位点**（用户用 `→` 扫出来的三处"没反应"）：
  ///   · 基座与**紧跟它的** `^`/`_` 之间（`\sum` 与 `_{…}`）：往那儿插字符会顶掉结合关系；
  ///   · 同一个基座的两个脚本之间（`_{i=1}` 与 `^{n}`）：同上；
  ///   · **裸参数**的内容开头（`a_i` 的 `i` 前）：插入物会**变成**那个参数。
  ///   这三处的注入/插入已经被 `neutralPoint` / `planInsert` 挪走，于是"位点在数据上不同、
  ///   屏幕上却是同一根像素" ⇒ 用户按 `→` 看到"没反应"。**按 §2.2 的原则（位点 = 合法插入位置）
  ///   它们本来就不该是位点**；去掉之后每一次 `→` 都有可见变化。
  /// 位点发射：区域两端 + 每个内容项的两端；空区域只有一个位点。
  ///
  /// ★★ 2026-10-17：**"粘合处"的位点要标出来**（用户用 `→` 扫出三处"没反应"）：
  ///   · 基座与**紧跟它的** `^`/`_` 之间（`\sum` 与 `_{…}`）；
  ///   · 同一个基座的两个脚本之间（`_{i=1}` 与 `^{n}`）；
  ///   · **裸参数**的内容开头（`a_i` 的 `i` 前）。
  ///   这三处的注入/插入都被 `neutralPoint` 挪进了"脚本内容开头"⇒ 视觉上与
  ///   脚本自己的第一个位点**同一根像素** ⇒ 按 `→` 看着像"没反应"。
  ///   ⇒ 位点**照旧保留**（点击/吸附要靠它，删了会让"点基座右半"吸附**倒退**），
  ///   只在**方向键**上跳过（`math_nav.next/prevCaretOffset`）。
  void _emit(_Region r, List<CaretSite> out) {
    // ★ 裸参数的"内容开头"**不是**粘合位点：它是那个脚本自己的第一格
    //   （旁边那个"基座与脚本之间"才是粘合位点，它被跳过之后这里就成了唯一的停靠）。
    out.add(CaretSite(r.start, r.path, 0));
    out.add(CaretSite(r.end, r.path, r.items.length));
    for (var k = 0; k < r.items.length; k++) {
      final _Item it = r.items[k];
      final bool glueBefore = k > 0 &&
          _isScriptItem(it) &&
          it.start == r.items[k - 1].end;
      final bool glueAfter = k + 1 < r.items.length &&
          _isScriptItem(r.items[k + 1]) &&
          r.items[k + 1].start == it.end;
      if (glueBefore) _glueOffsets.add(it.start);
      if (glueAfter) _glueOffsets.add(it.end);
      out.add(CaretSite(it.start, r.path, k, glue: glueBefore));
      out.add(CaretSite(it.end, r.path, k + 1, glue: glueAfter));
    }
    for (final _Item it in r.items) {
      for (final _Region s in it.slots) {
        _emit(s, out);
      }
    }
  }

  /// `^` / `_`（脚本项）
  static bool _isScriptItem(_Item it) =>
      it.cmd == '^' || it.cmd == '_';

  // ---------- 内容列表 ----------

  List<_Item> _parseItems(bool Function(_Tok) stop) {
    final List<_Item> out = <_Item>[];
    while (_i < _toks.length && !stop(_toks[_i])) {
      final _Tok t = _toks[_i];
      switch (t.kind) {
        case _K.rbrace:
          // 没有配对的 `}` → 配对失败 → 降级（设计稿 §2.3）
          _degraded = true;
          _degradeReason = '多余的 `}`（偏移 ${t.start}）';
          _i++;
        case _K.cmd:
          out.add(_parseCmd(t));
        case _K.sup:
        case _K.sub:
          out.add(_parseScript(t));
        case _K.lbrace:
          out.add(_parseGroup(t));
        case _K.amp:
        case _K.rowBreak:
          _i++; // 顶层出现的分隔符：跳过
        case _K.ch:
          out.add(_Item(t.start, t.end));
          _i++;
      }
    }
    return out;
  }

  /// 裸花括号组 `{...}`：是区域，但**不算槽**（路径透传给父层）。
  _Item _parseGroup(_Tok open) {
    _i++; // 吃掉 `{`
    final List<_Item> items = _parseItems((_Tok t) => t.kind == _K.rbrace);
    final bool closed = _i < _toks.length && _toks[_i].kind == _K.rbrace;
    final int interiorEnd = closed ? _toks[_i].start : tex.length;
    if (closed) _i++;
    final _Region region =
        _Region(open.end, interiorEnd, const <SlotStep>[], items);
    return _Item(
      open.start,
      closed ? interiorEnd + 1 : tex.length,
      <_Region>[region],
    );
  }

  /// 命令：只给 `_kArgSpec` 里的建槽，其余**透明**（不消费参数）。
  _Item _parseCmd(_Tok t) {
    if (t.name == 'begin') return _parseEnv(t);
    if (t.name == 'end') {
      _i++;
      _readGroupName(); // 孤儿 `\end{...}`：跳过
      return _Item(t.start, t.end, const <_Region>[], t.name);
    }
    // ★ 参数不是内容的命令（`\rule{宽}{高}` / `\textcolor{颜色}{内容}`）：
    //   把那些参数**整段跳过**（只走 token，不建槽也不建项）—— 理由见 [_kSkipArgs]。
    final int? skip = _kSkipArgs[t.name];
    if (skip != null) {
      _i++;
      var end = t.end;
      for (var k = 0; k < skip; k++) {
        if (_i >= _toks.length || _toks[_i].kind != _K.lbrace) break; // 裸参数不处理
        end = _skipTokenGroup();
      }
      return _Item(t.start, end, const <_Region>[], t.name);
    }
    final _ArgSpec? spec = _kArgSpec[t.name];
    if (spec == null) {
      _i++;
      // `\left(` / `\right)` / `\big|`：分隔符属于结构命令，两者之间的夹缝不是位点
      if (_kDelimCommands.contains(t.name) && _i < _toks.length) {
        final int e = _toks[_i].end;
        _i++;
        return _Item(t.start, e, const <_Region>[], t.name);
      }
      // ★ 命令后紧跟 `{...}` → 那是它的**参数**，必须合成为一个内容项。
      //   否则"命令与参数之间"会变成一个位点，往那儿注入会让命令吃掉注入内容 ——
      //   实测 `\text{中文}` 的偏移 5 注入成 `\text\textcolor{...}{\cursor{}}{中文}` → 解析失败。
      //   （对 `\alpha{x}` 这种"命令本来不吃参数"的写法，合并只是少一个位点，无副作用。）
      if (_i < _toks.length && _toks[_i].kind == _K.lbrace) {
        final _Item it = _parseArgItem(t.name, 0);
        return _Item(t.start, it.end, it.slots, t.name);
      }
      return _Item(t.start, t.end, const <_Region>[], t.name);
    }
    _i++;
    var end = t.end;
    final List<_Region> slots = <_Region>[];

    if (spec.optional && _isOpenBracket(_i)) {
      final _Item it = _parseBracketArg(t.name);
      slots.addAll(it.slots);
      end = it.end;
    }
    for (var k = 0; k < spec.args; k++) {
      if (_i >= _toks.length) break; // 参数还没打（打字中间态）→ 容忍
      final _Item it = _parseArgItem(t.name, k);
      slots.addAll(it.slots);
      end = it.end;
    }
    return _Item(t.start, end, slots, t.name);
  }

  bool _isOpenBracket(int at) =>
      at < _toks.length &&
      _toks[at].kind == _K.ch &&
      tex[_toks[at].start] == '[';

  /// **只走 token** 地跳过一个 `{...}` 组（当前位置必须是 `{`），返回它 `}` 的结束偏移。
  ///
  /// 与 [_parseGroup] 的区别：不建区域、不建内容项 —— 给"参数不是内容"的命令用
  /// （`\rule{宽}{高}`、`\textcolor{颜色}{内容}` 的第一个参数，见 [_kSkipArgs]）。
  int _skipTokenGroup() {
    var depth = 0;
    var end = tex.length;
    while (_i < _toks.length) {
      final _Tok t = _toks[_i];
      if (t.kind == _K.lbrace) {
        depth++;
      } else if (t.kind == _K.rbrace) {
        depth--;
        _i++;
        if (depth <= 0) return t.end;
        continue;
      }
      end = t.end;
      _i++;
    }
    return end;
  }

  /// `\sqrt[3]{x}` 的可选参数 `[3]`
  _Item _parseBracketArg(String command) {
    final _Tok open = _toks[_i];
    _i++;
    final List<_Item> items =
        _parseItems((_Tok k) => k.kind == _K.ch && tex[k.start] == ']');
    final bool closed = _i < _toks.length &&
        _toks[_i].kind == _K.ch &&
        tex[_toks[_i].start] == ']';
    final int interiorEnd = closed ? _toks[_i].start : tex.length;
    if (closed) _i++;
    final _Region r = _Region(
      open.end,
      interiorEnd,
      <SlotStep>[SlotStep(command, -1)],
      items,
      isSlot: true,
    );
    _slots.add(r);
    return _Item(open.start, closed ? interiorEnd + 1 : tex.length, <_Region>[r]);
  }

  /// 一个参数位：`{...}` 组，或单个原子 token（`\frac12` 这种紧凑写法）。
  _Item _parseArgItem(String command, int argIndex) {
    final List<SlotStep> path = <SlotStep>[SlotStep(command, argIndex)];
    final _Tok t = _toks[_i];

    if (t.kind == _K.lbrace) {
      _i++;
      final List<_Item> items = _parseItems((_Tok k) => k.kind == _K.rbrace);
      final bool closed = _i < _toks.length && _toks[_i].kind == _K.rbrace;
      final int interiorEnd = closed ? _toks[_i].start : tex.length;
      if (closed) _i++;
      final _Region r = _Region(t.end, interiorEnd, path, items, isSlot: true);
      _slots.add(r);
      return _Item(
        t.start,
        closed ? interiorEnd + 1 : tex.length,
        <_Region>[r],
      );
    }

    final _Item inner = _parseSingle();
    final _Region r = _Region(inner.start, inner.end, path, <_Item>[inner],
        isSlot: true, isBareArg: true);
    _slots.add(r);
    return _Item(inner.start, inner.end, <_Region>[r]);
  }

  /// 上标 / 下标：`^{...}` `^x`
  _Item _parseScript(_Tok t) {
    final String name = t.kind == _K.sup ? '^' : '_';
    _i++;
    if (_i >= _toks.length) return _Item(t.start, t.end, const <_Region>[], name);
    final _Item it = _parseArgItem(name, 0);
    return _Item(t.start, it.end, it.slots, name);
  }

  /// 单个原子（命令 / 字符 / 组）—— 供单 token 参数使用
  _Item _parseSingle() {
    final _Tok t = _toks[_i];
    switch (t.kind) {
      case _K.lbrace:
        return _parseGroup(t);
      case _K.cmd:
        return _parseCmd(t);
      case _K.sup:
      case _K.sub:
        return _parseScript(t);
      case _K.ch:
      case _K.rbrace:
      case _K.amp:
      case _K.rowBreak:
        _i++;
        return _Item(t.start, t.end);
    }
  }

  // ---------- 多行环境 ----------

  /// `\begin{aligned} 格 & 格 \\ 格 & 格 \end{aligned}`
  /// 按 `&`（列）与 `\\`（行）切成若干**格**，每格是一个槽（S5 的行列导航靠它）。
  _Item _parseEnv(_Tok begin) {
    _i++; // 吃掉 begin
    final String envName = _readGroupName();
    final String label = envName.isEmpty ? 'env' : envName;
    final List<_Region> cells = <_Region>[];
    var row = 0;
    var col = 0;
    var cellStart = _i < _toks.length ? _toks[_i].start : tex.length;
    var end = begin.end;

    while (true) {
      final List<_Item> items = _parseItems((_Tok t) =>
          t.kind == _K.amp ||
          t.kind == _K.rowBreak ||
          (t.kind == _K.cmd && t.name == 'end'));

      final int cellEnd = _i < _toks.length ? _toks[_i].start : tex.length;
      final _Region r = _Region(
        cellStart,
        cellEnd,
        <SlotStep>[SlotStep(label, 0, row: row, col: col)],
        items,
        isSlot: true,
      );
      cells.add(r);
      _slots.add(r);

      if (_i >= _toks.length) {
        end = tex.length; // 未闭合的环境：吃到文末（打字中间态）
        break;
      }
      final _Tok t = _toks[_i];
      if (t.kind == _K.cmd && t.name == 'end') {
        _i++;
        _readGroupName();
        end = _i > 0 ? _toks[_i - 1].end : t.end;
        break;
      }
      _i++; // 吃掉 `&` 或 `\\`
      cellStart = t.end;
      if (t.kind == _K.rowBreak) {
        row++;
        col = 0;
      } else {
        col++;
      }
    }
    return _Item(begin.start, end, cells, 'begin');
  }

  /// 读 `{name}`（吃掉整组），返回组内原始文本
  String _readGroupName() {
    if (_i >= _toks.length || _toks[_i].kind != _K.lbrace) return '';
    _i++;
    final StringBuffer sb = StringBuffer();
    while (_i < _toks.length && _toks[_i].kind != _K.rbrace) {
      final _Tok t = _toks[_i];
      sb.write(tex.substring(t.start, t.end));
      _i++;
    }
    if (_i < _toks.length) _i++; // 吃掉 `}`
    return sb.toString();
  }
}
