// 数语引擎 · **粘贴的语境归一**（纯 Dart，2026-10-23 公测反馈 A1 / F2）
//
// 一句话模型（`notes\design\剪贴板与跨语境粘贴.md` §一）：
//   **复制 = 产出「自洽片段」；粘贴 = 把片段归一成目标语境。**
//
// 于是 `$` / `$$` 属于**语境的属性**：
//   · 粘进**文字流** ⇒ 原样（片段自带 `$…$` 就是一个行内公式）；
//   · 粘进**数学里**（行内 / 行间 / 任何结构槽：分子 / 根号 / 上下标 / 矩阵格 / 极限后面）
//     ⇒ **剥掉外层定界符**，只插 tex（否则就成了嵌套 `$`）；
//   · 多行载荷进**行间块** ⇒ **整块内容替换**（仍是一块 —— 用户报的 F2 就是这条）；
//   · 多行载荷进**行内公式** ⇒ **提升**成新的行间块放到本行之后（行内不许换行）。

import '../render/math_nav.dart';

/// 粘贴该怎么落地
enum PasteApply {
  /// 目标在文字流里：走原来的"智能包裹 → 插入"链
  asIs,

  /// 目标在数学里：载荷已归一成**纯 tex**（或原样），直接插，**不再跑智能包裹**
  mathTex,

  /// 目标在行间块里、载荷是多行/整块：**整块内容替换**
  replaceBlock,

  /// 目标在行内公式里、载荷是多行：**提升**成新行间块放到本行之后
  promoteBlock,

  /// 载荷是"文字 + 公式"混合，塞不进公式里：**推到公式之后**再按文字插入
  pushOut,
}

class PasteDecision {
  const PasteDecision({
    required this.apply,
    required this.payload,
    this.at,
    this.replaceFrom,
    this.replaceTo,
    this.note,
  });

  final PasteApply apply;

  /// 真正要写进缓冲区的文本（`asIs` 时是**原始载荷**，交给智能包裹）
  final String payload;

  /// 落点（`pushOut` / `replaceBlock` / `promoteBlock` 用；`null` = 用当前光标）
  final int? at;

  /// `replaceBlock` 的替换区间
  final int? replaceFrom;
  final int? replaceTo;

  /// 状态栏提示（**只有"我们替你动了手脚"的情况才有**，原则 5：不许静默）
  final String? note;

  @override
  String toString() =>
      'PasteDecision(${apply.name})${note == null ? '' : ' 「$note」'} '
      'payload="${payload.length > 40 ? '${payload.substring(0, 40)}…' : payload}"';
}

/// 决定这次粘贴怎么落地。
///
/// [selStart] / [selEnd]：有选区时给选区（替换语义），没有就都等于 [caret]。
PasteDecision decidePaste({
  required String doc,
  required int caret,
  required int selStart,
  required int selEnd,
  required String payload,
}) {
  if (payload.isEmpty) {
    return const PasteDecision(apply: PasteApply.asIs, payload: '');
  }
  final bool hasSel = selEnd > selStart;
  final int probe = (hasSel ? selStart : caret).clamp(0, doc.length);
  final MathRegion? r = mathRegionAt(doc, probe);
  // 目标不在数学里 ⇒ 原样走老路（智能包裹 + 插入）
  if (r == null) {
    return PasteDecision(apply: PasteApply.asIs, payload: payload);
  }

  final bool multi = payload.contains('\n');
  if (multi) {
    final String inner = (_stripFences(payload) ?? payload).trim();
    if (r.isDisplay) {
      // 行间块里粘多行 ⇒ **整块内容替换**（一个块仍然是一个块）
      return PasteDecision(
        apply: PasteApply.replaceBlock,
        payload: inner,
        replaceFrom: r.contentStart,
        replaceTo: r.contentEnd,
        at: r.contentStart + inner.length,
        note: '已把这一整块换成粘贴内容',
      );
    }
    // 行内公式里放不下多行 ⇒ 提升成新的行间块，放到**本行之后**（不劈开公式）
    return PasteDecision(
      apply: PasteApply.promoteBlock,
      payload: inner,
      at: _lineEndOf(doc, r.closeEnd),
      note: '行内公式里放不下多行，已作为行间块放到本行之后',
    );
  }

  final String? one = _stripOnePiece(payload);
  if (one != null) {
    return PasteDecision(apply: PasteApply.mathTex, payload: one);
  }
  if (payload.contains(r'$')) {
    // 文字 + 公式混合：拆不动，推到公式之后（不硬塞进 tex）
    return PasteDecision(
      apply: PasteApply.pushOut,
      payload: payload,
      at: r.closeEnd,
      note: '含公式的混合文本放不进公式里，已放到公式之后',
    );
  }
  // 纯 tex / 纯文字 ⇒ **原样插**（用户 2026-10-23 拍板：与"公式内打中文"同口径）
  return PasteDecision(apply: PasteApply.mathTex, payload: payload);
}

int _lineEndOf(String doc, int i) {
  final int at = doc.indexOf('\n', i.clamp(0, doc.length));
  return at < 0 ? doc.length : at;
}

/// 载荷**整体**正好是一个 `$$…$$` 块（多行）⇒ 返回里面的 tex
String? _stripFences(String s) {
  final String t = s.trim();
  if (t.length < 4 || !t.startsWith(r'$$') || !t.endsWith(r'$$')) return null;
  final String inner = t.substring(2, t.length - 2);
  if (inner.contains(r'$')) return null;
  return inner;
}

/// 载荷**整体**正好是一个 `$…$` / `$$…$$`（内部没有别的 `$`）⇒ 返回里面的 tex
String? _stripOnePiece(String s) {
  final String t = s.trim();
  if (t.length >= 4 && t.startsWith(r'$$') && t.endsWith(r'$$')) {
    final String inner = t.substring(2, t.length - 2);
    if (!inner.contains(r'$')) return inner;
    return null;
  }
  if (t.length >= 2 && t.startsWith(r'$') && t.endsWith(r'$')) {
    final String inner = t.substring(1, t.length - 1);
    if (!inner.contains(r'$')) return inner;
    return null;
  }
  return null;
}
