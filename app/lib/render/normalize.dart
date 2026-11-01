// 数语引擎 · normalize（S3-5）
//
// 规格：notes/design/位点与结构导航.md §七
//   **提交点**（**只在**这些时刻跑，绝不逐击键）：失焦 · 光标离开该数学段 · 粘贴完成 · 明确动作
//   ① **空结构回收**：全空的结构单元（`\frac{}{}`、`^{}`）→ 删掉整个单元（与 §4.3 一致）
//   ② ~~多余花括号~~：**2026-11-01 撤**（拆花括号会合并位点、丢光标位置）
//   ③ 未闭合告警 → 走「问题清单」，本文件不管（那需要 UI）
//   ★ **normalize 不得让光标乱跳**：删除后光标落到"最近的前一个位点"（这里用精确的偏移映射）
//
// **纯 Dart。**

import 'caret_sites.dart';
import 'smart_delete.dart' show structureUnits, StructureUnit;

/// normalize 结果：新 tex + **映射后的光标偏移**
class NormalizeResult {
  const NormalizeResult(this.tex, this.caret, this.changes);

  final String tex;
  final int caret;

  /// 做了几处回收（0 = 没变）
  final int changes;

  bool get changed => changes > 0;

  @override
  String toString() => changed
      ? 'Normalize($changes 处：$tex @$caret)'
      : 'Normalize(无变化)';
}

