// 数语引擎 · 结构感知删除（S3-4 · smart delete）
//
// 规格：notes/design/位点与结构导航.md §四。目标手感：**像删字符一样干脆，但永不留下半个坏公式**。
//
//   §4.0 ★★ 通则（2026-10-15 定，用户提出）—— 删除目标 =
//        **与光标【同层】的、紧邻的那一个渲染对象**（「同层」= 落在同一个内容区域里）：
//          · 同层紧邻的是**原子**      → 删那个原子（`\alpha` 五个字符一次删光）
//          · 同层紧邻的是**结构**      → ★ **整个结构，含它的内容**（`\frac{a}{b}` 一次走）
//          · 同层紧邻的是**算子 + 作用域** → 整个操作对象（作用域表 §4.7 —— ⏳ **尚未实现**；
//            当前只由"紧跟其后的脚本属于它"这条**代理**，见 `_trailingScriptsEnd`）
//          · 同层**什么都没有**（空槽） → ★ **只移动**（等同方向键；**绝不连坐**删掉结构）
//          · `$` / `{}` 这类**不可见定界符** → **不是对象**，永远不是删除目标
//   §4.1 原子删除（含 4.1.1 的脚本规则：`^`/`_` 与它的参数**同生共死**）
//   §4.2 区域首 / 区域末 → **只跳不删**（跨结构墙靠方向键，不靠退格拆）
//   §4.4 降级模式 —— 配对失败 → 退化为**字节级**（笨但可预测）
//   §4.5 与 normalize 分工 —— 本文件**不做回收**，多余花括号 / 空结构只在提交点清（§七）
//
// ★★ 2026-10-15 改口径（① 删除对象收口）：
//   · 旧 §4.3「全空才删」判据（`u.allEmpty && u.end == r`）**作废** ——
//     它只在 tex 末尾那**一个**位点可达，直接造成「删不掉根号」（设计稿 §11.16 六）。
//   · 旧实现用"最近的**可见原子**"找邻居（`_atomLeftOf`）—— **不带层级** ⇒
//     在"分式整体之后"退格会删掉分母里的 `b`（用户实测抓出）⇒ 现在按**同层**找。
//   · 「结构在它自己那一层上被整体删」与「空槽里只移动」这两条，都由同层规则**自然给出**。
//
// ★ 本文件是**纯函数**，只在「一个数学段的 tex + 段内相对偏移」这一层工作。
//   文档级边界（公式首/公式尾、空壳要不要连定界符一起删）由 `math_nav.dart` 处理。
//
// **纯 Dart，不依赖 Flutter。**

import 'attachment.dart';
import 'caret_sites.dart';
import 'projection.dart' show isAsciiLetter;
import 'scope_table.dart';
import 'site_adjacency.dart';
import 'visible_atoms.dart';

/// 一次删除的处置结果。
class SmartEdit {
  const SmartEdit._(this.caret, this.from, this.to);

  /// **只把光标挪走**，不删任何东西（§4.2 区域首/末跨越）
  const SmartEdit.move(int caret) : this._(caret, null, null);

  /// 删掉 `[from, to)`，光标落到 [caret]
  const SmartEdit.remove(int from, int to, int caret) : this._(caret, from, to);

  /// 什么都不做（段内已无可删 —— 边界语义交给 `math_nav.dart`）
  static const SmartEdit none = SmartEdit._(-1, null, null);

  /// 处理后的段内相对光标（`none` 时为 -1）
  final int caret;

  /// 要删的区间（`null` = 不删，只是移动）
  final int? from;
  final int? to;

  bool get deletes => from != null;
  bool get isNone => caret < 0 && from == null;
  bool get isMove => caret >= 0 && from == null;

  @override
  String toString() => isNone
      ? 'SmartEdit.none'
      : isMove
          ? 'SmartEdit.move→$caret'
          : 'SmartEdit.remove[$from,$to)→$caret';
}

/// 一个「结构实例」：一个结构命令（或 `^`/`_`）+ 它的全部参数槽。
///
/// ★ 现在**只有 `normalize`（提交点回收）用它**；删除侧已改用「同层内容项」判据
///   （见 [TexItem] / [TexRegion]）。
class StructureUnit {
  const StructureUnit(this.start, this.end, this.slots);

  /// 结构起点（`\` 或 `^`/`_`）
  final int start;

  /// 结构终点（最后一个参数的收尾 `}` 之后）
  final int end;

  final List<SlotSpan> slots;

  /// **全空**（提交点回收的判据，§七）
  bool get allEmpty => slots.isNotEmpty && slots.every((SlotSpan s) => s.isEmpty);

  @override
  String toString() => 'Structure[$start,$end) slots=${slots.length}'
      '${allEmpty ? ' 全空' : ''}';
}

