// 数语引擎 · **智能包裹**（S4-a）：把"裸 LaTeX"识别成行内数学，自动补 `$…$`
//
// 为什么必须有它（用户拍板：**没有开关**）：
//   用户/AI 给我们的文本里，数学常常是**裸的**（`a_n`、`\varepsilon`、`\sum_{k=n+1}^m`），
//   不带 `$`。没有这一步，"粘贴/导入"这条链根本走不通 ⇒ 它是**数据进门的基础设施**，
//   不是可选项。（`/` 转分式那类**才是**可配置的快捷键，与本文件无关。）
//
// 三条设计原则：
//   ① **保守优先**：宁可少包，不要错包 —— 错包会把普通文字变成公式，比不包更难受；
//   ② **证据驱动**：一段文字要被判成数学，必须**含证据**（`\命令` / 上下标 / 数学关系符），
//      纯英文单词（"Cauchy Criterion"）**绝不**包；
//   ③ **不碰已有结构**：`$…$` / `$$…$$` / 代码块内部一律跳过。
//
// **纯 Dart**（没有 Flutter 依赖），方便单测。

/// 一处建议包裹：把 `source[start, end)` 包成 `$…$`（或 `$$…$$`）
class WrapRun {
  const WrapRun(this.start, this.end, {this.display = false});

  final int start;
  final int end;

  /// ★★ 2026-10-17 用户拍板（B'）：这一处要包成**行间块** `$$…$$`。
  ///
  /// 判据 = **整行只有这一个式子**（整行除首尾空白外都被它覆盖）**且**含"显示倾向"的证据
  /// （大算符 `\sum`/`\int`… 、分式、关系符 `=`/`≤`…）。
  /// 为什么必须这样：n 元算子的上下限**只在 display 样式下堆叠**（`\sum_{k=1}^n` 在行内
  /// 会画成右边的小上下标）—— 作业答案里"独立成行的推导"天生该是行间块；
  /// 而"行内夹在文字里的 `a_n`"必须保持行内（同权原则：数学是这一行的对象）。
  final bool display;

  @override
  String toString() => 'Wrap[$start,$end)${display ? ' 行间' : ''}';
}

/// 扫描结果：[runs] 是要包裹的区间（互不重叠、按位置升序）
class SmartWrapPlan {
  const SmartWrapPlan(this.runs);

  final List<WrapRun> runs;

  bool get isEmpty => runs.isEmpty;

  @override
  String toString() => 'SmartWrap(${runs.length} 处：$runs)';
}

/// 包一次：把每个区间写成 `$…$`（行间块写成 `$$\n…\n$$`）
String applySmartWrap(String source, SmartWrapPlan plan) {
  final StringBuffer sb = StringBuffer();
  var i = 0;
  for (final WrapRun r in plan.runs) {
    if (r.start < i) continue; // 防御：重叠就跳过
    sb.write(source.substring(i, r.start));
    sb.write(r'$');
    if (r.display) {
      // ★ 行间块：`$$` 独占一行（块模型的围栏判据要求整行 `$$`）
      sb.write(r'$');
      sb.write('\n');
      sb.write(source.substring(r.start, r.end).trim());
      sb.write('\n');
      sb.write(r'$');
      sb.write(r'$');
    } else {
      sb.write(source.substring(r.start, r.end));
      sb.write(r'$');
    }
    i = r.end;
  }
  sb.write(source.substring(i));
  return sb.toString();
}

