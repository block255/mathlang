// 数语引擎 · **叶盒 ↔ 可见原子 的配对**（"点屏幕 → 源偏移"的唯一判据）
//
// 规格：《位点与结构导航》**§11.24 六**（两种坏法）＋ **§11.26 三**（盒序 ≠ 源序）。
//
// ================================ 它修的是什么 ================================
// `hit_test` 原来按下标 zip 两列（第 k 个叶盒 ↔ 第 k 个原子），判据是"两列长度相等"。
// 2026-10-17 探针量出**两种坏法**（都在这张表上收口）：
//
// | 坏法 | 实测（字号 20，真实字体） | 用户看到 |
// |---|---|---|
// | **数量** | `\sin x` = **4 叶盒 / 2 原子**（`\sin` 画成 s、i、n 三个字形盒） | 含多字母算子名的公式**点了没反应** |
// | **顺序** | `\sum_{i=1}^{n}a_i` 叶盒序 `[上限n, ∑, 下限i, =, 1, a, i]`、源序 `[∑, i, =, 1, n, a, i]` | 点 A 落 B |
//
// ============================ 引擎的真实渲染顺序（探针实测） ============================
// 读引擎源码（`_cache\pub\...\flutter_math_fork-0.7.4`）＋ 逐盒打印得到下面五条，
// **不是猜的**（数据见设计稿 §11.29）：
//
// 1. **多字母算子名 → 每个字母一个字形盒**：`mathFunctions`（32 个：`\sin` `\cos` `\log`
//    `\exp` `\deg` …）走 `_parseMathFunction`，名字被 `stringToNode('sin')` 画成 3 个字形
//    ⇒ **1 原子 ↔ N 盒**。`\limsup` 额外多一个**零高空白盒**（它是指令宏，展开成 `lim\,sup`）。
// 2. **上下标 = `MultiscriptsNode(base, sub, sup)`** ⇒ 渲染顺序 **[base, sub, sup]** ——
//    **下标永远在上标之前**，与源码里 `^`/`_` 谁先写**无关**（实测 `x^{2}_{1}` → 盒序 x, 1, 2）。
// 3. **堆叠的上下限 = `Over(Under(base, sub), sup)`** ⇒ 渲染顺序 **[sup, base, sub]**。
//    哪些算子会堆叠（`parser/tex/functions/katex_base/op.dart`）：
//    · `mathLimits` 8 个（`\det \gcd \inf \lim \max \min \Pr \sup`）—— **与样式无关**，永远堆叠；
//    · 14 个 n 元算子（`\sum \prod \coprod \bigcup … \intop \smallint`）—— **只在 display 堆叠**，
//      text 样式退回脚本位（实测 `\sum_{i=1}^{n}` 行内 = `[∑, 下限, 上限]`）。
//    · `\int` 一族**不堆叠**（走 Multiscripts）⇒ 顺序同第 2 条。
// 4. **`\sqrt[n]{body}` = [body, index]**（次数画在后面，源码里写在前面）—— 词法侧早已照此产出。
// 5. **零高盒**：`\,` 这类间距、`cases` 的列间距、`\limsup` 名内的空格**都是零高叶盒**；
//    **`\not` 一族**（`\neq`）会多出一个**空文本字形盒**（那条斜杠）。⇒ 它们不占"一个原子"。
//
// ================================ 配对怎么做 ================================
// ① `renderOrderAtoms` 把词法原子按**上面那张表**重排（"源序" → "渲染序"）；
// ② `buildLeafPairing` 顺着两列走：**一个原子吃掉它该占的那几个盒**（多字母名 = N 个），
//    并用"**盒子画的是什么字**"对账（`\sin` 的三个盒拼出来必须是 `sin`）；
// ③ 对不上就**整份判为不完整**（`complete = false`）—— 调用方退回 ③-B 的结构层落点，
//    **宁可落到"结构之前/之后"，也不许点 A 落 B**。
//
// ★ 为什么"数量相等"不再是判据：`\sin` 4 盒 2 原子是**正确**的渲染，长度相等才是特例。
//
// **纯 Dart（只用到 `Rect`）。**

import 'package:flutter/rendering.dart';

import 'caret_sites.dart';
import 'leaf_boxes.dart';
import 'visible_atoms.dart';

