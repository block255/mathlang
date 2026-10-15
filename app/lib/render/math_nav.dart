// 数语引擎 · 数学段的文档级导航与删除（S3-3 + S3-4 的胶水层）
//
// 位点表 / 槽序（`caret_sites.dart` + `site_adjacency.dart`）与原子删除（`smart_delete.dart`）
// 都只在「**一个数学段的 tex** + 段内相对偏移」这一层工作。本文件负责把它们接到文档层：
//   · 找到光标所在的数学段（行内 `$...$` 走投影；行间 `$$ … $$` 走块模型）
//   · `←→` 跨 `$` 边界**进出公式**（§3.3：光标**不落在 `$` 上**）
//   · `Tab` / `↑↓` 在段内没有落点时**走出公式**
//   · **公式首退格**（§3.3）：前面是文字 → 删该文字；公式是空壳 → 连定界符整段删
//
// **纯 Dart，不依赖 Flutter。**

import '../core/block.dart';
import 'caret_sites.dart';
import 'projection.dart';
import 'site_adjacency.dart';
import 'smart_delete.dart';

/// 文档里的一个数学段（全部是**绝对**偏移）
class MathRegion {
  const MathRegion({
    required this.openStart,
    required this.contentStart,
    required this.contentEnd,
    required this.closeEnd,
    required this.tex,
    required this.isDisplay,
  });

  /// 开头定界符的起点（`$` 或 `$$` 的第一个字符）
  final int openStart;

  /// tex 的起点（= 开头定界符之后）
  final int contentStart;

  /// tex 的终点（= 收尾定界符的位置）
  final int contentEnd;

  /// 收尾定界符之后（= 出公式后光标的落点）
  final int closeEnd;

  /// 不含定界符的源码
  final String tex;

  /// 行间公式块（`$$ … $$`）还是行内（`$...$`）
  final bool isDisplay;

  /// tex 内的相对偏移 → 文档绝对偏移
  int abs(int rel) => contentStart + rel;

  /// 文档绝对偏移 → tex 内的相对偏移
  int rel(int abs) => abs - contentStart;

  @override
  String toString() => 'MathRegion[$openStart..$closeEnd)'
      '${isDisplay ? ' 行间' : ' 行内'} tex="$tex"';
}

/// 光标（绝对偏移）所在的数学段；不在任何数学段里则 `null`。
///
/// ★ 判定区间是 **`[contentStart, contentEnd]`**（两个定界符**之间**）：
/// 光标位置是"字符之间的缝"，所以 `contentStart - 1` 就是 `$` 之前那个缝（属于文字侧），
/// `contentEnd + 1` 是 `$` 之后那个缝（也属于文字侧）。这样"进出公式"才不会在边界上卡住。
MathRegion? mathRegionAt(String source, int offset) {
  final int o = offset.clamp(0, source.length);
  final BlockIndex idx = BlockIndex.parse(source);
  final LineIndex lines = idx.lines;
  final int line = lines.lineOf(o);

  // ① 行间公式块（`$$ … $$`）：整块的排版文本就是 tex
  for (final Block b in idx.blocks) {
    if (line < b.lineFrom || line >= b.lineTo) continue;
    if (b.type != BlockType.math) break;
    final int start = lines.starts[b.lineFrom];
    final int end = lines.ends[b.lineTo - 1];
    final String body = source.substring(start, end);
    final _Fence? f = _stripFence(body);
    if (f == null) break;
    return MathRegion(
      openStart: start,
      contentStart: start + f.prefix,
      contentEnd: start + f.prefix + f.tex.length,
      closeEnd: end,
      tex: f.tex,
      isDisplay: true,
    );
  }

  // ② 行内 `$...$`：在光标所在行里找（投影规则与渲染层完全一致）
  final int lineStart = lines.starts[line];
  for (final ProjectionSegment s in projectInline(lines.text(line))) {
    if (!s.isMath) continue;
    final int cs = lineStart + s.start; // tex 起点
    final int ce = lineStart + s.end; // 收尾 `$` 的位置
    if (o >= cs && o <= ce) {
      return MathRegion(
        openStart: cs - 1,
        contentStart: cs,
        contentEnd: ce,
        closeEnd: ce + 1,
        tex: s.tex,
        isDisplay: false,
      );
    }
  }
  return null;
}

/// 行间公式块只有**围栏式**（第一行就是 `$$`）才算得出 tex；
/// 其它形态（`$$x$$` 一行写完）本版不处理，返回 null（宁可不动，也不要算错）。
_Fence? _stripFence(String body) {
  final int nl = body.indexOf('\n');
  if (nl < 0) return null;
  if (body.substring(0, nl).trim() != r'$$') return null;
  final int lastNl = body.lastIndexOf('\n');
  if (lastNl <= nl) return null;
  if (body.substring(lastNl + 1).trim() != r'$$') return null;
  return _Fence(nl + 1, body.substring(nl + 1, lastNl));
}

