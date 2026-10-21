// 选区的**语义单位**：双击选什么、三击选什么（2026-10-17 用户拍板，2026-10-21 修订）
//
// · 双击 = **同层对象**：文本里 = 连续字母数字；数学段里 = **一个渲染节点**
//   （★ 2026-10-21 用户拍板「乙」：一个字形 + 它挂的上下标 / 一个结构 + 它的全部参数
//   ⇒ `a^2`、`x_n`、`\frac{a}{b}`、`\sum_{i=1}^{n}` 各算一个对象；`a` 单独**不是**对象。
//   节点表 = `caret_sites.CaretSiteTable.nodes`，与"位点/结构"共用一份判据）
// · 三击 = **整个单元**：行间公式块 = 整块；其余 = 整行

import 'caret_sites.dart';
import 'math_nav.dart';
import 'visible_atoms.dart';

/// 双击选中的区间（绝对偏移，`[start, end)`；`start == end` 表示没找到可选的单位）
({int start, int end}) wordRangeAt(String source, int offset) {
  final int o = offset.clamp(0, source.length);
  final MathRegion? m = mathRegionAt(source, o);
  if (m != null) {
    // ★★ 数学段里：选**一个渲染节点**（2026-10-21 用户拍板「乙」）
    //   定义 = 一个字形 + 它挂的上下标 / 一个结构 + 它的全部参数
    //   ⇒ `a^2`、`x_n`、`\frac{a}{b}`、`\sum_{i=1}^{n}` 各算**一个**对象；
    //   `a` 单独**不是**对象（平权：它没有意义）。
    //   节点表来自位点表（`CaretSiteTable.nodes`），与"位点/结构"共用一份判据。
    final int rel = (o - m.contentStart).clamp(0, m.tex.length);
    final List<MathNode> nodes = buildCaretSites(m.tex).nodes;
    MathNode? node;
    for (final MathNode n in nodes) {
      if (rel >= n.start && rel < n.end) {
        node = n;
        break;
      }
    }
    if (node == null) {
      // 光标贴着某个节点的末尾（点击右缘很常见）⇒ 也算选它
      for (final MathNode n in nodes) {
        if (rel == n.end) {
          node = n;
          break;
        }
      }
    }
    if (node != null && node.length > 0) {
      return (start: m.contentStart + node.start, end: m.contentStart + node.end);
    }
    // 兜底（位点表降级 / 空段）：退回"一个可见原子"的旧口径
    VisibleAtom? hit;
    for (final VisibleAtom a in lexVisibleAtoms(m.tex)) {
      if (rel >= a.start && rel < a.end) {
        hit = a;
        break;
      }
      if (rel == a.start) {
        hit = a;
        break;
      }
    }
    if (hit == null) return (start: o, end: o);
    return (start: m.contentStart + hit.start, end: m.contentStart + hit.end);
  }
  // 文本里：连续字母数字（中英各自成词；下划线/连字符不断词）
  var s = o;
  var e = o;
  while (s > 0 && _isWordChar(source.codeUnitAt(s - 1))) {
    s--;
  }
  while (e < source.length && _isWordChar(source.codeUnitAt(e))) {
    e++;
  }
  if (s == e) return (start: o, end: o);
  return (start: s, end: e);
}

/// 三击选中的区间：行间公式块（`$$…$$`）= 整块；其余 = 整行
({int start, int end}) unitRangeAt(String source, int offset) {
  final int o = offset.clamp(0, source.length);
  final MathRegion? m = mathRegionAt(source, o);
  if (m != null && m.isDisplay) {
    return (start: m.openStart, end: m.closeEnd);
  }
  final int lineStart = o == 0 ? 0 : source.lastIndexOf('\n', o - 1) + 1;
  var lineEnd = source.indexOf('\n', o);
  if (lineEnd < 0) lineEnd = source.length;
  return (start: lineStart, end: lineEnd);
}

bool _isWordChar(int c) {
  // 字母 / 数字 / 下划线 / 汉字
  if (c >= 0x30 && c <= 0x39) return true; // 0-9
  if (c >= 0x41 && c <= 0x5A) return true; // A-Z
  if (c >= 0x61 && c <= 0x7A) return true; // a-z
  if (c == 0x5F) return true; // _
  if (c >= 0x4E00 && c <= 0x9FFF) return true; // 汉字
  return false;
}
