// 数语引擎 · **断点字符（汉字 / 全角标点）落进数学段时怎么办**（批 18，2026-10-24 用户拍板）
//
// 一句话：**平权**（《整体设计》§三 第 0 条 · 推论 ④「围栏不是对象边界」）要求
// `$…$` 只做**排版上下文 + 存储记账**，**不许参与"一个字符归谁"**。
// 所以汉字/全角标点在任何围栏里都该落**文字层** —— 但落的方式要分**层**（用户 2026-10-24 定的四条口径）：
//
// | 光标在哪 | 行为 | 依据 |
// |---|---|---|
// | 行内公式**顶层**（一串平铺原子之间） | **拆段**：`$左$` + 文字 + `$右$` | 平权 ④：文字不该被围栏包住 |
// | 行内公式**结构槽里**（分子 / 指数 / `\text{}` 参数 …） | **不拆**，接受数学字体 | 用户："这种就接受变数学字体" |
// | **行间块** `$$…$$` 里 | **不拆**，接受数学字体 | 同上 |
// | **边界格**（内容首 / 内容末） | 不拆：某边为空就不补围栏，字直接落围栏外 | 见下 |
//
// 三条硬约束（都与已有口径一脉相承）：
//   ① **绝不造空段**：拆完的两半只要有空的，就不给它补围栏（空行内公式 = `$$`，
//      而"行内 `$$`"是批 17 刚清掉的那一类毛病 —— 见 `math_spans.inlineDoubleDollarLines`）；
//   ② **切前自检**：两半要各自"自洽"（花括号配平 / `\left`配 `\right` / `\begin`配`\end`；
//      右半不许以 `^` `_` `&` `}` `]` 开头）—— 不自洽就不切（接受数学字体，宁可不切也不弄坏 tex）；
//   ③ **混合载荷不切**：载荷必须**全部**是断点字符。实测：在数学段里粘贴时
//      `decidePaste` 一律判 `mathTex`（直接插 tex、根本不进这条通道）；打字时 IME 一次提交
//      整段中文、ascii 一个字符一次 ⇒ 混合载荷实际不会出现，规则取简更安全。
//
// **纯 Dart，不依赖 Flutter。**

import '../render/caret_sites.dart';
import '../render/math_nav.dart';
import '../render/site_adjacency.dart';

/// 中文标点里**不在** `0x3000–0x303F / 0xFF00–0xFFEF` 两大区段的那几个（破折号、省略号、引号、间隔号）。
const Set<String> _kExtraBreakPunctuation = <String>{
  '—', '–', '…', '·', '“', '”', '‘', '’', '〈', '〉', '～',
};

/// 这个字符是不是**断点字符**（= 进来只能当"文字"看的东西）。
///
/// 判据是**字符区段**，不是"看起来像中文"：
/// · `0x4E00–0x9FFF` 汉字基本区 · `0x3400–0x4DBF` 扩展 A · `0xF900–0xFAFF` 兼容汉字
/// · `0x3000–0x303F` CJK 符号与标点（`、。「」【】《》` …）
/// · `0xFF00–0xFFEF` 全角区（`，；：！？（）` 与全角字母）
/// · 外加 [_kExtraBreakPunctuation] 那几个
///
/// ★ 半角空格、半角标点、英文、数字**都不算**（它们留在数学层是合理的）。
bool isBreakChar(String ch) {
  if (ch.isEmpty) return false;
  final int c = ch.codeUnitAt(0);
  if (c >= 0x4E00 && c <= 0x9FFF) return true;
  if (c >= 0x3400 && c <= 0x4DBF) return true;
  if (c >= 0xF900 && c <= 0xFAFF) return true;
  if (c >= 0x3000 && c <= 0x303F) return true;
  if (c >= 0xFF00 && c <= 0xFFEF) return true;
  return _kExtraBreakPunctuation.contains(ch);
}

/// 载荷是不是**全部**由断点字符组成（空串 = false）。混合载荷一律 false（不切）。
bool isAllBreakChars(String s) {
  if (s.isEmpty) return false;
  for (final int unit in s.codeUnits) {
    if (!isBreakChar(String.fromCharCode(unit))) return false;
  }
  return true;
}

/// 一次"拆段"计划：把源文档 `[from, to)` 换成 [text]，完后光标落在 [caret]。
class BreakSplit {
  const BreakSplit({
    required this.from,
    required this.to,
    required this.text,
    required this.caret,
  });

  final int from;
  final int to;
  final String text;

  /// 替换之后光标的**绝对**偏移（替换点之前的内容没动 ⇒ 这个值直接可用）
  final int caret;

