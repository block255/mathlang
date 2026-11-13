// 数语引擎 · **剪贴板切片**（纯 Dart，2026-10-23 公测反馈 A1/A2）
//
// 一个选区要进剪贴板之前，先把它变成「**自洽片段**」—— 也就是"能单独渲染的完整源码"。
//
// 三条边界规则（顺序执行，见 `notes\design\剪贴板与跨语境粘贴.md` §二）：
//   ① **段级配平**：两端都在**同一个**数学段内部 ⇒ 补一对 `$…$`；
//      只有一端在段内 ⇒ 把那一端**扩到段边界**（`$` / `$$`）。
//   ② **括号配平**：片段里 `{}` 不平衡（拖选常切在 `\frac{` 中间）⇒ 向外扩到平衡。
//   ③ **控制词吸附**：边界落在 `\frac` / `\text` 这类**控制词中间** ⇒ 扩到词首 / 词尾。
//
// 为什么（平权口径）：`$` 是**渲染提示**，不是语义墙（《编辑地基与手感》§7.1）。
// 片段离开公式时**补**、进入公式时**剥**（粘贴侧见 `paste_context.dart`）——
// 于是剪贴板里永远是"完整源码"，贴到别处（含记事本 / DeepSeek）也永远能用。
//
// ★ 实测背景（2026-10-21 用户报）：复制行内公式里的一个分式，得到的是
//   `\frac{x^3}{\lvert\sin x\rvert^3}$` —— **缺开头 `$`、多结尾 `$`**（裸 substring 的必然结果）。

import 'env_table.dart';
import 'math_spans.dart';
import 'tex_structure.dart';

/// 一次复制/剪切要用的结果。
///
/// `[start, end)` 是**源区间**（剪切就删它）；[text] 是真正进剪贴板的文本。
/// 两者可能不一致：when [wrapped] 为真，[text] 是"片段 + 一对补出来的 `$`"，而源区间不变。
class ClipboardSlice {
  const ClipboardSlice({
    required this.start,
    required this.end,
    required this.text,
    this.wrapped = false,
  });

  /// 源区间起点（**剪切**要删的范围从这里算）
  final int start;

  /// 源区间终点（开区间）
  final int end;

  /// 进剪贴板的文本（自洽片段）
  final String text;

  /// 是不是替用户补了一对 `$…$`（状态栏 / 测试用）
  final bool wrapped;

  bool get isEmpty => text.isEmpty;

  @override
  String toString() =>
      'ClipboardSlice[$start,$end)${wrapped ? ' 补定界符' : ''} "$text"';
}

