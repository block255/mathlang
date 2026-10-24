// 批 26：**包裹不许把 `\begin{…}…\end{…}` 切碎**。
//
// 用户 2026-10-24 21:4x 粘贴自己的作业（第 2 题那行 `cases`），页面上出现
// `[公式不完整] , & [公式不完整] , & [公式不完整] , & [公式不完整]`。
//
// 根因（探针 v28 坐实）：`&` 不在 `_isMathChar` 名单里 ⇒ 贪心切段在**每个 `&`** 处断开
// ⇒ 一行 `cases` 被切成 4 段，只有中间两段"碰巧能解析"，另两段报
// `Expected & or \\ or \cr or \end` / `Expected 'EOF', got '\end'`。
//
// 修法：把单行环境**整段算段内**（与批 1 的 `\text{…}` 同族）；跨行环境整段锁住
// （行内 `$…$` 不许跨行 —— 批 17 的硬规则）。**不动 `_isMathChar`**：
// 把 `&` 加进数学字符会让 `A & B` 这种普通文本也被判成公式（见反例 ③）。

import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/math_spans.dart';
import 'package:mathlang/lang/smart_wrap.dart';

/// 用户那份作业的原样（第 2 题那行 `cases` 就是病灶；第 1 题本来就渲染正常，一起当回归）。
const String kHomework = r'''1. 证明：由题意得
对 \forall x_n \in [a, b]，\exists x_{n+1} \in [a, b]，使 |f(x_{n+1})| \le \frac{1}{2}|f(x_n)|

2. 记

F(x) = \begin{cases} \lim_{x \to a^+} f(x), & a \\ f(x), & a < x < b \\ \lim_{x \to b^-} f(x), & b \end{cases} 

则 由题意得：F(x) \in C[a, b] 且 F(a) = F(b)，记为 F_0
''';

int _count(String s, String sub) {
  var n = 0;
  var i = 0;
  while (true) {
    final int k = s.indexOf(sub, i);
    if (k < 0) return n;
    n++;
    i = k + sub.length;
  }
}

void main() {
  group('批 26 · 环境不许被切碎', () {
    test('★★ ① 用户那份作业：每个 run 里的 \\begin / \\end 必须配平（改前必红）', () {
      final SmartWrapPlan plan = planSmartWrap(kHomework);
      var withBegin = 0;
      for (final WrapRun r in plan.runs) {
        final String seg = kHomework.substring(r.start, r.end);
        if (!seg.contains(r'\begin')) continue;
        withBegin++;
        expect(_count(seg, r'\begin'), _count(seg, r'\end'),
            reason: 'run[${r.start},${r.end}) 把环境切开了：「$seg」——'
                '每段单独都不完整 ⇒ 页面上就是 [公式不完整]');
      }
      expect(withBegin, 1, reason: '这段作业里只有一个环境 ⇒ 应当恰好被一个 run 完整覆盖');
    });

    test('★★ ② 包裹结果：含 `cases` 的那一段必须是**一个**行间块且能解析', () {
      final SmartWrapPlan plan = planSmartWrap(kHomework);
      final String out = applySmartWrap(kHomework, plan);
      final List<MathSpan> spans = scanMathSpans(out);
      expect(spans.where((MathSpan s) => s.tex.contains(r'\begin')).length, 1,
          reason: '环境只能出现一次（被切碎就会出现多段）');
      for (final MathSpan sp in spans) {
        if (!sp.tex.contains(r'\begin')) continue;
        expect(sp.display, isTrue, reason: '整行一个 cases ⇒ 该是行间块');
        expect(Math.tex(sp.tex).parseError, isNull,
            reason: '包出来的这段必须能被引擎解析：${sp.tex}');
      }
      // `&` 不许留在数学段外面（改前：行内出现 `$, & $` 这种碎片）
      expect(out.contains(r'$, & $'), isFalse,
          reason: '改前的产物里 `&` 落在两段公式之间（用户截图里那三个 `&`）');
    });

    test('★ ③ 反例：没有环境的 `&` 仍然**不是**数学（别把 & 加进数学字符）', () {
      const String plain = 'A & B 交接，C & D 也交接。\n';
      expect(planSmartWrap(plain).runs, isEmpty,
          reason: '`&` 一旦被当成数学字符，这种普通文本会被包成 `\$A & B\$` ⇒ [公式不完整]');
    });

    test('★ ④ 跨行环境：整段**锁住**，不许产生与它重叠的 run', () {
      const String multi = '记\n\\begin{cases}\na \\\\\nb\n\\end{cases}\n完\n';
      final int from = multi.indexOf(r'\begin');
      final int to = multi.indexOf(r'\end') + r'\end{cases}'.length;
      for (final WrapRun r in planSmartWrap(multi).runs) {
        final bool overlap = r.start < to && r.end > from;
        expect(overlap, isFalse,
            reason: 'run[${r.start},${r.end}) 碰到了跨行环境 [$from,$to) —— '
                '行内 `\$…\$` 塞进换行会变成跨行段（批 17 明令禁止）');
      }
    });

    test('★ ⑤ 环境外的前缀仍在同一个 run 里（`F(x) =` 不许被切掉）', () {
      final SmartWrapPlan plan = planSmartWrap(kHomework);
      final WrapRun envRun = plan.runs.firstWhere(
          (WrapRun r) => kHomework.substring(r.start, r.end).contains(r'\begin'));
      expect(kHomework.substring(envRun.start, envRun.end),
          startsWith('F(x) = \\begin{cases}'),
          reason: '前缀 `F(x) =` 必须跟环境在同一段里（否则等号左边会掉成正文）');
    });
  });
}
