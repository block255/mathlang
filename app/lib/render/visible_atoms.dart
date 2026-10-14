// 数语引擎 · 可见原子扫描器
//
// ★ 这是**源偏移的唯一正确来源**。引擎的 `range` / `caretPositions` 是**渲染空间**坐标
//   （只覆盖渲染出来的原子，不含 `\frac{}` / `^` / `_` 等命令与结构字符），
//   实测 `\frac{a}{b}=\sqrt{2}` 给出 `[2,3) [4,5) [6,7) [8,9)`，**根本不是源码下标**。
//   详见 notes/design/技术选型与风险.md 9.8。
//
// 它同时给出**原子边界** → 直接支撑 S3 的「按结构删除」（smart delete）与行内选区。
// **纯 Dart，不依赖 Flutter。**

/// 一个「可见原子」：渲染出来、用户看得见的一个最小单位。
class VisibleAtom {
  const VisibleAtom(this.start, this.end, this.kind);

  /// 相对该段 tex 的源区间 `[start, end)`
  final int start;
  final int end;

  /// 原子种类：符号命令 `\alpha` / 单字符 `a` / 转义 `esc`
  final String kind;

  int get length => end - start;

  @override
  String toString() => '$kind[$start,$end)';
}

/// **结构命令**：它们**本身不是可见原子**（不渲染成字符），可见内容由它们的参数贡献。
/// 其余命令（`\alpha` `\le` `\sum` …）各自算**一个**可见原子。
const Set<String> kStructureCommands = <String>{
  'frac', 'dfrac', 'tfrac', 'sqrt', 'left', 'right', 'begin', 'end', 'binom',
  'overline', 'underline', 'vec', 'hat', 'bar', 'tilde', 'dot', 'ddot',
  'overrightarrow', 'xrightarrow', 'operatorname', 'mathrm', 'mathbf', 'mathbb',
  'mathcal', 'mathfrak', 'mathit', 'text', 'displaystyle', 'textstyle',
  'quad', 'qquad', 'limits', 'nolimits', 'not', 'color', 'phantom', 'enclose',
  'rule', 'kern', 'hspace', 'middle', 'big', 'Big', 'bigg', 'Bigg',
};

/// 把子串的词法结果整体平移（递归词法用）
List<VisibleAtom> _shift(List<VisibleAtom> a, int d) => <VisibleAtom>[
      for (final VisibleAtom x in a) VisibleAtom(x.start + d, x.end + d, x.kind),
    ];

/// 读「一个组 `{...}` 或单个原子」，返回 (内容起, 内容止, 下一个待扫位置)
({int from, int to, int next}) _readGroupOrAtom(String tex, int at) {
  var k = at;
  while (k < tex.length && tex[k] == ' ') {
    k++;
  }
  if (k >= tex.length) return (from: k, to: k, next: k);
  if (tex[k] == '{') {
    final int close = _matchBrace(tex, k);
    return close > 0
        ? (from: k + 1, to: close, next: close + 1)
        : (from: k + 1, to: tex.length, next: tex.length);
  }
  if (tex[k] == r'\') {
    var j = k + 1;
    while (j < tex.length && _isLetter(tex.codeUnitAt(j))) {
      j++;
    }
    return (from: k, to: j, next: j);
  }
  return (from: k, to: k + 1, next: k + 1);
}

/// 返回与 `tex[open]`（必须是 `{`）配对的 `}` 的下标；找不到返回 -1
int _matchBrace(String tex, int open) {
  var depth = 0;
  for (var i = open; i < tex.length; i++) {
    if (tex[i] == '{') {
      depth++;
    } else if (tex[i] == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

/// 把 tex 扫描成「可见原子」列表（每个原子的 `[start,end)` 是相对该段 tex 的源区间）。
///
/// ★ **顺序 = 渲染顺序（= 叶盒顺序）**，不是源码顺序！
/// 对绝大多数构造两者相同，但 `\sqrt[n]{body}` 例外：KaTeX 的 sqrt 节点是 `[body, index]`，
/// 而源码里次数写在前面。实测若按源码顺序产出原子，**叶盒序与原子序会整体错位**，
/// 点击次数会指到被开方数（S3-2 实测）。所以这里对 `\sqrt` 按渲染顺序递归产出。
///
/// 规则（覆盖我们方言的子集）：
///   · 结构命令 → **跳过**，由参数贡献原子
///   · 符号命令（`\alpha` `\le` `\sum` …）→ **一个**可见原子
///   · 换行 `\\` / `{` `}` `^` `_` `&` / 空格 / 换行符 → 跳过
///   · `\sqrt[n]{body}` 的 `[` `]` 是**语法**（不是可见原子）
///   · 其余每个字符（字母 / 数字 / 运算符）各自是一个可见原子
List<VisibleAtom> lexVisibleAtoms(String tex) {
  final out = <VisibleAtom>[];
  var i = 0;
  while (i < tex.length) {
    if (tex.startsWith(r'\\', i)) {
      i += 2; // 行分隔，不是可见原子
      continue;
    }
    final c = tex[i];
    if (c == r'\') {
      if (i + 1 < tex.length && _isLetter(tex.codeUnitAt(i + 1))) {
        var j = i + 1;
        while (j < tex.length && _isLetter(tex.codeUnitAt(j))) {
          j++;
        }
        final name = tex.substring(i + 1, j);

        // ★ `\sqrt[n]{body}`：按**渲染顺序**（body 在前、次数在后）递归产出
        if (name == 'sqrt') {
          var k = j;
          while (k < tex.length && tex[k] == ' ') {
            k++;
          }
          if (k < tex.length && tex[k] == '[') {
            final int close = tex.indexOf(']', k + 1);
            if (close > 0) {
              final ({int from, int to, int next}) body =
                  _readGroupOrAtom(tex, close + 1);
              out.addAll(_shift(
                lexVisibleAtoms(tex.substring(body.from, body.to)),
                body.from,
              ));
              out.addAll(_shift(
                lexVisibleAtoms(tex.substring(k + 1, close)),
                k + 1,
              ));
              i = body.next;
              continue;
            }
          }
        }

        if (!kStructureCommands.contains(name)) {
          out.add(VisibleAtom(i, j, '\\$name'));
        }
        i = j;
        continue;
      }
      if (i + 1 < tex.length) {
        out.add(VisibleAtom(i, i + 2, 'esc'));
        i += 2;
        continue;
      }
      i++;
      continue;
    }
    if (c == '{' || c == '}' || c == '^' || c == '_' || c == '&' || c == ' ' || c == '\n') {
      i++;
      continue;
    }
    out.add(VisibleAtom(i, i + 1, c));
    i++;
  }
  return out;
}

bool _isLetter(int c) =>
    (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
