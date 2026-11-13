// 数语引擎 · **结构完整性**（纯 Dart，2026-11-02「选择边界与剪贴板」批）
//
// 口径（讨论定稿，见 `notes/handover/20261102-选择边界与剪贴板.md` §3.1）：
//   **完整 = 壳有主 + 命令参数齐 + 环境成对**
//
// 壳 = `{` `}` `[` `]` `^` `_` `\begin` `\end` **`\left` `\right`** `&` `\\`（§3.1 原表）。
//
// ★★ 2026-11-13（三条反馈①③）：补上**当初漏实现的两行**——
//   · `\left` / `\right` / `\middle`：按**成对**判（`\mid`/`\big|` 那些单分隔符不算壳）；
//   · **命令参数齐**：`\frac` 必须跟两个花括号组。`\frac{bxc}` 这种 KaTeX 不报错、
//     但会把紧跟的 `+` 当分母吃掉（静默错位），必须判为不完整。
//   判据只收紧、不放松：它只用于**复制载荷 / 删除剩余 / 替换**的"自洽"判断，
//   源码本来就坏的公式仍走各自的老路（删除侧有"源本来就坏：不修"的早退）。

// ---------------------------------------------------------------------------
// 命令 → 需要几个花括号参数
// ---------------------------------------------------------------------------

/// 需要花括号参数的命令 → 参数个数（0 = 不需要参数，或不是要参数的写法）。
///
/// 这份表只服务"结构完整性"：它不追求覆盖全部 TeX，只覆盖本编辑器会生成、
/// 以及用户文档里真出现过的结构命令。漏一个的后果是**少补**，不会误删。
int requiredArgs(String name) {
  switch (name) {
    case 'frac':
    case 'dfrac':
    case 'tfrac':
    case 'cfrac':
    case 'binom':
    case 'dbinom':
    case 'tbinom':
    case 'overset':
    case 'underset':
    case 'stackrel':
      return 2;
    case 'sqrt':
    case 'overline':
    case 'underline':
    case 'hat':
    case 'bar':
    case 'vec':
    case 'dot':
    case 'ddot':
    case 'tilde':
    case 'widehat':
    case 'widetilde':
    case 'overrightarrow':
    case 'overleftarrow':
    case 'overbrace':
    case 'underbrace':
    case 'boxed':
    case 'text':
    case 'textrm':
    case 'textbf':
    case 'mathrm':
    case 'mathbf':
    case 'mathcal':
    case 'mathbb':
    case 'mathfrak':
    case 'operatorname':
      return 1;
  }
  return 0;
}

/// 吃**可选参数** `[...]` 的命令（本项目只有 `\sqrt`）。
bool takesOptionalArg(String name) => name == 'sqrt';

// ---------------------------------------------------------------------------
// 片段级检查（只看片段自己）
// ---------------------------------------------------------------------------

