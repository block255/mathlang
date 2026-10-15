// 数语引擎 · 结构感知删除（S3-4 · smart delete）
//
// 规格：notes/design/位点与结构导航.md §四。目标手感：**像删字符一样干脆，但永不留下半个坏公式**。
//   §4.1 原子删除 —— 紧邻一个**可见原子** → 整个原子一起删（`\alpha` 5 个字符一次删光）
//   §4.2 槽间跨越 —— 光标在槽首/槽末、而前/后一个位点在**别的槽** → **只跳不删**
//   §4.3 结构单元 —— **全空才删**（`\frac{}{}` 9 个字符一次消失；任一槽非空则绝不拆结构）
//   §4.4 降级模式 —— 配对失败 → 退化为**字节级**（笨但可预测）
//   §4.5 与 normalize 分工 —— 本文件**不做回收**，多余花括号只在提交点清（§七）
//
// ★ 本文件是**纯函数**，只在「一个数学段的 tex + 段内相对偏移」这一层工作。
//   文档级边界（公式首/公式空壳要不要连定界符一起删）由 `math_nav.dart` 处理。
//
// **纯 Dart，不依赖 Flutter。**

import 'caret_sites.dart';
import 'projection.dart' show isAsciiLetter;
import 'site_adjacency.dart';
import 'visible_atoms.dart';

/// 一次删除的处置结果。
class SmartEdit {
  const SmartEdit._(this.caret, this.from, this.to);

  /// **只把光标挪走**，不删任何东西（§4.2 槽间跨越）
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
class StructureUnit {
  const StructureUnit(this.start, this.end, this.slots);

  /// 结构起点（`\` 或 `^`/`_`）
  final int start;

  /// 结构终点（最后一个参数的收尾 `}` 之后）
  final int end;

  final List<SlotSpan> slots;

