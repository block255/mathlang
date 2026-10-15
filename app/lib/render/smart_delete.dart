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
/// 靠 `siblingSlots`（同父路径 + 同命令 + 同行列）聚合。
List<StructureUnit> structureUnits(CaretSiteTable t) {
  if (t.degraded) return const <StructureUnit>[];
  final Set<String> seen = <String>{};
  final List<StructureUnit> out = <StructureUnit>[];
  for (final SlotSpan s in t.slots) {
    if (s.path.isEmpty) continue;
    final String key = _instanceKey(s.path);
    if (!seen.add(key)) continue;
    final List<SlotSpan> inst = siblingSlots(t, s.path);
    if (inst.isEmpty) continue;
    var first = inst.first.start;
    var last = _extentEnd(t.tex, inst.first.end);
    for (final SlotSpan x in inst) {
      if (x.start < first) first = x.start;
      final int e = _extentEnd(t.tex, x.end);
      if (e > last) last = e;
    }
    final int? start = structureStartBefore(t.tex, first);
    if (start == null) continue;
    out.add(StructureUnit(start, last, inst));
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

/// ★★ **形状固定**的 accent（2026-10-15 晚，用户实测提出）—— 它们按**一个字符**处理。
///
/// 名单 = 引擎的分类，**读源码得来，不是猜的**（`flutter_math_fork`
/// `parser/tex/functions/katex_base/accent.dart` 的 `nonStretchyAccents`）：
/// `\acute \grave \ddot \tilde \bar \breve \check \hat \vec \dot \mathring`。
///
/// 为什么它们要当"一个字符"：
/// · 装饰是**一个小字形**，盒子被**强制撑到内容宽**（引擎原话：
///   *"Non stretchy accent can not contribute to overall width, thus they must fit exactly
///   with the width even if it means overflow"*）⇒ **结构右缘 == 内容右缘**
///   ⇒ "内容末尾"与"结构末尾"**永远在同一根像素**上，尾垫也救不了
///   （尾垫只把**盒**撑宽，那个定宽字形**不会跟着变长** —— 实测 `\hat{x\rule{3pt}{0pt}}`
///   的装饰盒 16 → 20.8，但墨迹不动）。
/// · 于是同一个像素上，"里面"和"外面"给出**两个不同的删除结果**（用户实测：
///   「点底下和点整体的判定很难分清」）⇒ 违反 §3.3 的规律
///   「**删除与点击不区分**；方向性语义区分」。
///
/// ⇒ 处置（**只合并内容【末尾】**，见 [_fixedShapeAccentOuter]）：
///   在内容末尾，**退格 = 删整个 `\hat{x}`**（而不是留下 `\hat{}`）、**`Delete` = 删它右边那一个对象** ——
///   与"结构末尾"那一格**完全一致**（做法是把偏移**重映射到结构末尾**，见下）。
///
/// ⚠️ **为什么左端不合并**：内容首位点（`{` 之后）是**"点进去改字"的入口**
///   （§5.2 归属表：点装饰 = 去改里面的内容）。若左端也整体删，用户就**没法只换里面的字**
///   （`\hat{a}` → `\hat{b}` 得整段重打，而符号面板还没做）。左端"多按一次退格"的代价是
///   一次**看不见的移动**，可以接受；右端不合并则是"**根本删不掉整个 accent**"。
const Set<String> kFixedShapeAccents = <String>{
  'acute', 'grave', 'ddot', 'tilde', 'bar', 'breve',
  'check', 'hat', 'vec', 'dot', 'mathring',
};

/// 该内容项在**它自己那一层**上是不是一个"可见对象"（而不是透明包装）。
bool isOpaqueItem(TexItem it) =>
    _isScript(it) || (it.command != null && kOpaqueCommands.contains(it.command));

/// 光标停在**形状固定 accent**（[kFixedShapeAccents]）的**内容末尾**时，
/// 返回它应该被当作"**那一个字符**"的源码区间 —— 否则返回 `null`。
///
/// 为什么是区间而不是"偏移重映射"：**裸参数形式**（`\hat x`）下，
/// 内容末尾、结构末尾、tex 末尾是**同一个偏移**，没有"外面"可去 —— 只能直接给出区间。
///
/// **级联到最外层**（`\hat{\bar{x}}`）：三层装饰都不占宽、`{`/`}` 不可见
/// ⇒ 三者的**像素完全相同** ⇒ 按「同一根像素 ⇒ 同一行为」，取**最外**那一层的区间
/// （若只取内层，会得到 `[6,13)` 这种"删掉内层 + 外层收尾 `}`"的**坏区间** —— 留下 `\hat{`）。
///
/// ★ **只处理内容【末尾】**（左端见 [kFixedShapeAccents] 的注释）：
///   左端是"点进去改字"的入口，不能整体删。
_Span? _fixedShapeAccentSpanEndingAt(CaretSiteTable t, int rel) {
  _Span? acc = _accentItemEndingAtContent(t, rel);
  if (acc == null) return null;
  // **级联到最外层**：同一根像素上还可能套着别的定宽 accent（`\hat{\bar{x}}`）——
  // 内层 accent 的**结构末尾**就是外层 accent 的**内容末尾**，所以要拿 `acc.end` 再问一次。
  while (true) {
    final _Span? outer = _accentItemEndingAtContent(t, acc!.end);
    if (outer == null || outer.end <= acc.end) break;
    acc = outer;
  }
  return acc;
}

/// 找**内容末尾**正好是 [contentEnd] 的定宽 accent（取最内层 = 区间最短的那一个）。
///
/// ★ 必须同时认两种写法（实测的项表，见 `accent_as_one_object_test.dart` 的注释）：
///   · **花括号**：`\hat{x}` 是一个项 `[0,7) cmd=hat hasSlots=true` ⇒ 项本身就含参数组
///   · **裸参数**：`\hat x` 是**两个**项 —— `[0,4) cmd=hat hasSlots=false` ＋ `[5,6) x`
///     ⇒ 参数 = **紧跟着的那一个项**（TeX 的单记号规则：`\hat xy` 只盖住 `x`）
_Span? _accentItemEndingAtContent(CaretSiteTable t, int contentEnd) {
  _Span? best;
  for (final TexRegion r in t.regions) {
    for (var i = 0; i < r.items.length; i++) {
      final TexItem it = r.items[i];
      final String? cmd = it.command;
      if (cmd == null || !kFixedShapeAccents.contains(cmd)) continue;
      final int spanEnd;
      if (it.hasSlots) {
        spanEnd = it.end;
      } else {
        if (i + 1 >= r.items.length) continue; // `\hat` 后面什么都没有
        spanEnd = r.items[i + 1].end;
      }
      if (_contentEnd(t.tex, spanEnd) != contentEnd) continue;
      if (best == null || (spanEnd - it.start) < (best.end - best.start)) {
        best = _Span(it.start, spanEnd);
      }
    }
  }
  return best;
}

/// 内容项的**内容末尾**：`\hat{x}` 的项是 `[0,7)` ⇒ 内容末尾 **6**；裸参数 `[0,6)` ⇒ 6
/// （与 [_extentEnd] 互逆）
int _contentEnd(String tex, int itemEnd) =>
    (itemEnd > 0 && itemEnd <= tex.length && tex[itemEnd - 1] == '}')
        ? itemEnd - 1
        : itemEnd;

// ---------------------------------------------------------------------------
// 删除
// ---------------------------------------------------------------------------

/// `Backspace`：段内相对偏移 [rel] 处往前删。
SmartEdit smartBackspace(CaretSiteTable t, int rel) {
  final int r = rel.clamp(0, t.tex.length);
  if (r <= 0) return SmartEdit.none;

  // §4.4 降级：字节级，笨但可预测
  if (t.degraded) return SmartEdit.remove(r - 1, r, r - 1);

  final CaretSite s = t.snap(r);

  // ★★ 形状固定的 accent（`\hat` `\bar` …）：内容末尾 == 结构末尾（同一根像素）
  //    ⇒ 退格删**整个** `\hat{x}`（与"从外面删"同一结果），而不是留下 `\hat{}`
  final _Span? acc = _fixedShapeAccentSpanEndingAt(t, s.offset);
  if (acc != null) return SmartEdit.remove(acc.start, acc.end, acc.start);

  final int idx = t.indexOf(s.offset);
  final TexRegion? reg = innermostRegionAt(t, s.offset);

  // §4.2 区域首 → **只跳不删**（空槽里、裸组里、`\frac{a}{b}` 的 `}{` 之间…）
  if (reg != null && s.offset == reg.start && idx > 0) {
    return SmartEdit.move(t.sites[idx - 1].offset);
  }

  // ★ §4.7 + §4.0：光标停在某个**操作对象的右端** ⇒ 删的是**整个操作对象**
  //   （算子 + 紧跟的上下限 + 被它作用的内容 —— `\sin 2x` / `\sum_{i=1}^{n}a_i b_i`）
  final OpScope? scope = scopeEndingAt(t.tex, s.offset);
  if (scope != null) return SmartEdit.remove(scope.start, scope.end, scope.start);

  // §4.0 通则：与光标**同层**、紧邻左侧的那一个可见对象
  final _Span? obj = _objectLeftOf(t, s.offset);
  if (obj == null) return SmartEdit.none; // 同层左边什么都没有
  return SmartEdit.remove(obj.start, obj.end, obj.start);
}

/// `Delete`：段内相对偏移 [rel] 处往后删（与 [smartBackspace] 镜像）。
SmartEdit smartDelete(CaretSiteTable t, int rel) {
  final int r = rel.clamp(0, t.tex.length);
  if (r >= t.tex.length) return SmartEdit.none;

  if (t.degraded) return SmartEdit.remove(r, r + 1, r);

  final CaretSite s = t.snap(r);

  // ★★ 形状固定的 accent：内容末尾 == 结构末尾（同一根像素）⇒ 与"从外面删"同一结果
  //    · 花括号形式：越过收尾 `}` 之后照常算（删的通常是**它右边**那一个同层对象）
  //    · 裸参数形式：结构末尾就是 tex 末尾 ⇒ 交给文档层的边界语义（`math_nav`）
  final _Span? acc = _fixedShapeAccentSpanEndingAt(t, s.offset);
  if (acc != null) {
    return acc.end > s.offset ? smartDelete(t, acc.end) : SmartEdit.none;
  }

  final int idx = t.indexOf(s.offset);
  final TexRegion? reg = innermostRegionAt(t, s.offset);

  // §4.2 区域末 → **只跳不删**（槽间跨越：`\frac{a}{b}` 的分子末 → 跳到分母首）
  if (reg != null && s.offset == reg.end && idx >= 0 && idx + 1 < t.sites.length) {
    return SmartEdit.move(t.sites[idx + 1].offset);
  }

  // ★ §4.7 + §4.0（与 [smartBackspace] 对称）：光标停在操作对象的**左端** ⇒ 删整个操作对象
  final OpScope? scope = scopeStartingAt(t.tex, s.offset);
  if (scope != null) return SmartEdit.remove(scope.start, scope.end, scope.start);

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
  if (reg == null) return null;

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

/// 结构起点：从参数内容起点往前找 `\cmd` 或 `^`/`_`
int? structureStartBefore(String tex, int contentStart) {
  var i = contentStart - 1;
  while (i >= 0 && (tex[i] == '{' || tex[i] == ' ')) {
    i--;
  }
  if (i < 0) return null;
  if (tex[i] == '^' || tex[i] == '_') return i;
  if (!isAsciiLetter(tex.codeUnitAt(i))) return null;
  while (i >= 0 && isAsciiLetter(tex.codeUnitAt(i))) {
    i--;
  }
  return (i >= 0 && tex[i] == r'\') ? i : null;
}

int _extentEnd(String tex, int slotEnd) =>
    (slotEnd < tex.length && tex[slotEnd] == '}') ? slotEnd + 1 : slotEnd;

String _instanceKey(List<SlotStep> path) {
  final SlotStep me = path.last;
  return '${_pathKey(path.sublist(0, path.length - 1))}>${me.command}'
      '@${me.row}:${me.col}';
}

String _pathKey(List<SlotStep> path) =>
    path.map((SlotStep s) => '${s.command}(${s.argIndex})').join('/');