class _Fence {
  const _Fence(this.prefix, this.tex);
  final int prefix;
  final String tex;
}

// ---------------------------------------------------------------- ←→

/// `→`：下一个文档级光标落点。**跨 `$` 边界进公式，且光标不落在 `$` 上。**
int nextCaretOffset(String source, int offset) {
  final int o = offset.clamp(0, source.length);
  final MathRegion? r = mathRegionAt(source, o);
  if (r == null) {
    // 文字里：右边紧邻一个 `$` → 直接进该公式的**第一个位点**
    final MathRegion? nr = o + 1 <= source.length ? mathRegionAt(source, o + 1) : null;
    if (nr != null && nr.openStart == o) {
      final CaretSiteTable t = buildCaretSites(nr.tex);
      return nr.abs(t.snap(0).offset);
    }
    return o + 1;
  }
  final CaretSiteTable t = buildCaretSites(r.tex);
  final CaretSite s = t.snap(r.rel(o));
  final int i = t.indexOf(s.offset);
  // ★★ 「甲」方案（2026-10-15 用户拍板）：**`→` 跳过"数学段内的末尾位点"**。
  //
  // 为什么：`tex.length` 那个位点（= 闭合 `$` 所在那一格）与 `closeEnd`（公式之后）
  // **在屏幕上是同一根像素** —— 收尾 `$` 不可见，两者无从分辨。停在它上面有两个害处：
  //   ① 用户按 `→` 会以为"按了没反应"（光标其实挪了，只是看不出来）
  //   ② 在它上面断块会把公式**劈开**（`$` 配成单数 → 整行退化成源码；用户实测抓出）
  // ⇒ `→` 的语义是"往前走 / 出去"，就**一步出公式**，不停在看不见的边界上。
  //
  // ★ `←` **故意不跳**（见 [prevCaretOffset]）：从公式外面进到公式末尾，
  //   是"我要继续改这段数学"的正当动作 —— 这是**有意的不对称**：`←` 进去、`→` 出去。
  final int next = i + 1;
  if (next < t.sites.length && t.sites[next].offset < r.tex.length) {
    return r.abs(t.sites[next].offset);
  }
  return r.closeEnd; // 段内没有更靠右的位点了 → 走出到 `$` 之后
}

/// `←`：上一个文档级光标落点（与 [nextCaretOffset] 镜像）。
int prevCaretOffset(String source, int offset) {
  final int o = offset.clamp(0, source.length);
  final MathRegion? r = mathRegionAt(source, o);
  if (r == null) {
    // 文字里：左边紧邻一个收尾 `$` → 进该公式的**最后一个位点**
    final MathRegion? pr = o - 1 >= 0 ? mathRegionAt(source, o - 1) : null;
    if (pr != null && pr.closeEnd == o) {
      final CaretSiteTable t = buildCaretSites(pr.tex);
      return pr.abs(t.sites.last.offset);
    }
    return o - 1;
  }
  final CaretSiteTable t = buildCaretSites(r.tex);
  final CaretSite s = t.snap(r.rel(o));
  final int i = t.indexOf(s.offset);
  if (i > 0) return r.abs(t.sites[i - 1].offset);
  return r.openStart; // 段内第一个位点 → 走出到 `$` 之前
}
// ★ 注意：`←` **不做**「跳过 tex 末位点」那件事（与 [nextCaretOffset] 有意不对称）——
//   从公式外面按 `←` 就是要**进到公式末尾**继续改这段数学，那是正当落点。

// ---------------------------------------------------------------- Tab / ↑↓

/// `Tab`（`forward`）/ `Shift+Tab` 的落点；`null` = **不在公式里，Tab 交给焦点遍历**。
///
/// 段内没有落点时**走出公式**（§十-①：空槽 → 槽末尾 → 退出公式）。
int? tabStopAt(String source, int offset, {required bool forward}) {
  final MathRegion? r = mathRegionAt(source, offset);
  if (r == null) return null;
  final CaretSiteTable t = buildCaretSites(r.tex);
  final int rel = r.rel(offset.clamp(0, source.length));
  final int? next = forward ? tabForward(t, rel) : tabBackward(t, rel);
  if (next != null) return r.abs(next);
  return forward ? r.closeEnd : r.openStart;
}