/// 枚举 tex 里所有结构实例（按起点升序）。
///
/// 同一次结构调用的多个参数（如 `\frac` 的分子分母）算**同一个实例** ——
/// 靠 [callSlotsAround]（同路径 ＋ 相邻槽之间只有语法粘合剂）聚合。
///
/// ★★ **2026-10-17 修掉的身份判据**（《位点》§11.24 六① 记的账）：
/// 原来用 `_instanceKey(path)` = 「父路径 + 命令 + 行列」当实例身份 ——
/// 而同一层里**两个 `\frac` 的槽路径完全一样**（`SlotStep` 只有命令 + 参数号，不含位置），
/// 于是 `\frac{a}{b}+\frac{c}{d}` 实测只返回**一个**实例、而且那个实例
/// **横跨两个分式**（[0,23)）⇒ normalize 会把中间的 `+` 一起回收。
///
/// ⇒ 身份改成 **实例在源码里的起点**（[structureStartInfo] 解出来的偏移），
///   而"哪些槽属于同一次调用"改用 [callSlotsAround]。
List<StructureUnit> structureUnits(CaretSiteTable t) {
  if (t.degraded) return const <StructureUnit>[];
  final Set<String> seen = <String>{};
  final List<StructureUnit> out = <StructureUnit>[];
  for (final SlotSpan s in t.slots) {
    if (s.path.isEmpty) continue;
    final List<SlotSpan> inst = callSlotsAround(t, s);
    if (inst.isEmpty) continue;
    var first = inst.first.start;
    var last = _extentEnd(t.tex, inst.first.end);
    for (final SlotSpan x in inst) {
      if (x.start < first) first = x.start;
      final int e = _extentEnd(t.tex, x.end);
      if (e > last) last = e;
    }
    final StructureStart? start = structureStartInfo(t.tex, first);
    if (start == null) continue;
    final String key =
        '${_pathKey(s.path.sublist(0, s.path.length - 1))}@${start.at}';
    if (!seen.add(key)) continue;
    var end = last;
    if (start.envName != null) {
      // 环境（`\begin{cases}…`）：范围必须盖到 `\end{cases}`，否则回收会留下一个孤儿 `\end`
      final int e = environmentEnd(t.tex, start.envName!, last);
      if (e > end) end = e;
    }
    out.add(StructureUnit(start.at, end, inst));
  }
  out.sort((StructureUnit a, StructureUnit b) => a.start.compareTo(b.start));
  return out;
}

// ---------------------------------------------------------------------------
// ★★ 「渲染成一个整体」的结构命令（§4.0 通则第 2 行）
// ---------------------------------------------------------------------------

/// 判据是**渲染出来的形态**：分式 / 根号 / 上下限有**二维偏移**，accent 有**装饰**，
/// 环境有**框** ⇒ 整段在屏幕上就是**一个东西**。
///
/// 而 `\text{}` / `\mathrm{}` 这类**透明包装**渲染出来只是它的内容 ⇒ 删的是**内容里的**东西。
///
/// ⚠️ **保守原则：名单外的命令按"透明"处理** —— 那至多多按一次退格，
/// 绝不会把周围的东西误删（比反过来安全）。
const Set<String> kOpaqueCommands = <String>{
  // 分式族 / 二项式 / 根号（真正的二维结构）
  'frac', 'dfrac', 'tfrac', 'cfrac', 'genfrac',
  'binom', 'dbinom', 'tbinom', 'choose', 'brack', 'brace',
  'sqrt',
  // 装饰 / 覆盖类（渲染出来带一条线/一个帽子）
  'overline', 'underline', 'vec', 'hat', 'widehat', 'bar', 'dot', 'ddot',
  'tilde', 'widetilde', 'check', 'breve', 'acute', 'grave', 'mathring',
  'overbrace', 'underbrace', 'overbracket', 'underbracket',
  'overrightarrow', 'overleftarrow', 'overleftrightarrow',
  'underrightarrow', 'underleftarrow', 'underleftrightarrow',
  'overgroup', 'undergroup', 'overlinesegment', 'underlinesegment',
  // 堆叠 / 上下关系
  'substack', 'overset', 'underset', 'stackrel', 'pmb', 'boxed', 'fbox',
  'cancel', 'bcancel', 'xcancel', 'sout', 'angl', 'tag',
  // 多行环境（整块）
  'begin',
};

/// 上标 / 下标：它们**与基座同生共死**（`x^2` 在 TeX 里就是一个原子）
bool _isScript(TexItem it) => it.command == '^' || it.command == '_';

/// 该内容项在**它自己那一层**上是不是一个"可见对象"（而不是透明包装）。
bool isOpaqueItem(TexItem it) =>
    _isScript(it) || (it.command != null && kOpaqueCommands.contains(it.command));

// ---------------------------------------------------------------------------
// ★★ 挂件（脚本 `^`/`_` ＋ 定宽 accent）的边缘像素（§4.0'，2026-10-15 晚用户定）
// ---------------------------------------------------------------------------

