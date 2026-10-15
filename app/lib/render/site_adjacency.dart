// 数语引擎 · 槽序与邻接（S3-3）
//
// 规格：notes/design/位点与结构导航.md
//   §三   槽序 = **深度优先 · 源顺序**；`Tab`/`Shift+Tab` 走槽序；`↑↓` 走竖直邻接
//   §十-① `Tab` 落点：**下一个空槽 → 槽内容末尾 → 走出公式**（Word 语义）
//   §十-⑤ `↑↓` **v1 用语法特例表**（分式 / 根号次数 / 大算符上下限），几何法留后续
//
// ★ 本文件只做**纯函数**：输入 = 位点表 + 公式内的相对偏移，输出 = 目标**相对偏移**
//   （`null` = 表内没有落点 → 由调用方负责"走出公式"）。
//   文档级的"跨 `$` 边界进出"在 `math_nav.dart`（它才知道 `$...$` 在哪）。
//
// **纯 Dart，不依赖 Flutter。**

import 'caret_sites.dart';

// ---------------------------------------------------------------- 槽序

/// 槽序：**深度优先 · 源顺序**。
///
/// ⚠️ **不能直接用 `table.slots` 的顺序** —— 解析器是"子槽先入表"
/// （`_parseArgItem` 在 `_parseItems` 返回之后才 `_slots.add`），那是**后序**；
/// 规范要的是**前序**。所以这里按 `(内容起点, 路径深度)` 排序：
/// 父槽与子槽起点相同时，**父槽在前**（先进分子，再进分子里的根号）。
List<SlotSpan> slotOrder(CaretSiteTable t) {
  final List<SlotSpan> out = List<SlotSpan>.of(t.slots);
  out.sort((SlotSpan a, SlotSpan b) {
    final int c = a.start.compareTo(b.start);
    if (c != 0) return c;
    return a.path.length.compareTo(b.path.length);
  });
  return out;
}

/// 包含 [rel] 的**最内层**槽（路径最长的那一个）。端点是闭区间（光标可以停在 `}` 之前）。
SlotSpan? innermostSlotAt(CaretSiteTable t, int rel) {
  SlotSpan? best;
  for (final SlotSpan s in t.slots) {
    if (rel < s.start || rel > s.end) continue;
    if (best == null || s.path.length > best.path.length) best = s;
  }
  return best;
}

/// 同一个「结构实例」的全部槽（同父路径 + 同命令 + 同行列）
List<SlotSpan> siblingSlots(CaretSiteTable t, List<SlotStep> path) {
  if (path.isEmpty) return const <SlotSpan>[];
  final List<SlotStep> parent = path.sublist(0, path.length - 1);
  final SlotStep me = path.last;
  return <SlotSpan>[
    for (final SlotSpan s in t.slots)
      if (s.path.isNotEmpty &&
          s.path.last.command == me.command &&
          s.path.last.row == me.row &&
          s.path.last.col == me.col &&
          _samePath(s.path.sublist(0, s.path.length - 1), parent))
        s,
  ];
}

bool _samePath(List<SlotStep> a, List<SlotStep> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].command != b[i].command ||
        a[i].argIndex != b[i].argIndex ||
        a[i].row != b[i].row ||
        a[i].col != b[i].col) {
      return false;
    }
  }
  return true;
}

// ---------------------------------------------------------------- 同层区域（§4.0）

/// 包含 [rel] 的**最内层内容区域**（主行 / 某槽 / 裸花括号组 / 环境的一格）。
///
/// ★ 「同层」= 落在同一个区域里 —— 这是 §4.0 通则「删除目标 = 与光标**同层**的、
/// 紧邻的那一个渲染对象」的**唯一层级判据**（区域表由解析器导出：`caret_sites.dart`
/// 的 [TexRegion]，构造时与位点表同一次遍历）。
///
/// ⚠️ **裸花括号组不产生槽**（§2.2），但它是**更小的区域** ⇒ 光标在 `{ab}` 里面时，
/// 同层兄弟是 `a` `b`，而不是外层的那个"组对象"。
TexRegion? innermostRegionAt(CaretSiteTable t, int rel) {
  TexRegion? best;
  for (final TexRegion r in t.regions) {    if (rel < r.start || rel > r.end) continue;
    if (best == null || _narrower(r, best)) best = r;
  }
  return best;
}