/// 片段是否结构完整（壳栈 + 命令参数齐 + 环境成对 + 定界符成对 + 首尾规则）。
///
/// ★ 不检查 `]`：`[` `]` 在数学里是普通字符（`[0,1]` 合法），
///   只有"可选参数的收尾"才有主人概念 —— 那要 doc 上下文，见 [orphanOwnerBefore]。
bool isCompleteFragment(String tex) {
  final String t = tex.trim();
  if (t.isEmpty) return true;
  if (t.startsWith('}') || t.startsWith('^') || t.startsWith('_')) return false;

  final List<int> braces = <int>[];
  final List<String> envs = <String>[];
  final List<int> delims = <int>[]; // `\left` 栈（`\middle` 不改深度）
  var i = 0;
  while (i < tex.length) {
    final String c = tex[i];
    if (c == r'\') {
      // ★ 2026-11-03（表批）：`\\` 的主人 = **所在环境**。
      //   裸着的行分隔符（没有 `\begin` 可依附）⇒ 片段不完整。
      if (envs.isEmpty &&
          braces.isEmpty &&
          delims.isEmpty &&
          i + 1 < tex.length &&
          tex[i + 1] == r'\') {
        return false;
      }
      final int j = _skipControl(tex, i);
      final String word = _controlWord(tex, i);
      // ★★ 2026-11-13（反馈①）：`\left` / `\right` / `\middle` 是**成对的壳**。
      if (word == 'left' || word == 'right' || word == 'middle') {
        if (word == 'left') {
          delims.add(i);
        } else {
          if (delims.isEmpty) return false; // 孤立的 `\right` / `\middle`
          if (word == 'right') delims.removeLast();
        }
        i = _delimTokenEnd(tex, i); // 连它后面那个分隔符一起跳过（`\{` `|` `.` …）
        continue;
      }
      if (word == 'begin' || word == 'end') {
        final int k = _skipSpaces(tex, j);
        final String? name = _readBraceName(tex, k);
        if (name == null) return false; // `\begin` 没有名字
        if (word == 'begin') {
          envs.add(name);
        } else {
          if (envs.isEmpty || envs.last != name) return false;
          envs.removeLast();
        }
        i = _afterBraceName(tex, k);
        continue;
      }
      // ★★ 2026-11-13（反馈③）：**命令参数齐**。`\frac{bxc}+d` 里 KaTeX 会把 `+`
      //   当第二个参数吃掉 —— 没有红字，但结构已经错了 ⇒ 判不完整。
      //   ★ 只**向前看**参数够不够，不在这里吞掉参数组：让主循环继续扫内容
      //     （参数里的嵌套结构、`\left` 等照样要被检查）。
      final int need = requiredArgs(word);
      if (need > 0 && !_hasArgsAhead(tex, j, need, word)) return false;
      i = j;
      continue;
    }
    if (c == '{') {
      braces.add(i);
    } else if (c == '}') {
      if (braces.isEmpty) return false; // 没有开括号的闭括号
      braces.removeLast();
    } else if (c == '&' && envs.isEmpty && braces.isEmpty) {
      // ★ 2026-11-03（表批）：`&` 的主人 = 所在环境；裸着的对齐符 ⇒ 不完整。
      return false;
    }
    i++;
  }
  if (braces.isNotEmpty) return false;
  if (envs.isNotEmpty) return false;
  if (delims.isNotEmpty) return false;

  // 末尾停在"要参数的命令"上 ⇒ 参数没进来
  final Match? m = RegExp(r'\\([A-Za-z]+)\s*$').firstMatch(tex);
  if (m != null && requiredArgs(m.group(1)!) > 0) return false;
  // 末尾停在 `^` / `_` 上 ⇒ 参数没进来
  if (RegExp(r'[\^_]\s*$').hasMatch(tex)) return false;
  return true;
}

/// `from` 起（跳过空白与可选参数）够不够 [need] 个花括号组。
bool _hasArgsAhead(String s, int from, int need, String name) {
  var k = from;
  var have = 0;
  while (have < need) {
    k = _skipSpaces(s, k);
    if (k < s.length && s[k] == '[' && takesOptionalArg(name)) {
      final int close = s.indexOf(']', k);
      if (close < 0) return false;
      k = close + 1;
      continue;
    }
    if (k >= s.length || s[k] != '{') return false;
    final int close = _matchBrace(s, k);
    if (close < 0) return false;
    have++;
    k = close + 1;
  }
  return true;
}

/// 片段里有没有**未闭合的开壳**（`{` / `\begin` / `\left`）—— 向右补全用。
///
/// 与 [isCompleteFragment] 的区别：**只看开壳**，不看"孤立的闭壳"。
/// 右侧能补的只有开壳；左侧的闭壳要走 [orphanOwnerBefore]。
bool hasUnclosedOpener(String tex) {
  final List<int> braces = <int>[];
  final List<String> envs = <String>[];
  final List<int> delims = <int>[];
  var i = 0;
  while (i < tex.length) {
    final String c = tex[i];
    if (c == r'\') {
      final int j = _skipControl(tex, i);
      final String word = _controlWord(tex, i);
      if (word == 'left' || word == 'right' || word == 'middle') {
        if (word == 'left') {
          delims.add(i);
        } else if (delims.isNotEmpty && word == 'right') {
          delims.removeLast();
        }
        i = _delimTokenEnd(tex, i);
        continue;
      }
      if (word == 'begin' || word == 'end') {
        final int k = _skipSpaces(tex, j);
        final String? name = _readBraceName(tex, k);
        if (name != null) {
          if (word == 'begin') {
            envs.add(name);
          } else if (envs.isNotEmpty && envs.last == name) {
            envs.removeLast();
          }
          i = _afterBraceName(tex, k);
          continue;
        }
      }
      i = j;
      continue;
    }
    if (c == '{') {
      braces.add(i);
    } else if (c == '}' && braces.isNotEmpty) {
      braces.removeLast();
    }
    i++;
  }
  return braces.isNotEmpty || envs.isNotEmpty || delims.isNotEmpty;
}