/// 一个**挂件**：它的整体区间 ＋ 它**内容**的区间。
///
/// · **脚本**（`x_{2}`）：`span = [1,5)`（`_{2}`，**不含基座**）；内容 `= [3,4)`；
///   ⇒ "把挂件掏空" = 删掉挂件本身，**基座留下**（`x`）—— 用户 10-15 选的「甲」。
/// · **定宽 accent**（`\hat{a}`）：`span = [0,7)`（**含基座**，基座就是它的内容）；
///   内容 `= [5,6)`；⇒ "把挂件掏空" = 整个 `\hat{a}` 走 —— 用户 10-15 选的「乙」。
///
/// 两者的差别**不是随手定的**：脚本是"挂在基座**旁边**"，accent 是"套在基座**上面**"，
/// 所以"掏空"的后果不同（脚本掏空后只剩基座 ✓；accent 掏空后剩一顶**悬空的帽子** ✗ = 半成品）。
class _Attachment {
  const _Attachment(this.span, this.cStart, this.cEnd, this.owner,
      {required this.isScript});
  final _Span span;
  final int cStart;
  final int cEnd;

  /// 它挂在哪个区域里（脚本的右端 `Delete` 要在**外一层**找右邻，见 [smartDelete]）
  final TexRegion owner;

  /// 脚本（`^`/`_`）还是定宽 accent —— 两者的**掏空**后果不同，见 [_attachmentEdgeAt]
  final bool isScript;

  int get width => span.end - span.start;
}

/// 光标落在一个挂件的**边缘那一格**：返回该挂件 + 是"右端"还是"左端"。
///
/// 边缘 = `{内容首, 挂件首}` / `{内容末, 挂件末}` —— 挂件的**装饰不占宽**
/// （脚本的基座、accent 的装饰都不贡献宽度），所以这两格**永远落在同一根像素**上
/// ⇒ 按 §3.3「**删除与点击不区分**」，同一个像素必须给**同一个结果**。
///
/// ★★ **位点一个都不删**（用户 2026-10-15 晚的关键修正）：
///   「有的时候可能还需要**下标的下标**，确实不能完全不给加完后的下标开放编辑路径」
///   ⇒ 合并的是**删除结果**，不是位点本身 —— 光标照样能点进挂件里打字（包括再挂一层）。
///
/// ★ **脚本的左端（内容首）不是共享像素**（脚本在基座**右边** ⇒ 它左端外面还是基座那一段），
///   所以脚本只拦**右端**；accent 套在基座**上面**，两端都是共享像素 ⇒ 两端都拦。
({_Attachment att, bool atEnd})? _attachmentEdgeAt(CaretSiteTable t, int rel) {
  final List<_Attachment> all = _attachments(t);
  _Attachment? inner;
  var innerAtEnd = false;
  for (final _Attachment a in all) {
    final bool atEnd = rel == a.cEnd || rel == a.span.end;
    final bool atStart = rel == a.cStart || rel == a.span.start;
    if (!atEnd && !atStart) continue;
    if (inner == null || a.width < inner.width) {
      inner = a;
      innerAtEnd = atEnd;
    }
  }
  if (inner == null) return null;
  var att = inner;
  var atEnd = innerAtEnd;
  // 级联到**最外层**：外层挂件的对应那一端与本挂件的相应一端在同一根像素上
  // （`\hat{\bar{x}}`：内层内容末尾 11 / 内层挂件末尾 12 / 外层内容末尾 12 是同一根像素）
  var changed = true;
  while (changed) {
    changed = false;
    for (final _Attachment b in all) {
      if (b.span.start > att.span.start || b.span.end < att.span.end) continue;
      if (b.width <= att.width) continue;
      final bool same = atEnd
          ? (b.cEnd == att.span.end || b.span.end == att.span.end)
          : (b.cStart == att.span.start || b.span.start == att.span.start);
      if (same) {
        att = b;
        changed = true;
        break;
      }
    }
  }
  return (att: att, atEnd: atEnd);
}

/// 枚举 tex 里**所有挂件**（脚本 + 定宽 accent），无论花括号还是裸参数写法。
List<_Attachment> _attachments(CaretSiteTable t) {
  final out = <_Attachment>[];
  for (final TexRegion r in t.regions) {
    for (var i = 0; i < r.items.length; i++) {
      final TexItem it = r.items[i];
      final String? cmd = it.command;
      if (cmd == null) continue;
      final bool isScript = cmd == '^' || cmd == '_';
      if (!isScript && !kFixedShapeAccents.contains(cmd)) continue;
      final TexRegion? slot = _slotRegionOf(t, it);
      if (slot != null) {
        out.add(_Attachment(
            _Span(it.start, it.end), slot.start, slot.end, r,
            isScript: isScript));
      } else if (i + 1 < r.items.length) {
        // 裸参数（`\hat x` / `x^2`）：参数 = **紧跟着的那一个项**（TeX 单记号规则）
        final TexItem arg = r.items[i + 1];
        out.add(_Attachment(
            _Span(it.start, arg.end), arg.start, arg.end, r,
            isScript: isScript));
      }
    }
  }
  return out;
}