// ---------------------------------------------------------------------------
// 引擎事实（名单来自引擎源码，见文件头 §3）
// ---------------------------------------------------------------------------

/// **永远**把上下限放在正上/正下的算子（引擎 `mathLimits`，8 个）。
const Set<String> kAlwaysStackedOps = <String>{
  'det', 'gcd', 'inf', 'lim', 'max', 'min', 'Pr', 'sup',
};

/// **只在 display 样式**堆叠的 n 元算子（引擎 `_bigOpHandler` 的名单）。
///
/// ★★ 2026-10-17 实测纠正：**`\smallint` 在 display 下也不堆叠**（3 盒 / 3 原子，
///   按堆叠顺序对账当场失败）⇒ 已从名单里去掉。
///   同批实测：`\int_a^b` 在 display **不堆叠**（只是换更大的 ∫ 字形，高 28→50.2、
///   上下限仍在右边）—— 它在词法里是 `\int`（不在这张表里），本来就没被判成堆叠，正确。
///   `intop` 保留（没人会手打它；留着不影响任何常见写法）。
const Set<String> kDisplayStackedOps = <String>{
  'sum', 'prod', 'coprod', 'bigvee', 'bigwedge', 'biguplus', 'bigcap',
  'bigcup', 'intop', 'bigotimes', 'bigoplus', 'bigodot', 'bigsqcup',
};

/// 上下限被画在**内容之前**的结构（实测：`\overbrace{a+b}^{n}` 的盒子序是 `[n, a, +, b]`）。
const Set<String> kScriptFirstOps = <String>{'overbrace'};

/// 字形**家族**：源码里的同一个字，引擎在不同上下文会画成不同的码点，
/// 对账时必须算"同一个字"。
///
/// ★★ 2026-10-17 实测（用户报"点击判定不太对"的真因之一）：
///   普通 `|` 画的是 `∣`(U+2223)，而 **`\left|…\right|` 画的是 ASCII `|`(U+007C)**
///   ⇒ 旧的对账表只认 `∣` ⇒ `\left| x \right|` 整份配对失败 ⇒ 点击退回结构层（粗）。
const List<Set<String>> _kGlyphFamilies = <Set<String>>[
  {'∣', '|'},
  {'‖', '∥'},
  {'−', '-'},
  {'∗', '*'},
  {'′', "'"},
];

/// 两个字形是不是**同一个字**（含家族归并）
bool sameGlyph(String? expect, String? actual) {
  if (expect == null || actual == null) return false;
  if (expect == actual) return true;
  for (final Set<String> fam in _kGlyphFamilies) {
    if (fam.contains(expect) && fam.contains(actual)) return true;
  }
  return false;
}

/// 竖线族（会被**拉伸**成多段盒的那一族）
bool isBarGlyph(String? t) => t == '∣' || t == '|' || t == '‖' || t == '∥';

/// 数学模式下"源码字符 → 画出来的字"的替换表（2026-10-17 逐字探针实测）。
///
/// 这几个是**引擎做了替换**的（其余 ASCII 原样画）：
/// `-` → `−`(U+2212) · `*` → `∗`(U+2217) · `|` → `∣`(U+2223) · `'` → `′`(U+2032)。
/// 转义图形：`\{` → `{`、`\}` → `}`、`\%` → `%`、`\&` → `&`、`\#` → `#`。
///
/// ★ 只用于**对账**（见 [buildLeafPairing]）；对不上只会让这一份**退化为不完整**，
///   不会算错落点 —— 所以这张表缺一项的代价是"少一分精度"，不是"点错"。
const Map<String, String> kMathGlyphSubst = <String, String>{
  '-': '−',
  '*': '∗',
  '|': '∣',
  "'": '′',
};

