// 数语引擎 · 算子作用域表（§4.7，2026-10-15）
//
// 规格：notes/design/位点与结构导航.md **§4.7 作用域表**。
// 目标：回答「**一个操作对象到哪结束**」——
//   `\sin` / `\log` / `\sum` / `\int` / `\lim` 这类算子**"接上值"才形成整体**，
//   而那个值在 LaTeX 语法里**不属于它**（`\sum_{i=1}^{n} a_i` 的 `a_i` 只是**主行上的下一个东西**）
//   ⇒ 必须按**数学的结合力**另行界定。
//
// 判据（§4.7.1，两条来源 + 一条修正）：
//   ① **数学的优先级 / 结合力**：函数应用比加减紧；**并置乘法是一个"项"**；写出来的运算记号 = 主运算 = 断点
//   ② **KaTeX 的原子类别**（Ord / Op / Bin / Rel / Open / Close / Punct / Inner）
//   ③ `\frac` / `\sqrt` / `\binom` / 括号 / `\text{}` 的参数是**显式**的 ⇒ 本文件**不管**它们
//
// 规则（照 §4.7.1 实现）：
//   【起点】先吃掉**紧跟算子名的 `^` / `_`**（含参数）= 算子自己的上标 / 上下限 / 底数
//          —— 这才是 `\sin^2 x`（=(sin x)²）与 `\sin x^2`（=sin(x²)）的分水岭
//   【扫描】沿**同一个区域**向右取最长一段（花括号 / `\left…\right` / 环境格 = 层级边界，**不跨**）
//           · 可见的**二元运算记号** / **关系记号** / **分隔记号** ⇒ **停**
//           · **另一个算子名**：参数还没开始 ⇒ 它是参数（嵌套 `\sin\log x`）；
//             参数已开始 ⇒ **停**（`\sin x\cos y` = sin x · cos y）
//           · 并置的原子 / 上下标 / 包裹结构 / `\text{}` / 间距命令 ⇒ **黏结**
//
// ★ 本文件**只读**：不改源码、不参与渲染；纯函数、可单测（§4.7.3 的 P1–P6）。
// ★ 实现在**解析器导出的内容项表**（`caret_sites.dart` 的 [TexItem] / [TexRegion]）之上，
//   **不另写一套词法** —— 与位点表、删除对象模型共用同一份判据。
//
// **纯 Dart，不依赖 Flutter。**

import 'caret_sites.dart';

/// 一个算子的**作用域**（它自己 + 紧跟的上下限 + 被它作用的内容）。
class OpScope {
  const OpScope({
    required this.command,
    required this.opStart,
    required this.limitsEnd,
    required this.argEnd,
    required this.hasArg,
  });

  /// 算子命令名（`sin` / `log` / `sum` / `int` …）
  final String command;

  /// 算子名的起点（`\` 的位置）
  final int opStart;

  /// **紧跟的 `^` / `_`（含参数）吃完之后**的位置 = 参数起点
  final int limitsEnd;

  /// 参数终点（**不含**）；`hasArg == false` 时等于 [limitsEnd]
  final int argEnd;

  /// 有没有接上值（`\sin` 后面什么都没有 ⇒ false；**静默**，只在提交点进问题清单）
  final bool hasArg;

  /// 整个操作对象的区间（含算子名、上下限、内容）
  int get start => opStart;
  int get end => argEnd;

  @override
  String toString() => 'Op\\$command[$opStart,$argEnd)'
      '${hasArg ? "" : " 无值"}（上下限到 $limitsEnd）';
}

/// 会不会"接值才成整体"的算子（§4.7.1 前提）
const Set<String> kOperatorCommands = <String>{
  // 三角 / 反三角 / 双曲
  'sin', 'cos', 'tan', 'cot', 'sec', 'csc',
  'arcsin', 'arccos', 'arctan', 'arccot',
  'sinh', 'cosh', 'tanh', 'coth',
  // 指数 / 对数
  'exp', 'log', 'ln', 'lg',
  // 极限 / 极值 / 其它算子名
  'lim', 'limsup', 'liminf', 'max', 'min', 'sup', 'inf', 'arg', 'argmax', 'argmin',
  'deg', 'det', 'gcd', 'lcm', 'dim', 'ker', 'hom', 'coker', 'Pr', 'mod', 'bmod',
  // 大算符（上下限 + 被作用内容）
  'sum', 'prod', 'coprod', 'int', 'oint', 'iint', 'iiint', 'iiiint', 'idotsint',
  'bigcup', 'bigcap', 'bigvee', 'bigwedge', 'bigoplus', 'bigotimes', 'bigodot',
  'bigsqcup', 'biguplus',
};

/// 原子类别（只用到会"打断作用域"的三类；其余一律按"黏结"处理）
enum _K { ord, op, bin, rel, punct }