/// 属于内容项 [it] 的**槽区域**（即它的参数组）；裸参数形式没有 ⇒ `null`
TexRegion? _slotRegionOf(CaretSiteTable t, TexItem it) {
  TexRegion? best;
  for (final TexRegion r in t.regions) {
    if (r.path.isEmpty) continue;
    if (r.path.last.command != it.command) continue;
    if (r.start < it.start || r.end > it.end) continue;
    if (best == null || (r.end - r.start) > (best.end - best.start)) {
      best = r; // 取最大的那个（= 最外层的参数组）
    }
  }
  return best;
}

/// 挂件内容里的**可见原子个数**（判"删这一下会不会把它掏空"）
int _contentAtoms(String tex, _Attachment a) => lexVisibleAtoms(tex)
    .where((VisibleAtom x) => x.start >= a.cStart && x.end <= a.cEnd)
    .length;

// ---------------------------------------------------------------------------
// 删除
// ---------------------------------------------------------------------------

/// `Backspace`：段内相对偏移 [rel] 处往前删。
SmartEdit smartBackspace(CaretSiteTable t, int rel) {
  final int r = rel.clamp(0, t.tex.length);
  if (r <= 0) return SmartEdit.none;

  // §4.4 降级：字节级，笨但可预测
  if (t.degraded) return SmartEdit.remove(r - 1, r, r - 1);

  // ★★ 2026-10-18：**分隔符不可单删**（`\left(` / `\right)` / `\middle|` 的字符）。
  //   否则会删出 `\left2\right)` 这种非法 tex ⇒ KaTeX 抛 Parser Error（用户实测"点删除报错"）。
  //   判据：删到分隔符 ⇒ **整对一起删**（与 §4.6「删除要干脆」同一口径）。
  final _DelimPair? pair = _delimPairAt(t.tex, r - 1);
  if (pair != null) return SmartEdit.remove(pair.start, pair.end, pair.start);

  // ★★★ 2026-10-24（批 4c · D1）：**本来就是空的**结构，退格 = 把这个结构**整块回收**。
  //
  // 用户口径（2026-10-18 那条的补集）：「删空留壳」只针对"**槽里有内容、删掉内容**"：
  //   槽里本来就没东西时，退格该去掉的是**这个结构本身** —— 否则用户永远删不掉一个
  //   误插的 `_{}` / `\left|{}\right|`（实测：退格会去啃 `{` `}` `\left` 这些语法字符，
  //   直接把 tex 弄坏 ⇒ `[公式不完整]`）。
  //   · 空挂件 `x_{}` / `x^{}` ⇒ 删**挂件本身**（基座留下，与 §4.0'「甲」一致）
  //   · 空定界符对 `\left|{}\right|` ⇒ **整对**一起删
  //   ★ 有内容的结构一律不走这条（照旧"删内容、留空壳"）。
  final _Span? emptyStruct = _emptyStructureAt(t.tex, r);
  if (emptyStruct != null) {
    return SmartEdit.remove(emptyStruct.start, emptyStruct.end, emptyStruct.start);
  }

  final CaretSite s = t.snap(r);

  // ★ §4.7 **优先**：光标停在某个**操作对象的右端** ⇒ 删的是**整个操作对象**
  //   （`\sin 2x` / `\sum_{i=1}^{n}a_i b_i` —— 用户已复验；它比"挂件边缘"更粗一层）
  final OpScope? scope = scopeEndingAt(t.tex, s.offset);
  if (scope != null) return SmartEdit.remove(scope.start, scope.end, scope.start);

  // ★★ §4.0' 挂件的边缘像素（见 [_attachmentEdgeAt]）：
  //    `⌫ = 左边最近的墨迹` —— 在挂件**右端那一格**上，左边的墨迹就是挂件里最后一个原子。
  //    **accent 的例外**：那个原子是它最后一个内容 ⇒ 删了会剩一顶**悬空的帽子**
  //    ⇒ 整个 accent 一起走；**脚本不适用**（删完只剩基座，且花括号形式留下合法的 `x^{}`
  //    —— §4.1.1 的既有口径，还方便原地重打）。
  final ({_Attachment att, bool atEnd})? att = _attachmentEdgeAt(t, s.offset);
  if (att != null) {
    final _Attachment a = att.att;
    // accent 的空挂件（`\hat{}`）：里面什么都没有 ⇒ **两个方向都整个走**
    // （本来就空；而且留着会剩一顶**悬空的帽子** = 半成品。脚本不同：空脚本什么也看不见）
    if (!a.isScript && a.cStart == a.cEnd) {
      return SmartEdit.remove(a.span.start, a.span.end, a.span.start);
    }
    if (att.atEnd) {
      if (!a.isScript && _contentAtoms(t.tex, a) <= 1) {
        return SmartEdit.remove(a.span.start, a.span.end, a.span.start);
      }
      if (s.offset != a.cEnd) return smartBackspace(t, a.cEnd); // 挂件末尾 ⇒ 按内容末尾算
    } else if (!a.isScript && a.span.start < s.offset) {
      // accent **左端**那一格：左边的墨迹在挂件**外面**（与"从外面删"同一结果）
      return smartBackspace(t, a.span.start);
    }
    // 其余情况（脚本左端 / 已经在内容末尾）⇒ 落到下面的常规路径
  }

  final int idx = t.indexOf(s.offset);
  final TexRegion? reg = innermostRegionAt(t, s.offset);

  // §4.2 区域首 → **只跳不删**（空槽里、裸组里、`\frac{a}{b}` 的 `}{` 之间…）
  if (reg != null && s.offset == reg.start && idx > 0) {
    return SmartEdit.move(t.sites[idx - 1].offset);
  }

  // §4.0 通则：与光标**同层**、紧邻左侧的那一个可见对象
  final _Span? obj = _objectLeftOf(t, s.offset);
  if (obj == null) return SmartEdit.none; // 同层左边什么都没有
  // ★★★ 2026-10-24 **安全网**（用户实测"每次必坏"）：要删的那一项若是**纯语法**
  //   （定界符 `|` / 花括号 / `^` `_` / `\left` `\right` 这类），而光标左边紧贴着一个
  //   **普通字母** ⇒ 改删那个字母。
  //   实测的坏法：在 `\left|{sinx}\right|` 的组内容里任意两个字母之间退格，
  //   `_objectLeftOf` 返回的都是 `\left` 后面那根 `|`（[18,19)）⇒ `\left{sinx}\right|`
  //   ⇒ KaTeX 报 `[公式不完整]`；而且删的总是同一根 `|`，所以每处都报错。
  //   ★ 只拦"纯语法"这一种坏结果，不改变其它任何既有口径（`\alpha` 整词、`b^2` 裸参数连删、
  //     挂件边缘、算子作用域… 那些 obj 都不是纯语法 ⇒ 一律照旧）。
  if (_isSyntaxOnly(t.tex.substring(obj.start, obj.end.clamp(0, t.tex.length)))) {
    final String prev = r > 0 ? t.tex[r - 1] : '';
    if (RegExp(r'[A-Za-z0-9]').hasMatch(prev)) {
      return SmartEdit.remove(r - 1, r, r - 1);
    }
  }
  return SmartEdit.remove(obj.start, obj.end, obj.start);
}

