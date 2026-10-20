// 数语引擎 · **块类型快捷键**（纯 Dart，S4-c）
//
// 规格：《快捷键系统.md》§二·结构类（`Ctrl+1/2/3` 标题、`Ctrl+Shift+7/8/9` 列表/引用、
//       `Ctrl+Alt+C` 代码块、`Ctrl+Enter` 分页符）。
//
// ★★ 唯一的实现原则：**改的仍然只是 L0 里的行首标记**（《块模型与md往返》R2–R7 的
//   "唯一真相在 L0"）。所以这里全是"算一个区间替换"的纯函数：
//   - 标题 / 列表 / 引用 ⇒ **只替换行首标记那一段**（最小编辑，撤销栈里就是这一处）；
//   - 代码块 ⇒ 一次覆盖"上围栏行 … 下围栏行"的整段（**同一次编辑**，不许拆成两次）；
//   - 分页符 ⇒ 一次插入（载荷边界交给 `insert_guard.planInsert`，落在公式里会被推出去）。
//
// ★ 为什么不做成 `DocBuffer.setLineBlockType` 的封装：那个函数**只会设置**、不会"再按一次回正文"，
//   而且它直接动缓冲区；这里要的是"先算出结果、再由编辑层一次性落盘"（与面板插入同一条纪律）。
//
// **纯 Dart**，可单测。

import '../core/block.dart';
import '../render/insert_guard.dart';

/// 块类型快捷键能做的事
enum BlockOp {
  /// 标题 1 / 2 / 3（**再按一次回正文**）
  h1,
  h2,
  h3,

  /// 有序列表 `1. `
  ol,

  /// 无序列表 `- `
  ul,

  /// 引用块 `> `
  quote,

  /// 代码块（```` ``` ```` 上下围栏）
  codeblock,

  /// 手动分页符 `<!-- pagebreak -->`
  pagebreak,
}

/// 一次块操作 = **一个区间替换** `[from, to) → insert`。
///
/// 编辑层拿到它只做一次 `_buf.replace`（⇒ 一步撤销），然后把光标放到 [caret]。
class BlockOpResult {
  const BlockOpResult({
    required this.from,
    required this.to,
    required this.insert,
    required this.caret,
    required this.op,
  });

  final int from;
  final int to;
  final String insert;

  /// 操作完成后的光标（绝对偏移）
  final int caret;
  final BlockOp op;

  /// 什么都不用改（例如"整块语义的行不许加标题标记"）
  bool get isNoop => from == to && insert.isEmpty;

  @override
  String toString() => 'BlockOpResult(${op.name}, $from..$to, '
      '"${insert.replaceAll('\n', r'\n')}", caret=$caret)';
}

/// 计算一次块操作。返回 `null` = **这一次按键什么都不该发生**（例如在 `$$` 围栏行上按标题键，
/// 或代码块里按标题键）。
///
/// [caret] 只需合法（越界会被夹住）。
BlockOpResult? planBlockOp(String doc, int caret, BlockOp op) {
  final int c = caret.clamp(0, doc.length);
  switch (op) {
    case BlockOp.h1:
      return _planLineMarker(doc, c, op, '# ');
    case BlockOp.h2:
      return _planLineMarker(doc, c, op, '## ');
    case BlockOp.h3:
      return _planLineMarker(doc, c, op, '### ');
    case BlockOp.ol:
      return _planLineMarker(doc, c, op, '1. ');
    case BlockOp.ul:
      return _planLineMarker(doc, c, op, '- ');
    case BlockOp.quote:
      return _planLineMarker(doc, c, op, '> ');
    case BlockOp.codeblock:
      return _planCodeBlock(doc, c);
    case BlockOp.pagebreak:
      return _planPageBreak(doc, c);
  }
}

// ---------------------------------------------------------------------------
// 行首标记类（标题 / 列表 / 引用）
// ---------------------------------------------------------------------------

