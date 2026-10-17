// 选区的**语义单位**：双击选什么、三击选什么（2026-10-17 用户拍板）
//
// · 双击 = **同层对象**：文本里 = 连续字母数字；数学段里 = **一个可见原子**
//   （`\frac{a}{b}` 双击选中整个分式、`\sum_{i=1}^{n}` 双击选中整个 ∑ 节点 —— 与"位点/对象"体系一致）
// · 三击 = **整个单元**：行间公式块 = 整块；其余 = 整行

import 'math_nav.dart';
import 'visible_atoms.dart';

/// 双击选中的区间（绝对偏移，`[start, end)`；`start == end` 表示没找到可选的单位）
({int start, int end}) wordRangeAt(String source, int offset) {
  final int o = offset.clamp(0, source.length);
  final MathRegion? m = mathRegionAt(source, o);
  if (m != null) {
    // ★ 数学段里：选**一个可见原子**（它是有墨迹的那个对象）
    final int rel = (o - m.contentStart).clamp(0, m.tex.length);
    // 找**覆盖该偏移**的可见原子；落在边界上时取"后一个"（与右键/双击的直觉一致）
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
