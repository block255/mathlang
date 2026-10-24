// 数语引擎 · 数学段的文档级导航与删除（S3-3 + S3-4 的胶水层）
//
// 位点表 / 槽序（`caret_sites.dart` + `site_adjacency.dart`）与原子删除（`smart_delete.dart`）
// 都只在「**一个数学段的 tex** + 段内相对偏移」这一层工作。本文件负责把它们接到文档层：
//   · 找到光标所在的数学段（行内 `$...$` 走投影；行间 `$$ … $$` 走块模型）
//   · `←→` 跨 `$` 边界**进出公式**（§3.3：光标**不落在 `$` 上**）
//   · `Tab` / `↑↓` 在段内没有落点时**走出公式**
//   · **公式外侧的删除**（§3.3 + §4.0）：紧邻的是**空壳** → 连定界符整段删；
//     否则**委托进公式的内层边界**（公式末尾与公式之后是同一根像素 ⇒ 行为必须相同）
//
// **纯 Dart，不依赖 Flutter。**

import '../core/block.dart';
import 'caret_sites.dart';
import 'projection.dart';
import 'site_adjacency.dart';
import 'smart_delete.dart';

/// 文档里的一个数学段（全部是**绝对**偏移）
class MathRegion {
  const MathRegion({
    required this.openStart,
    required this.contentStart,
    required this.contentEnd,
    required this.closeEnd,
    required this.tex,
    required this.isDisplay,
  });

  /// 开头定界符的起点（`$` 或 `$$` 的第一个字符）
  final int openStart;

  /// tex 的起点（= 开头定界符之后）
  final int contentStart;

  /// tex 的终点（= 收尾定界符的位置）
  final int contentEnd;

  /// 收尾定界符之后（= 出公式后光标的落点）
  final int closeEnd;

  /// 不含定界符的源码
  final String tex;

  /// 行间公式块（`$$ … $$`）还是行内（`$...$`）
  final bool isDisplay;

  /// tex 内的相对偏移 → 文档绝对偏移
  int abs(int rel) => contentStart + rel;

  /// 文档绝对偏移 → tex 内的相对偏移
  int rel(int abs) => abs - contentStart;

  @override
  String toString() => 'MathRegion[$openStart..$closeEnd)'
      '${isDisplay ? ' 行间' : ' 行内'} tex="$tex"';
}

/// 光标（绝对偏移）所在的数学段；不在任何数学段里则 `null`。
///
/// ★ 判定区间是 **`[contentStart, contentEnd]`**（两个定界符**之间**）：
/// 光标位置是"字符之间的缝"，所以 `contentStart - 1` 就是 `$` 之前那个缝（属于文字侧），
/// `contentEnd + 1` 是 `$` 之后那个缝（也属于文字侧）。这样"进出公式"才不会在边界上卡住。
MathRegion? mathRegionAt(String source, int offset) {
  final int o = offset.clamp(0, source.length);
  final BlockIndex idx = BlockIndex.parse(source);
  final LineIndex lines = idx.lines;
  final int line = lines.lineOf(o);

  // ① 行间公式块（`$$ … $$`）：整块的排版文本就是 tex
  for (final Block b in idx.blocks) {
    if (line < b.lineFrom || line >= b.lineTo) continue;
    if (b.type != BlockType.math) break;
    final int start = lines.starts[b.lineFrom];
    final int end = lines.ends[b.lineTo - 1];
    // ★★ 2026-10-17：**围栏字符本身也算"在公式里"**（区间看作 `(start, end]`）。
    //   为什么：光标停在两个 `$` 之间时，插入/换行会把 `$` 配成单数 ⇒ 公式退化成源码。
    //   只放掉 `start`（块所在行**行首之前**那一格）—— 那一格按 `Enter` 应该在块**之前**断段。
    if (o <= start || o > end) continue;
    final String body = source.substring(start, end);
    final _Fence? f = _stripFence(body);
    if (f == null) break;
    return MathRegion(
      openStart: start,
      contentStart: start + f.prefix,
      contentEnd: start + f.prefix + f.tex.length,
      closeEnd: end,
      tex: f.tex,
      isDisplay: true,
    );
  }

  // ② 行内 `$...$`：在光标所在行里找（投影规则与渲染层完全一致）
  final int lineStart = lines.starts[line];
  for (final ProjectionSegment s in projectInline(lines.text(line))) {
    if (!s.isMath) continue;
    final int cs = lineStart + s.start; // tex 起点
    final int ce = lineStart + s.end; // 收尾 `$` 的位置
    if (o >= cs && o <= ce) {
      return MathRegion(
        openStart: cs - 1,
        contentStart: cs,
        contentEnd: ce,
        closeEnd: ce + 1,
        tex: s.tex,
        isDisplay: false,
      );
    }
  }
  return null;
}