/// 统一口径：**新标记与旧标记相同 ⇒ 去掉标记（回正文）**，否则换成新标记。
BlockOpResult? _planLineMarker(String doc, int caret, BlockOp op, String marker) {
  final LineIndex lines = LineIndex.of(doc);
  final int line = lines.lineOf(caret);
  final String text = lines.text(line);
  // ★ 整块语义的行（`$$` 围栏 / 代码围栏 / 分隔线 / 分页符）**不许**改行首标记：
  //   改了就等于把那个块拆了（`$$` 少两个字符 ⇒ 数学块塌成段落）。
  if (_isWholeBlockLine(text)) return null;
  final int lineStart = lines.starts[line];
  final int oldLen = BlockMarkers.markerLength(text);
  final String oldMarker = text.substring(0, oldLen);
  final String next = oldMarker == marker ? '' : marker;
  // 光标跟着标记长度变化走，但**不许跑出这一行**
  final int inLine = (caret - lineStart).clamp(0, text.length);
  final int contentIn = (inLine - oldLen).clamp(0, text.length - oldLen);
  final int caretOut = lineStart + next.length + contentIn;
  return BlockOpResult(
    from: lineStart,
    to: lineStart + oldLen,
    insert: next,
    caret: caretOut,
    op: op,
  );
}

/// ★★ 2026-10-19（U6）：**设置**语义的行首标记（不是"再按一次回正文"）。
///
/// 顶栏「块类型」下拉用它：用户是在**选择**目标类型，不是在切换 ——
/// 所以"已经是标题 2"时再选标题 2 应当是**什么都不做**，而不是被切成正文。
///
/// [desired] = 目标行首标记（`''` = 正文）。返回 `null` = 这一行不能改（整块语义的行），
/// 或本来就是目标（无需改动）。
BlockOpResult? planLineMarkerSet(String doc, int caret, String desired) {
  final LineIndex lines = LineIndex.of(doc);
  final int line = lines.lineOf(caret.clamp(0, doc.length));
  final String text = lines.text(line);
  if (_isWholeBlockLine(text)) return null;
  final int lineStart = lines.starts[line];
  final int oldLen = BlockMarkers.markerLength(text);
  final String oldMarker = text.substring(0, oldLen);
  if (oldMarker == desired) return null;
  final int inLine = (caret - lineStart).clamp(0, text.length);
  final int contentIn = (inLine - oldLen).clamp(0, text.length - oldLen);
  return BlockOpResult(
    from: lineStart,
    to: lineStart + oldLen,
    insert: desired,
    caret: lineStart + desired.length + contentIn,
    // 下拉里的"正文"也是一次块操作；`op` 只用于日志/调试，沿用 h1 这一族
    op: BlockOp.h1,
  );
}

bool _isWholeBlockLine(String text) =>
    BlockMarkers.isFence(text) ||
    BlockMarkers.isMathFence(text) ||
    BlockMarkers.isDivider(text) ||
    BlockMarkers.isPageBreak(text);

// ---------------------------------------------------------------------------
// 代码块
// ---------------------------------------------------------------------------