/// 这一段源码是不是**纯语法**（没有任何内容字符）：花括号 / `^` / `_` / 反斜杠命令 / 定界符。
bool _isSyntaxOnly(String s) {
  if (s.isEmpty) return false;
  if (RegExp(r'^[\s{}^_\\|(){}\[\]<>.,;:]+$').hasMatch(s)) return true;
  return false;
}

/// 位置 [r] 是否落在**一个空结构**里；是 ⇒ 返回它该被回收的整体区间（`null` = 不是）。
///
/// 只认两种（都是用户实测过、删不掉的形状）：
/// ① **空挂件** `x_{}` / `x^{}`（含 `{ }` 里只有空白）⇒ 区间 = `_{}` / `^{}`（**不含基座**）；
/// ② **空定界符对** `\left|{}\right|`（内容只有空白 / 空组）⇒ 区间 = 整对。
///
/// ★ 有内容的结构**一律不认**（照旧"删内容、留空壳"）—— 所以这里只做"空"的检查，
///   不碰任何有内容的形状。
_Span? _emptyStructureAt(String tex, int r) {
  // ① 空挂件：`^` / `_` 后面紧跟空组
  for (final RegExpMatch m
      in RegExp(r'[\^_]\s*\{\s*\}').allMatches(tex)) {
    if (r >= m.start && r <= m.end) return _Span(m.start, m.end);
  }
  // ② 空定界符对：`\left…` 与紧邻的 `\right…` 之间只有空白 / 空组
  final List<({int start, int end, String name})> toks = _delimTokens(tex);
  for (var k = 0; k + 1 < toks.length; k++) {
    if (toks[k].name != 'left') continue;
    if (toks[k + 1].name != 'right') continue;
    final String inner = tex.substring(toks[k].end, toks[k + 1].start);
    final String bare = inner
        .replaceAll(RegExp(r'\s'), '')
        .replaceAll(RegExp(r'\{\s*\}'), '');
    if (bare.isNotEmpty) continue; // 有内容 ⇒ 不是空结构
    if (r >= toks[k].start && r <= toks[k + 1].end) {
      return _Span(toks[k].start, toks[k + 1].end);
    }
  }
  return null;
}