/// 更内层 = 路径更深；同深度取**区间更小**的那个（裸组不加深路径，但区间更小）。
bool _narrower(TexRegion a, TexRegion b) {
  if (a.path.length != b.path.length) return a.path.length > b.path.length;
  return (a.end - a.start) < (b.end - b.start);
}

// ---------------------------------------------------------------- Tab 走槽

/// `Tab` 的落点（相对偏移）；`null` = **走出公式**。
///
/// 规则（§十-①）：**下一个空槽 → 槽内容末尾 → 走出公式**。
int? tabForward(CaretSiteTable t, int rel) {
  if (t.degraded) return null; // 降级：交给调用方按位点/字节走
  // ① 下一个**空槽**（严格在光标右侧）
  for (final SlotSpan s in slotOrder(t)) {
    if (!s.isEmpty) continue;
    if (s.start > rel) return s.start;
  }
  // ② 当前槽（最内层）的内容末尾；不在槽里就取最后一个槽的末尾
  final List<SlotSpan> order = slotOrder(t);
  final SlotSpan? target = innermostSlotAt(t, rel) ?? (order.isEmpty ? null : order.last);
  if (target == null) return null;
  if (target.end > rel) return target.end;
  // ③ 走出公式
  return null;
}

/// `Shift+Tab` 的落点（相对偏移）；`null` = **从左侧走出公式**。
///
/// 镜像规则：**上一个空槽 → 当前槽内容开头 → 走出公式**。
int? tabBackward(CaretSiteTable t, int rel) {
  if (t.degraded) return null;
  final List<SlotSpan> order = slotOrder(t);
  // ① 上一个空槽（严格在光标左侧）：取最靠右的那个
  SlotSpan? empty;
  for (final SlotSpan s in order) {
    if (!s.isEmpty) continue;
    if (s.start < rel) empty = s;
  }
  if (empty != null) return empty.start;
  // ② 当前槽内容开头
  final SlotSpan? cur = innermostSlotAt(t, rel);
  if (cur != null && cur.start < rel) return cur.start;
  // ③ 走出公式
  return null;
}

// ---------------------------------------------------------------- ↑↓ 竖直邻接

/// 分式家族：`arg0` 在上、`arg1` 在下
const Set<String> _kStackCommands = <String>{
  'frac', 'dfrac', 'tfrac', 'cfrac', 'binom', 'dbinom', 'tbinom',
  'overset', 'underset', 'stackrel',
};

/// 「上下限」型大算符：它们的 `^`/`_` 真的是**上下**；而 `x^2` 的指数是**右上**
/// （设计稿 §三 的说明）—— 所以 `^`/`_` 的竖直关系**只在大算符上成立**。
const Set<String> _kLargeOps = <String>{
  'sum', 'prod', 'coprod', 'int', 'oint', 'iint', 'iiint',
  'lim', 'max', 'min', 'sup', 'inf', 'limsup', 'liminf', 'argmax', 'argmin',
  'bigcup', 'bigcap', 'bigvee', 'bigwedge', 'bigoplus', 'bigotimes', 'bigodot',
  'bigsqcup', 'biguplus',
};

