// 数语引擎 · **粘贴的语境归一**（纯 Dart，2026-10-23 公测反馈 A1 / F2；2026-10-26 批 37 改口径）
//
// 一句话模型（`notes\design\剪贴板与跨语境粘贴.md` §一）：
//   **复制 = 产出「自洽片段」；粘贴 = 把片段归一成目标语境。**
//
// 于是 `$` / `$$` 属于**语境的属性**：
//   · 粘进**文字流** ⇒ 原样（片段自带 `$…$` 就是一个行内公式）；
//   · 粘进**数学里**（行内 / 行间 / 任何结构槽：分子 / 根号 / 上下标 / 矩阵格 / 极限后面）
//     ⇒ **归一成 tex**：剥外层定界符，**内部成对的 `$…$` 也剥**（tex 里不许有 `$`）；
//   · 多行载荷进**行间块** ⇒ **整块内容替换**（仍是一块 —— 用户报的 F2 就是这条）；
//   · 多行载荷进**行内公式** ⇒ **提升**成新的行间块放到本行之后（行内不许换行）。
//
// ★★ 2026-10-26（批 37，用户实测 A2）**改掉了"混合文本推出去"这条**：
//   改前（2026-10-23 R6）：载荷里含 `$` 的"文字+公式"混排 ⇒ 拆不动 ⇒ 推到公式之后 + 说明。
//   改后：**归一成 tex 之后就地插**。依据（用户拍板 + 已实测）：
//     · 文字本来就能待在数学区里 —— 10-23 决定 2 实测 `x+中文+y` 与 `x+\text{中文}+y` 逐像素同尺寸
//       （138.06×20.0），所以当初要挡的**只有 `$`**；
//     · 而 `$` 可以剥掉（同一份规格 §一 就写着"片段进入公式 ⇒ 剥掉定界符"），
//       没有理由连文字一起推出去；
//     · 实测后果：在空行间块里粘「即 $\forall…$」⇒ 载荷被推到 `$$` 之后**紧贴着粘上去**
//       ⇒ 那一行以 `$$` 开头却没有收尾 ⇒ 块模型找不到闭合 ⇒ 下面整片「公式不完整」。
//   ⇒ 现在只有**落单**的 `$`（配不成对）才推出去，而且落点必须是**块所在行的下一行行首**。

import '../render/math_nav.dart';
import 'math_spans.dart';

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
    final String innerRaw = (_stripFences(payload) ?? payload).trim();
    final _Texified? tex = _texify(innerRaw);
    if (tex == null) {
      // 落单的 `$` 配不成对 ⇒ 不猜（塞进 tex 必炸）⇒ 当普通文本推到块之后
      return _pushOut(doc, r, payload);
    }
    final String inner = tex.tex;
    final String note = tex.stripped == 0
        ? '已把这一整块换成粘贴内容'
        : '已把这一整块换成粘贴内容（剥掉 ${tex.stripped} 处 `\$…\$` 定界符）';
    if (r.isDisplay) {
      // 行间块里粘多行 ⇒ **整块内容替换**（一个块仍然是一个块）
      return PasteDecision(
        apply: PasteApply.replaceBlock,
        payload: inner,
        replaceFrom: r.contentStart,
        replaceTo: r.contentEnd,
        at: r.contentStart + inner.length,
        note: note,
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
  // ★★ 批 37：混合文本 ⇒ **归一成 tex**（剥掉内部成对的 `$`）后就地插。
  //   ★ 文字照样能待在 tex 里（10-23 决定 2），所以这里不再有"推出去"这一档。
  final _Texified? tex = _texify(payload);
  if (tex != null) {
    return PasteDecision(
      apply: PasteApply.mathTex,
      payload: tex.tex,
      note: tex.stripped == 0
          ? null
          : '已剥掉 ${tex.stripped} 处 `\$…\$` 定界符（数学里不能有 `\$`）',
    );
  }
  // 落单的 `$` ⇒ 兜底
  return _pushOut(doc, r, payload);
}

/// 兜底：**落单的 `$`** 拆不动 ⇒ 推到公式之后。
///
/// ★★ 批 37：落点必须是**块所在行的下一行行首**。
///   原来给的是 `r.closeEnd`（紧贴收尾围栏那一格）—— 文字粘上去会变成 `$$即 …`，
///   而块模型要求围栏**整行**是 `$$` ⇒ 找不到闭合 ⇒ 一路吞到下一个 `$$`
///   ⇒ 用户看到「公式不完整」占满下面一整片（2026-10-26 实测）。
PasteDecision _pushOut(String doc, MathRegion r, String payload) {
  const String note = '载荷里有落单的 `\$`，放不进公式里，已放到公式之后';
  final int lineEnd = _lineEndOf(doc, r.closeEnd);
  if (lineEnd >= doc.length) {
    // 块就是文末那一行 ⇒ 落到文末，并在载荷前补一个换行
    return PasteDecision(
      apply: PasteApply.pushOut,
      payload: '\n$payload',
      at: doc.length,
      note: note,
    );
  }
  return PasteDecision(
    apply: PasteApply.pushOut,
    payload: payload,
    at: lineEnd + 1,
    note: note,
  );
}

/// 「归一成 tex」的结果：[stripped] = 剥掉了几处定界符。
class _Texified {
  const _Texified(this.tex, this.stripped);

  final String tex;
  final int stripped;
}

/// **归一成 tex**：把载荷里**成对**的 `$…$` / `$$…$$` 剥掉（tex 里不许出现 `$`）。
///
/// 返回 `null` = 有**落单**的 `$`（配不成对）⇒ 调用方走兜底（推到块之后 + 说明）。
///
/// ★ `\$`（转义）不算定界符 —— 与 `math_spans.scanMathSpans` 同一套判据。
_Texified? _texify(String s) {
  final List<MathSpan> spans = scanMathSpans(s);
  var total = 0;
  for (var i = 0; i < s.length; i++) {
    if (s.codeUnitAt(i) != 0x24) continue; // `$`
    if (i > 0 && s.codeUnitAt(i - 1) == 0x5C) continue; // `\$`
    total++;
  }
  var consumed = 0;
  for (final MathSpan sp in spans) {
    consumed += sp.display ? 4 : 2; // `$$…$$` 两个围栏 / `$…$` 一对
  }
  if (consumed != total) return null;
  if (spans.isEmpty) return _Texified(s, 0);
  final StringBuffer sb = StringBuffer();
  var i = 0;
  for (final MathSpan sp in spans) {
    sb.write(s.substring(i, sp.start));
    sb.write(sp.tex);
    i = sp.end;
  }
  sb.write(s.substring(i));
  return _Texified(sb.toString(), spans.length);
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
