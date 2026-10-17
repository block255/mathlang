// 数语引擎 · 可见原子扫描器
//
// ★ 这是**源偏移的唯一正确来源**。引擎的 `range` / `caretPositions` 是**渲染空间**坐标
//   （只覆盖渲染出来的原子，不含 `\frac{}` / `^` / `_` 等命令与结构字符），
//   实测 `\frac{a}{b}=\sqrt{2}` 给出 `[2,3) [4,5) [6,7) [8,9)`，**根本不是源码下标**。
//   详见 notes/design/技术选型与风险.md 9.8。
//
// 它同时给出**原子边界** → 直接支撑 S3 的「按结构删除」（smart delete）与行内选区。
// **纯 Dart，不依赖 Flutter。**

import 'slot_pad.dart';

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
///
/// ⚠️ **漏一个的后果不是"少一个原子"而是"多一个幻影原子"**（2026-10-15 晚探针量出）：
/// `\widehat` / `\widetilde` / `\overbrace` / `\underbrace` 原先**不在这张表里**
/// ⇒ 它们各自被当成 1 个可见原子，而引擎**一个字形都不画**（装饰是矢量图/横线）
/// ⇒ "叶盒数 ≠ 原子数" ⇒ `hitTestMathTex` **静默返回 null**
/// ⇒ **这些结构里点击也一直没反应**（与 accent 装饰盒是同一个 bug 家族，见 §11.21.2）。
/// 实测：`\widehat{AB}` 2 盒 vs **3** 原子、`\overbrace{AB}` 2 盒 vs **3** 原子 ✓（修好后 2 = 2）。
const Set<String> kStructureCommands = <String>{
  'frac', 'dfrac', 'tfrac', 'cfrac', 'sqrt', 'left', 'right', 'begin', 'end', 'binom',
  'overset', 'stackrel',
  'overline', 'underline', 'vec', 'hat', 'bar', 'tilde', 'dot', 'ddot',
  'widehat', 'widetilde', 'overbrace', 'underbrace',
  'overbracket', 'underbracket',
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
    final int close = matchBrace(tex, k);
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
///
/// （公开：`smart_delete.dart` 的"删整个花括号组"也要用它，避免两处各写一份配对逻辑。）
int matchBrace(String tex, int open) {
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

/// 这些命令有**若干参数不参与渲染**（颜色名、尺寸、间距），词法必须**整段跳过**。
///
/// ★★ 为什么这条很关键（2026-10-14 实测发现，属**现存 bug**）：
///   点击定位靠"**引擎叶盒 ↔ 我们的可见原子**"一一对应（`hit_test` + `leaf_boxes`），
///   数量不等时 `hitTestMathTex` 会**静默返回 null**（点公式没反应、也不报错 —— S1 上过这个当）。
///   而给光标注入的 `\textcolor{#1E88E5}{\cursor{}}` 里，颜色名会被当成 **9 个可见原子**，
///   引擎却一个字形都不画 → 数量天然不等 → **含光标那个单元里点公式会失效**。
///   这条修法也是 S3-5「空槽占位」能接进渲染的前置条件。
///
/// 值 = 要跳过的**参数组个数**（`\textcolor{颜色}{内容}` 只跳第一个，内容照常递归）。
const Map<String, int> kNonRenderedArgCount = <String, int>{
  'textcolor': 1, // \textcolor{颜色}{内容}
  'color': 1, // \color{颜色}
  'rule': 2, // \rule{宽}{高}
  'hspace': 1, 'kern': 1, 'mspace': 1, 'vspace': 1, 'hskip': 1, 'vskip': 1,
  'phantom': 1, 'hphantom': 1, 'vphantom': 1, // 占位但不画
  // ★★ 环境名（2026-10-17 探针量出）：`\begin{cases}` / `\end{cases}` 的 `{cases}`
  //   **不是墨迹** —— 它只是环境的**名字**。原先把这 5 个字母当可见原子 ⇒
  //   `\begin{cases}a&b\\c&d\end{cases}` 实测 **8 叶盒 vs 14 原子**（多出 10 个幻影原子）
  //   ⇒ `hitTestMathTex` 静默不可靠 ⇒ 分段函数的公式里点击全废。
  //   与 `\widehat` 那一族（见 [kStructureCommands] 的注释）是同一个 bug 家族。
  'begin': 1, 'end': 1,
};

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
    // ★★ 空槽占位垫的**宽度垫**（`slot_pad.kSlotPadFiller`）：词法上 0 原子，
    //   而引擎照样给它一个叶盒（零高 `_RenderColoredBox`，实测 4.8 × 0）⇒
    //   不在这里补 **1 个合成原子**，就会"叶盒数 ≠ 原子数" ⇒
    //   `hitTestMathTex` **静默返回 null**（公式内点击全废）—— 与 §11.18 尾垫同一个坑。
    //   ★ 必须**在走查顺序里**产出（= 渲染顺序）：`\sqrt[n]{…}` 的次数渲染在后、
    //     算子的上下限折进算子 —— 若改成"按源码偏移排序"补账，这些结构里会整体错位（§11.26 三）。
    if (tex.startsWith(kSlotPadFiller, i)) {
      out.add(VisibleAtom(i, i + kSlotPadFiller.length, 'slotpad'));
      i += kSlotPadFiller.length;
      continue;
    }
    // ★★ **结构尾垫**（`slot_pad.kStructTailTex`）：同样是"0 原子 / 1 叶盒"的注入物。
    //   原先它由 `injection_map.atomsForHitTest` 事后补出来、再**按源偏移排序**插进去 ——
    //   2026-10-17 探针量出那样做是**错的**：排序会毁掉本函数刻意维持的"渲染顺序"
    //   （`\sqrt[n]{…}` 的次数在源码里在前、渲染在后 ⇒ 排完序次数跑到被开方数前面 ⇒ 点 A 落 B）。
    //   ⇒ 改成**在走查顺序里**就地认出它，与上面的占位垫同一机制。
    if (tex.startsWith(kStructTailTex, i)) {
      out.add(VisibleAtom(i, i + kStructTailTex.length, 'tail'));
      i += kStructTailTex.length;
      continue;
    }
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

        // ★ 参数不参与渲染的命令：整段跳过那些参数（否则颜色名/尺寸会被当成可见原子）
        final int? skipArgs = kNonRenderedArgCount[name];
        if (skipArgs != null) {
          var k = j;
          for (var n = 0; n < skipArgs; n++) {
            while (k < tex.length && tex[k] == ' ') {
              k++;
            }
            if (k < tex.length && tex[k] == '{') {
              final int close = matchBrace(tex, k);
              k = close < 0 ? tex.length : close + 1;
            } else if (k < tex.length) {
              // 裸参数写法（`\kern 2pt`、`\hspace -1em`）：跳过"数字 + 单位"这一小段记号
              while (k < tex.length &&
                  (tex[k].codeUnitAt(0) == 0x2D || // -
                      tex[k].codeUnitAt(0) == 0x2B || // +
                      tex[k].codeUnitAt(0) == 0x2E || // .
                      (tex.codeUnitAt(k) >= 0x30 && tex.codeUnitAt(k) <= 0x39))) {
                k++;
              }
              while (k < tex.length && _isLetter(tex.codeUnitAt(k))) {
                k++;
              }
            }
          }
          i = k;
          continue;
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