// ---------------------------------------------------------------------------
// ★★ 2026-11-13（反馈①）：`\left…\right` 的配对 / 扩对 / 半边识别
// ---------------------------------------------------------------------------

/// 一个定界符 token：`\left` / `\right` / `\middle` **连同它后面那个分隔符**
/// （`\{` `\|` `.` `(` `\lvert` …）。
typedef DelimToken = ({int start, int end, bool isLeft, bool isRight});

/// 扫 [lower, upper) 里的定界符 token（按位置升序）。
List<DelimToken> delimiterTokensIn(String doc, int lower, int upper) {
  final int lo = lower.clamp(0, doc.length);
  final int hi = upper.clamp(lo, doc.length);
  final List<DelimToken> out = <DelimToken>[];
  var i = lo;
  while (i < hi) {
    if (doc[i] != r'\') {
      i++;
      continue;
    }
    final String word = _controlWord(doc, i);
    if (word != 'left' && word != 'right' && word != 'middle') {
      i++;
      continue;
    }
    final int end = _delimTokenEnd(doc, i);
    out.add((
      start: i,
      end: end,
      isLeft: word == 'left',
      isRight: word == 'right',
    ));
    i = end;
  }
  return out;
}

/// 片段 `[s,e)` 切开了 [lower,upper) 里的 `\left…\right` 对 ⇒ 扩到整对。
///
/// 规则（§3.2「不完整 ⇒ 扩到最小完整单位」）：只要一对与片段**相交**而没被完整包含，
/// 就把它的两端都收进来；嵌套的重复到稳定。配不平（源本来就坏 / 越出框）⇒ 原样返回。
({int start, int end}) expandDelimiterPairs(
  String doc,
  int s,
  int e, {
  required int lower,
  required int upper,
}) {
  final int lo = lower.clamp(0, doc.length);
  final int hi = upper.clamp(lo, doc.length);
  var a = s.clamp(lo, hi);
  var b = e.clamp(a, hi);
  if (a >= b) return (start: a, end: b);
  final List<DelimToken> toks = delimiterTokensIn(doc, lo, hi);
  if (toks.isEmpty) return (start: a, end: b);
  // 全局配对（限定在 [lo,hi) 内）
  final List<int> stack = <int>[];
  final List<({int leftStart, int rightEnd})> pairs =
      <({int leftStart, int rightEnd})>[];
  for (var i = 0; i < toks.length; i++) {
    final DelimToken t = toks[i];
    if (t.isLeft) {
      stack.add(i);
    } else if (t.isRight && stack.isNotEmpty) {
      final DelimToken l = toks[stack.removeLast()];
      pairs.add((leftStart: l.start, rightEnd: t.end));
    }
  }
  for (var round = 0; round < 8; round++) {
    var changed = false;
    for (final ({int leftStart, int rightEnd}) p in pairs) {
      if (p.leftStart >= b || p.rightEnd <= a) continue; // 不相交
      if (p.leftStart >= a && p.rightEnd <= b) continue; // 完整包含
      if (p.leftStart < lo || p.rightEnd > hi) return (start: s, end: e);
      if (p.leftStart < a) {
        a = p.leftStart;
        changed = true;
      }
      if (p.rightEnd > b) {
        b = p.rightEnd;
        changed = true;
      }
    }
    if (!changed) break;
  }
  return (start: a, end: b);
}

/// [offset] 落在哪个定界符 token 上（`\left` / `\right` / `\middle` 连分隔符）；否则 `null`。
DelimToken? delimiterTokenAt(String doc, int offset) {
  final int o = offset.clamp(0, doc.length);
  for (final DelimToken t in delimiterTokensIn(doc, 0, doc.length)) {
    if (o >= t.start && o < t.end) return t;
  }
  return null;
}

/// [offset] 正好落在某个 **`\right` token 的末尾**（点那根竖线时上报的就是这里）；否则 null。
DelimToken? delimiterTokenEndingAt(String doc, int offset) {
  final int o = offset.clamp(0, doc.length);
  for (final DelimToken t in delimiterTokensIn(doc, 0, doc.length)) {
    if (t.end == o && t.isRight) return t;
  }
  return null;
}