/// `Delete`：段内相对偏移 [rel] 处往后删（与 [smartBackspace] 镜像）。
SmartEdit smartDelete(CaretSiteTable t, int rel) {
  final int r = rel.clamp(0, t.tex.length);
  if (r >= t.tex.length) return SmartEdit.none;

  if (t.degraded) return SmartEdit.remove(r, r + 1, r);

  // ★★ 2026-10-18：分隔符不可单删（见 [smartBackspace] 的说明）⇒ 整对一起删
  final _DelimPair? pair = _delimPairAt(t.tex, r);
  if (pair != null) return SmartEdit.remove(pair.start, pair.end, pair.start);

  final CaretSite s = t.snap(r);

  // ★ §4.7 **优先**（与 [smartBackspace] 对称）：光标停在操作对象的**左端** ⇒ 删整个操作对象
  final OpScope? scope = scopeStartingAt(t.tex, s.offset);
  if (scope != null) return SmartEdit.remove(scope.start, scope.end, scope.start);

  // ★★ §4.0' 挂件边缘（§3.3：同一根像素 ⇒ 同一结果）
  //    `Del = 右边最近的墨迹` —— 在挂件**右端那一格**上，右边的墨迹在挂件**外面**；
  //    在挂件**左端那一格**上，右边的墨迹就是挂件里第一个原子（accent 若只剩一个 ⇒ 整个走）。
  final ({_Attachment att, bool atEnd})? att = _attachmentEdgeAt(t, s.offset);
  if (att != null) {
    final _Attachment a = att.att;
    // accent 的空挂件（`\hat{}`）：两个方向都整个走（同 [smartBackspace]）
    if (!a.isScript && a.cStart == a.cEnd) {
      return SmartEdit.remove(a.span.start, a.span.end, a.span.start);
    }
    if (!att.atEnd) {
      if (!a.isScript && _contentAtoms(t.tex, a) <= 1) {
        return SmartEdit.remove(a.span.start, a.span.end, a.span.start);
      }
      if (!a.isScript && s.offset != a.cStart) {
        return smartDelete(t, a.cStart); // 挂件首 ⇒ 按内容首算
      }
      // 脚本左端 ⇒ 常规路径（保留"进去逐字删"）
    } else {
      // 挂件**右端**那一格：右边的墨迹在挂件外面
      if (a.isScript) {
        // 脚本要用**外一层**的区域去找右邻（内容末尾那一格的内层是脚本自己，找不到东西）
        final _Span? obj = _objectRightOfIn(t, a.owner, a.span.end);
        return obj == null ? SmartEdit.none : SmartEdit.remove(obj.start, obj.end, obj.start);
      }
      if (a.span.end > s.offset) return smartDelete(t, a.span.end);
    }
    // 其余情况 ⇒ 落到下面的常规路径
  }

  final int idx = t.indexOf(s.offset);
  final TexRegion? reg = innermostRegionAt(t, s.offset);

  // §4.2 区域末 → **只跳不删**（槽间跨越：`\frac{a}{b}` 的分子末 → 跳到分母首）
  if (reg != null && s.offset == reg.end && idx >= 0 && idx + 1 < t.sites.length) {
    return SmartEdit.move(t.sites[idx + 1].offset);
  }

  // §4.0 通则：与光标**同层**、紧邻右侧的那一个可见对象
  final _Span? obj = _objectRightOf(t, s.offset);
  if (obj == null) return SmartEdit.none;
  return SmartEdit.remove(obj.start, obj.end, obj.start);
}

// ---------------------------------------------------------------------------
// ★★ 同层邻居（§4.0 通则的唯一实现）
// ---------------------------------------------------------------------------

class _Span {
  const _Span(this.start, this.end);
  final int start;
  final int end;
  @override
  String toString() => '[$start,$end)';
}

/// 与 [rel] 同层、紧邻**左侧**的可见对象的源码区间；`null` = 同层左边没有东西。
_Span? _objectLeftOf(CaretSiteTable t, int rel) {
  final TexRegion? reg = innermostRegionAt(t, rel);
  if (reg == null) return null;

  // ① 同层最后一个"结束于光标左侧"的内容项
  var idx = -1;
  for (var i = 0; i < reg.items.length; i++) {
    if (reg.items[i].end <= rel) {
      idx = i;
    }
  }
  if (idx < 0) return null;
  final TexItem it = reg.items[idx];

  // ② **透明包装**（`\text{}` / 裸组 / 无装饰命令）：对象是它**里面**最后一个可见原子；
  //    里面一个可见原子都没有（如 `\text{}`）⇒ 对象就是它自己 —— 否则会变成删不掉的陷阱。
  //    ⚠️ 例外：整个项**本身就是那一个原子**时（`x` / `\alpha`），要走 ③ ——
  //    因为紧跟它的脚本属于它（`x^2` 是一个 TeX 原子）。
  if (!isOpaqueItem(it)) {
    final VisibleAtom? a = _lastAtomIn(t.tex, it.start, it.end, rel);
    if (a != null && !(a.start == it.start && a.end == it.end)) {
      return _Span(_bareScriptStart(t.tex, reg, a.start), a.end);
    }
  }

  // ③ ★ `x^2` / `\sum_{i=1}^{n}`：**紧跟其后的脚本属于它** —— 留一个悬空的 `^`/`_` 会炸（§4.1.1）
  return _Span(
    _bareScriptStart(t.tex, reg, it.start),
    _trailingScriptsEnd(reg.items, idx),
  );
}

/// 与 [rel] 同层、紧邻**右侧**的可见对象的源码区间；`null` = 同层右边没有东西。
_Span? _objectRightOf(CaretSiteTable t, int rel) {
  final TexRegion? reg = innermostRegionAt(t, rel);
  return reg == null ? null : _objectRightOfIn(t, reg, rel);
}