/// 代码块：**上围栏 + 本行 + 下围栏**。
///
/// - 本行正好被上下两道围栏夹住（`上一行 == ```、下一行 == ```）⇒ **拆掉**（一次区间替换）；
/// - 否则 ⇒ 在**本行的前后各起一行**围栏（围栏必须独占一行，否则不是围栏）。
BlockOpResult? _planCodeBlock(String doc, int caret) {
  final LineIndex lines = LineIndex.of(doc);
  final int line = lines.lineOf(caret);
  final String text = lines.text(line);
  // 围栏行 / 公式围栏行上不接这个动作（会造出嵌套围栏）
  if (BlockMarkers.isMathFence(text)) return null;

  final bool prevFence = line > 0 && _isFenceLine(lines.text(line - 1));
  final bool nextFence =
      line + 1 < lines.count && _isFenceLine(lines.text(line + 1));

  if (prevFence && nextFence) {
    // 拆掉：区间 = [上一行行首, 下一行行尾)，内容 = 中间原样
    final int from = lines.starts[line - 1];
    final int to = lines.ends[line + 1];
    final String inner = doc.substring(lines.starts[line], lines.ends[line]);
    return BlockOpResult(
      from: from,
      to: to,
      insert: inner,
      caret: (from + (caret - lines.starts[line])).clamp(from, from + inner.length),
      op: BlockOp.codeblock,
    );
  }

  // 加围栏：本行整行换成三行 —— ` ``` \n 本行 \n ``` `
  //
  // ★ 两边**不额外补换行**：本行自己的前后 `\n` 已经把它隔开了；多补一个的话，
  //   拆掉围栏（另一次同样的按键）就会在旁边留下空行（实测：`print(1)` 拆完变 `\nprint(1)\n`）。
  final int from = lines.starts[line];
  final int to = lines.ends[line];
  final String body = doc.substring(from, to);
  final String wrapped = '$kFence\n$body\n$kFence';
  final int inLine = (caret - from).clamp(0, body.length);
  return BlockOpResult(
    from: from,
    to: to,
    insert: wrapped,
    // 内容行的行首 = from + 3(```) + 1(换行)
    caret: from + kFence.length + 1 + inLine,
    op: BlockOp.codeblock,
  );
}

bool _isFenceLine(String text) => text.trim() == kFence;

// ---------------------------------------------------------------------------
// 分页符
// ---------------------------------------------------------------------------

/// 分页符：`<!-- pagebreak -->` **必须独占一行**（R7），否则 md 里就是一行普通文字。
///
/// ★ 实测（2026-10-18 探针）：`planInsert` 对**不含 `\n` 的载荷**不做任何挪位 ——
///   直接插会得到 `前<!-- pagebreak -->一段`（不是分页符）甚至插进公式中间
///   （`$\f<!-- pagebreak -->rac{a}{b}$` ⇒ tex 当场坏掉）。
///   ⇒ 载荷自带换行（`\n<!-- pagebreak -->\n`）：既保证独占一行，也**顺带激活**
///   `insert_guard` 规则 ①（含 `\n` 的载荷落在数学段里会被推到 `closeEnd`）。
BlockOpResult? _planPageBreak(String doc, int caret) {
  final int c = caret.clamp(0, doc.length);
  // 已经紧邻一个分页符 ⇒ 不重复插（幂等：连按不会堆出一串分页符）
  final LineIndex lines = LineIndex.of(doc);
  final int line = lines.lineOf(c);
  if (BlockMarkers.isPageBreak(lines.text(line))) return null;
  if (line > 0 && BlockMarkers.isPageBreak(lines.text(line - 1))) return null;
  if (line + 1 < lines.count && BlockMarkers.isPageBreak(lines.text(line + 1))) {
    return null;
  }

  final String payload0 = '\n$kPageBreakMarker\n';
  final InsertPlan plan = planInsert(doc, c, payload0);
  final String payload = plan.padText(payload0);
  final int at = plan.offset.clamp(0, doc.length);
  return BlockOpResult(
    from: at,
    to: at,
    insert: payload,
    // ★ 2026-10-20：光标停在**分页符那一行的行尾**（不是下一行）——
    //   这样顶栏按钮立刻变成「取消分页」，用户一眼就知道再点一下能撤销。
    caret: (at + payload.length - 1).clamp(0, doc.length + payload.length),
    op: BlockOp.pagebreak,
  );
}