/// 剥掉行间公式块的围栏，给出（tex 起点相对块文本的偏移, tex）。
///
/// ★★ 2026-10-17 修：**单行闭合的 `$$…$$` 原先认不出来**（只认"`$$` 独占一行 … `$$` 独占一行"），
///   于是 `$$x=1$$` 掉进行内分支、被当成 `$x=1$`（`display=false`，`closeEnd` 落在**两个闭合 `$` 之间**）
///   ⇒ 在那格按 `Enter` 就把 `\n\n` 插进 `$$` 中间 ⇒ **围栏被劈开、公式退化成源码**
///   （用户实测："点在 `a_i` 后面按回车，编码就爆出来了"）。同一族的还有退格/删除。
_Fence? _stripFence(String body) {
  final String trimmed = body.trimRight();
  final int lead = trimmed.length - trimmed.trimLeft().length;
  final String l = trimmed.substring(lead);
  // ① **单行闭合**：`$$…$$`（判据与块模型 `BlockMarkers.isClosedMathFence` 一致：长度 > 4）
  if (!l.contains('\n')) {
    if (l.length <= 4 || !l.startsWith(r'$$') || !l.endsWith(r'$$')) return null;
    return _Fence(lead + 2, l.substring(2, l.length - 2));
  }
  // ② **多行**：首行 `$$`、末行 `$$`
  final int nl = body.indexOf('\n');
  if (body.substring(0, nl).trim() != r'$$') return null;
  final int lastNl = body.lastIndexOf('\n');
  if (lastNl <= nl) return null;
  if (body.substring(lastNl + 1).trim() != r'$$') return null;
  return _Fence(nl + 1, body.substring(nl + 1, lastNl));
}

class _Fence {
  const _Fence(this.prefix, this.tex);
  final int prefix;
  final String tex;
}

// ---------------------------------------------------------------- ←→