/// 同上，但**指定在哪一层找**（脚本的右端要在它**外面**那一层找右邻，见 [smartDelete]）
_Span? _objectRightOfIn(CaretSiteTable t, TexRegion reg, int rel) {
  var idx = -1;
  for (var i = 0; i < reg.items.length; i++) {
    if (reg.items[i].start >= rel) {
      idx = i;
      break;
    }
  }
  if (idx < 0) return null;
  final TexItem it = reg.items[idx];

  if (!isOpaqueItem(it)) {
    final VisibleAtom? a = _firstAtomIn(t.tex, it.start, it.end, rel);
    if (a != null && !(a.start == it.start && a.end == it.end)) {
      return _Span(_bareScriptStart(t.tex, reg, a.start), a.end);
    }
  }
  // 基座与它的脚本同生共死（`x^2` 删 `x` 必须连 `^2` 一起走）
  return _Span(
    _bareScriptStart(t.tex, reg, it.start),
    _trailingScriptsEnd(reg.items, idx),
  );
}

/// `^`/`_` 的**裸参数**（`b^2` 没有花括号）：删它的内容必须**连 `^`/`_` 一起删** ——
/// 留下"`^` 后面什么都没有"的源码会让引擎报 `Parser Error: Expected group after '^'`
/// （设计稿 §4.1.1，用户 2026-10-14 给出的精确复现路径）。
///
/// 花括号形式（`b^{2}`）**不受影响**：`{}` 是合法的空组，删内容得到 `b^{}` ✓。
int _bareScriptStart(String tex, TexRegion reg, int start) {
  if (start <= 0 || reg.path.isEmpty) return start;
  final String c = reg.path.last.command;
  if (c != '^' && c != '_') return start;
  return tex[start - 1] == c ? start - 1 : start;
}

/// 从第 [idx] 项开始，把**紧跟其后的脚本项**（`^` / `_`，且紧邻无缝隙）一并纳入。
int _trailingScriptsEnd(List<TexItem> items, int idx) {
  var end = items[idx].end;
  for (var j = idx + 1; j < items.length; j++) {
    final TexItem nx = items[j];
    if (nx.start != end || !_isScript(nx)) break;
    end = nx.end;
  }
  return end;
}

/// `[start, end)` 内、结束于 [rel] 之前的**最后一个可见原子**
VisibleAtom? _lastAtomIn(String tex, int start, int end, int rel) {
  VisibleAtom? best;
  for (final VisibleAtom a in lexVisibleAtoms(tex)) {
    if (a.start < start || a.end > end) continue;
    if (a.end > rel) continue;
    if (best == null || a.end > best.end) best = a;
  }
  return best;
}

/// `[start, end)` 内、起始于 [rel] 之后的**第一个可见原子**
VisibleAtom? _firstAtomIn(String tex, int start, int end, int rel) {
  VisibleAtom? best;
  for (final VisibleAtom a in lexVisibleAtoms(tex)) {
    if (a.start < start || a.end > end) continue;
    if (a.start < rel) continue;
    if (best == null || a.start < best.start) best = a;
  }
  return best;
}

// ---------------------------------------------------------------------------
// 结构实例的辅助（`normalize` 用）
// ---------------------------------------------------------------------------

/// 结构起点的**完整信息**：起点偏移 ＋（若它是环境）环境名。
class StructureStart {
  const StructureStart(this.at, [this.envName]);

  /// `\` 或 `^`/`_` 的位置
  final int at;

  /// 环境名（`\begin{cases}` ⇒ `cases`）；不是环境时为 null
  final String? envName;

  @override
  String toString() => 'StructureStart@$at${envName == null ? '' : ' env=$envName'}';
}