/// [offset] 落在哪个定界符 token 上 ⇒ 返回它**那一对**的完整区间；否则 `null`。
///
/// 用途：双击 `\left|` / `\right|` 那根竖线时，把选区扩到整对（半边定界符
/// 不是"一个可替换的对象"）。`\middle|` ⇒ 返回包住它的那一对。
({int start, int end})? delimiterPairAt(String doc, int offset) {
  final int o = offset.clamp(0, doc.length);
  final List<DelimToken> toks = delimiterTokensIn(doc, 0, doc.length);
  if (toks.isEmpty) return null;
  final List<int> stack = <int>[];
  final Map<int, int> leftOf = <int, int>{}; // tokIndex(right) → tokIndex(left)
  for (var i = 0; i < toks.length; i++) {
    final DelimToken t = toks[i];
    if (t.isLeft) {
      stack.add(i);
    } else if (t.isRight && stack.isNotEmpty) {
      leftOf[i] = stack.removeLast();
    }
  }
  for (var i = 0; i < toks.length; i++) {
    final DelimToken t = toks[i];
    if (o < t.start || o >= t.end) continue;
    if (t.isLeft) {
      // 找与它配对的 right
      for (final MapEntry<int, int> e in leftOf.entries) {
        if (e.value == i) {
          return (start: t.start, end: toks[e.key].end);
        }
      }
      return null;
    }
    if (t.isRight && leftOf.containsKey(i)) {
      final DelimToken l = toks[leftOf[i]!];
      return (start: l.start, end: t.end);
    }
    // `\middle`：找最内层包住它的那一对
    ({int start, int end})? best;
    for (final MapEntry<int, int> e in leftOf.entries) {
      final DelimToken l = toks[e.value];
      final DelimToken r = toks[e.key];
      if (l.start < o && r.end > o) {
        if (best == null || (r.end - l.start) < (best.end - best.start)) {
          best = (start: l.start, end: r.end);
        }
      }
    }
    return best;
  }
  return null;
}

/// 从 `\left` / `\right` / `\middle` 的 `\` 起，跳过**它后面那个分隔符**之后的位置。
int _delimTokenEnd(String s, int i) {
  final int j = _skipControl(s, i);
  final String word = _controlWord(s, i);
  if (word != 'left' && word != 'right' && word != 'middle') return j;
  var k = j;
  while (k < s.length && (s[k] == ' ' || s[k] == '\t' || s[k] == '\n')) {
    k++;
  }
  if (k >= s.length) return k;
  if (s[k] == r'\') {
    // `\{` `\|` `.` … / `\lvert` `\langle` …
    if (k + 1 < s.length && !_isLetter(s[k + 1])) return k + 2;
    var m = k + 1;
    while (m < s.length && _isLetter(s[m])) {
      m++;
    }
    return m;
  }
  return k + 1;
}

// ---------------------------------------------------------------------------
// 起点侧：找"没有主人的壳"的主人（doc 坐标）
// ---------------------------------------------------------------------------