/// `→`：下一个文档级光标落点。**跨 `$` 边界进公式，且光标不落在 `$` 上。**
int nextCaretOffset(String source, int offset) {
  final int o = offset.clamp(0, source.length);
  final MathRegion? r = mathRegionAt(source, o);
  if (r == null) {
    // 文字里：右边紧邻一个 `$` → 直接进该公式的**第一个位点**
    final MathRegion? nr = o + 1 <= source.length ? mathRegionAt(source, o + 1) : null;
    if (nr != null && nr.openStart == o) {
      final CaretSiteTable t = buildCaretSites(nr.tex);
      return nr.abs(t.snap(0).offset);
    }
    return o + 1;
  }
  final CaretSiteTable t = buildCaretSites(r.tex);
  final CaretSite s = t.snap(r.rel(o));
  final int i = t.indexOf(s.offset);
  // ★★ 「甲」方案（2026-10-15 用户拍板）：**`→` 跳过"数学段内的末尾位点"**。
  //
  // 为什么：`tex.length` 那个位点（= 闭合 `$` 所在那一格）与 `closeEnd`（公式之后）
  // **在屏幕上是同一根像素** —— 收尾 `$` 不可见，两者无从分辨。停在它上面有两个害处：
  //   ① 用户按 `→` 会以为"按了没反应"（光标其实挪了，只是看不出来）
  //   ② 在它上面断块会把公式**劈开**（`$` 配成单数 → 整行退化成源码；用户实测抓出）
  // ⇒ `→` 的语义是"往前走 / 出去"，就**一步出公式**，不停在看不见的边界上。
  //
  // ★ `←` **故意不跳**（见 [prevCaretOffset]）：从公式外面进到公式末尾，
  //   是"我要继续改这段数学"的正当动作 —— 这是**有意的不对称**：`←` 进去、`→` 出去。
  // ★★ 2026-10-17：**跳过"粘合位点"**（用户用 `→` 扫出三处"没反应"）——
  //   基座与它自己的 `^`/`_` 之间、同一基座两个脚本之间、裸参数内容开头。
  //   这些位置的注入被挪进了"脚本内容开头"⇒ 与脚本第一个位点**同一根像素**。
  //   位点本身保留（点击/吸附要用），只在**方向键**上跳过。
  var next = i + 1;
  while (next < t.sites.length) {
    if (t.sites[next].glue) {
      next++;
      continue;
    }
    final int off = t.sites[next].offset;
    // ★ 注：`}` 之后那一格与内容末尾**同一根像素**（括号不可见）—— 但**不统一跳**：
    //   2026-10-15 用户扫出来的"金表"（`\sum_{i=1}^{n}a_i`）明确要求 14 那一格**要停**，
    //   统一跳会把它抹掉。D2 只对下面这两族用"同一根像素"规则。
    //
    // ★★ 2026-10-24（批 3 · D2）：「`\left…\right` 组里最后一格」与「`\right` 之前」同一根像素
    //   ⇒ 跳过。实测（`\left|{sinx}\right|`）：不跳时从 `x` 之后出发，第 1 下停在 `}` 与 `\right|`
    //   之间（屏幕上**一点没动**），第 2 下才出组 —— 用户说的"要点两下才能出去"就是它。
    //
    // ★★★ 2026-10-24（批 5b · 嵌套普查）：**这条只在"前一个字符不可见"时才成立**。
    //   普查抓到的反例：`\left(x^2\right)` 的 `x^2` —— `2` 之后那一格**也**紧跟着 `\right`，
    //   但它前面是**看得见的 `2`** ⇒ 跳过就等于"`→` 从 `2` 之前一下蹦出公式"，
    //   用户根本停不到"写完指数"的位置（实测 `→ 0 → 6 → 8 → 出公式`，9 被吃掉）。
    //   判据收窄成：**前一字符是 `}`**（组收尾，不可见）才跳。
    final bool afterGroupBrace = off > 0 && r.tex[off - 1] == '}';
    if (afterGroupBrace && off <= r.tex.length && r.tex.substring(off).startsWith(r'\right')) {
      next++;
      continue;
    }
    // ★★★ 2026-10-24（批 3 · D2 续）：**`→` 按"对象"走，不钻进脚本内部**。
    //
    // 口径来由：用户要"打完绝对值里最后一个字符，一下就出去"。而 `|…|^{3}` 里的 `3` 是
    // 那个对象的**挂件**（乙口径：字形 + 挂件 = 一个对象）⇒ `→` 从对象里出去就该**一步出去**；
    // 想改脚标要么**点**它、要么**`←`** 从右边进来（`←` 有意不跳，见 [prevCaretOffset]）、
    // 要么用 `Tab` 走槽。
    // 实测（`\frac{x^{3}}{\left|{sinx}\right|^{3}}`）：不跳时要依次停在 34（`3` 前）、35（`3` 后）、
    // 36（`}` 后）—— 用户说的"要点两下"就是这两格。
    final List<SlotStep> cur = t.sites[i].path;
    final List<SlotStep> cand = t.sites[next].path;
    final bool entersScript = cand.length == cur.length + 1 &&
        _samePath(cand, cur) &&
        (cand.last.command == '^' || cand.last.command == '_') &&
        // ★ 只对"挂在**闭合定界符**后面的脚标"生效（`\left|…\right|^3`）：
        //   `\sum_{i=1}^{n}` 的上下限、`x^2` 的指数都**保持原样**（用户 2026-10-15 扫出来的
        //   "金表"序列就是逐步穿过上下限的，别把那条顺手改掉）。
        _scriptAfterRightDelim(r.tex, off);
    if (entersScript) {
      final List<SlotStep> scriptPrefix = cand;
      while (next < t.sites.length && _samePath(t.sites[next].path, scriptPrefix)) {
        next++;
      }
      continue;
    }
    break;
  }

  // ★★★ 2026-10-24（批 5 · H1）：**从"粘合位点"出发时，右边第一格要再跳一格**。
  //
  // 用户实测：「点 `x` 与 `3` 之间，再按 `→`，**点两下**才到 `3` 右边；
  // 你是不是把 x 后面和 3 前面显示成一样的了」—— **确实一样**：
  // 粘合位点（`x` 之后，注入被挪进脚本内容开头）与"脚本自己的第一个位点"（`3` 之前）
  // **同一根像素**（这正是 `CaretSite.glue` 的由来）。
  // 平时撞不上：`→` 的**到达**规则已经跳过粘合位点（上面那个 while）。
  // 但 D5 之后"点挂件左半 ⇒ 落到对象之前"会把光标停在粘合位点上 ⇒ 再按一下就"没动"。
  if (t.sites[i].glue && next == i + 1 && next + 1 < t.sites.length) {
    next++;
  }

  // ★★★ 2026-10-24（批 9 · H6）：**行间块要停在 tex 末位**（那就是 ∑ / ∫ 的"正右边"）。
  //
  // 用户实测（`\sum_{i=1}^{n}`）：打完上限 `n` 按 `→`，光标**没有**停在 ∑ 正右边，
  //   而是直接出了公式、落到"块之后"那一格（竖条贴块底 ⇒ 看起来"掉到 ∑ 下面"），
  //   在那里按删除**整块**就没了。
  // 判据：`$` 不可见 ⇒ 行内公式的 tex 末位与"公式之后"同一根像素 ⇒ 跳过（原有口径，别动）；
  //   而**行间块的末位是看得见的**（∑ 的右侧），必须停 —— 再按一下才出块。
  if (next < t.sites.length &&
      (t.sites[next].offset < r.tex.length || r.isDisplay)) {
    return r.abs(t.sites[next].offset);
  }
  return r.closeEnd; // 段内没有更靠右的位点了 → 走出到 `$` 之后
}

