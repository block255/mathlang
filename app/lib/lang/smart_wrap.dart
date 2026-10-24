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

import 'math_spans.dart';

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
///
/// ★ 2026-10-23（批 1 · G2）：本函数被 [_blockedByDangling] 取代 ——
///   它还要区分"**整行**以 `=` 开头的续行"（`= 1`），那种必须包。留着只为记录旧口径。

/// 强证据：段里有 `\命令` / 上下标 ⇒ **一定是数学**，哪怕首尾挂着运算符。
///
/// ★★ 2026-10-20（T-D 实测，用户粘贴 AI 答案时看到"编码露出来"）：多行推导的**续行**
/// 就是 `=\lim_{x\to 0}\frac{…}{…}` 这种，整行以 `=` 开头。若"首尾挂运算符一律不包"，
/// 那种续行就原样露出 LaTeX（实测三行 `=\lim…` 一个都没包）。
/// ⇒ 让强证据优先：段里有 `\` / `^` / `_` 时，首尾的 `=` 就是"接着上一行写"，照旧包。
bool _hasStrongMathEvidence(String s) =>
    s.contains(r'\') || s.contains('_') || s.contains('^');

/// 纯英文（含空格的单词序列，如 "Cauchy Criterion"）⇒ **不是**数学
bool _looksLikePlainEnglish(String s) {
  final String t = s.trim();
  if (t.isEmpty) return true;
  if (!RegExp(r'^[A-Za-z ]+$').hasMatch(t)) return false;
  // 纯字母+空格：再要求"不是单个字母"（单个 `x` 也可能是数学，但保守起见不包）
  return t.split(RegExp(r'\s+')).where((String w) => w.isNotEmpty).isNotEmpty;
}

/// ★★ 2026-10-23（批 1 · G2）：**以运算符开头**的整行是"续行"，不是"悬空"。
///
/// 实测（DeepSeek 抄写稿）：多行推导的最后一行常常是 `= 1` / `= -1` / `= \frac{2}{3}`。
/// 旧判据"首尾挂运算符就不包"把它们整行漏掉 ⇒ 页面上落成正文文字（用户看到的"行间被识别成行内"）。
///
/// 区分**两条**不同的直觉：
/// * **尾部**挂着 `= < > + - * /` ⇒ 那就是没写完（`a 大于 b >` 里的 `b >`）⇒ 拦住（F13 那条不许退化）；
/// * **头部**挂着运算符、而这一段**就是整行** ⇒ 那是"接着上一行写"的续行 ⇒ 放行。
///   只有"夹在句子中间、左边还有字"的头部运算符仍然算悬空。
bool _blockedByDangling(String seg, {required bool wholeLine}) {
  if (seg.isEmpty) return false;
  if (_hasStrongMathEvidence(seg)) return false;
  const String ops = '=<>+-*/';
  if (ops.contains(seg[seg.length - 1])) return true;
  if (!wholeLine && ops.contains(seg[0])) return true;
  return false;
}

/// ★★ 2026-10-23（批 1 · G1）：`\text{…}` 这类**文本模式命令**的参数组。
///
/// 为什么需要：作业/答案里 `\quad (\text{旁注：当 } x\to+\infty …)` 这种写法极常见。
/// 切段器原来只认"数学字符"（中文**不算**）⇒ 段被从「旁注」处切断 ⇒
/// `\text{` 和它的 `}` 被分到两个包裹里 ⇒ 两段都语法不完整 ⇒ 页面上 `[公式不完整]`。
/// 实测：整份抄写稿 69 段包裹里 **20 段悬空**，全是这一类。
///
/// 判据：命令名后面的参数组**整段**算"段内"（组里允许中文 / 全角标点）。
const Set<String> _kTextCommands = <String>{
  'text', 'textrm', 'textbf', 'textit', 'textsf', 'texttt', 'textnormal', //
  'mbox', 'hbox',
};

List<({int from, int to})> _textGroups(String source) {
  final List<({int from, int to})> out = <({int from, int to})>[];
  var i = 0;
  while (i < source.length) {
    if (source[i] != r'\') {
      i++;
      continue;
    }
    var j = i + 1;
    while (j < source.length && _isLetterCode(source.codeUnitAt(j))) {
      j++;
    }
    final String name = source.substring(i + 1, j);
    if (!_kTextCommands.contains(name)) {
      i = j > i ? j : i + 1;
      continue;
    }
    var k = j;
    while (k < source.length && source[k] == ' ') {
      k++;
    }
    if (k >= source.length || source[k] != '{') {
      i = k > i ? k : i + 1;
      continue;
    }
    var depth = 0;
    var m = k;
    while (m < source.length) {
      final String ch = source[m];
      if (ch == r'\') {
        m += 2; // 跳过转义（`\{` / `\}`）
        continue;
      }
      if (ch == '{') depth++;
      if (ch == '}') {
        depth--;
        if (depth == 0) {
          m++;
          break;
        }
      }
      m++;
    }
    out.add((from: i, to: m.clamp(0, source.length)));
    i = m;
  }
  return out;
}

bool _isLetterCode(int c) =>
    (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

/// [a, b) 这一段是不是"碰着 `$`"（含 `$`、或左/右紧邻 `$`）。
///
/// ★★ 批 17 的出口闸：碰着就**不包**。理由见 `planSmartWrap` ③·补 的注释 ——
///   包裹一旦紧挨已有定界符就会拼出 `$$`，而行内 `$$` 没有任何合法含义。
bool _touchesDollar(String s, int a, int b) =>
    (a > 0 && s[a - 1] == r'$') ||
    (b < s.length && s[b] == r'$') ||
    s.substring(a, b).contains(r'$');

/// **扫描整篇文本**，给出建议包裹的区间
///
/// 会跳过：已有的 `$…$`、`$$…$$` 块、代码块（三反引号围栏）、行内代码、行首列表标记、URL。
SmartWrapPlan planSmartWrap(String source) {
  final List<WrapRun> runs = <WrapRun>[];
  // ① 先标记"不能碰"的区间：已有的**数学段**（由 `math_spans` 权威给出）
  //
  // ★★ 2026-10-23（批 1）：这里原来自己扫 `$` —— 于是"哪里有数学段"这件事**有两份判据**
  //   （`smart_wrap` vs `math_spans`），《编辑地基与手感》§六-1/2 明令禁止。
  //   `scanMathSpans` 还额外处理了 `\$` 转义与 `$$` 优先，比自扫更准。
  final List<({int from, int to})> locked = <({int from, int to})>[
    for (final MathSpan sp in scanMathSpans(source)) (from: sp.start, to: sp.end),
  ];
  bool inLocked(int pos) =>
      locked.any((({int from, int to}) r) => pos >= r.from && pos < r.to);
  // 落单的 `$`（该行 `$` 个数为奇数）⇒ 整行不碰。
  // 定界符配不上时**不猜**（老实现是把落单的 `$` 之后全锁掉；这里收窄成"锁这一行"，
  // 既保留了保守性，又不会让后面整篇都失去包裹机会）。
  var lineOff = 0;
  for (final String line in source.split('\n')) {
    var dollars = 0;
    for (var k = 0; k < line.length; k++) {
      if (line.codeUnitAt(k) == 0x24 && !inLocked(lineOff + k)) dollars++;
    }
    if (dollars.isOdd) {
      locked.add((from: lineOff, to: lineOff + line.length));
    }
    lineOff += line.length + 1;
  }
  // 代码围栏 / 行内代码（这两种是**字面量**，永远不许变成公式）
  var i = 0;
  while (i < source.length) {
    if (inLocked(i)) {
      i++;
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
    i++;
  }

  // ①·补 ★★ 2026-10-23（G1）：`\text{…}` 的参数组**整段算段内**
  //   （组里可以有中文和全角标点 —— 作业里的 `\text{旁注：当 }`）
  final List<({int from, int to})> textGroups = _textGroups(source);
  bool inTextGroup(int pos) =>
      textGroups.any((({int from, int to}) r) => pos >= r.from && pos < r.to);

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
        (inTextGroup(q) || _isMathChar(source.codeUnitAt(q)))) {
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
      // 这一段是不是"整行只有它"（缩进不算、行尾空白不算）
      final int lineFrom = a == 0 ? 0 : source.lastIndexOf('\n', a - 1) + 1;
      var lineTo = source.indexOf('\n', b);
      if (lineTo < 0) lineTo = source.length;
      final bool wholeLine = source.substring(lineFrom, a).trim().isEmpty &&
          source.substring(b, lineTo).trim().isEmpty;
      // ★ 悬空运算符只在"**没有**强证据"时才拦（续行 `=\lim…` 有强证据 ⇒ 照旧包）；
      //   ★★ 2026-10-23（G2）：**整行**以运算符开头是续行（`= 1`），不拦。
      final bool danglingBlocks = _blockedByDangling(seg, wholeLine: wholeLine);
      if (!url &&
          _hasMathEvidence(seg) &&
          _hasMathSubstance(seg) &&
          !danglingBlocks &&
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

  // ③·补 ★★★ 2026-10-24（批 17）：**出口加闸 —— run 一律不许碰 `$`**
  //
  // 实测事故（用户导入 `20261021作业编辑`）：① 那一行的 `span` 表一旦错位，
  // "已有结构、不许碰"的跳过区也跟着错 ⇒ 包裹会在 `$\to$` **外面**再套一对 `$`
  // ⇒ `$$\to$$` ⇒ 整行 LaTeX 裸奔、`{` 被吞的还会报 `[公式不完整]`。
  // 判据（宁可少包一处，也绝不动已有公式）：
  //   · run 里**不含** `$`；
  //   · run 的两端**都不与 `$` 相邻**（相邻就会拼出 `$$`）。
  final List<WrapRun> safe = <WrapRun>[
    for (final WrapRun r in merged)
      if (!_touchesDollar(source, r.start, r.end)) r,
  ];

  // ④ ★★ 行间块升级（B'）：**整行只有这一个式子**且含"显示倾向"的证据 ⇒ `$$…$$`
  final List<WrapRun> settled = <WrapRun>[];
  for (final WrapRun r in safe) {
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