/// 把选区 `[selStart, selEnd)` 变成自洽片段。区间可以反着给（`selStart > selEnd` 也行）。
///
/// ★★ 2026-11-03（围栏不参与选区 · 定稿 §七）：**选区只看可见流**。
///   `$` 是零宽记账——不扩选区、也不进载荷。载荷按源里的 span 切成
///   “数学 / 文字”交替的 run：数学 run 包 `$`（对象补齐在 run 内做），文字 run 原样；
///   源里的 `$` 一律跳过（不重复包）。
ClipboardSlice clipboardSlice(String doc, int selStart, int selEnd) {
  final int lo = selStart <= selEnd ? selStart : selEnd;
  final int hi = selStart <= selEnd ? selEnd : selStart;
  var s = lo.clamp(0, doc.length);
  var e = hi.clamp(0, doc.length);
  if (e <= s) {
    return ClipboardSlice(start: s, end: e, text: '');
  }

  // ③ 先做控制词吸附（吸附可能把区间吃进别的地方，所以要**在下判断之前**做）
  s = _snapCommandStart(doc, s);
  e = _snapCommandEnd(doc, e);
  if (e <= s) {
    return ClipboardSlice(start: s, end: e, text: '');
  }

  final List<MathSpan> spans = scanMathSpans(doc);
  // ★★ 2026-11-13（反馈②）：**跨 2+ 个行间段**才把"完整覆盖的段"落成 `$$…$$` 块；
  //   单个行间段永远按**片段**（单行化）——否则行间块复制就没法舒服地粘进行内。
  final int displayHits = spans
      .where((MathSpan sp) => sp.display && sp.end > s && sp.start < e)
      .length;
  final bool cross = displayHits >= 2;
  final StringBuffer sb = StringBuffer();
  var cursor = s;
  var anyMath = false;
  for (final MathSpan sp in spans) {
    if (sp.end <= s || sp.start >= e) continue;
    final int pad = sp.display ? 2 : 1;
    final int cs = sp.start + pad;
    final int ce = sp.end - pad;

    // 段前的文字：止于开定界符（`$` 不进载荷）
    final int textEnd = e < sp.start ? e : sp.start;
    if (textEnd > cursor) {
      sb.write(doc.substring(cursor, textEnd));
      cursor = textEnd;
    }

    // 数学 run：只取**内容**的交集；对象补齐在 run 内做（不碰 `$`）
    final int ms = s > cs ? s : cs;
    final int me = e < ce ? e : ce;
    if (ms < me) {
      // ★★ 2026-11-03（表批）：选区**跨格**地落在多行环境里 ⇒ 载荷是整格矩形
      //   （局部表补中性 `bmatrix`，整表保留原类型）。单格不在此列（照旧复制内容）。
      final String? table =
          sp.display ? _tablePayload(sp, ms, me, cs) : null;
      if (table != null) {
        sb.write(r'$');
        sb.write(table);
        sb.write(r'$');
        anyMath = true;
      } else if (sp.display) {
        final String? payload = _displayPayload(doc, sp, ms, me, cross: cross);
        if (payload != null) {
          sb.write(payload);
          anyMath = true;
        }
      } else {
        final ({int start, int end}) fix = _completeWithin(doc, ms, me, sp);
        sb.write(r'$');
        sb.write(doc.substring(fix.start, fix.end));
        sb.write(r'$');
        anyMath = true;
      }
    }

    // 跳过收尾定界符（选区跨过它时）
    final int next = e < sp.end ? e : sp.end;
    if (next > cursor) cursor = next;
    if (cursor >= e) break;
  }
  if (cursor < e) sb.write(doc.substring(cursor, e));
  return ClipboardSlice(
    start: s,
    end: e,
    text: sb.toString(),
    wrapped: anyMath,
  );
}

/// 行间段的复制载荷（2026-11-13 反馈②）。
///
/// · **单块**：永远片段 —— 内容单行化（块格式换行压成空格；
///   `aligned`/`matrix` 的行内渲染由 KaTeX 负责，`\\` 不受影响）；
///   选中内容跨多行却没覆盖整段 ⇒ 先扩到整段（对象完整性），再单行化。
/// · **跨块**：完整覆盖的段 ⇒ `$$\n…\n$$` 块（保留块地位）；否则片段。
String? _displayPayload(
  String doc,
  MathSpan sp,
  int ms,
  int me, {
  required bool cross,
}) {
  final int cs = sp.start + 2;
  final int ce = sp.end - 2;
  final int vs = _trimStart(doc, cs, ce);
  final int ve = _trimEnd(doc, cs, ce);
  if (vs >= ve) return null;
  final bool whole = ms <= vs && me >= ve;
  if (cross && whole) {
    final String tex = doc.substring(vs, ve);
    if (tex.trim().isEmpty) return null;
    return '\$\$\n$tex\n\$\$';
  }
  var a = ms.clamp(vs, ve);
  var b = me.clamp(vs, ve);
  if (b <= a) return null;
  // ★ 片段的"对象完整性"照旧走 `_completeWithin`（命令参数 / 环境 / 控制词 / 定界符对）
  //   —— 行间段不因为"是块"就跳过这一步（否则切在 `\frac{` 上会吐出 `$\frac$`）。
  final ({int start, int end}) fix = _completeWithin(doc, a, b, sp);
  String tex = doc.substring(fix.start, fix.end);
  if (tex.contains('\n')) {
    // 片段跨了多行（多半只选了 aligned 的几行）⇒ 扩到整段再单行化：
    // 半个环境不是自洽片段。
    tex = doc.substring(vs, ve);
  }
  tex = _oneLine(tex);
  if (tex.isEmpty) return null;
  return '\$$tex\$';
}