/// `path` 是否以 [prefix] 开头（逐级相等）
bool _samePath(List<SlotStep> path, List<SlotStep> prefix) {
  if (path.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (!identical(path[i], prefix[i])) {
      // SlotStep 没有 ==，按内容比
      if (path[i].command != prefix[i].command ||
          path[i].argIndex != prefix[i].argIndex ||
          path[i].row != prefix[i].row ||
          path[i].col != prefix[i].col) {
        return false;
      }
    }
  }
  return true;
}

/// 这个位点前面的那个 `^` / `_`，是不是挂在**闭合定界符**后面（`\right|` / `\right)` …）。
///
/// 判据：从 [off] 往前跳过 `{` 与空格，遇到 `^`/`_` 后，再看它前面的文本是否以
/// `\right|` / `\right)` / `\right]` / `\right\}` / `\right.` 结尾。
///
/// ★ 2026-10-24（批 3 · D2）：只有这一族脚标按"挂件"处理（`→` 一步出去）；
///   `\sum_{i=1}^{n}` 的上下限、`x^2` 的指数**保持原来的逐格**（金表不许漂）。
bool _scriptAfterRightDelim(String tex, int off) {
  var i = off - 1;
  while (i >= 0 && (tex[i] == '{' || tex[i] == ' ')) {
    i--;
  }
  if (i < 0 || (tex[i] != '^' && tex[i] != '_')) return false;
  final String head = tex.substring(0, i).trimRight();
  const List<String> tails = <String>[
    r'\right|', r'\right)', r'\right]', r'\right\}', r'\right.', r'\right\|', //
    r'\right\vert', r'\right\Vert',
  ];
  for (final String t in tails) {
    if (head.endsWith(t)) return true;
  }
  return false;
}

/// `←`：上一个文档级光标落点（与 [nextCaretOffset] 镜像）。
int prevCaretOffset(String source, int offset) {
  final int o = offset.clamp(0, source.length);
  final MathRegion? r = mathRegionAt(source, o);
  if (r == null) {
    // 文字里：左边紧邻一个收尾 `$` → 进该公式的**最后一个位点**
    final MathRegion? pr = o - 1 >= 0 ? mathRegionAt(source, o - 1) : null;
    if (pr != null && pr.closeEnd == o) {
      final CaretSiteTable t = buildCaretSites(pr.tex);
      return pr.abs(t.sites.last.offset);
    }
    return o - 1;
  }
  final CaretSiteTable t = buildCaretSites(r.tex);
  final CaretSite s = t.snap(r.rel(o));
  final int i = t.indexOf(s.offset);
  // ★ `←` 也跳过粘合位点（对称；理由见 [nextCaretOffset]）。
  var back = i - 1;
  while (back >= 0 && t.sites[back].glue) {
    back--;
  }
  if (back >= 0) return r.abs(t.sites[back].offset);
  return r.openStart; // 段内第一个位点 → 走出到 `$` 之前
}
// ★ 注意：`←` **不做**「跳过 tex 末位点」那件事（与 [nextCaretOffset] 有意不对称）——
//   从公式外面按 `←` 就是要**进到公式末尾**继续改这段数学，那是正当落点。

// ---------------------------------------------------------------- Tab / ↑↓

