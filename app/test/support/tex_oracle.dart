// 守卫用的**独立 oracle**（2026-11-13 三条反馈）。
//
// 为什么不复用 `lang/tex_structure.isCompleteFragment`：那是**被测对象**本身。
// 11-02 那轮的守卫就是拿它自己验自己 ⇒ `\left/\right` 根本没实现，载荷只剩半个
// `\left` 也照样绿。这里独立实现一遍（壳栈 + 命令参数计数 + 定界符栈），
// 两边都过才算数。

/// 返回 `null` = 结构完整；否则返回问题描述。
String? texProblem(String tex) {
  final String t = tex.trim();
  if (t.isEmpty) return null;
  if (t.startsWith('}') || t.startsWith(']') || t.startsWith('^') || t.startsWith('_')) {
    return '以闭壳/悬空脚本开头: $t';
  }
  final List<int> braces = <int>[];
  final List<String> envs = <String>[];
  final List<int> lefts = <int>[];
  var i = 0;
  while (i < t.length) {
    final String c = t[i];
    if (c == r'\') {
      var j = i + 1;
      var word = '';
      if (j < t.length && _isLetter(t[j])) {
        final int s = j;
        while (j < t.length && _isLetter(t[j])) {
          j++;
        }
        word = t.substring(s, j);
      } else {
        j = (i + 2).clamp(0, t.length);
      }
      if (word.isEmpty && j == i + 2 && i + 1 < t.length && t[i + 1] == r'\') {
        // 裸的 `\\`：主人是所在环境；顶层出现不合法
        if (envs.isEmpty && braces.isEmpty) return '顶层 \\\\ @$i';
        i = j;
        continue;
      }
      if (word == 'left') {
        lefts.add(i);
        i = _skipDelim(t, j);
        continue;
      }
      if (word == 'right') {
        if (lefts.isEmpty) return r'孤立的 \right @' '$i';
        lefts.removeLast();
        i = _skipDelim(t, j);
        continue;
      }
      if (word == 'middle') {
        if (lefts.isEmpty) return r'孤立的 \middle @' '$i';
        i = _skipDelim(t, j);
        continue;
      }
      if (word == 'begin' || word == 'end') {
        final int k = _skipSpace(t, j);
        if (k >= t.length || t[k] != '{') return '\\$word 没有名字';
        final int close = _matchBrace(t, k);
        if (close < 0) return '\\$word 的名字没闭';
        final String name = t.substring(k + 1, close).trim();
        if (word == 'begin') {
          envs.add(name);
        } else {
          if (envs.isEmpty || envs.last != name) return '孤立的 \\end{$name}';
          envs.removeLast();
        }
        i = close + 1;
        continue;
      }
      final int need = _argsOf(word);
      if (need > 0) {
        var k = j;
        var have = 0;
        while (have < need) {
          while (k < t.length && t[k] == ' ') {
            k++;
          }
          if (k < t.length && t[k] == '[') {
            final int close = t.indexOf(']', k);
            if (close < 0) return '\\$word 的可选参数没闭';
            k = close + 1;
            continue;
          }
          if (k >= t.length || t[k] != '{') {
            return '\\$word 参数不够（$have/$need）';
          }
          final int close = _matchBrace(t, k);
          if (close < 0) return '\\$word 的参数组没闭';
          have++;
          k = close + 1;
        }
        i = k;
        continue;
      }
      i = j;
      continue;
    }
    if (c == '{') {
      braces.add(i);
    } else if (c == '}') {
      if (braces.isEmpty) return '孤立的 } @$i';
      braces.removeLast();
    } else if (c == '&') {
      if (envs.isEmpty && braces.isEmpty) return '裸 & @$i';
    }
    i++;
  }
  if (braces.isNotEmpty) return '未闭合的 {';
  if (envs.isNotEmpty) return '未闭合的环境 ${envs.last}';
  if (lefts.isNotEmpty) return r'未闭合的 \left';
  return null;
}

int _argsOf(String name) {
  const Map<String, int> table = <String, int>{
    'frac': 2, 'dfrac': 2, 'tfrac': 2, 'cfrac': 2, 'binom': 2, 'dbinom': 2,
    'tbinom': 2, 'overset': 2, 'underset': 2, 'stackrel': 2,
    'sqrt': 1, 'overline': 1, 'underline': 1, 'hat': 1, 'bar': 1, 'vec': 1,
    'dot': 1, 'ddot': 1, 'tilde': 1, 'widehat': 1, 'widetilde': 1,
    'overrightarrow': 1, 'overleftarrow': 1, 'overbrace': 1, 'underbrace': 1,
    'boxed': 1, 'text': 1, 'textrm': 1, 'textbf': 1, 'mathrm': 1, 'mathbf': 1,
    'mathcal': 1, 'mathbb': 1, 'mathfrak': 1, 'operatorname': 1,
  };
  return table[name] ?? 0;
}

int _skipDelim(String t, int i) {
  if (i >= t.length) return i;
  if (t[i] == r'\') {
    var j = i + 1;
    if (j < t.length && (t[j] == '{' || t[j] == '}' || t[j] == '|' || t[j] == '.')) {
      return j + 1;
    }
    while (j < t.length && _isLetter(t[j])) {
      j++;
    }
    return j;
  }
  return i + 1;
}

int _skipSpace(String t, int i) {
  var j = i;
  while (j < t.length && (t[j] == ' ' || t[j] == '\t' || t[j] == '\n')) {
    j++;
  }
  return j;
}

int _matchBrace(String t, int open) {
  var depth = 0;
  for (var i = open; i < t.length; i++) {
    if (t[i] == r'\') {
      i++;
      continue;
    }
    if (t[i] == '{') depth++;
    if (t[i] == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

bool _isLetter(String c) {
  final int u = c.codeUnitAt(0);
  return (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A);
}