/// 片段 `[s, e)` 里"没有主人的壳"的**主人起点**（doc 坐标）；没有 ⇒ `null`。
///
/// 这是**向左扩**的唯一入口。只找"开启者在选区左边"的三类：
///   ① 片段开头就是 `{`，而紧挨在前的是一个**要参数的命令** ⇒ 主人 = 那个命令；
///   ② 片段里有**孤立闭括号 `}`**（它的 `{` 在选区外）⇒ 主人 = `{` 前的命令（没有命令就是 `{`）；
///   ③ 片段里有**孤立 `\end{X}`** ⇒ 主人 = 选区外那个 `\begin{X}`；
///   ④ 片段里有**可选参数的收尾 `]`**（它的 `[` 在选区外，且 `[` 前是 `\sqrt`）⇒ 主人 = `\sqrt`。
///
/// 返回**离 s 最近**的那个（最小扩张）。
int? orphanOwnerBefore(String doc, int s, int e) {
  final int a = s.clamp(0, doc.length);
  final int b = e.clamp(a, doc.length);
  if (a >= b) return null;
  int? best;

  void take(int at) {
    if (at < a && (best == null || at > best!)) best = at;
  }

  // ① 开头是 `{`：看它前面的命令
  final int first = _firstNonSpace(doc, a, b);
  if (first >= 0 && doc[first] == '{') {
    final int? owner = _ownerOfBrace(doc, first);
    if (owner != null) take(owner);
  }

  // ②③④ 扫片段
  final List<int> stack = <int>[]; // 未闭合的 `{`
  final List<String> envs = <String>[];
  var i = a;
  while (i < b) {
    final String c = doc[i];
    if (c == r'\') {
      final String word = _controlWord(doc, i);
      final int j = _skipControl(doc, i);
      if (word == 'begin' || word == 'end') {
        final int k = _skipSpaces(doc, j);
        final String? name = _readBraceName(doc, k);
        if (name != null) {
          if (word == 'begin') {
            envs.add(name);
          } else if (envs.isNotEmpty && envs.last == name) {
            envs.removeLast();
          } else {
            // 孤立的 `\end{X}`：去选区外找它的 `\begin{X}`
            final int begin = _lastBeginBefore(doc, a, name);
            if (begin >= 0) take(begin);
          }
          i = _afterBraceName(doc, k);
          continue;
        }
      }
      i = j;
      continue;
    }
    if (c == '{') {
      stack.add(i);
    } else if (c == '}') {
      if (stack.isEmpty) {
        // 孤立 `}`：它的 `{` 在选区左
        final int open = _matchBraceBack(doc, i);
        if (open >= 0) {
          final int? owner = _ownerOfBrace(doc, open);
          take(owner ?? open);
        }
      } else {
        stack.removeLast();
      }
    } else if (c == ']') {
      // 只有"可选参数的收尾"才算壳：`[` 前是 `\sqrt`
      final int open = _matchBracketBack(doc, i);
      if (open >= 0 && open < a) {
        final int owner = _commandEndingAt(doc, open);
        if (owner >= 0 && takesOptionalArg(_controlWord(doc, owner))) {
          take(owner);
        }
      }
    }
    i++;
  }

  // ⑤ 片段顶层有 `&` / `\\`（单元格分隔符），而它的环境 `\begin{X}` 在选区左边
  //    ⇒ 主人 = 那个 `\begin{X}`（环境成对，整表才自成一体）。
  //    ★ 「顶层」= 花括号与环境之外；`\text{a&b}` 里的 `&`、嵌套环境里的 `\\` 不算。
  if (_hasBareSeparator(doc, a, b)) {
    final int begin = _enclosingBeginBefore(doc, a);
    if (begin >= 0) take(begin);
  }
  return best;
}

/// 片段 `[a, b)` 里有没有**裸着**的 `&` / `\\`（花括号与环境之外）。
bool _hasBareSeparator(String doc, int a, int b) {
  final List<String> envs = <String>[];
  final List<int> braces = <int>[];
  var i = a;
  while (i < b) {
    final String c = doc[i];
    if (c == r'\') {
      if (envs.isEmpty &&
          braces.isEmpty &&
          i + 1 < b &&
          doc[i + 1] == r'\') {
        return true;
      }
      final String word = _controlWord(doc, i);
      if (word == 'begin' || word == 'end') {
        final int k = _skipSpaces(doc, _skipControl(doc, i));
        final String? name = _readBraceName(doc, k);
        if (name != null) {
          if (word == 'begin') {
            envs.add(name);
          } else if (envs.isNotEmpty && envs.last == name) {
            envs.removeLast();
          }
          i = _afterBraceName(doc, k);
          continue;
        }
      }
      i = _skipControl(doc, i);
      continue;
    }
    if (c == '{') {
      braces.add(i);
    } else if (c == '}' && braces.isNotEmpty) {
      braces.removeLast();
    } else if (c == '&' && envs.isEmpty && braces.isEmpty) {
      return true;
    }
    i++;
  }
  return false;
}

/// `before` 之前**还没闭合**的那个 `\begin{X}` 的 `\` 下标；没有 ⇒ -1。
int _enclosingBeginBefore(String doc, int before) {
  final List<({int at, String name})> stack = <({int at, String name})>[];
  final RegExp rx = RegExp(r'\\(begin|end)\s*\{([^{}]*)\}');
  for (final Match m in rx.allMatches(doc)) {
    if (m.start >= before) break;
    final String name = m.group(2)!.trim();
    if (m.group(1) == 'begin') {
      stack.add((at: m.start, name: name));
    } else if (stack.isNotEmpty && stack.last.name == name) {
      stack.removeLast();
    }
  }
  return stack.isEmpty ? -1 : stack.last.at;
}

// ---------------------------------------------------------------------------
// 小工具
// ---------------------------------------------------------------------------

