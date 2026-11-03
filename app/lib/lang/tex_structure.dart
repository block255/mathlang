// 数语引擎 · **结构完整性**（纯 Dart，2026-11-02「选择边界与剪贴板」批）
//
// 口径（讨论定稿，见 `notes/handover/20261102-选择边界与剪贴板.md` §3.1）：
//   **完整 = 壳有主 + 命令参数齐 + 环境成对**
//
// 这里只做"够用"的检查，不做 TeX 解析：
//   · `{}` 用**栈**（跳过 `\{` `\}`）—— ★ 计数平不算数：
//     `a_{1}}+\sqrt[x]{a_{2}` 两个开两个闭，但结构是**交叉**的；
//   · `\begin{X}…\end{X}` 按名字配对；
//   · 开头不许是 `}` `^` `_`（没有开括号的闭括号 / 没有底的脚本）；
//   · 末尾不许停在需要参数的命令上（`\frac` `\sqrt` …）；
//   · 片段里的 `]` 若是**可选参数**的收尾、而它的 `[` 在选区外 ⇒ 也算缺主人
//     （这一条要 doc 上下文，见 [orphanOwnerBefore]）。
//
// **不算壳**（用户拍板）：普通括号 `(` `)`；围栏 `$` `$$`（走段边界规则）。
// 口径细节：`\text` / `\mathrm` 这类**只换字体**的命令**仍算**"要参数的命令"——
//   §3.1 的"透明"只用于判断能不能挂挂件，不用于判断"壳有没有主人"。

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

/// 片段是否结构完整（`{}` 栈 + 环境配对 + 开头不是闭壳 + 末尾不是缺参数的命令）。
///
/// ★ 不检查 `]`：`[` `]` 在数学里是普通字符（`[0,1]` 合法），
///   只有"可选参数的收尾"才有主人概念 —— 那要 doc 上下文，见 [orphanOwnerBefore]。
bool isCompleteFragment(String tex) {
  final String t = tex.trim();
  if (t.isEmpty) return true;
  if (t.startsWith('}') || t.startsWith('^') || t.startsWith('_')) return false;

  final List<int> braces = <int>[];
  final List<String> envs = <String>[];
  var i = 0;
  while (i < tex.length) {
    final String c = tex[i];
    if (c == r'\') {
      // ★ 2026-11-03（表批）：`\\` 的主人 = **所在环境**。
      //   裸着的行分隔符（没有 `\begin` 可依附）⇒ 片段不完整。
      if (envs.isEmpty &&
          braces.isEmpty &&
          i + 1 < tex.length &&
          tex[i + 1] == r'\') {
        return false;
      }
      final int j = _skipControl(tex, i);
      final String word = _controlWord(tex, i);
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

  // 末尾停在"要参数的命令"上 ⇒ 参数没进来
  final Match? m = RegExp(r'\\([A-Za-z]+)\s*$').firstMatch(tex);
  if (m != null && requiredArgs(m.group(1)!) > 0) return false;
  // 末尾停在 `^` / `_` 上 ⇒ 参数没进来
  if (RegExp(r'[\^_]\s*$').hasMatch(tex)) return false;
  return true;
}

/// 片段里有没有**未闭合的开壳**（`{` 或 `\begin`）—— 向右补全用。
///
/// 与 [isCompleteFragment] 的区别：**只看开壳**，不看"孤立的闭壳"。
/// 右侧能补的只有开壳；左侧的闭壳要走 [orphanOwnerBefore]。
bool hasUnclosedOpener(String tex) {
  final List<int> braces = <int>[];
  final List<String> envs = <String>[];
  var i = 0;
  while (i < tex.length) {
    final String c = tex[i];
    if (c == r'\') {
      final int j = _skipControl(tex, i);
      final String word = _controlWord(tex, i);
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
  return braces.isNotEmpty || envs.isNotEmpty;
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