  @override
  String toString() =>
      'BreakSplit[$from,$to) -> "${text.replaceAll('\n', r'\n')}" caret=$caret';
}

/// 给定文档 + 光标/选区 + 载荷 ⇒ 返回拆段计划；**不需要拆**（或不该拆）时返回 null。
///
/// 调用方（`EditView._commitText`）拿到非 null 就**一次 `replace`** 写进去 —— 一步撤销。
BreakSplit? planBreakSplit({
  required String doc,
  required int caret,
  required int selStart,
  required int selEnd,
  required String payload,
}) {
  if (!isAllBreakChars(payload)) return null;
  final int c = caret.clamp(0, doc.length);
  final int s = selStart.clamp(0, doc.length);
  final int e = selEnd.clamp(0, doc.length);
  final bool hasSel = e > s;
  final int anchor = hasSel ? s : c;
  final MathRegion? r = mathRegionAt(doc, anchor);
  if (r == null) return null;
  if (r.isDisplay) return null; // 行间块：接受数学字体
  if (hasSel && (s < r.contentStart || e > r.contentEnd)) {
    // 选区跨出了这个段 ⇒ 不拆（"两边"已经不是一个段了，硬拆会造出半个公式）
    return null;
  }
  final int relStart = (anchor - r.contentStart).clamp(0, r.tex.length);
  final int relEnd = hasSel ? (e - r.contentStart).clamp(0, r.tex.length) : relStart;
  if (relEnd < relStart) return null;

  // 层级：**只有顶层**才拆（结构槽里接受数学字体）
  //   ★ 判据与"行内公式里按 Enter 断栅栏"（`EditView._splitInlineMathOnEnter`）**同一条**：
  //     用 `innermostSlotAt` 看**位置**落在哪个槽里，而不是看 `snap()` 最近的位点 ——
  //     `snap` 会把"结构内部"的偏移吸到外侧的顶层位点上（实测 `\frac{a}{b}` 的分子里
  //     会吸到 offset 0 ⇒ 误判成顶层 ⇒ 把分子拆成 `$\fr$` 这种坏 tex）。
  final CaretSiteTable t = buildCaretSites(r.tex);
  // ★ 只有**真位点**才许切：rel=1 这种"命令名中间"（`$\frac…` 的 `\` 与 `frac` 之间）
  //   不是位点，切下去会得到 `$\$任$frac{a}{b}$` 这种坏 tex。
  if (t.snap(relStart).offset != relStart) return null;
  if (hasSel && t.snap(relEnd).offset != relEnd) return null;
  final SlotSpan? slot = innermostSlotAt(t, relStart);
  if (slot != null && slot.path.isNotEmpty) return null;

  final String left = r.tex.substring(0, relStart);
  final String right = r.tex.substring(relEnd);

  // 自检：要保留的那一半必须各自自洽（空的那一半不补围栏）
  if (left.isNotEmpty && !_halfIsSelfContained(left)) return null;
  if (right.isNotEmpty && !_halfIsSelfContained(right)) return null;
  if (right.isNotEmpty && _startsWithOrphan(right)) return null;

  final String head = left.isEmpty ? '' : '\$$left\$';
  final String tail = right.isEmpty ? '' : '\$$right\$';
  return BreakSplit(
    from: r.openStart,
    to: r.closeEnd,
    text: '$head$payload$tail',
    caret: r.openStart + head.length + payload.length,
  );
}

/// 这一半 tex 单独拿去能不能解析（结构级的三条配平）。
bool _halfIsSelfContained(String s) {
  if (_braceDepth(s) != 0) return false;
  if (_count(s, r'\left') != _count(s, r'\right')) return false;
  if (_count(s, r'\begin{') != _count(s, r'\end{')) return false;
  return true;
}

/// 右半**不许**以这些东西开头（切了就会"没有基座 / 没有开者"）：
/// `^` `_`（脚本缺基座）、`&`（对齐点缺左边）、`}` `]`（闭合缺开者）。
bool _startsWithOrphan(String right) {
  final String first = right.substring(0, 1);
  return first == '^' || first == '_' || first == '&' || first == '}' || first == ']';
}

/// `{}` 深度（跳过 `\{` / `\}` 转义）。
int _braceDepth(String s) {
  var d = 0;
  var i = 0;
  while (i < s.length) {
    final String ch = s[i];
    if (ch == r'\') {
      i += 2;
      continue;
    }
    if (ch == '{') d++;
    if (ch == '}') d--;
    i++;
  }
  return d;
}

int _count(String s, String pat) {
  var n = 0;
  var i = 0;
  while (true) {
    final int k = s.indexOf(pat, i);
    if (k < 0) return n;
    n++;
    i = k + pat.length;
  }
}