/// 对**一个数学段的 tex** 跑 normalize（幂等：反复调用第二次无变化）。
NormalizeResult normalizeTex(String tex, int caretRel) {
  var cur = tex;
  var caret = caretRel.clamp(0, tex.length);
  var total = 0;

  for (var round = 0; round < 8; round++) {
    final CaretSiteTable t = buildCaretSites(cur);
    if (t.degraded) break; // 结构不可靠就别动（§4.4 同样的克制）

    // `lead` = 区域开头**被丢掉**的字符数（去花括号时 = 1，因为 `{` 不属于 repl）。
    // ★ 少了它，光标落在"内容开头"时会算成 +1 —— 2026-10-17 探针实测：
    //   `x^{2}` 的位点 3（`2` 之前）失焦后变成"`2` 之后"，光标右移一格；
    //   `\sum_{i=1}^{n}` 同理（"n 之前"跳到"n 之后"）。
    final List<({int from, int to, String repl, int lead})> edits =
        <({int from, int to, String repl, int lead})>[];

    // ① 全空结构：整段删
    //   ★★ 2026-10-18 例外：**多行环境**（`\begin{aligned}…\end{aligned}` / `cases` …）不回收。
    //      它的"空格子"是**模板本身的骨架**（用户从面板刚插进来时必然全空），
    //      按"全空结构"删掉就等于：**一失焦（提交点）就把刚插入的对齐推导吞成空壳**。
    //      实测（探针）：`normalizeTex(r'\begin{aligned}&=\\&=\end{aligned}')` 修复前返回 `""`。
    //   ★★★ 2026-10-20（T-A 实测 F8，用户拍板"乙"）：**光标还落在里面的空结构也不回收**。
    //      实测现场：空文档点面板「分式」⇒ `$\frac{}{}$`（11 字符，光标在第一个空槽里）⇒
    //      点一下搜索框（编辑器失焦 = 提交点）⇒ 只剩 `$$`（2 字符）——用户看到的是
    //      "**我刚插进去的模板凭空没了**"。
    //      口径：**只保住"光标所在的那一个"空结构**；别处的空壳照样回收（免得空壳越堆越多）。
    //      ★ 判据用**闭区间**（`u.start <= caret <= u.end`）：光标贴在结构末尾（按过 `→` 出槽）
    //        也算"还在它身上"，否则一按右箭头再点开别处还是会被吞掉。
    for (final StructureUnit u in structureUnits(t)) {
      if (!u.allEmpty) continue;
      if (caret >= u.start && caret <= u.end) continue;
      final String slice = tex.substring(
        u.start.clamp(0, tex.length),
        u.end.clamp(0, tex.length),
      );
      if (slice.contains(r'\begin{')) continue;
      edits.add((from: u.start, to: u.end, repl: '', lead: 0));
    }

    // ★★★ 2026-11-01（用户拍板「甲」）：**②③ 已撤**。
    //   ② 原本会在提交点把「单原子脚本参数」的花括号拆掉（`x^{2}` → `x^2`），
    //   而 `}` 虽然零宽，却**占一个偏移**：一拆，同一对象的「下标末尾」与「对象之后」
    //   就并成同一个偏移 ⇒ **那个光标位置永久消失**——
    //   2026-10-17「`\lim_{x\to0}` 的 `n` 之后点不到」是它第一次咬人，
    //   2026-11-01「`$f_-$` 的『对象之后』消失」是第二次（同一根因）。
    //   ③ 是给 ② 打的补丁（结构槽尾再把括号补回来），随 ② 一起撤；
    //   它配套的四条例外 (a)(b)(c)(d) 也随之作废。
    //   口径：**花括号是用户看不见的存储细节，不许为「源码好看」牺牲可编辑性**
    //    （平权 推论④「围栏/记号不是对象边界」/ 原则 2「用户不需要看数学编码」）。
    //   已知代价（用户 2026-11-01 接受）：老文档里已存在的裸参数（导入的 md 如 `a_n`）
    //   不会被自动补括号 ⇒ 那几格的「对象之后」仍然缺；新写的都带括号。

    // ★★★ 2026-11-01（用户拍板 1–4）：**撇号归一成 `^{\prime}`**。
    //
    // 为什么（探针实测，`f'_{+}` / `f_{+}'` 两种打字顺序）：
    //   `'` 是 `^{\prime}` 的语法糖，但**在源码里它只是个普通字符** ⇒ `f'` 不是"一个对象"，
    //   而是「`f`」+「带下标的撇」；`_{-}` 于是贴在**撇**身上，不贴在 f 身上。
    //   后果全是"顺序依赖"：退格在 off=7 只删 `f`（留 `'_{+}`）、在 off=5 只删 `f_{-}`（留 `'`）；
    //   两种顺序删出来的残骸相反，且"f 与下标之间"那一格的语义也不一致。
    // 归一之后：`f'` → `f^{\prime}` ⇒ 撇变成**普通的 `^` 脚本**，与 `x^{2}` 同一套模型
    //   ⇒ 一个对象、删整块、位点一致，**打字顺序不再影响任何行为**。
    // ★ 渲染完全等价（实测：`f'` 与 `f^{\prime}` 都是 14.39×13.89、叶盒 `"f""′"` 一致；
    //   `f'_{-}` / `f^{\prime}_{-}` / `f_{-}'` / `f_{-}^{\prime}` 四种一律 18.91×20.31）。
    // ★ 跳过 `\text{}` / `\mbox{}` / `\hbox{}` 里的撇（那是正文，`don't` 不许改）。
    {
      final List<({int from, int to})> textRanges = _textArgRanges(cur);
      var i = 0;
      while (i < cur.length) {
        if (cur[i] != "'") {
          i++;
          continue;
        }
        var j = i;
        while (j < cur.length && cur[j] == "'") {
          j++;
        }
        final bool inText = textRanges
            .any((({int from, int to}) g) => i >= g.from && j <= g.to);
        if (!inText) {
          final int n = j - i;
          final String repl = '^{${List<String>.filled(n, r'\prime').join()}}';
          edits.add((from: i, to: j, repl: repl, lead: 0));
        }
        i = j;
      }
    }

    // ★★★ 2026-11-01（用户拍板 1–4，第二步）：**脚本顺序归一 —— 撇的脚本永远排第一**。
    //
    // 为什么需要它：`f'_{+}` 与 `f_{+}'` 是**同一张画面**的两种写法
    // （`f^{\prime}_{+}` / `f_{+}^{\prime}`，实测两者渲染完全一致 18.91×20.31）。
    // 但它们的**位点 / 删除行为不同**（`f^{\prime}_{+}` 末尾退格只删挂件、`f_{+}^{\prime}` 删整块）
    // ⇒ 只把撇归一成 `^{\prime}` 还不够，必须让**两种打字顺序产出同一份源码**。
    // 判据：TeX 里同一基座的多个脚本**顺序无关** ⇒ 把 `^{\prime…}` 移到最前，
    //   其余脚本保持原相对顺序。一轮只换一对，由外层 ≤8 轮循环收敛，幂等。
    final RegExp scriptThenPrime = RegExp(
      r'(_\{[^{}]*\}|\^\{[^{}]*\})(\^(?:\{(?:\\prime)+\}))',
    );
    for (final Match m in scriptThenPrime.allMatches(cur)) {
      if (m.group(1)!.startsWith(r'^{\prime')) continue; // 已经是"撇在前" ⇒ 不动
      edits.add((
        from: m.start,
        to: m.end,
        repl: '${m.group(2)!}${m.group(1)!}',
        lead: 0,
      ));
    }

    if (edits.isEmpty) break;

    // 去掉互相重叠的：**外层优先**（嵌套的空结构只删最外层就够）
    edits.sort((({int from, int to, String repl, int lead}) a,
            ({int from, int to, String repl, int lead}) b) =>
        a.from != b.from ? a.from.compareTo(b.from) : b.to.compareTo(a.to));
    final List<({int from, int to, String repl, int lead})> kept =
        <({int from, int to, String repl, int lead})>[];
    for (final ({int from, int to, String repl, int lead}) e in edits) {
      if (kept.isNotEmpty && e.from < kept.last.to) continue;
      kept.add(e);
    }

    // ★ 从右往左应用，并**精确映射光标**（不得乱跳）
    for (final ({int from, int to, String repl, int lead}) e in kept.reversed) {
      if (caret >= e.to) {
        caret += e.repl.length - (e.to - e.from);
      } else if (caret > e.from) {
        // ★ 减掉 `lead`：区域开头那些**被丢掉**的字符不该算进 repl 的偏移
        caret = e.from + (caret - e.from - e.lead).clamp(0, e.repl.length);
      }
      cur = cur.substring(0, e.from) + e.repl + cur.substring(e.to);
    }
    caret = caret.clamp(0, cur.length);
    total += kept.length;
  }
  return NormalizeResult(cur, caret, total);
}

/// `\text{}` / `\mbox{}` / `\hbox{}` 的**内容区间**（不含命令名与花括号本身）。
///
/// 用途：撇号归一成 `^{\prime}` 时要跳过正文里的撇（`\text{don't}` 是散文，不是数学）。
List<({int from, int to})> _textArgRanges(String tex) {
  final List<({int from, int to})> out = <({int from, int to})>[];
  for (final String cmd in <String>[r'\text', r'\mbox', r'\hbox']) {
    var i = 0;
    while (true) {
      final int at = tex.indexOf(cmd, i);
      if (at < 0) break;
      var k = at + cmd.length;
      if (k < tex.length && tex[k] == '{') {
        var depth = 0;
        var j = k;
        for (; j < tex.length; j++) {
          if (tex[j] == '{') depth++;
          if (tex[j] == '}') {
            depth--;
            if (depth == 0) break;
          }
        }
        if (j < tex.length) out.add((from: k + 1, to: j));
        i = j + 1;
      } else {
        i = k;
      }
    }
  }
  return out;
}