/// **纯 LaTeX 命令词表**（有这些就足以断定"这是数学"）
///
/// 只收"一定属于数学、且不会出现在普通英文里"的；`\sin` 这类函数名也在内。
const Set<String> kMathCommands = <String>{
  // 希腊
  'alpha', 'beta', 'gamma', 'delta', 'epsilon', 'varepsilon', 'zeta', 'eta',
  'theta', 'vartheta', 'iota', 'kappa', 'lambda', 'mu', 'nu', 'xi', 'pi',
  'rho', 'sigma', 'tau', 'upsilon', 'phi', 'varphi', 'chi', 'psi', 'omega',
  'Gamma', 'Delta', 'Theta', 'Lambda', 'Xi', 'Pi', 'Sigma', 'Phi', 'Psi', 'Omega',
  // 运算 / 关系
  'le', 'leq', 'ge', 'geq', 'ne', 'neq', 'approx', 'equiv', 'sim', 'to',
  'rightarrow', 'Rightarrow', 'leftarrow', 'Leftarrow', 'mapsto', 'infty',
  'pm', 'mp', 'times', 'div', 'cdot', 'cdots', 'ldots', 'dots', 'vdots', 'ddots',
  'forall', 'exists', 'in', 'notin', 'subset', 'subseteq', 'cup', 'cap',
  'emptyset', 'varnothing', 'sum', 'prod', 'int', 'iint', 'oint', 'lim',
  'sup', 'inf', 'partial', 'nabla',
  // 函数名
  'sin', 'cos', 'tan', 'cot', 'sec', 'csc', 'arcsin', 'arccos', 'arctan',
  'sinh', 'cosh', 'tanh', 'log', 'ln', 'exp', 'max', 'min', 'det', 'dim',
  'ker', 'deg', 'gcd', 'Pr', 'mod', 'bmod',
  // 定界符 / 结构
  'left', 'right', 'frac', 'dfrac', 'tfrac', 'sqrt', 'overline', 'underline',
  'hat', 'bar', 'vec', 'dot', 'ddot', 'text', 'mathrm', 'mathbf', 'mathcal',
  'mathbb', 'operatorname', 'begin', 'end', 'quad', 'qquad', 'not',
  'langle', 'rangle', 'lfloor', 'rfloor', 'lceil', 'rceil', 'mid', 'Vert',
  'vert', 'perp', 'parallel', 'angle', 'triangle', 'circ', 'prime',
};

/// 允许出现在"数学片段"里的 ASCII 字符（中文/全角标点都**不在**里面 ⇒ 天然把中英文分开）
bool _isMathChar(int c) {
  if (c == 0x20) return true; // 空格
  if (c >= 0x30 && c <= 0x39) return true; // 0-9
  if (c >= 0x41 && c <= 0x5A) return true; // A-Z
  if (c >= 0x61 && c <= 0x7A) return true; // a-z
  const String extra = r'\_{}^()[]|+-=<>/*.,:;!?±≤≥≠≈·×÷→←⇒⇐∞∂∇';
  return extra.codeUnits.contains(c) || c == 0x27; // 单引号（f'）
}