  /// **全空**才允许整体删除（§4.3）
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

/// `Backspace`：段内相对偏移 [rel] 处往前删。
SmartEdit smartBackspace(CaretSiteTable t, int rel) {
  final int r = rel.clamp(0, t.tex.length);
  if (r <= 0) return SmartEdit.none;

  // §4.4 降级：字节级，笨但可预测
  if (t.degraded) return SmartEdit.remove(r - 1, r, r - 1);

  // §4.3 全空结构：整段删（`\frac{}{}` 一次消失）
  for (final StructureUnit u in structureUnits(t)) {
    if (u.allEmpty && u.end == r) {
      return SmartEdit.remove(u.start, u.end, u.start);
    }
  }

  // §4.2 槽间跨越：在**槽首**、且前一个位点在别的槽 → 只跳不删
  final CaretSite s = t.snap(r);
  final int idx = t.indexOf(s.offset);
  final SlotSpan? cur = innermostSlotAt(t, s.offset);
  if (cur != null && s.offset == cur.start && idx > 0) {
    return SmartEdit.move(t.sites[idx - 1].offset);
  }

  // §4.1 原子删除：紧邻左侧的可见原子
  final VisibleAtom? atom = _atomLeftOf(t.tex, r);
  if (atom != null) return _removeAtom(t.tex, atom, forward: false);

  // 单独删一个 `{` 会破坏配对 → 删整组 `{...}`
  if (t.tex[r - 1] == '{') {
    final int close = matchBrace(t.tex, r - 1);
    if (close > 0) {
      // ★★ 若这个组是 `^`/`_` 的参数，**必须连 `^`/`_` 一起删** ——
      //   否则会剩一个**悬空的 `^`** → `Parser Error: Expected group after '^'`（用户实测抓出）。
      //   脚本（`^{...}`）本来就是一个整体：要么都在，要么都不在。
      final int from =
          (r >= 2 && (t.tex[r - 2] == '^' || t.tex[r - 2] == '_')) ? r - 2 : r - 1;
      return SmartEdit.remove(from, close + 1, from);
    }
  }

  return SmartEdit.remove(r - 1, r, r - 1); // 兜底（理论上很少走到）
}

/// `Delete`：段内相对偏移 [rel] 处往后删（与 [smartBackspace] 镜像）。
SmartEdit smartDelete(CaretSiteTable t, int rel) {
  final int r = rel.clamp(0, t.tex.length);
  if (r >= t.tex.length) return SmartEdit.none;

  if (t.degraded) return SmartEdit.remove(r, r + 1, r);

  // §4.3 全空结构：整段删
  for (final StructureUnit u in structureUnits(t)) {
    if (u.allEmpty && u.start == r) {
      return SmartEdit.remove(u.start, u.end, u.start);
    }
  }

  // §4.2 槽间跨越：在**槽末**、且后一个位点在别的槽 → 只跳不删
  final CaretSite s = t.snap(r);
  final int idx = t.indexOf(s.offset);
  final SlotSpan? cur = innermostSlotAt(t, s.offset);
  if (cur != null && s.offset == cur.end && idx >= 0 && idx + 1 < t.sites.length) {
    final CaretSite next = t.sites[idx + 1];
    final SlotSpan? nextSlot = innermostSlotAt(t, next.offset);
    if (nextSlot == null || !_sameSpan(nextSlot, cur)) {
      return SmartEdit.move(next.offset);
    }
  }

  // §4.1 原子删除
  final VisibleAtom? atom = _atomRightOf(t.tex, r);
  if (atom != null) return _removeAtom(t.tex, atom, forward: true);

  if (r < t.tex.length && t.tex[r] == '{') {
    final int close = matchBrace(t.tex, r);
    if (close > 0) {
      // ★★ 同 smartBackspace：若这个组是 `^`/`_` 的参数，连 `^`/`_` 一起删（否则留悬空的 `^`）
      final int from =
          (r >= 1 && (t.tex[r - 1] == '^' || t.tex[r - 1] == '_')) ? r - 1 : r;
      return SmartEdit.remove(from, close + 1, from);
    }
  }

  return SmartEdit.remove(r, r + 1, r);
}

// ---------------------------------------------------------------- 内部工具

/// 删一个可见原子 —— ★ 若它是 `^`/`_` 的**裸参数**（`b^2` 没有花括号），
/// **必须连 `^`/`_` 一起删**。
///
/// 为什么（2026-10-14 用户实测抓出，并给出了精确复现路径）：
/// 在 `\sqrt{b^2-4ac}` 里把光标放在 `c` 后面连按删除键，删到 `b^2` 的 `2` 时，
/// 只删 `2` 会得到 **`b^-4ac`** —— 引擎立刻报
/// `Parser Error: Expected group after '^'`。
/// 脚本（`^2`）本来就是一个整体：**要么都在，要么都不在**。
/// （花括号形式 `b^{2}` 不受影响：删掉内容得到 `b^{}` 仍然合法。）
SmartEdit _removeAtom(String tex, VisibleAtom atom, {required bool forward}) {
  final int start = atom.start;
  final int from = (start >= 1 && (tex[start - 1] == '^' || tex[start - 1] == '_'))
      ? start - 1
      : start;
  return SmartEdit.remove(from, atom.end, from);
}

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

bool _sameSpan(SlotSpan a, SlotSpan b) =>
    a.start == b.start && a.end == b.end && _pathKey(a.path) == _pathKey(b.path);

/// 紧邻 [rel] **左侧**的可见原子 —— §4.0 通则："左边第一个**看得见**的对象"。
///
/// ★ 2026-10-15：**去掉了"中间只能夹花括号/空格"的限制**（原限制见下方 `_atomRightOf`）。
/// 中间夹着的东西（命令名 / `^` `_` / `{` `}` / 间距命令）本来就都是**不可见**的语法，
/// 跨过去删"第一个看得见的东西"才是通则的意思；否则会掉进字节级兜底、**删到语法字符**上。
VisibleAtom? _atomLeftOf(String tex, int rel) {
  VisibleAtom? best;
  for (final VisibleAtom a in lexVisibleAtoms(tex)) {
    if (a.end > rel) continue;
    if (best == null || a.end > best.end) best = a;
  }
  return best;
}

/// 紧邻 [rel] **右侧**的可见原子 —— §4.0 通则："右边第一个**看得见**的对象"。
///
/// ★★ 2026-10-15 修（新写的测试当场抓出来的**另一个同类 bug**）：
/// 原实现要求"光标与原子之间只允许夹 `{` `}` 和空格"，于是
/// **`Delete` 在 `\frac{a}{b}` 的最开头（rel = 0）会返回 null → 掉进字节级兜底
/// → 把命令的 `\` 删掉**（得到 `frac{a}{b}`）—— 又是"删到了看不见的语法"。
/// 顺带修好对称的一面：`x^2` 里把光标放在 `x` 与 `^` 之间按 `Delete`，
/// 原文会删掉裸 `^`（留下 `x2`），现在会连 `^2` 一起删（与退格侧一致，见 `_removeAtom`）。
VisibleAtom? _atomRightOf(String tex, int rel) {
  VisibleAtom? best;
  for (final VisibleAtom a in lexVisibleAtoms(tex)) {
    if (a.start < rel) continue;
    if (best == null || a.start < best.start) best = a;
  }
  return best;
}
