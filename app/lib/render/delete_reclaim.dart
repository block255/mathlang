// 数语引擎 · **删除要干脆**：删空数学段 ⇒ 连定界符一起删（2026-10-18）
//
// ============================ 用户口径 ============================
// 「删空留壳」**只针对数学结构里的子位点**（`\frac{□}{□}` 的槽、`\sqrt{□}` 的参数）——
// 删掉槽里的内容，槽本身留着（空槽占位照画，提醒你去填）。
// **把整个数学语言删掉没有任何"留壳回打"的义务** —— 用户原话：
// 「比如根号结构、分式结构，在它们整个的后面点删除是直接删掉整个结构，而不是留下一个空框」。
//
// ============================ 本文件的规则 ============================
// 一次删除如果**把某个数学段的内容删空**（剩下的全是空白），就把那一段的定界符**一起删掉**：
//   · 同一步操作 ⇒ **一步撤销**（不是"先删结构、再删壳"两下）；
//   · **只对"删除"生效** —— `行间公式段` 那种"主动插入的空段"照样可以空着等你去填
//     （它是"新建"，不是"删剩"）。
//
// ★ 为什么必须在删除侧做：用户改了两次口径都是同一句话"要干脆"。
//   上一批我把空壳画成了可见的虚线框（§6.1.1），于是"删一次不够"从"看不见"变成"看得见的残留"——
//   这个函数就是那件事的收口。
//
// **纯 Dart**（只依赖 `SmartEdit` 与 `mathRegionAt`），可全域扫描测试。

import 'math_nav.dart';
import 'smart_delete.dart';

/// 若这次删除把数学段删空 ⇒ 扩成"连定界符整段删"；否则原样返回。
SmartEdit reclaimEmptiedMath(String doc, SmartEdit e) {
  if (!e.deletes) return e;
  final int from = e.from!;
  final int to = e.to!;
  final MathRegion? r = _regionTouching(doc, from, to);
  if (r == null) return e;
  // 只认"碰到了**内容**"的删除（删公式外面的文字不该把公式带走）
  if (to <= r.contentStart || from >= r.contentEnd) return e;

  final int len = r.contentEnd - r.contentStart;
  final String content = doc.substring(r.contentStart, r.contentEnd);
  final String rest = content.replaceRange(
    (from - r.contentStart).clamp(0, len),
    (to - r.contentStart).clamp(0, len),
    '',
  );
  // ★ 只剩空白 ⇒ 这一段没有内容了 ⇒ 它不该继续存在（"干脆"）
  if (rest.trim().isNotEmpty) return e;

  var a = r.openStart;
  var b = r.closeEnd;
  // 行间块：围栏各占一行，顺手把外侧那个换行也吃掉一格（否则原地留一个空行）
  if (r.isDisplay) {
    if (a > 0 && doc[a - 1] == '\n') a -= 1;
    if (b < doc.length && doc[b] == '\n') b += 1;
  }
  return SmartEdit.remove(a, b, a);
}

/// 找到与 `[from, to)` 有关系的那个数学段（先看删除起点，再看终点，再看它们的前一格）
MathRegion? _regionTouching(String doc, int from, int to) {
  for (final int p in <int>[from, from - 1, to, to - 1]) {
    if (p < 0 || p > doc.length) continue;
    final MathRegion? r = mathRegionAt(doc, p);
    if (r != null) return r;
  }
  return null;
}