/// 这段文字里有没有"这是数学"的**证据**
bool _hasMathEvidence(String s) {
  if (s.contains(r'\')) return true; // 命令
  if (s.contains('_') || s.contains('^')) return true; // 上下标
  // 关系符 / 运算符（单个字母 + 空格不算）
  for (final String op in <String>['=', '<', '>', '±', '≤', '≥', '≠', '≈', '→', '∞']) {
    if (s.contains(op)) return true;
  }
  return false;
}

/// ★★ 2026-10-20（T-C 实测 F13）：**"有证据"还不够，还得有"实体"**。
///
/// 实测现场（导入 `homework20261014-answer.md`）：md 里两处被**错包**成公式
///   · 行首引用标记 `> 素材：…` ⇒ `>` 被包成 `$>$`（引用块被破坏，页面上出现数学盒子里的 `>`）
///   · 行内代码 `` `test_data\homework20261014\` `` ⇒ 路径里的 `\` 被当成命令 ⇒ 包成 `$…$`
///     ⇒ KaTeX 报 `\h` 不认识 ⇒ 页面上红字 `[公式不完整]`
///
/// 判据（只收紧、不放松）：一段要被判成数学，除了 [ _hasMathEvidence ] 之外，
/// 还必须**含至少一个字母 / 数字**（`\命令` 也算：命令名本身就是字母）。
/// 这样"只有运算符"的段（`>`、`<`、`+`）永远不会被包 —— 它们不构成数学段。
bool _hasMathSubstance(String s) {
  for (var i = 0; i < s.length; i++) {
    final int c = s.codeUnitAt(i);
    if (c >= 0x30 && c <= 0x39) return true; // 0-9
    if ((c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)) return true; // A-Z a-z
  }
  return false;
}

/// ★★ 2026-10-20（T-C F13 续）：段**首/尾挂着运算符**的不包。
///
/// 实测：`a 大于 b >` 里切出来的 `b >` 有字母也有 `>` ⇒ 按旧判据会被包成 `$b >$`。
/// 但那是个**悬空的**比较符（中文里"大于"后面跟个 `>` 是语气），不是数学。
/// 判据：首尾若还是 `= < > + - * /`，说明这个"数学段"没写完整 ⇒ 保守不包。
bool _hasDanglingOperator(String s) {
  const String ops = '=<>+-*/';
  if (s.isEmpty) return false;
  if (ops.contains(s[0])) return true;
  if (ops.contains(s[s.length - 1])) return true;
  return false;
}

/// 纯英文（含空格的单词序列，如 "Cauchy Criterion"）⇒ **不是**数学
bool _looksLikePlainEnglish(String s) {
  final String t = s.trim();
  if (t.isEmpty) return true;
  if (!RegExp(r'^[A-Za-z ]+$').hasMatch(t)) return false;
  // 纯字母+空格：再要求"不是单个字母"（单个 `x` 也可能是数学，但保守起见不包）
  return t.split(RegExp(r'\s+')).where((String w) => w.isNotEmpty).isNotEmpty;
}

/// **扫描整篇文本**，给出建议包裹的区间
///
/// 会跳过：已有的 `$…$`、`$$…$$` 块、代码块（三反引号围栏）、行首列表标记、URL。
SmartWrapPlan planSmartWrap(String source) {
  final List<WrapRun> runs = <WrapRun>[];
  // ① 先标记"不能碰"的区间：`$…$` / `$$…$$` / ``` 代码块
  final List<({int from, int to})> locked = <({int from, int to})>[];
  var i = 0;
  while (i < source.length) {
    if (source.startsWith(r'$$', i)) {
      final int end = source.indexOf(r'$$', i + 2);
      final int to = end < 0 ? source.length : end + 2;
      locked.add((from: i, to: to));
      i = to;
      continue;
    }
    if (source.startsWith('```', i)) {
      final int end = source.indexOf('```', i + 3);
      final int to = end < 0 ? source.length : end + 3;
      locked.add((from: i, to: to));
      i = to;
      continue;
    }
    // ★★ 2026-10-20（T-C 实测 F13）：**行内代码** `` `…` `` 同样不碰。
    //   实测：`test_data\homework20261014\` 这段路径里的 `\` 被当成 LaTeX 命令
    //   ⇒ 包成 `$…$` ⇒ KaTeX 报 `\h` 不认识 ⇒ 页面上红字 `[公式不完整]`。
    //   行内代码里写的是**字面量**（路径 / 命令名 / 文件名），绝不该变成公式。
    if (source.startsWith('`', i)) {
      final int nl = source.indexOf('\n', i + 1);
      final int end = source.indexOf('`', i + 1);
      final bool sameLine = end >= 0 && (nl < 0 || end < nl);
      final int to = sameLine ? end + 1 : i + 1; // 同行的下一个反引号才算一对
      if (sameLine) {
        locked.add((from: i, to: to));
      }
      i = to;
      continue;
    }
    if (source.startsWith(r'$', i)) {
      final int end = source.indexOf(r'$', i + 1);
      final int to = end < 0 ? source.length : end + 1;
      locked.add((from: i, to: to));
      i = to;
      continue;
    }
    i++;
  }
  bool inLocked(int pos) =>
      locked.any((({int from, int to}) r) => pos >= r.from && pos < r.to);

  // ② 按"数学字符"贪心成段，再逐段判定
  var p = 0;
  while (p < source.length) {
    if (inLocked(p) || !_isMathChar(source.codeUnitAt(p))) {
      p++;
      continue;
    }
    var q = p;
    while (q < source.length &&
        !inLocked(q) &&
        _isMathChar(source.codeUnitAt(q))) {
      q++;
    }
    // 去掉首尾的空格/标点
    var a = p;
    var b = q;
    while (a < b && ' .,;:!?'.contains(String.fromCharCode(source.codeUnitAt(a)))) {
      a++;
    }
    while (b > a && ' .,;:!?'.contains(String.fromCharCode(source.codeUnitAt(b - 1)))) {
      b--;
    }
    if (b > a) {
      final int lineStart =
          a == 0 ? 0 : source.lastIndexOf('\n', a - 1) + 1;
      // ★ 行首的列表标记（`1. ` / `- ` / `· `）与**引用标记（`>`）**不参与包裹：
      //   整段跳过标记再判。★ 2026-10-20（T-C F13）：引用标记原先没跳 ⇒ `>` 被包成 `$>$`。
      if (a == lineStart) {
        final Match? mk = RegExp(r'^\s*(\d+[.)]|[-*·]|>+)\s*')
            .firstMatch(source.substring(a, b));
        if (mk != null && a + mk.end < b) a += mk.end;
        // 跳掉标记之后如果什么都不剩（整行就是 `>`）⇒ 这一行没有数学
        if (a >= b) {
          p = q;
          continue;
        }
      }
      final String seg = source.substring(a, b);
      final bool url = seg.contains('://') || seg.startsWith('www.');
      if (!url &&
          _hasMathEvidence(seg) &&
          _hasMathSubstance(seg) &&
          !_hasDanglingOperator(seg) &&
          !_looksLikePlainEnglish(seg)) {
        runs.add(WrapRun(a, b));
      }
    }
    p = q;
  }

  // ③ 相邻/重叠的合并（`a_n = (-1)^n` 里的空格会把它们分开，但两段都该包）
  runs.sort((WrapRun x, WrapRun y) => x.start.compareTo(y.start));
  final List<WrapRun> merged = <WrapRun>[];
  for (final WrapRun r in runs) {
    if (merged.isNotEmpty && r.start <= merged.last.end) {
      final WrapRun last = merged.removeLast();
      merged.add(WrapRun(last.start, r.end > last.end ? r.end : last.end));
    } else {
      merged.add(r);
    }
  }

  // ④ ★★ 行间块升级（B'）：**整行只有这一个式子**且含"显示倾向"的证据 ⇒ `$$…$$`
  final List<WrapRun> settled = <WrapRun>[];
  for (final WrapRun r in merged) {
    final int lineStart =
        r.start == 0 ? 0 : source.lastIndexOf('\n', r.start - 1) + 1;
    int lineEnd = source.indexOf('\n', r.end);
    if (lineEnd < 0) lineEnd = source.length;
    final bool wholeLine = source.substring(lineStart, r.start).trim().isEmpty &&
        source.substring(r.end, lineEnd).trim().isEmpty;
    settled.add(WrapRun(
      r.start,
      r.end,
      display: wholeLine && _wantsDisplayBlock(source.substring(r.start, r.end)),
    ));
  }
  return SmartWrapPlan(List<WrapRun>.unmodifiable(settled));
}

/// 这些命令/符号一出现，就说明"这一行是**推导**，不是行内的小记号" ⇒ 该用行间块。
///
/// ★ 判据只在"整行只有一个式子"时才被问到（[planSmartWrap] 第 ④ 步），
///   所以不需要更聪明的启发：行内夹在文字里的 `a_n` 永远是行内。
const Set<String> _kDisplayCommands = <String>{
  'sum', 'prod', 'coprod', 'int', 'iint', 'iiint', 'oint',
  'bigcup', 'bigcap', 'biguplus', 'bigvee', 'bigwedge', 'bigotimes', 'bigoplus',
  'frac', 'dfrac', 'lim', 'limsup', 'liminf', 'left',
};

bool _wantsDisplayBlock(String seg) {
  for (final Match m in RegExp(r'\\([A-Za-z]+)').allMatches(seg)) {
    if (_kDisplayCommands.contains(m.group(1))) return true;
  }
  for (final String op in <String>['=', '<', '>', '≤', '≥', '≈', '→', '⇒']) {
    if (seg.contains(op)) return true;
  }
  return false;
}