/// 从 `\` 开始的控制序列之后的下标（`\frac` → 跳过 5 个字符；`\{` → 跳过 2 个）。
int _skipControl(String s, int i) {
  if (i >= s.length || s[i] != r'\') return i + 1;
  var j = i + 1;
  if (j >= s.length) return j;
  if (!_isLetter(s[j])) return j + 1; // 控制符号：`\{` `\\` `\,`
  while (j < s.length && _isLetter(s[j])) {
    j++;
  }
  return j;
}

/// `\` 后面的命令名（不是命令 ⇒ 空串）。
String _controlWord(String s, int i) {
  if (i >= s.length || s[i] != r'\') return '';
  var j = i + 1;
  final int start = j;
  while (j < s.length && _isLetter(s[j])) {
    j++;
  }
  return s.substring(start, j);
}

bool _isLetter(String c) {
  final int u = c.codeUnitAt(0);
  return (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A);
}

int _skipSpaces(String s, int i) {
  var j = i;
  while (j < s.length && (s[j] == ' ' || s[j] == '\t' || s[j] == '\n')) {
    j++;
  }
  return j;
}

/// `k` 处是 `{` ⇒ 读出 `{name}` 的 name（不校验闭合后的位置）；不是 ⇒ null。
String? _readBraceName(String s, int k) {
  if (k >= s.length || s[k] != '{') return null;
  final int close = _matchBrace(s, k);
  if (close < 0) return null;
  final String name = s.substring(k + 1, close).trim();
  if (name.isEmpty) return null;
  return name;
}

int _afterBraceName(String s, int k) {
  if (k >= s.length || s[k] != '{') return k;
  final int close = _matchBrace(s, k);
  return close < 0 ? s.length : close + 1;
}

/// 从 `open` 处的 `{` 找配对的 `}`（跳过 `\{` `\}`）；找不到 ⇒ -1。
int _matchBrace(String s, int open) {
  var d = 0;
  for (var i = open; i < s.length; i++) {
    if (s[i] == r'\') {
      i = _skipControl(s, i) - 1;
      continue;
    }
    if (s[i] == '{') d++;
    if (s[i] == '}') {
      d--;
      if (d == 0) return i;
    }
  }
  return -1;
}

/// 从 `close` 处的 `}` 往回找配对的 `{`；找不到 ⇒ -1。
int _matchBraceBack(String s, int close) {
  var d = 0;
  for (var i = close; i >= 0; i--) {
    if (i > 0 && s[i - 1] == r'\') continue; // 跳过 `\{` `\}`
    if (s[i] == '}') d++;
    if (s[i] == '{') {
      d--;
      if (d == 0) return i;
    }
  }
  return -1;
}

/// 从 `close` 处的 `]` 往回找最近的 `[`（跳过转义）；找不到 ⇒ -1。
int _matchBracketBack(String s, int close) {
  for (var i = close - 1; i >= 0; i--) {
    if (i > 0 && s[i - 1] == r'\') continue;
    if (s[i] == '[') return i;
  }
  return -1;
}

/// `brace` 处 `{` 的主人：紧挨在前的**要参数的命令**；没有 ⇒ null。
int? _ownerOfBrace(String s, int brace) {
  final int cmd = _commandEndingAt(s, brace);
  if (cmd < 0) return null;
  final String word = _controlWord(s, cmd);
  if (requiredArgs(word) > 0) return cmd;
  return null;
}

/// `end`（不含）之前紧挨着的命令的 `\` 下标；不是命令 ⇒ -1。
int _commandEndingAt(String s, int end) {
  var j = end - 1;
  while (j >= 0 && (s[j] == ' ' || s[j] == '\t' || s[j] == '\n')) {
    j--;
  }
  if (j < 0) return -1;
  if (!_isLetter(s[j])) {
    // `\{` 之类的控制符号：`\` 紧贴在前面
    return (s[j] == r'\') ? j : -1;
  }
  while (j >= 0 && _isLetter(s[j])) {
    j--;
  }
  if (j >= 0 && s[j] == r'\') return j;
  return -1;
}

/// 选区左边最近的 `\begin{name}`（`\` 的下标）；没有 ⇒ -1。
int _lastBeginBefore(String doc, int before, String name) {
  final RegExp rx = RegExp(r'\\begin\s*\{' + RegExp.escape(name) + r'\}');
  var found = -1;
  for (final Match m in rx.allMatches(doc)) {
    if (m.start >= before) break;
    found = m.start;
  }
  return found;
}

int _firstNonSpace(String s, int a, int b) {
  for (var i = a; i < b; i++) {
    final String c = s[i];
    if (c != ' ' && c != '\t' && c != '\n') return i;
  }
  return -1;
}