/// 可见的**二元运算记号**（§4.7.1 第 1 行）—— 手写出来的就是**主运算**
const Set<String> _kBin = <String>{
  '+', '-', '/', '*', r'\pm', r'\mp', r'\cdot', r'\times', r'\div', r'\ast',
  r'\star', r'\circ', r'\bullet', r'\cup', r'\cap', r'\setminus', r'\smallsetminus',
  r'\wedge', r'\vee', r'\oplus', r'\otimes', r'\odot', r'\dagger', r'\ddagger',
  r'\amalg', r'\wr', r'\triangleleft', r'\triangleright', r'\bigtriangleup',
  r'\bigtriangledown', r'\sqcup', r'\sqcap', r'\uplus', r'\diamond',
};

/// **关系记号** —— 比一切算术都松
const Set<String> _kRel = <String>{
  '=', '<', '>', r'\le', r'\leq', r'\ge', r'\geq', r'\ne', r'\neq', r'\approx',
  r'\equiv', r'\sim', r'\simeq', r'\cong', r'\to', r'\rightarrow', r'\leftarrow',
  r'\Rightarrow', r'\Leftrightarrow', r'\mapsto', r'\in', r'\notin', r'\ni',
  r'\subset', r'\subseteq', r'\supset', r'\supseteq', r'\perp', r'\parallel',
  r'\propto', r'\ll', r'\gg', r'\prec', r'\succ', r'\asymp', r'\doteq',
  r'\models', r'\vdash', r'\dashv', r'\mid', r'\nmid',
};

/// **分隔记号** —— 划界
const Set<String> _kPunct = <String>{',', ';', r'\colon', '&', r'\\', r'\end'};

/// 一个算子的作用域记录 + "吃完之后的下标"（供外层算子复用）
class _Arg {
  const _Arg(this.end, this.next);
  final int end;
  final int next;
}

/// 建**算子作用域表**（纯函数；同一 tex 永远给同一张表）。
List<OpScope> operatorScopes(String tex) {
  final CaretSiteTable t = buildCaretSites(tex);
  if (t.degraded) return const <OpScope>[];
  final List<OpScope> out = <OpScope>[];
  for (final TexRegion reg in t.regions) {
    out.addAll(_scopesInRegion(tex, reg));
  }
  out.sort((OpScope a, OpScope b) => a.opStart.compareTo(b.opStart));
  return out;
}

/// 某个 tex 偏移处、**恰好结束**的那个作用域（`null` = 没有）。
///
/// ★ 删除侧要用它：光标停在"操作对象的右端"时，删的应当是**整个操作对象**
///   （§4.0 通则的"算子 + 作用域"那一格）。
OpScope? scopeEndingAt(String tex, int rel) {
  OpScope? best;
  for (final OpScope s in operatorScopes(tex)) {
    if (!s.hasArg || s.end != rel) continue;
    if (best == null || s.start < best.start) best = s; // 取**最外层**（最长）那个
  }
  return best;
}

/// 某个 tex 偏移处、**恰好开始**的那个作用域（`null` = 没有）—— `Delete` 方向用。
OpScope? scopeStartingAt(String tex, int rel) {
  OpScope? best;
  for (final OpScope s in operatorScopes(tex)) {
    if (s.start != rel) continue;
    if (best == null || s.end > best.end) best = s; // 取**最外层**（最长）那个
  }
  return best;
}

// ---------------------------------------------------------------- 内部

List<OpScope> _scopesInRegion(String tex, TexRegion reg) {
  final List<TexItem> items = reg.items;
  final Map<int, _Arg> memo = <int, _Arg>{}; // 算子下标 → 它的作用域（右往左算）
  final List<OpScope> out = <OpScope>[];

  for (var i = items.length - 1; i >= 0; i--) {
    final TexItem it = items[i];
    final String? cmd = it.command;
    if (cmd == null || !kOperatorCommands.contains(cmd)) continue;

    // ① 先吃**紧跟算子名**的 `^` / `_`（含参数）＝ 算子自己的上下限 / 底数
    var j = i + 1;
    var limitsEnd = it.end;
    while (j < items.length &&
        _isScript(items[j]) &&
        items[j].start == limitsEnd) {
      limitsEnd = items[j].end;
      j++;
    }

    // ② 再吃**一个紧整体**当参数（断点规则见文件头）
    final _Arg a = _consumeTight(tex, items, j, memo);
    final bool hasArg = a.next > j;
    memo[i] = _Arg(hasArg ? a.end : limitsEnd, a.next);
    out.add(OpScope(
      command: cmd,
      opStart: it.start,
      limitsEnd: limitsEnd,
      argEnd: hasArg ? a.end : limitsEnd,
      hasArg: hasArg,
    ));
  }
  return out;
}

