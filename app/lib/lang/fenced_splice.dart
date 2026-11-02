// 数语引擎 · **带围栏的自动展开落盘**（2026-11-02，R-甲1/2 收口）
//
// 背景：`_planScript` 的"整对括号当基座"分支返回的是一段**完整行内公式**（`$…$`），
// 不是裸 tex。旧路径把它交给 `applySymbolInsert`（它的契约是"裸 tex + 光标在哪"）：
//   · 光标紧贴公式 ⇒ 规则 ①b 把它推出公式，规则 ⑤ 再补一个**换行** ⇒ 公式掉行；
//   · 光标在正文里 ⇒ 被**再包一层 `$`** 成 `$$…$$` ⇒ 判成行间块。
// 本文件只做一件事：把"把某个区间换成一段完整行内公式"做对。
//
// 口径（2026-11-02 用户拍板「乙」）：
//   · 左 / 右**紧贴**一段行内公式 ⇒ **合并围栏**（只移动 `$`，**零新增字符**）；
//   · 邻居是文字 / 行首 / 行尾 ⇒ 直接放（`ln$…$` 本来就不会产生 `$$`）；
//   · 邻居是 `$$`（行间）⇒ 不处理，返回 null 交给旧路径（只可能是畸形文档）。
//
// **纯 Dart，不依赖 Flutter。**

import '../render/math_nav.dart';
import 'symbol_insert.dart' show firstSlotOffset;

/// 一次落盘的结果。
class FencedSplice {
  const FencedSplice({
    required this.doc,
    required this.caret,
    required this.mergedLeft,
    required this.mergedRight,
    required this.leftSpace,
    required this.rightSpace,
  });

  /// 新文档（整份替换进 `DocBuffer`）
  final String doc;

  /// 新光标（模板 = 空槽里；撇 = 载荷之后）
  final int caret;

  /// 左邻 / 右邻的行内公式被合并了
  final bool mergedLeft;
  final bool mergedRight;

  /// 畸形兜底：确实紧贴 `$`、但那一侧不是可合并的段 ⇒ 补一个空格防 `$$`
  /// （**只应出现在畸形文档里**，守卫钉着）
  final bool leftSpace;
  final bool rightSpace;

  @override
  String toString() => 'FencedSplice(mergedLeft=$mergedLeft, '
      'mergedRight=$mergedRight, leftSpace=$leftSpace, rightSpace=$rightSpace, '
      'caret=$caret, doc="${doc.replaceAll('\n', r'\n')}")';
}

/// 把 `[from, to)` 换成一段**完整行内公式** [fenced]（必须是恰好一对 `$`）。
///
/// 返回 `null`：`fenced` 不是完整行内公式，或邻居是 `$$`（畸形，交给旧路径）。
FencedSplice? spliceFencedInline({
  required String doc,
  required int from,
  required int to,
  required String fenced,
  required bool template,
}) {
  if (!_isCompleteInlineMath(fenced)) return null;

  final int a = from.clamp(0, doc.length);
  final int b = to.clamp(a, doc.length);

  // 邻居是 `$$` 的任一半 ⇒ 不在这里处理（正常文档里不可能：行间围栏独占一行）。
  final bool leftDouble =
      a > 0 && doc[a - 1] == r'$' && a >= 2 && doc[a - 2] == r'$';
  final bool rightDouble =
      b < doc.length && doc[b] == r'$' && b + 1 < doc.length && doc[b + 1] == r'$';
  if (leftDouble || rightDouble) return null;

  // ---- 左邻：紧贴一段**行内**公式的收尾 `$` ----
  MathRegion? left;
  if (a > 0 && doc[a - 1] == r'$') {
    final MathRegion? r = mathRegionAt(doc, a - 1);
    if (r != null && r.closeEnd == a && !r.isDisplay) left = r;
  }

  // ---- 右邻：紧贴一段**行内**公式的开头 `$` ----
  MathRegion? right;
  if (b < doc.length && doc[b] == r'$') {
    final MathRegion? r = mathRegionAt(doc, b + 1);
    if (r != null && r.openStart == b && !r.isDisplay) right = r;
  }

  final String inner = fenced.substring(1, fenced.length - 1);
  final String head = left?.tex ?? '';
  final String tail = right?.tex ?? '';
  final int start = left?.openStart ?? a;
  final int end = right?.closeEnd ?? b;

  // 兜底：确实紧贴一个 `$`（且不是 `$$`），但那一侧不是可合并的段（落单 `$` 等畸形）
  final bool leftSpace = left == null && a > 0 && doc[a - 1] == r'$';
  final bool rightSpace = right == null && b < doc.length && doc[b] == r'$';

  final StringBuffer out = StringBuffer()
    ..write(doc.substring(0, start));
  if (leftSpace) out.write(' ');
  out
    ..write(r'$')
    ..write(head)
    ..write(inner)
    ..write(tail)
    ..write(r'$');
  if (rightSpace) out.write(' ');
  out.write(doc.substring(end));

  final String newDoc = out.toString();
  final int innerStart = start + (leftSpace ? 1 : 0) + 1 + head.length;
  final int caret = template
      ? innerStart + (firstSlotOffset(fenced) - 1)
      : innerStart + inner.length;

  return FencedSplice(
    doc: newDoc,
    caret: caret.clamp(0, newDoc.length),
    mergedLeft: left != null,
    mergedRight: right != null,
    leftSpace: leftSpace,
    rightSpace: rightSpace,
  );
}

/// `$…$`，且里面**没有**第二个 `$` ⇒ 一段完整的行内公式。
bool _isCompleteInlineMath(String s) {
  if (s.length < 3) return false;
  if (!s.startsWith(r'$') || !s.endsWith(r'$')) return false;
  return !s.substring(1, s.length - 1).contains(r'$');
}
