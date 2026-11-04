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
  // ★★ 2026-11-03（围栏不参与选区 · 讨论定稿 §七）：
  //   **行间**块只剩空白 ⇒ 算空、连围栏回收（一块空的行间区域没有保留意义）；
  //   **行内**只剩空白 ⇒ **不算空**、保留 —— 空白是**没被选中**的内容
  //   （`\ ` 有真实宽度；裸空格零宽但仍是源里的字符）。用户看不见 `$`，
  //   不能把他没选中的空白连同围栏一起"顺手"删掉。
  final bool emptied = r.isDisplay ? rest.trim().isEmpty : rest.isEmpty;
  if (!emptied) return e;

  var a = r.openStart;
  var b = r.closeEnd;
  // 行间块：围栏各占一行 ⇒ 顺手把**后面**那个换行也吃掉一格（否则原地留一个空行）。
  //
  // ★★★ 2026-11-01（用户三张图：删空块之后**整段崩成裸源码** / `=0` 与 `---` 粘成一行）：
  //   **不许吃前面那个换行**。原来 `if (a > 0 && doc[a-1] == '\n') a -= 1;` 会把
  //   "上一行的行尾" 和 "块后面那一行" 直接缝在一起：
  //     · `只能f'(0)=0` ⏎ `$$…$$` ⏎ `---`  ⇒ 删完变成 `只能f'(0)=0---`（两行粘成一行）；
  //     · 更糟：块**紧贴**下一个块时（`$$\n…\n$$\n$$\n…$$`），缝完变成
  //       `…上一行文字$$` ⇒ 那个 `$$` 跑到行中间、**不再是围栏** ⇒ 后面所有块配对全体错位
  //       ⇒ 一串 `[公式不完整]` ＋ 裸源码（用户第二张图的相貌）。
  //   块占的是**自己的行**：删掉它只该少一行，不该动别人的行尾。
  if (r.isDisplay) {
    if (b < doc.length && doc[b] == '\n') b += 1;
  }
  // ★★★ 2026-11-04（N2）：**删除区一直延伸到文末时，光标退一格**。
  //   现场（用户 ①）：`a⏎⏎$f^{\prime}$⏎` 里在公式之后按 ⌫ ⇒ 整段回收，光标停在 `openStart`；
  //   可新缓冲区是 `a⏎⏎⏎`，那个偏移已经是**下一行**（实测竖条 175.8，而公式原来在 133.8，
  //   用户："光标到了第三行，第二行实打实是个空行"）。
  //   判据与 `math_nav._normalizeEmptyParagraph` 的"文末例外"同一条：别站在"文末下一行"上。
  var caret = a;
  // 判据：删除区**后面只剩换行**（= 文末），且它左边就是行终止符 ⇒ 光标退一格。
  // 只在"删的是最后一行内容"时成立；中间行（后面还有正文）不受影响。
  if (a > 0 &&
      doc[a - 1] == '\n' &&
      doc.substring(b).trim().isEmpty) {
    caret = a - 1;
  }
  return SmartEdit.remove(a, b, caret);
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