/// `↑`/`↓` 的落点；`null` = **没有竖直邻居 → 不移动**（§三：不要乱跳）。
int? verticalStopAt(String source, int offset, {required bool up}) {
  final MathRegion? r = mathRegionAt(source, offset);
  if (r == null) return null;
  final CaretSiteTable t = buildCaretSites(r.tex);
  final int? v = verticalNeighbor(t, r.rel(offset.clamp(0, source.length)), up: up);
  return v == null ? null : r.abs(v);
}

// ---------------------------------------------------------------- 退格 / 删除

/// 文档级 `Backspace` / `Delete` 的处置（**绝对偏移**）。
///
/// 不在数学段里 → 字节级；在段里 → 交给 [smartBackspace] / [smartDelete]，
/// 段内已无可删时处理**公式首/公式尾的边界语义**（§3.3）。
SmartEdit smartEditAt(String source, int offset, {required bool forward}) {
  final int o = offset.clamp(0, source.length);
  final MathRegion? r = mathRegionAt(source, o);

  // ① 不在公式里（含"紧贴公式**外侧**"）→ 交给文字层：
  //    删的是**左右紧邻的那一个可见对象**（§4.0 通则；数学段算一个对象）
  if (r == null) return _textLayerDelete(source, o, forward: forward);

  final CaretSiteTable t = buildCaretSites(r.tex);
  final int rel = r.rel(o);
  final SmartEdit e = forward ? smartDelete(t, rel) : smartBackspace(t, rel);
  if (!e.isNone) {
    if (!e.deletes) return SmartEdit.move(r.abs(e.caret));
    return SmartEdit.remove(r.abs(e.from!), r.abs(e.to!), r.abs(e.caret));
  }

  // ③ 段内没得删 → 边界语义。
  //    ★★ 关键：先处理空壳，再把落点**挪到定界符外侧**、回到 ① 的"可见对象"规则 ——
  //    **不要**在这里自己写"删一个字符"：外侧紧邻的可能**又是一个公式段**
  //    （`$\frac{}{}$$\frac{}{}$` 这种相邻写法），那时要删的是**那一整段**，
  //    而不是它那个看不见的定界符。全域不变量测试当场抓出过这一条。
  final bool emptyShell = r.tex.trim().isEmpty;
  if (!forward && rel <= 0) {
    if (emptyShell) return SmartEdit.remove(r.openStart, r.closeEnd, r.openStart);
    return _textLayerDelete(source, r.openStart, forward: false);
  }
  if (forward && rel >= r.tex.length) {
    if (emptyShell) return SmartEdit.remove(r.openStart, r.closeEnd, r.openStart);
    return _textLayerDelete(source, r.closeEnd, forward: true);
  }
  return SmartEdit.none;
}

/// **文字层**的删除：删的是"左右紧邻的那一个**可见对象**"（设计稿 §4.0 通则）。
///
/// · 文字里一个对象 = **一个字符**
/// · **数学段一个对象 = 整个公式段**（含定界符）—— 它渲染出来就是**一个**东西
///
/// ★★ 为什么必须这样（2026-10-15 用户实测 + 全域不变量测试）：
/// 定界符 `$` 对用户**不可见**，删掉它只会让"半个公式"的源码爆出来（违反原则 2）。
/// 原先这里是两句字节级 `remove(o∓1, o)`，于是两条路都会删到 `$`：
///   ① 光标在公式**之后**退格 → 删掉收尾 `$`（**用户报的那条**）
///   ② 光标在公式 A 的**末尾**按 `Delete` → A 之后紧邻的正好是公式 B 的开头 `$`
///      → 把 B 的定界符删了（**新写的全域测试当场抓出来的**）
SmartEdit _textLayerDelete(String source, int offset, {required bool forward}) {
  final int o = offset.clamp(0, source.length);
  if (!forward) {
    // `Backspace`：左边紧邻的是一个公式段？→ 删整段
    final MathRegion? prev = o - 1 >= 0 ? mathRegionAt(source, o - 1) : null;
    if (prev != null && prev.closeEnd == o) {
      return SmartEdit.remove(prev.openStart, prev.closeEnd, prev.openStart);
    }
    return o <= 0 ? SmartEdit.none : SmartEdit.remove(o - 1, o, o - 1);
  }
  // `Delete`：右边紧邻的是一个公式段？→ 删整段
  final MathRegion? next =
      o + 1 <= source.length ? mathRegionAt(source, o + 1) : null;
  if (next != null && next.openStart == o) {
    return SmartEdit.remove(next.openStart, next.closeEnd, next.openStart);
  }
  return o >= source.length ? SmartEdit.none : SmartEdit.remove(o, o + 1, o);
}