/// 「这个原子**应该画成什么字**」；`null` = 不校验（符号命令、垫子）。
///
/// · 单字符原子 ⇒ 该字符（过一遍 [kMathGlyphSubst]）
/// · 转义 `\{` ⇒ 第二个字符
/// · 命令 `\alpha` ⇒ `null`（画的是 `α`，源码里没有这个字，无从对账）
/// · 命令 `\sin` ⇒ 交给"多盒尝试"（见 [buildLeafPairing]），这里不预先判
String? expectedGlyphFor(String tex, VisibleAtom a) {
  if (a.kind == 'tail' || a.kind == 'slotpad') return null;
  if (a.kind == 'esc') {
    final String c = a.start + 1 < tex.length ? tex[a.start + 1] : '';
    if (c.isEmpty || ' ,;:!'.contains(c)) return null; // `\,` `\;` `\!` 这类**没有墨迹**
    return kMathGlyphSubst[c] ?? c;
  }
  if (a.kind.startsWith(r'\')) return null; // 符号命令：画什么由引擎决定
  return kMathGlyphSubst[a.kind] ?? a.kind;
}

/// 这个原子**是垫子**（没有墨迹、只占版面）吗？
bool isPadAtom(VisibleAtom a) => a.kind == 'tail' || a.kind == 'slotpad';

/// 这个原子**有墨迹**吗？（`\,` 这类间距命令没有 ⇒ 不进配对）
///
/// ★★ 2026-10-18 晚（探针 P2 逼出来的）：**`\ `（空格命令）必须算"有墨迹"**。
///   引擎给 `\ ` 画的是一个**文本为空格的字形盒**（不是零高垫子），
///   而 `expectedGlyphFor` 对空格返回 `null`（"不必对账"）—— 旧代码把这个 `null`
///   当成了"没有墨迹"⇒ 丢掉这个原子 ⇒ **它后面每个原子都往前错一格**
///   ⇒ 整份配对不完整 ⇒ 含 `\ ` 的公式点击整体退化（实测：`\Rightarrow…\square`
///   命令形式 16 原子/16 盒，却报"还剩字形盒 □ 没配上原子"）。
///   ⇒ 判据改成"**源码里那一个字符本身是不是空白**"：是 ⇒ 它有盒、要吃一个盒（只是不校验字形）。
bool hasInk(String tex, VisibleAtom a) {
  if (isPadAtom(a)) return true;
  if (a.kind == 'esc') {
    if (expectedGlyphFor(tex, a) != null) return true;
    // `\ `：源码是反斜杠＋空格 ⇒ 引擎画得出一个空格盒
    return a.start + 1 < tex.length && tex[a.start + 1] == ' ';
  }
  return true;
}

// ---------------------------------------------------------------------------
// 渲染顺序
// ---------------------------------------------------------------------------

/// 把词法原子从**源序**重排成**引擎的渲染顺序**（规则见文件头）。
///
/// 覆盖不全（区域表降级 / 有原子没被任何区域收进去）时**原样返回源序**，
/// 由配对的对账步骤兜底（对不上 ⇒ 整份不完整）。
///
/// ★ 注意：词法本身已经处理了 `\sqrt[n]`（body 在前、次数在后），这里**不要**再动它 ——
///   否则那一条规则就有两份判据（本仓反复踩过的坑）。
List<VisibleAtom> renderOrderAtoms(String tex, {required bool displayStyle}) {
  final List<VisibleAtom> atoms = lexVisibleAtoms(tex);
  if (atoms.isEmpty) return atoms;
  final CaretSiteTable table = buildCaretSites(tex);
  if (table.degraded) return atoms;
  final List<TexRegion> roots = <TexRegion>[
    // ★ 只认**盖住整段 tex** 的那个区域当根。
    //   `path` 为空的区域不止一个：裸花括号组也是（它透明、不产生层级）——
    //   2026-10-17 之前把它们都当根 ⇒ 同一批原子被走两遍 ⇒ 重排整份被放弃。
    for (final TexRegion r in table.regions)
      if (r.path.isEmpty && r.start == 0 && r.end == tex.length) r,
  ];
  if (roots.isEmpty) return atoms;
  final _Walker w = _Walker(table, atoms, displayStyle);
  final List<int> order = <int>[];
  for (final TexRegion r in roots) {
    order.addAll(w.walk(r));
  }
  if (order.length != atoms.length) return atoms;
  final Set<int> seen = <int>{};
  for (final int i in order) {
    if (i < 0 || i >= atoms.length || !seen.add(i)) return atoms;
  }
  return <VisibleAtom>[for (final int i in order) atoms[i]];
}

class _Walker {
  _Walker(this.table, this.atoms, this.display);

  final CaretSiteTable table;
  final List<VisibleAtom> atoms;
  final bool display;

  /// 一个区域里的原子，按**渲染顺序**给出（返回值是 [atoms] 的下标）。
  List<int> walk(TexRegion r) {
    final List<int> out = <int>[];
    final List<TexItem> items = r.items;
    var i = 0;
    while (i < items.length) {
      final TexItem base = items[i];
      // 紧跟其后的 `^` / `_`（**紧邻无缝隙**才算挂在这个基座上）
      final scripts = <TexItem>[];
      var j = i + 1;
      while (j < items.length && _isScript(items[j])) {
        if (items[j].start != items[j - 1].end) break;
        scripts.add(items[j]);
        j++;
      }
      TexItem? sup;
      TexItem? sub;
      for (final TexItem s in scripts) {
        if (s.command == '^') {
          sup = s;
        } else {
          sub = s;
        }
      }
      final List<int> baseIdx = _ofItem(r, base);
      final List<int> subIdx = sub == null ? const <int>[] : _ofItem(r, sub);
      final List<int> supIdx = sup == null ? const <int>[] : _ofItem(r, sup);
      // ★ 规则 3：堆叠的上下限 ⇒ [sup, base, sub]；否则规则 2 ⇒ [base, sub, sup]
      // ★ 规则 3b（2026-10-17）：`\overbrace` 的标注画在**内容之前** ⇒ 同样 [sup, base, sub]
      if ((_stacked(base) || _scriptFirst(base)) && supIdx.isNotEmpty) {
        out
          ..addAll(supIdx)
          ..addAll(baseIdx)
          ..addAll(subIdx);
      } else {
        out
          ..addAll(baseIdx)
          ..addAll(subIdx)
          ..addAll(supIdx);
      }
      i = j;
    }
    return out;
  }

  bool _stacked(TexItem base) {
    final String? cmd = base.command;
    if (cmd == null) return false;
    if (kAlwaysStackedOps.contains(cmd)) return true;
    return display && kDisplayStackedOps.contains(cmd);
  }

  /// 上下限画在内容**之前**（`\overbrace` 一族）
  bool _scriptFirst(TexItem base) =>
      base.command != null && kScriptFirstOps.contains(base.command);

  /// 一个内容项占的原子（结构项要**递归**进它的槽区域 —— 槽里可能还有上下标/堆叠算子）。
  List<int> _ofItem(TexRegion parent, TexItem it) {
    final List<TexRegion> kids = _children(parent, it);
    if (kids.isEmpty) return _inRange(it.start, it.end);
    final List<TexRegion> sorted = List<TexRegion>.of(kids);
    // ★ 规则 4：`\sqrt[n]{body}` = [body(argIndex 0), 次数(argIndex -1)]，与源码顺序相反
    if (it.command == 'sqrt') {
      sorted.sort((TexRegion a, TexRegion b) {
        int rank(TexRegion r) {
          final int? ai = r.path.isEmpty ? null : r.path.last.argIndex;
          return ai == 0 ? 0 : (ai == -1 ? 1 : 2);
        }

        final int d = rank(a).compareTo(rank(b));
        return d != 0 ? d : a.start.compareTo(b.start);
      });
    } else {
      sorted.sort((TexRegion a, TexRegion b) => a.start.compareTo(b.start));
    }
    final List<int> out = <int>[];
    for (final TexRegion k in sorted) {
      out.addAll(walk(k));
    }
    // 结构项里"自己"可能还有原子（一般没有；有就按源序补在后面 —— 例如 `\left(` 的分隔符）
    for (final int i in _inRange(it.start, it.end)) {
      if (!out.contains(i)) out.add(i);
    }
    return out;
  }

  /// [it] 的**直接**子区域（路径比父区域多一步、且最后一步属于这个命令、**范围落在该项之内**）
  ///
  /// ★ "范围落在该项之内"这一条不能省：同一层可以有好几个同命令的脚本
  ///   （`\sum_{i=1}^{n}a_i` 里有两个 `_#0`）—— 只按命令名匹配会把**别人的**槽也收进来，
  ///   于是 `order.length != atoms.length`，重排被整份放弃（实测：`\sum` 的上下限一直没被重排）。
  List<TexRegion> _children(TexRegion parent, TexItem it) {
    if (!it.hasSlots || it.command == null) return const <TexRegion>[];
    final List<TexRegion> out = <TexRegion>[];
    for (final TexRegion r in table.regions) {
      if (r.path.length != parent.path.length + 1) continue;
      if (!_prefixOf(r.path, parent.path)) continue;
      if (r.path.last.command != it.command) continue;
      if (r.start < it.start || r.end > it.end) continue;
      out.add(r);
    }
    return out;
  }

  static bool _prefixOf(List<SlotStep> longer, List<SlotStep> prefix) {
    if (longer.length < prefix.length) return false;
    for (var k = 0; k < prefix.length; k++) {
      if (!_sameStep(longer[k], prefix[k])) return false;
    }
    return true;
  }

  static bool _sameStep(SlotStep a, SlotStep b) =>
      a.command == b.command &&
      a.argIndex == b.argIndex &&
      a.row == b.row &&
      a.col == b.col;

  List<int> _inRange(int start, int end) => <int>[
        for (var k = 0; k < atoms.length; k++)
          if (atoms[k].start >= start && atoms[k].end <= end) k,
      ];
}

bool _isScript(TexItem it) => it.command == '^' || it.command == '_';

// ---------------------------------------------------------------------------
// 配对
// ---------------------------------------------------------------------------

/// 一个配对组：**一段源区间** ↔ **一串连续的叶盒**。
///
/// 多字母算子名（`\sin`）会把 3 个盒并进**同一个组** —— 因为对用户来说它是
/// **一个字**：点 `s` 的左半 = 它之前，点 `n` 的右半 = 它之后，中间不可插入。
class PairGroup {
  const PairGroup(this.srcStart, this.srcEnd, this.boxFrom, this.boxTo, this.atom);

  final int srcStart;
  final int srcEnd;

  /// 叶盒下标区间 `[boxFrom, boxTo)`
  final int boxFrom;
  final int boxTo;

  /// 它对应的那个原子（诊断用）
  final VisibleAtom atom;

  bool containsBox(int i) => i >= boxFrom && i < boxTo;

  /// 这一组的**外框**（点左半 / 右半就是靠它判）
  Rect hull(List<LeafBox> boxes) {
    Rect r = boxes[boxFrom].rect;
    for (var i = boxFrom + 1; i < boxTo && i < boxes.length; i++) {
      r = r.expandToInclude(boxes[i].rect);
    }
    return r;
  }

  @override
  String toString() =>
      'Pair[$srcStart,$srcEnd) ↔ 盒[$boxFrom,$boxTo) ${atom.kind}';
}

/// 一份配对的结果。
class LeafPairing {
  const LeafPairing({
    required this.groups,
    required this.complete,
    this.reason,
  });

  final List<PairGroup> groups;

  /// ★ 两列**全部对上**了吗？
  /// `false` ⇒ 调用方必须退回"结构层落点"（③-B），**不许**用 [groups] 里的偏移。
  final bool complete;

  /// 不完整的原因（写给人看，会出现在测试失败信息里）
  final String? reason;

  /// 命中第 [boxIndex] 个叶盒 ⇒ 它属于哪一组（没有则 null）
  PairGroup? groupOfBox(int boxIndex) {
    for (final PairGroup g in groups) {
      if (g.containsBox(boxIndex)) return g;
    }
    return null;
  }

  @override
  String toString() => complete
      ? 'LeafPairing(${groups.length} 组 ✓)'
      : 'LeafPairing(不完整：$reason)';
}

/// ★ **唯一入口**：把两列配对起来。
///
/// [atoms] 必须是**渲染顺序**（[renderOrderAtoms] 的产物），不是词法源序。
/// [tex] 是渲染用的 tex（要它来认"这个原子画的是什么字"）。
///
/// ★★ 2026-10-18 晚（探针 P3/P4/P5 逼出来的）：**环境（矩阵 / cases）自带外框字符**。
///   `\begin{pmatrix} a & b \\ c & d \end{pmatrix}` 只写了 4 个原子，
///   但引擎画了 **6 个字形盒**（`(` `a` `b` `c` `d` `)`）—— 那两个括号**源码里没有**，
///   于是第一遍配对在"原子 `a` 期望 `a`、实际盒是 `(`"处直接判死 ⇒ 整份退化
///   ⇒ 点矩阵里任何一个格子都落到"结构之前/之后"（用户实测："矩阵那一行点不进去"）。
///   ⇒ 两遍走：
///     · 第一遍照旧（**任何现在能过的公式都不受影响**）；
///     · 只有第一遍失败时，才把"**没有任何原子认领的定界符盒**"标记为 `skip`
///       （定界符 ＋ 没有原子期望画这个字 ⇒ 它是外框，不是字符）再走一遍；
///       重试成功才采用 —— 否则照样返回第一遍的失败结果（**不掩盖**）。
LeafPairing buildLeafPairing({
  required String tex,
  required List<LeafBox> boxes,
  required List<VisibleAtom> atoms,
}) {
  final LeafPairing first =
      _pairOnce(tex: tex, boxes: boxes, atoms: atoms);
  if (first.complete) return first;

  final Set<int> frame = unclaimedDelimiterBoxes(
      tex: tex, boxes: boxes, atoms: atoms);
  if (frame.isEmpty) return first;

  final LeafPairing again =
      _pairOnce(tex: tex, boxes: boxes, atoms: atoms, skip: frame);
  if (!again.complete) return first;
  return LeafPairing(
    groups: again.groups,
    complete: true,
    reason: null,
  );
}

/// 环境外框那类"**源码里没有的盒**"：字形是定界符，且**没有原子期望画它**。
///
/// ★ 只在第一遍配对失败时才用（见 [buildLeafPairing]）——
///   `\left(…\right)` 里的括号**有**原子认领（源码里真的有两个字符），不会被误跳。
Set<int> unclaimedDelimiterBoxes({
  required String tex,
  required List<LeafBox> boxes,
  required List<VisibleAtom> atoms,
}) {
  final Set<String> expected = <String>{
    for (final VisibleAtom a in atoms)
      if (expectedGlyphFor(tex, a) != null) expectedGlyphFor(tex, a)!,
  };
  final Set<int> out = <int>{};
  for (var i = 0; i < boxes.length; i++) {
    final LeafBox b = boxes[i];
    if (b.kind != LeafBoxKind.glyph) continue;
    final String t = b.text ?? '';
    if (!kFrameDelimiters.contains(t)) continue;
    if (expected.contains(t)) continue;
    out.add(i);
  }
  return out;
}

/// 可能由"环境外框"画出来的定界符字形
const Set<String> kFrameDelimiters = <String>{
  '(', ')', '[', ']', '{', '}', '|', '∣', '‖', '∥', '⌈', '⌉', '⌊', '⌋', '⟨', '⟩',
};

LeafPairing _pairOnce({
  required String tex,
  required List<LeafBox> boxes,
  required List<VisibleAtom> atoms,
  Set<int> skip = const <int>{},
}) {
  final List<PairGroup> groups = <PairGroup>[];
  var bi = 0;
  String? reason;

  String? fail(String why) {
    reason = why;
    return null;
  }

  /// 从 [from] 起"跳过垫子 / 空字盒 / 外框盒"后数 [span] 个字形盒；不够返回 null
  ///
  /// ★ **只跳"中间"的垫子，不吞"后面"的垫子**：尾垫（`\rule{3pt}{0pt}`）本身就是一个
  ///   **垫子原子**，它紧跟在内容末尾 —— 若这里把尾随垫子也并进组里，
  ///   尾垫原子就找不到自己的盒了（实测：`\sqrt[3]{x}` 报"第 2 个是 3"）。
  ({int to, List<String> texts})? peek(int from, int span) {
    final List<String> texts = <String>[];
    var k = from;
    while (k < boxes.length && texts.length < span) {
      if (skip.contains(k)) {
        k++; // 环境外框（源码里没有这个字符）
        continue;
      }
      final LeafBox b = boxes[k];
      if (b.kind == LeafBoxKind.pad) {
        k++;
        continue; // 零高空白：不占原子
      }
      final String t = b.text ?? '';
      if (t.isEmpty) {
        k++;
        continue; // `\not` 那条斜杠：与别的字形重合，不占原子
      }
      texts.add(t);
      k++;
    }
    if (texts.length < span) return null;
    return (to: k, texts: texts);
  }

  for (final VisibleAtom a in atoms) {
    if (!hasInk(tex, a)) continue; // `\,` 这类间距命令：没有墨迹，不进配对
    while (bi < boxes.length && skip.contains(bi)) {
      bi++; // 外框盒：直接越过
    }
    if (isPadAtom(a)) {
      // 垫子原子必须落在一个**垫子盒**上（字形盒 ⇒ 说明两列已经错位了）
      while (bi < boxes.length &&
          boxes[bi].kind == LeafBoxKind.glyph &&
          (boxes[bi].text ?? '').isEmpty) {
        bi++; // 先跳过多余的"空字盒"
      }
      if (bi >= boxes.length || boxes[bi].kind != LeafBoxKind.pad) {
        fail('垫子原子 ${a.kind}[${a.start},${a.end}) 处没有垫子盒'
            '（第 $bi 个是 ${bi < boxes.length ? boxes[bi] : "越界"}）');
        break;
      }
      groups.add(PairGroup(a.start, a.end, bi, bi + 1, a));
      bi++;
      continue;
    }

    // ① 命令原子：先试"多字母名 = N 个盒"（`\sin` = 3 盒），再退回 1 盒
    final String? expect = expectedGlyphFor(tex, a);
    final String name = a.kind.startsWith(r'\') ? a.kind.substring(1) : '';
    if (expect == null && name.length > 1) {
      final ({int to, List<String> texts})? multi = peek(bi, name.length);
      if (multi != null && multi.texts.join() == name) {
        groups.add(PairGroup(a.start, a.end, bi, multi.to, a));
        bi = multi.to;
        continue;
      }
    }
    // ② 单盒
    final ({int to, List<String> texts})? one = peek(bi, 1);
    if (one == null) {
      fail('原子 ${a.kind}[${a.start},${a.end}) 没有盒了（共 ${boxes.length} 盒）');
      break;
    }
    if (expect != null && !sameGlyph(expect, one.texts.first)) {
      fail('原子 ${a.kind}[${a.start},${a.end}) 期望画 "$expect"，'
          '实际盒是 "${one.texts.first}"（第 $bi 个）');
      break;
    }
    groups.add(PairGroup(a.start, a.end, bi, one.to, a));
    final LeafBox firstBox = boxes[one.to - 1];
    bi = one.to;
    // ★★ ②b（2026-10-17）**拉伸的竖线 = 一个原子吃 N 盒**：
    //   引擎把一根竖直定界符画成**同列的多段**盒（实测 display 下 `\left|…\right|`
    //   围绕堆叠的 `\sum` 时每根竖线 **5 段** ⇒ 整份配对失败 ⇒ 点击退回结构层）。
    //   判据只有两条：**竖线族** ＋ **与第一段同一列**（横向有重叠）。
    //   ★ 不会误并两根本不相干的竖线：`|x|` 的两根 x 区间不重叠。
    if (expect != null && isBarGlyph(expect)) {
      final int from = bi;
      while (bi < boxes.length) {
        final LeafBox nb = boxes[bi];
        if (nb.kind != LeafBoxKind.glyph) break;
        if (!sameGlyph(expect, nb.text)) break;
        final bool sameCol = nb.rect.left < firstBox.rect.right - 0.5 &&
            nb.rect.right > firstBox.rect.left + 0.5;
        if (!sameCol) break;
        bi++;
      }
      if (bi > from) {
        final PairGroup merged = groups.removeLast();
        groups.add(PairGroup(
            merged.srcStart, merged.srcEnd, merged.boxFrom, bi, merged.atom));
      }
    }
  }

  if (reason == null) {
    // 剩下没被吃掉的**字形盒** ⇒ 一定错位了（垫子/空字盒/外框盒无害，允许剩下）
    for (var k = bi; k < boxes.length; k++) {
      if (skip.contains(k)) continue;
      if (boxes[k].kind != LeafBoxKind.glyph) continue;
      final String t = boxes[k].text ?? '';
      if (t.isEmpty) continue;
      // ★ 2026-10-18 晚：**纯空白的字形盒不算"剩盒"**。
      //   `\ ` `\;` 这类间距命令在不同引擎版本里有时画垫子、有时画空格字形盒；
      //   它们没有墨迹、也不对应可点的字符 ⇒ 留在末尾不该让整份配对判死。
      if (t.trim().isEmpty) continue;
      reason = '还剩字形盒 "$t"（第 $k 个）没配上原子';
      break;
    }
  }
  if (reason == null && groups.isEmpty && boxes.isNotEmpty) {
    reason = '一个组都没配上（原子 ${atoms.length} / 盒 ${boxes.length}）';
  }

  return LeafPairing(
    groups: groups,
    complete: reason == null,
    reason: reason,
  );
}