/// ★★ 2026-10-20（用户："能手动分页，是不是也需要能手动取消分页"）：
/// **删掉光标所在那一行的分页符**（连同它自己那一行的换行一起删，免得留下空行）。
///
/// 返回 `null` = 光标不在分页符那一行（调用方什么都不做）。
BlockOpResult? planRemovePageBreak(String doc, int caret) {
  final int c = caret.clamp(0, doc.length);
  final LineIndex lines = LineIndex.of(doc);
  final int line = lines.lineOf(c);
  final String text = lines.text(line);
  if (!BlockMarkers.isPageBreak(text)) return null;
  final int start = lines.starts[line];
  final int end = start + text.length; // 不含换行
  // 后面还有内容 ⇒ 删 `[start, end+1)`（含换行）；已经是最后一行 ⇒ 连前面的换行一起删
  final int from = end < doc.length ? start : (start > 0 ? start - 1 : 0);
  final int to = end < doc.length ? end + 1 : end;
  return BlockOpResult(
    from: from,
    to: to,
    insert: '',
    caret: from,
    op: BlockOp.pagebreak,
  );
}

/// ★★ 2026-10-20（用户拍板"接缝带"）：判断光标是否落在**两页之间的那道缝**上。
///
/// 用户的洞察：「用户怎么知道分页符行在哪？实际效果就是根本不知道点哪里才出取消按钮」
/// ⇒ 判据不能是"光标正好在 `<!-- pagebreak -->` 那一行"，而应是**接缝带**：
///   · 分页符行本身；
///   · 它**上面的连续空行**（属于上一页末尾）；
///   · 它**下面的连续空行**（属于下一页开头）。
///
/// 返回接缝带覆盖的 `[from, to)`（**不含**两侧正文行）；光标不在接缝带里 ⇒ `null`。
({int from, int to, int breakLine})? seamBand(String doc, int caret) {
  final LineIndex lines = LineIndex.of(doc);
  final int c = caret.clamp(0, doc.length);
  // ★★ 用户口径（2026-10-20）：接缝 = **上一页最后一个字符之后 .. 下一页第一个字符之前**
  //   （含中间的空行与分页符行）。所以判据就一条：**光标落在这一段闭区间里**。
  //   这样"光标停在正文末尾/下一页开头"都算，而正文中间不算 —— 符合人的直觉，
  //   也不用让用户知道"分页符那一行"长什么样。
  for (var i = 0; i < lines.count; i++) {
    if (!BlockMarkers.isPageBreak(lines.text(i))) continue;
    var above = i - 1;
    while (above >= 0 && lines.text(above).trim().isEmpty) {
      above--;
    }
    var below = i + 1;
    while (below < lines.count && lines.text(below).trim().isEmpty) {
      below++;
    }
    final int from =
        above >= 0 ? lines.starts[above] + lines.text(above).length : 0;
    final int to = below < lines.count ? lines.starts[below] : doc.length;
    if (c >= from && c <= to) {
      return (from: from, to: to, breakLine: i);
    }
  }
  return null;
}
/// 删掉"接缝带"（见 [seamBand]）：两侧都有正文 ⇒ 换成一个换行（一个段落边界）；
/// 有一侧没有正文 ⇒ 直接抹掉，不留开头/结尾的空行。**一步撤销**。
BlockOpResult? planRemoveSeam(String doc, int caret) {
  final ({int from, int to, int breakLine})? band = seamBand(doc, caret);
  if (band == null) return null;
  final bool hasBefore = doc.substring(0, band.from).trim().isNotEmpty;
  final bool hasAfter = doc.substring(band.to).trim().isNotEmpty;
  final String insert = (hasBefore && hasAfter) ? '\n' : '';
  final int from = band.from;
  final int to = band.to;
  return BlockOpResult(
    from: from,
    to: to,
    insert: insert,
    caret: (from + insert.length).clamp(0, doc.length - (to - from) + insert.length),
    op: BlockOp.pagebreak,
  );
}
String applyBlockOpTo(String doc, BlockOpResult? r) {
  if (r == null || r.isNoop) return doc;
  return doc.replaceRange(r.from, r.to, r.insert);
}

/// 便捷判断：这条按键在这个位置**有没有效果**（状态栏/测试用）
bool blockOpApplies(String doc, int caret, BlockOp op) {
  final BlockOpResult? r = planBlockOp(doc, caret, op);
  return r != null && !r.isNoop;
}