/// `Tab`（`forward`）/ `Shift+Tab` 的落点；`null` = **不在公式里，Tab 交给焦点遍历**。
///
/// 段内没有落点时**走出公式**（§十-①：空槽 → 槽末尾 → 退出公式）。
int? tabStopAt(String source, int offset, {required bool forward}) {
  final MathRegion? r = mathRegionAt(source, offset);
  if (r == null) return null;
  final CaretSiteTable t = buildCaretSites(r.tex);
  final int rel = r.rel(offset.clamp(0, source.length));
  final int? next = forward ? tabForward(t, rel) : tabBackward(t, rel);
  if (next != null) return r.abs(next);
  return forward ? r.closeEnd : r.openStart;
}

/// `↑`/`↓` 的落点；`null` = **没有竖直邻居 → 不移动**（§三：不要乱跳）。
int? verticalStopAt(String source, int offset, {required bool up}) {
  final MathRegion? r = mathRegionAt(source, offset);
  if (r == null) return null;
  final CaretSiteTable t = buildCaretSites(r.tex);
  final int? v = verticalNeighbor(t, r.rel(offset.clamp(0, source.length)), up: up);
  return v == null ? null : r.abs(v);
}

// ---------------------------------------------------------------- 退格 / 删除

/// 光标紧邻的那一段连续 `\n` 里，**一次删除该吃掉几个**（`null` = 不归这条管）。
///
/// 与 Enter 的插入规则**镜像**（`EditView._enterPayload`）：
///
/// | 紧邻的 `\n` 个数 | 一次删除吃掉 | 为什么 |
/// |---|---|---|
/// | `k == 0` / `k == 1` | 不归这条管（交给文字层删 1 个字符 / 软换行） | 软换行就是一个字符 |
/// | `k == 2` | **2** | 一个**段落边界**（Enter 从正文里插的正是 `\n\n`） |
/// | `k >= 3` | **1** | 真空段落里"在空行上按 Enter"只补了 1 个 ⇒ 退格也还 1 个 |
///
/// ★ 判据只看**光标紧邻**的那一段，不看整篇：`一\n\n\n行` 从左到右退格会
///   先吃掉真空段落那一行（k=3 ⇒ 删 1），再吃掉段落边界（k=2 ⇒ 删 2）。
SmartEdit? _paragraphBreakDelete(String source, int o, {required bool forward}) {
  var k = 0;
  if (forward) {
    while (o + k < source.length && source[o + k] == '\n') {
      k++;
    }
  } else {
    while (o - 1 - k >= 0 && source[o - 1 - k] == '\n') {
      k++;
    }
  }
  if (k < 2) return null;
  final int n = k == 2 ? 2 : 1;
  if (forward) {
    if (o + n > source.length) return null;
    return SmartEdit.remove(o, o + n, o);
  }
  return SmartEdit.remove(o - n, o, o - n);
}

/// 文档级 `Backspace` / `Delete` 的处置（**绝对偏移**）。
///
/// 不在数学段里 → 字节级；在段里 → 交给 [smartBackspace] / [smartDelete]，
/// 段内已无可删时处理**公式首/公式尾的边界语义**（§3.3）。
SmartEdit smartEditAt(String source, int offset, {required bool forward}) {
  final int o = offset.clamp(0, source.length);

  // ★★★ 2026-10-18 晚（用户实测）：**段落边界是一个对象**。
  //   现象：「`一|行` 按 Enter ⇒ `一\n\n行`（新段），**按一次删除没还原、要按两次**」。
  //   根因：Enter 插的是 `\n\n`**两个**字符，而退格一次只删一个。
  //   口径与 §4.6「删除要干脆」一致：**Enter 造出来的结构，一次退格整个撤销**。
  final SmartEdit? brk = _paragraphBreakDelete(source, o, forward: forward);
  if (brk != null) return brk;

  final MathRegion? r = mathRegionAt(source, o);

  // ① 不在公式里（含"紧贴公式**外侧**"）→ 交给文字层：
  //    删的是**左右紧邻的那一个可见对象**（§4.0 通则；数学段算一个对象）
  if (r == null) return _textLayerDelete(source, o, forward: forward);

  final CaretSiteTable t = buildCaretSites(r.tex);
  final int rel = r.rel(o);
  final SmartEdit e = forward ? smartDelete(t, rel) : smartBackspace(t, rel);
  if (!e.isNone) {
    if (!e.deletes) return SmartEdit.move(r.abs(e.caret));
    return SmartEdit.remove(r.abs(e.from!), r.abs(e.to!), r.abs(e.caret));
  }

  // ③ 段内没得删 → 边界语义。
  //    ★★ 关键：先处理空壳，再把落点**挪到定界符外侧**、回到 ① 的"可见对象"规则 ——
  //    **不要**在这里自己写"删一个字符"：外侧紧邻的可能**又是一个公式段**
  //    （`$\frac{}{}$$\frac{}{}$` 这种相邻写法），那时要删的是**那一整段**，
  //    而不是它那个看不见的定界符。全域不变量测试当场抓出过这一条。
  final bool emptyShell = r.tex.trim().isEmpty;
  if (!forward && rel <= 0) {
    if (emptyShell) return SmartEdit.remove(r.openStart, r.closeEnd, r.openStart);
    return _textLayerDelete(source, r.openStart, forward: false);
  }
  if (forward && rel >= r.tex.length) {
    if (emptyShell) return SmartEdit.remove(r.openStart, r.closeEnd, r.openStart);
    return _textLayerDelete(source, r.closeEnd, forward: true);
  }
  return SmartEdit.none;
}