/// 结构起点：从参数内容起点往前找 `\cmd` / `^`/`_` / `\begin{env}`。
///
/// 往前要跳过的东西（都是"参数与命令之间"的语法）：
/// **花括号** `{` `}`、**可选参数的方括号** `[` `]`（`\sqrt[3]{x}` 的次数槽）、空格。
/// ★ 跳过方括号是 2026-10-17 补的：`\sqrt[3]{x}` 的次数槽内容前面是 `[`，
///   原来一律返回 null ⇒ **整个根号实例枚举不到** ⇒ normalize 回收不到它。
StructureStart? structureStartInfo(String tex, int contentStart) {
  var i = contentStart - 1;
  while (i >= 0 && '{}[] '.contains(tex[i])) {
    i--;
  }
  if (i < 0) return null;
  if (tex[i] == '^' || tex[i] == '_') return StructureStart(i);
  if (!isAsciiLetter(tex.codeUnitAt(i))) return null;
  var j = i;
  while (j >= 0 && isAsciiLetter(tex.codeUnitAt(j))) {
    j--;
  }
  if (j < 0) return null;
  final String name = tex.substring(j + 1, i + 1);
  if (tex[j] == r'\') return StructureStart(j);
  if (tex[j] == '{') {
    // `\begin{cases}` / `\end{cases}`：名字前面是 `\begin{`
    final String head = tex.substring(0, j);
    for (final String kw in const <String>[r'\begin', r'\end']) {
      if (head.endsWith(kw)) {
        return StructureStart(
          head.length - kw.length,
          kw == r'\begin' ? name : null,
        );
      }
    }
  }
  return null;
}

/// 结构起点（只要偏移的旧接口 —— 保留给既有调用方 / 测试）
int? structureStartBefore(String tex, int contentStart) =>
    structureStartInfo(tex, contentStart)?.at;

/// `\end{name}` 之后的位置；找不到返回 [from]（**绝不猜**）
int environmentEnd(String tex, String name, int from) {
  final String needle = '\\end{$name}';
  final int k = tex.indexOf(needle, from);
  return k < 0 ? from : k + needle.length;
}

int _extentEnd(String tex, int slotEnd) =>
    (slotEnd < tex.length && tex[slotEnd] == '}') ? slotEnd + 1 : slotEnd;

/// 父路径的字符串键（**不含命令与行列** —— 实例身份由"源码起点"决定，见 [structureUnits]）
String _pathKey(List<SlotStep> path) =>
    path.map((SlotStep s) => '${s.command}(${s.argIndex})').join('/');

// ---------------------------------------------------------------- 分隔符对（2026-10-18）

/// `\left X … \right Y` 的一对（`start` = `\left` 起点，`end` = `\right` 之后）
class _DelimPair {
  const _DelimPair(this.start, this.end);
  final int start;
  final int end;
}

const List<String> _kDelimCommands = <String>['left', 'right', 'middle'];

/// 分隔符 token 的结束位置（命令名之后，吃掉空白与分隔符本身）
int _delimTokenEnd(String tex, int from) {
  int j = from;
  while (j < tex.length && tex[j] == ' ') {
    j++;
  }
  if (j >= tex.length) return j;
  if (tex[j] == r'\') {
    j++;
    if (j < tex.length && tex[j] == '{') return j + 1; // `\{` `\}`
    while (j < tex.length) {
      final int c = tex.codeUnitAt(j);
      final bool letter =
          (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
      if (!letter) break;
      j++;
    }
    return j;
  }
  return j + 1;
}

/// 扫出所有 `\left` / `\right` / `\middle` token（含它们的分隔符）
List<({int start, int end, String name})> _delimTokens(String tex) {
  final List<({int start, int end, String name})> out =
      <({int start, int end, String name})>[];
  int i = 0;
  while (i < tex.length) {
    if (tex[i] != r'\') {
      i++;
      continue;
    }
    int j = i + 1;
    final int nameStart = j;
    while (j < tex.length) {
      final int c = tex.codeUnitAt(j);
      final bool letter = (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
      if (!letter) break;
      j++;
    }
    final String name = tex.substring(nameStart, j);
    if (_kDelimCommands.contains(name)) {
      out.add((start: i, end: _delimTokenEnd(tex, j), name: name));
      i = _delimTokenEnd(tex, j);
      continue;
    }
    i = j > i + 1 ? j : i + 1;
  }
  return out;
}

/// **覆盖字符 [at] 的分隔符 token** 所属的那一对；不在分隔符语法上 ⇒ null。
///
/// 为什么要它：单个分隔符被删掉会得到 `\left2\right)` 这种**非法 tex**
/// （KaTeX 直接抛 `Invalid delimiter type`，用户实测"点删除报错"）。
_DelimPair? _delimPairAt(String tex, int at) {
  if (at < 0 || at >= tex.length) return null;
  final List<({int start, int end, String name})> toks = _delimTokens(tex);
  int hit = -1;
  for (int k = 0; k < toks.length; k++) {
    if (at >= toks[k].start && at < toks[k].end) {
      hit = k;
      break;
    }
  }
  if (hit < 0) return null;

  final String name = toks[hit].name;
  if (name == 'left') {
    int depth = 0;
    for (int k = hit; k < toks.length; k++) {
      if (toks[k].name == 'left') depth++;
      if (toks[k].name == 'right') {
        depth--;
        if (depth == 0) return _DelimPair(toks[hit].start, toks[k].end);
      }
    }
    return null;
  }
  if (name == 'right') {
    int depth = 0;
    for (int k = hit; k >= 0; k--) {
      if (toks[k].name == 'right') depth++;
      if (toks[k].name == 'left') {
        depth--;
        if (depth == 0) return _DelimPair(toks[k].start, toks[hit].end);
      }
    }
    return null;
  }
  // \middle：归它外面那一对
  int? leftStart;
  int depth = 0;
  for (int k = hit - 1; k >= 0; k--) {
    if (toks[k].name == 'right') depth++;
    if (toks[k].name == 'left') {
      if (depth == 0) {
        leftStart = toks[k].start;
        break;
      }
      depth--;
    }
  }
  if (leftStart == null) return null;
  for (int k = hit + 1; k < toks.length; k++) {
    if (toks[k].name == 'right') return _DelimPair(leftStart, toks[k].end);
  }
  return null;
}