/// 把"块格式的换行"压成空格（TeX 里单换行本来就是空白；`\\` 是环境自己的行分隔，不动）。
String _oneLine(String s) => s.replaceAll(RegExp(r'[ \t]*\n[ \t\n]*'), ' ').trim();

int _trimStart(String s, int from, int to) {
  var i = from.clamp(0, s.length);
  final int end = to.clamp(i, s.length);
  while (i < end && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n')) {
    i++;
  }
  return i;
}

int _trimEnd(String s, int from, int to) {
  var j = to.clamp(0, s.length);
  final int start = from.clamp(0, j);
  while (j > start && (s[j - 1] == ' ' || s[j - 1] == '\t' || s[j - 1] == '\n')) {
    j--;
  }
  return j;
}

bool _isLetterCode(int c) =>
    (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

/// 选区**跨格**地落在多行环境体内 ⇒ 返回整格矩形的载荷（带壳、不含 `$`）；否则 null。
///
/// · 局部表 ⇒ 中性 `bmatrix`；整表 ⇒ 保留原类型（§3.2）；
/// · `cases` / `aligned` ⇒ **整行**（行单位），壳沿用原类型；
/// · 只压在一格里 ⇒ null（照旧复制那一格的内容，§3.5「不扩」）。
String? _tablePayload(MathSpan sp, int s, int e, int contentStart) {
  final int ls = s - contentStart;
  final int le = e - contentStart;
  final EnvTable? t = envTableForRange(sp.tex, ls, le);
  if (t == null) return null;
  final CellSpan? rect = cellsSpanning(t, ls, le);
  if (rect == null) return null;
  if (rect.r0 == rect.r1 && rect.c0 == rect.c1) return null;
  return cellsPayload(t, sp.tex, rect);
}

/// 切在 `\f|rac` 这种**控制词中间**时，把起点挪回 `\`
int _snapCommandStart(String doc, int i) {
  if (i <= 0 || i >= doc.length) return i;
  final int c = doc.codeUnitAt(i);
  if (!_isLetterCode(c)) return i; // 右边不是字母 ⇒ 不在词中间
  if (!_isLetterCode(doc.codeUnitAt(i - 1))) return i; // 左边不是字母 ⇒ 恰在词首
  var j = i;
  while (j > 0 && _isLetterCode(doc.codeUnitAt(j - 1))) {
    j--;
  }
  if (j > 0 && doc[j - 1] == r'\') j--;
  return j;
}

/// 切在 `\fr|ac` 这种**控制词中间**时，把终点挪到词尾之后
int _snapCommandEnd(String doc, int i) {
  if (i <= 0 || i >= doc.length) return i;
  if (!_isLetterCode(doc.codeUnitAt(i))) return i;
  if (!_isLetterCode(doc.codeUnitAt(i - 1))) return i;
  var j = i;
  while (j < doc.length && _isLetterCode(doc.codeUnitAt(j))) {
    j++;
  }
  return j;
}


/// 在 [sp] 这个数学段的**内容**里把 `[s, e)` 修成**自洽**的片段。
///
/// ★★ 2026-11-02（选择边界批 · 定稿 §3.1）：**向左补主人** ＋ **右侧用栈补开壳**。
///   旧实现只朝右补（`_completeArgs` / `_completeEnvs`），左边缺的主子没人管：
///   · `{...}{2020}` —— 片段以参数的 `{` 开头，`\frac` 在选区左 ⇒ 丢分数线；
///   · `x]{…}` —— `]` 的 `[` 在选区左 ⇒ 丢 `\sqrt[`；
///   · `…\end{cases}` —— `\begin` 在选区左 ⇒ 孤立 `\end`。
///   现在先把"没有主人的壳"的主子拉进来，再用**栈**补右侧（计数平不算数）。
///
/// ★ 2026-11-03（§七）：上限是**内容**（`ce`），不是 `$`——围栏不参与。
({int start, int end}) _completeWithin(String doc, int s, int e, MathSpan sp) {
  final int pad = sp.display ? 2 : 1;
  final int cs = sp.start + pad;
  final int ce = sp.end - pad;
  // ★★ 2026-11-13（反馈①）：**切开 `\left…\right` 对 ⇒ 扩到整对**。
  final ({int start, int end}) pair =
      expandDelimiterPairs(doc, s, e, lower: cs, upper: ce);
  s = pair.start;
  e = pair.end;
  for (var k = 0; k < 8; k++) {
    final int? owner = orphanOwnerBefore(doc, s, e);
    if (owner == null || owner >= s || owner < cs) break;
    s = owner;
  }
  final ({int start, int end}) head = _completeArgs(doc, s, e, ce);
  final ({int start, int end}) tail =
      _completeTrailingCommand(doc, head.start, head.end, ce);
  // ★★★ 2026-11-01（反馈 16 · R6）：**环境（`\begin{cases}…\end{cases}`）也要自洽**。
  //   实测动因：用户从 `\begin{cases}` 选到 `y=3tsint` 松手（尾巴没带上 `\end{cases}`）
  //   ⇒ 旧代码原样吐出 `$\begin{cases}x=3tcost\\⏎y=3tsint$`（不配平）⇒ 粘到行内就是
  //   `[公式不完整]`。旧的自洽化只认 `\frac{a}` 这种**命令参数**，不认环境。
  final ({int start, int end}) env =
      _completeEnvs(doc, tail.start, tail.end, ce);
  // ★ 右侧：未闭合的开壳（`{` / `\begin`）补到闭合为止（栈判据）。
  var end = env.end;
  while (end < ce && hasUnclosedOpener(doc.substring(env.start, end))) {
    end++;
  }
  // 补不齐（原文本来就坏）⇒ 退到整段**内容**（不含定界符）。
  if (!isCompleteFragment(doc.substring(env.start, end))) {
    return (start: cs, end: ce);
  }
  return (start: env.start, end: end);
}

/// 片段里有**没闭合的 `\begin{X}`** ⇒ 把结尾扩到那个 `\end{X}` 之后（最多到 [limit]）。
///
/// 判据：按出现顺序压栈，走到片段末尾时栈里还剩下的 `\begin` 就是"缺尾巴"的；
/// 继续往后扫，直到栈空 —— 中途出现的**别的**环境照旧压栈（嵌套要一起补齐）。
/// ★ 只做"往后补"这一向；"选区从环境中间起"（开头多出 `\end`）另行处理（台账登记）。
({int start, int end}) _completeEnvs(String doc, int s, int e, int limit) {
  final RegExp rx = RegExp(r'\\(begin|end)\s*\{([A-Za-z*]+)\}');
  final List<({int start, int end, bool isBegin, String name})> toks =
      <({int start, int end, bool isBegin, String name})>[];
  for (final Match m in rx.allMatches(doc.substring(0, limit.clamp(0, doc.length)))) {
    toks.add((
      start: m.start,
      end: m.end,
      isBegin: m.group(1) == 'begin',
      name: m.group(2)!,
    ));
  }
  final List<String> stack = <String>[];
  // ★ 只认**片段自己打开**的环境：起点之前就有的 `\begin{X}` 不算 ——
  //   否则"选区落在分段块某一格里"也会被当成"缺尾巴"而扩到 `\end{cases}`，
  //   删除就会把围栏拆坏（守卫 `delete_cross_math_test`「选区落在分段块内部」抓到过）。
  var i = 0;
  while (i < toks.length && toks[i].start < s) {
    i++;
  }
  while (i < toks.length && toks[i].start < e) {
    final t = toks[i];
    if (t.isBegin) {
      stack.add(t.name);
    } else if (stack.isNotEmpty && stack.last == t.name) {
      stack.removeLast();
    }
    i++;
  }
  if (stack.isEmpty) return (start: s, end: e);
  var end = e;
  while (stack.isNotEmpty && i < toks.length) {
    final t = toks[i];
    if (t.isBegin) {
      stack.add(t.name);
    } else if (stack.last == t.name) {
      stack.removeLast();
      end = t.end;
    }
    i++;
  }
  // 补不齐（跑到 math span 尽头还没闭合）⇒ 原样返回，让上层按"落单"处理
  if (stack.isNotEmpty) return (start: s, end: e);
  return (start: s, end: end);
}

/// 片段**末尾**正好停在一个结构命令后面（`x+\sqrt`）⇒ 把它的参数组补进来。
({int start, int end}) _completeTrailingCommand(
    String doc, int s, int e, int limit) {
  final Match? m = RegExp(r'\\([A-Za-z]+)\s*$').firstMatch(doc.substring(s, e));
  if (m == null) return (start: s, end: e);
  final int need = _requiredArgs(m.group(1)!);
  if (need == 0) return (start: s, end: e);
  var have = 0;
  var i = e;
  var end = e;
  while (have < need && i < limit) {
    if (doc[i] == ' ') {
      i++;
      continue;
    }
    if (doc[i] == '[') {
      final int j = _matchPair(doc, i, '[', ']');
      if (j < 0) break;
      i = j + 1;
      continue;
    }
    if (doc[i] != '{') break;
    final int j = _matchPair(doc, i, '{', '}');
    if (j < 0) break;
    have++;
    end = j + 1;
    i = j + 1;
  }
  return (start: s, end: end);
}

/// 片段**正好以结构命令开头**时，把它缺的参数组补进来。
///
/// 实测动因：拖选很容易停在 `\frac{a}` 这种"参数只选到一半"的地方，
/// 那样的片段单独渲染必然报错（KaTeX: expected 2 args）。
/// 只认"必须显式参数组"的结构命令；其余命令原样。
int _requiredArgs(String name) => requiredArgs(name);

({int start, int end}) _completeArgs(String doc, int s, int e, int limit) {
  final Match? m = RegExp(r'^\\([A-Za-z]+)').firstMatch(doc.substring(s, e));
  if (m == null) return (start: s, end: e);
  final int need = _requiredArgs(m.group(1)!);
  if (need == 0) return (start: s, end: e);
  var have = 0;
  var i = s + m.end;
  var end = e;
  // ① 先数片段里**已经完整包含**的参数组（`\sqrt[3]{x}` 的 `[…]` 不算参数）
  while (i < end) {
    if (doc[i] == ' ') {
      i++;
      continue;
    }
    if (doc[i] == '[') {
      final int j = _matchPair(doc, i, '[', ']');
      if (j < 0) break;
      i = j + 1;
      continue;
    }
    if (doc[i] == '{') {
      final int j = _matchPair(doc, i, '{', '}');
      if (j < 0) break;
      have++;
      i = j + 1;
      continue;
    }
    break;
  }
  // ② 缺的组往后补（不许越过数学段）
  while (have < need && i < limit) {
    if (doc[i] == ' ') {
      i++;
      continue;
    }
    if (doc[i] != '{') break;
    final int j = _matchPair(doc, i, '{', '}');
    if (j < 0) break;
    have++;
    end = j + 1;
    i = j + 1;
  }
  return (start: s, end: end);
}

/// 从 `open` 处的左定界符找配对的右定界符（返回下标；找不到 -1）
int _matchPair(String doc, int open, String left, String right) {
  var depth = 0;
  for (var i = open; i < doc.length; i++) {
    if (i > 0 && doc[i - 1] == r'\') continue;
    if (doc[i] == left) depth++;
    if (doc[i] == right) {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}