/// 从 [j] 起吃掉**一个紧整体**（并置乘法链），返回终点与"吃完之后的下标"。
_Arg _consumeTight(
  String tex,
  List<TexItem> items,
  int j,
  Map<int, _Arg> memo,
) {
  if (j >= items.length) return _Arg(j > 0 ? items[j - 1].end : 0, j);
  var end = items[j].start;
  var next = j;
  var started = false;

  while (next < items.length) {
    final TexItem nx = items[next];
    final _K kind = _atomKind(tex, nx);

    // 断点：主运算 / 关系 / 分隔 ⇒ 作用域到此为止
    if (kind == _K.bin || kind == _K.rel || kind == _K.punct) break;

    if (kind == _K.op) {
      // 并置的两个"算子型整体" = **相乘**，不是嵌套（`\sin x\cos y`）⇒ 停
      if (started) break;
      final _Arg? inner = memo[next];
      if (inner == null) break; // 理论上不会发生（右往左已经算过）
      end = inner.end;
      next = inner.next;
      started = true;
      continue;
    }

    // ★ **显式括号**（`(` `[` `\{` `\left(`）连同它的**配对收尾**算**一个整体**
    //   （KaTeX 的 Open/Close 原子；不这么做 `\sin(x+y)` 会在 `+` 处断掉 → 参数只剩 `(x`）
    final int? close = _closingIndex(tex, items, next);
    if (close != null) {
      end = items[close].end;
      next = _afterScripts(items, close);
      started = true;
      continue;
    }

    // 原子 / 包裹结构 / 透明包装：连它自己的脚本一起算一个整体 ⇒ 黏结
    end = _spanEndWithScripts(items, next);
    next = _afterScripts(items, next);
    started = true;
  }
  return _Arg(end, next);
}

/// 括号配对表（按**渲染出来的文本**判；`\left…\right` 另判）
const Map<String, String> _kDelimPair = <String, String>{
  '(': ')',
  '[': ']',
  r'\{': r'\}',
};

/// `items[j]` 是一个**开括号**时，返回它**配对收尾**的下标（同一个区域里按层数配对）；
/// 不是开括号 / 没有配对（打字中间态）⇒ `null`（那就当普通项处理，不报错）。
int? _closingIndex(String tex, List<TexItem> items, int j) {
  final String open = tex.substring(items[j].start, items[j].end);
  final String? close =
      _kDelimPair[open] ?? (open.startsWith(r'\left') ? r'\right' : null);
  if (close == null) return null;
  final bool delimCmd = close.startsWith('\\');
  var depth = 0;
  for (var k = j; k < items.length; k++) {
    final String t = tex.substring(items[k].start, items[k].end);
    final bool isOpen = t == open || (delimCmd && t.startsWith(r'\left'));
    final bool isClose = delimCmd ? t.startsWith(close) : t == close;
    if (isOpen) {
      depth++;
      continue;
    }
    if (isClose) {
      depth--;
      if (depth == 0) return k;
    }
  }
  return null;
}

bool _isScript(TexItem it) => it.command == '^' || it.command == '_';

/// 原子类别：**算子名**由命令表判；二元 / 关系 / 分隔由**渲染出来的文本**判（含 `/` 这种 Ord 类但看得见运算记号的）。
_K _atomKind(String tex, TexItem it) {
  final String? cmd = it.command;
  if (cmd != null && kOperatorCommands.contains(cmd)) return _K.op;
  final String text = tex.substring(it.start, it.end);
  if (cmd != null) {
    final String at = '\\$cmd';
    if (_kBin.contains(at)) return _K.bin;
    if (_kRel.contains(at)) return _K.rel;
    if (_kPunct.contains(at)) return _K.punct;
    return _K.ord; // 含 `\frac` / `\sqrt` / `\overline` / `\text`…：包裹型或透明包装，一律黏结
  }
  if (text.length == 1 || text.startsWith('\\')) {
    if (_kBin.contains(text)) return _K.bin;
    if (_kRel.contains(text)) return _K.rel;
    if (_kPunct.contains(text)) return _K.punct;
  }
  return _K.ord;
}

/// 某一项**连它紧跟的脚本**一起的终点（`x^2` 在 TeX 里就是一个原子）
int _spanEndWithScripts(List<TexItem> items, int idx) {
  var end = items[idx].end;
  for (var k = idx + 1; k < items.length; k++) {
    final TexItem nx = items[k];
    if (nx.start != end || !_isScript(nx)) break;
    end = nx.end;
  }
  return end;
}

/// 跳过某一项**紧跟的脚本**之后的下标
int _afterScripts(List<TexItem> items, int idx) {
  var k = idx + 1;
  var end = items[idx].end;
  while (k < items.length && items[k].start == end && _isScript(items[k])) {
    end = items[k].end;
    k++;
  }
  return k;
}