/// **文字层**的删除：删的是"左右紧邻的那一个**可见对象**"（设计稿 §4.0 通则）。
///
/// · 文字里一个对象 = **一个字符**
/// · **数学段**：★ **空壳**（tex 空）本身就是一个可见对象 ⇒ 连定界符整段删；
///   **非空** ⇒ **委托进公式的内层边界**（§3.3：公式末尾与公式之后是**同一根像素**，
///   必须给出同一个结果 ⇒ 删的是公式里最后 / 最前那个**同层对象**；删空了 ⇒ 留空壳 §4.6）
///
/// ★★ 为什么**不再"整段删"**（2026-10-15 改口径，用户实测）：那是**公式块**思路
/// （把 `$` 当成一层）。用户原话：「点分式**整体**后面删 = 删掉整个分式」——
/// 而"整个分式"是**公式里的一个对象**，不是"整个公式段"。
///
/// ★ 也不能在这里写"删一个字符"：外侧紧邻的可能**又是一个公式段**
/// （`$\frac{}{}$$\frac{}{}$` 这种相邻写法，公式 A 的末尾按 `Delete` 就是这种情形）——
/// 那种情况要把决定权交给**那个公式的内层边界**，而不是去碰它那个看不见的定界符。
SmartEdit _textLayerDelete(String source, int offset, {required bool forward}) {
  final int o = offset.clamp(0, source.length);
  final MathRegion? adj = forward
      ? (o + 1 <= source.length ? mathRegionAt(source, o + 1) : null)
      : (o - 1 >= 0 ? mathRegionAt(source, o - 1) : null);
  final bool adjacent =
      adj != null && (forward ? adj.openStart == o : adj.closeEnd == o);
  if (adjacent) {
    // 空壳 = 一个可见对象 ⇒ 整段删（含定界符）
    if (adj.tex.trim().isEmpty) {
      return SmartEdit.remove(adj.openStart, adj.closeEnd, adj.openStart);
    }
    return _innerBoundaryDelete(adj, forward: forward);
  }
  // 文字：一个对象 = 一个字符
  if (!forward) return o <= 0 ? SmartEdit.none : SmartEdit.remove(o - 1, o, o - 1);
  return o >= source.length ? SmartEdit.none : SmartEdit.remove(o, o + 1, o);
}

/// 从**公式外侧**删除 ⇒ **委托进公式的内层边界**（§3.3「同一根像素」）：
/// 把光标当作停在 tex 末尾（退格）/ tex 开头（`Delete`）来算同一个"同层对象"。
SmartEdit _innerBoundaryDelete(MathRegion r, {required bool forward}) {
  final CaretSiteTable t = buildCaretSites(r.tex);
  final int rel = forward ? 0 : r.tex.length;
  final SmartEdit e = forward ? smartDelete(t, rel) : smartBackspace(t, rel);
  if (e.isNone) {
    // tex 非空却找不到同层对象（理论上不该发生）⇒ 稳妥：整段删
    return SmartEdit.remove(r.openStart, r.closeEnd, r.openStart);
  }
  if (!e.deletes) return SmartEdit.move(r.abs(e.caret));
  return SmartEdit.remove(r.abs(e.from!), r.abs(e.to!), r.abs(e.caret));
}
