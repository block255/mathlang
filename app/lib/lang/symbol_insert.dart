// 数语引擎 · **面板插入语义**（S4-b）：符号/模板 → 一次编辑写进缓冲区
//
// 用户 2026-10-17 确认过的口径（《界面与布局.md》§7）：
//   ① 光标**在数学段里**（含紧邻 ±1 格）⇒ **并入那一段**（`$x$` 后点 `+` ⇒ `$x+$`），不新建第二个 `$…$`；
//   ② 光标在**纯文字**里 ⇒ **自动建壳**：插入 `$<tex>$`（"用户不写编码" = 编辑器替用户写）；
//   ③ 有选区 ⇒ **替换选区**（选区里已有数学段就替换成 tex、不重复包）。
// 不管哪一条，都是**一次区间替换** ⇒ 一步撤销。
//
// ★ 走 `insert_guard.planInsert`，**不绕过守门人**（行边界 ③④⑤、粘合处挪位 ② 全都照旧）。
//
// **纯 Dart**（只依赖核心/渲染层的纯函数），可单测。

import '../render/insert_guard.dart';
import '../render/math_nav.dart';

/// 插入时做的三选一（诊断与守卫用）
enum SymbolInsertMode { mergeIntoMath, wrapNewInlineMath, replaceSelection }

class SymbolInsertResult {
  const SymbolInsertResult({
    required this.doc,
    required this.caret,
    required this.mode,
    required this.wrapped,
    required this.inserted,
  });

  /// 新文档（整份替换进 `DocBuffer` = 一次编辑）
  final String doc;

  /// 新光标（模板 = 第一个空槽里；符号 = 插入内容之后）
  final int caret;

  final SymbolInsertMode mode;

  /// 是否替用户补了 `$…$`（状态栏"自动包裹 N 处"要报它）
  final bool wrapped;

  /// 真正写进缓冲区的文本（含壳 / 补的行边界；诊断用）
  final String inserted;

  @override
  String toString() => 'SymbolInsert(${mode.name}, wrapped=$wrapped, '
      'caret=$caret, inserted="${inserted.replaceAll('\n', r'\n')}")';
}

/// tex 里**第一个空槽**的偏移（空槽 = 一对空的 `{}` 或 `[]`）。
///
/// ★ 为什么不用位点表的第一个位点：位点表包含"tex 之前/之后"这类**边界位点**，
///   而这里要的是"**空槽内部**的第一个落点"（模板插入后光标就该停在那个空格里）。
///   判据就是源码里的空组 —— 与 `slot_marks` 认空槽的口径一致（空 `{}` / 空 `[]`）。
int firstSlotOffset(String tex) {
  final int a = tex.indexOf('{}');
  final int b = tex.indexOf('[]');
  if (a < 0 && b < 0) return tex.length;
  if (a < 0) return b + 1;
  if (b < 0) return a + 1;
  return (a < b ? a : b) + 1;
}

/// 把 [tex] 插到光标处（或替换选区），返回新文档与新光标。
SymbolInsertResult applySymbolInsert({
  required String doc,
  required int caret,
  required int selStart,
  required int selEnd,
  required String tex,
  required bool template,
}) {
  final int c = caret.clamp(0, doc.length);
  final int s = selStart.clamp(0, doc.length);
  final int e = selEnd.clamp(0, doc.length);

  SymbolInsertMode mode;
  String text;
  bool wrapped;
  int? mergeAt;

  if (e > s) {
    // ③ 替换选区
    mode = SymbolInsertMode.replaceSelection;
    wrapped = !_touchesMath(doc, s, e);
    text = wrapped ? '\$$tex\$' : tex;
  } else if (_mergeRegion(doc, c) != null) {
    // ① 并入数学段（★ 落点要**挪进段内**：段边界那一格在 `mathRegionAt` 里算"段外"）
    mode = SymbolInsertMode.mergeIntoMath;
    wrapped = false;
    text = tex;
    mergeAt = _mergeRegion(doc, c)!.at;
  } else {
    // ② 在文字里 ⇒ 自动建壳
    mode = SymbolInsertMode.wrapNewInlineMath;
    wrapped = true;
    text = '\$$tex\$';
  }

  // ★ 走同一条守门人链（含行边界 ③④⑤、粘合处挪位 ②、裸参数补花括号）
  final int at0 = e > s ? s : (mergeAt ?? c);
  final InsertPlan plan = planInsert(doc, at0, text);
  var d = doc;
  if (plan.wrapBareArg != null) {
    final ({int start, int end}) w = plan.wrapBareArg!;
    d = d.replaceRange(w.start, w.end, '{${d.substring(w.start, w.end)}}');
  }
  final String payload = plan.padText(text);
  final int at = plan.offset.clamp(0, d.length);
  final int delEnd = (e > s) ? (e + (d.length - doc.length)).clamp(at, d.length) : at;
  final String newDoc = d.replaceRange(at, delEnd, payload);

  // 新光标：模板 ⇒ 第一个空槽；符号 ⇒ 插入内容之后
  final int padPrefix = plan.padding.prefixNewline ? 1 : 0;
  final int shellPrefix = wrapped ? 1 : 0;
  final int texStart = at + padPrefix + shellPrefix;
  final int caretOut = template
      ? (texStart + firstSlotOffset(tex)).clamp(0, newDoc.length)
      : (at + payload.length).clamp(0, newDoc.length);

  return SymbolInsertResult(
    doc: newDoc,
    caret: caretOut,
    mode: mode,
    wrapped: wrapped,
    inserted: payload,
  );
}

/// 光标是否"在数学段里或紧贴它的边界"；是则返回 **并入时的落点**。
///
/// ★ 落点必须**挪进段内**：段边界那一格（`closeEnd` / `openStart`）在 `mathRegionAt` 里算"段外"，
///   直接按原光标插会插到 `$` 外面（实测：`$x$` 后点 `+` 变成 `$x$+` 而不是 `$x+$`）。
({MathRegion region, int at})? _mergeRegion(String doc, int caret) {
  final MathRegion? here = mathRegionAt(doc, caret);
  if (here != null) return (region: here, at: caret);
  // 紧贴左边：`$x$|` ⇒ 落进段内末尾
  if (caret > 0) {
    final MathRegion? left = mathRegionAt(doc, caret - 1);
    if (left != null && left.closeEnd == caret) {
      return (region: left, at: left.contentEnd);
    }
  }
  // 紧贴右边：`|$x$` ⇒ 落进段内开头
  final MathRegion? right =
      caret < doc.length ? mathRegionAt(doc, caret + 1) : null;
  if (right != null && right.openStart == caret) {
    return (region: right, at: right.contentStart);
  }
  return null;
}

/// 选区内是否"碰到"数学段（有任何一段与选区相交 ⇒ 不重复包壳）
bool _touchesMath(String doc, int from, int to) {
  for (var o = from; o <= to; o++) {
    if (mathRegionAt(doc, o) != null) return true;
  }
  return false;
}