/// `↑`/`↓` 的落点（相对偏移）；`null` = **没有竖直邻居 → 不移动**（§三：不要乱跳）。
int? verticalNeighbor(CaretSiteTable t, int rel, {required bool up}) {
  if (t.degraded) return null;
  final SlotSpan? cur = innermostSlotAt(t, rel);
  if (cur == null || cur.path.isEmpty) return null; // 主行上没有"竖直邻居"（v1）
  final SlotStep me = cur.path.last;

  // ① 分式家族：分子(arg0) ↔ 分母(arg1)
  if (_kStackCommands.contains(me.command) && (me.argIndex == 0 || me.argIndex == 1)) {
    return _siblingStart(t, cur.path, up ? 0 : 1);
  }
  // ② 根号：次数（`[n]` → argIndex -1，在上） ↔ 被开方数（arg0，在下）
  if (me.command == 'sqrt' && (me.argIndex == 0 || me.argIndex == -1)) {
    return _siblingStart(t, cur.path, up ? -1 : 0);
  }
  // ③ 大算符上下限：`^` 在上、`_` 在下（落点同样是槽的右端）
  if ((me.command == '^' || me.command == '_') &&
      _baseIsLargeOperator(t.tex, cur.start, me)) {
    return _siblingArg(t, cur.path, up ? '^' : '_', 0, atEnd: true);
  }
  return null;
}

/// 同结构实例里 `argIndex == want` 那个槽的**内容末尾**。
///
/// ★ 落点是**槽的右端**（2026-10-14 用户拍板）：
/// 上下跨越通常是"换个地方接着往后写"，落在末尾才能直接续写；
/// 落在左端则每次都要先 `→` 走一遍内容。（"保持列位置"是 §三 的几何法，留 S5。）
int? _siblingStart(CaretSiteTable t, List<SlotStep> path, int want) =>
    _siblingArg(t, path, path.last.command, want, atEnd: true);

int? _siblingArg(CaretSiteTable t, List<SlotStep> path, String command, int argIndex,
    {bool atEnd = false}) {
  if (path.isEmpty) return null;
  final List<SlotStep> parent = path.sublist(0, path.length - 1);
  final SlotStep me = path.last;
  for (final SlotSpan s in t.slots) {
    if (s.path.isEmpty) continue;
    final SlotStep last = s.path.last;
    if (last.command != command || last.argIndex != argIndex) continue;
    if (last.row != me.row || last.col != me.col) continue;
    if (!_samePath(s.path.sublist(0, s.path.length - 1), parent)) continue;
    return atEnd ? s.end : s.start;
  }
  return null;
}

/// `^`/`_` 的基座是不是一个大算符？（`\sum_{i}^{n}` 的上下限算"上下"，`x^2` 不算）
///
/// ★ 必须**倒着跳过夹在中间的其它脚本**：`\sum_{i}^{n}` 里 `^` 前面是 `_{i}`，
/// 直接正则 `\\cmd\s*$` 会因为末尾是 `}` 而匹配不上（实测踩过）。
bool _baseIsLargeOperator(String tex, int slotStart, SlotStep me) {
  var i = slotStart - 1;
  // 花括号形式 `^{...}`：内容起点前面是 `{`，再前面才是 `^`
  if (i >= 0 && tex[i] == '{') i--;
  if (i < 0 || tex[i] != me.command) return false;
  i--; // 越过 `^` / `_`
  while (i >= 0) {
    final String c = tex[i];
    if (c == ' ') {
      i--;
      continue;
    }
    if (c == '}') {
      // 跳过整个 `{...}`（倒着数括号）
      var depth = 0;
      while (i >= 0) {
        if (tex[i] == '}') {
          depth++;
        } else if (tex[i] == '{') {
          depth--;
          if (depth == 0) {
            i--;
            break;
          }
        }
        i--;
      }
      continue;
    }
    if (c == '^' || c == '_') {
      // 相邻的另一个脚本符号本身也要越过（`\sum_{i}^{n}` 倒着走会先遇到 `_`）
      i--;
      continue;
    }
    break;
  }
  final Match? m = RegExp(r'\\([A-Za-z]+)$').firstMatch(tex.substring(0, i + 1));
  return m != null && _kLargeOps.contains(m.group(1));
}
