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
import 'env_table.dart';
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

  /// ★ 2026-11-13（反馈②）：载荷是**多个完整的行间块**（跨块复制）⇒ 按块序列
  /// 落到**本行之后**（一块一个 `$$…$$`，顺序不变）。
  /// 行内/行间都塞不下多块；正文走原样插入。
  blocks,

  /// 载荷是"文字 + 公式"混合，塞不进公式里：**推到公式之后**再按文字插入
  pushOut,

  /// 载荷是**局部表片段**（我们补的中性 `matrix`）、落点在**正文**：
  /// **按行落成行内公式**（`&` → 空格），不再就地造一个矩阵。
  /// ★ 2026-11-03（用户拍板）：片段往往不是想要的矩阵形状，正文里没有第三个用处。
  tableLines,

  /// 落点在**表内**、载荷也是一张表 ⇒ **写进格子**
  /// （当前格为左上角、整格覆盖、超界裁剪）。
  /// `payload` = 替换文本，`replaceFrom/To` = 区间，`at` = 落点后的光标。
  tableCells,
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
    // ★★ 2026-11-03（表批 B · 用户拍板）：**局部表片段**粘到正文 ⇒ 按行落成行内公式。
    //   理由：拖选是线性的，片段常常不是用户想要的矩阵形状；在正文里"造一个新矩阵"
    //   大概率不是他要的东西，而且正文里也没有必要。
    final List<String>? lines = _tableRowsText(payload);
    if (lines != null) {
      return PasteDecision(
        apply: PasteApply.tableLines,
        payload: lines.join('\n'),
        note: '表格片段已按行落成文字（${lines.length} 行）',
      );
    }
    return PasteDecision(apply: PasteApply.asIs, payload: payload);
  }

  // ★★ 2026-11-03 晚（表批 B · 落格）：**落点在表内**且载荷是一张表 ⇒ 写格。
  //   原来会把 `\begin{matrix}…\end{matrix}` 原样插进格子里，把外面那张表拆散
  //   （用户实测：一粘就变成"一堆散字 + 一个新矩阵"）。
  final PasteDecision? cells = _tableCellsDecision(r, probe, payload);
  if (cells != null) return cells;

  final bool multi = payload.contains('\n');
  if (multi) {
    // ★★ 2026-11-13（反馈②）：**跨块载荷**（≥2 个完整的行间段）⇒ 按块序列落到行后。
    //   行内放不下块、行间也不能把多块并成一块（合并会改变语义）。
    if (_displayBlockCount(payload) >= 2) {
      return PasteDecision(
        apply: PasteApply.blocks,
        payload: payload.trim(),
        at: _lineEndOf(doc, r.closeEnd),
        note: '已按块粘贴到本行之后',
      );
    }
    final String? fences = _stripFences(payload);
    final String innerRaw = (fences ?? payload).trim();
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
    // ★★ 2026-11-13（反馈②）：**行内 + 单块** ⇒ 剥围栏、块格式换行压成空格，
    //   当**行内 tex** 插（`cases`/`aligned`/`matrix` 行内本来就能渲染，
    //   见《位点与结构导航》§「`\\` 能不能当数学段内换行」）。
    //   11-02 之前这里是 `promoteBlock`（提升成块）—— 与"行间块复制要能舒服地
    //   粘进行内"的体感冲突。
    if (fences != null) {
      return PasteDecision(
        apply: PasteApply.mathTex,
        payload: _oneLine(inner),
        note: '行内放不下换行，已把块格式的换行压成空格后插入',
      );
    }
    // 普通多行文本（不是块）⇒ 老口径：提升成块，不劈开公式
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

/// 载荷里**完整的行间段**个数（`$$…$$`；按 `scanMathSpans` 的判据）。
int _displayBlockCount(String s) =>
    scanMathSpans(s).where((MathSpan sp) => sp.display).length;

/// 块格式的换行压成空格（`\\` 是环境自己的行分隔，不动）。
String _oneLine(String s) =>
    s.replaceAll(RegExp(r'[ \t]*\n[ \t\n]*'), ' ').trim();

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

/// **落点在表内 + 载荷是矩阵族表** ⇒ 落格（超出边界裁剪，状态栏说明）；否则 null。
///
/// 口径（§3.2）：剥壳取格、当前格 = 左上角、**整格覆盖**、超界裁剪。
/// `cases` / `aligned` 载荷不参与格分配（它们是整块环境，见 `cellGridOf`）。
PasteDecision? _tableCellsDecision(
    MathRegion r, int probe, String payload) {
  final int local = probe - r.contentStart;
  final EnvTable? target = envTableAt(r.tex, local);
  if (target == null) return null;
  final String? payloadTex = _stripOnePiece(payload) ?? _stripFences(payload);
  if (payloadTex == null) return null;
  final List<List<String>>? grid = cellGridOf(payloadTex.trim());
  if (grid == null) return null;
  final ({int r, int c})? at = cellNear(target, local);
  if (at == null) return null;
  final CellWrite? w = cellWritePlan(target, r.tex, at.r, at.c, grid);
  if (w == null) return null;
  final String size = '${w.rows} 行 × ${w.cols} 列';
  return PasteDecision(
    apply: PasteApply.tableCells,
    payload: w.replacement,
    replaceFrom: r.contentStart + w.from,
    replaceTo: r.contentStart + w.to,
    at: r.contentStart + w.caretAfter,
    note: w.clipped
        ? '已粘进表格（$size；超出表格边界的部分已裁剪）'
        : '已粘进表格（$size）',
  );
}

/// **局部表片段**（载荷是我们补的中性 `matrix`）⇒ 按行拆成行内公式；不是 ⇒ null。
///
/// ★ 只认 **`matrix`（不带括号）**：整表复制会**保留原类型**（`bmatrix` / `pmatrix` / `vmatrix` / …），
///   所以"无括号的 `matrix`"正好是"局部片段"的标记。
///   （2026-11-03 晚改：本来用 `bmatrix`，可源表本身常常就是 `bmatrix`
///   ⇒ 整表复制也会被按行拆，用户实测打回。）
List<String>? _tableRowsText(String payload) {
  final String? tex = _stripOnePiece(payload) ?? _stripFences(payload);
  if (tex == null) return null;
  final String s = tex.trim();
  final List<EnvTable> tables = envTablesIn(s);
  if (tables.isEmpty) return null;
  final EnvTable t = tables.first;
  if (t.name != 'matrix') return null;
  if (!s.contains('&') && !s.contains(r'\\')) return null;
  final List<String> lines = <String>[];
  for (final List<EnvCell> row in t.rows) {
    final List<String> cells = <String>[
      for (final EnvCell c in row) s.substring(c.start, c.end).trim(),
    ];
    final String body = cells.where((String x) => x.isNotEmpty).join(r'\ ');
    if (body.isEmpty) continue;
    lines.add('\$$body\$');
  }
  return lines.isEmpty ? null : lines;
}
