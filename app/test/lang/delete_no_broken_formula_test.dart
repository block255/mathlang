// 2026-11-10 晚 · 拖选"起点切进行内公式内部" ⇒ 删除后留下**结构不完整的 tex**
//
// 现场（用户两张截图）：同一条行看起来差不多的两次拖选，一次只剩 `$f$`（正常），
// 另一次渲染成 `[公式不完整]`（剩下的 tex 是 `f^{(n-1` 这种残片）。
//
// 根因：`delete_range.dart` 文件头写着「删完结构成立就照删；**不成立才扩到最小单位**」，
// 但 `_repairOnce` 只**列举**了几种局部悬挂（左挂 `{`/`^`/`_`/命令；右挂 `^`/`_`/`]`/`}`/`\end`）。
// 没列举到的形状（剩下 tex 开头就是个 `}`、括号深度中途变负、`^{` 被劈掉一半……）它会 `break` 放弃
// ⇒ 残片留在文件里 ⇒ 渲染成 `[公式不完整]`。
// 实测（真实那一行）：**4851 种选区里 844 种**会留残片；坏起点 10 个（终点取"零点之后/行末"都一样）。
//
// 口径（已与用户对齐）：**局部修不动 ⇒ 扩到整个 `$...$`**（宁可多删，不造残片）。
//
// 本文件钉三条：
//   ① **全域**：这一行**任意选区**删除后，结果里不许出现不完整的行内公式；
//   ② 可修位置不回归：切在结构内部但可修的（`\frac{a}{b}` 里删 `b`）仍只删到成立，不许整段吃掉；
//   ③ A 形态不变：起点在 `^`（= 剩下 `f`）时仍然只剩 `$f$`。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/delete_range.dart';
import 'package:mathlang/lang/math_spans.dart';
import 'package:mathlang/lang/tex_structure.dart';

const String kReal =
    r'$f^{(n-1)}(x) = n(n-1) \dots 2 a_n x + (n-1)! a_{n-1}$ 有 2 个零点                                 (n)';

String _apply(String doc, int s, int e) {
  final DeletePlan p = planDelete(doc, s, e);
  return doc.replaceRange(p.from, p.to, p.replacement);
}

List<String> _broken(String doc) {
  final List<String> bad = <String>[];
  for (final MathSpan sp in scanMathSpans(doc)) {
    if (sp.display) continue;
    if (!isCompleteFragment(sp.tex)) bad.add(sp.tex);
  }
  return bad;
}

void main() {
  test('① 全域：真实那一行任意选区删除 ⇒ 不许留下不完整的行内公式', () {
    final String doc = '……\n\n$kReal\n\n尾行\n';
    final int s0 = doc.indexOf(kReal);
    final int end = s0 + kReal.length;
    final List<String> bad = <String>[];
    for (int s = s0; s <= end; s++) {
      for (int e = s + 1; e <= end; e++) {
        final String after = _apply(doc, s, e);
        final List<String> b = _broken(after);
        if (b.isNotEmpty && bad.length < 8) {
          bad.add('s=${s - s0} e=${e - s0} 残片="${b.first}"');
        }
      }
    }
    expect(bad, isEmpty, reason: '这些选区删完会留残片（渲染成 [公式不完整]）：\n${bad.join('\n')}');
  });

  test('② 可修位置不回归：`\\frac{a}{b}` 里删 `b` ⇒ 只删到能成立，不许整段吃掉', () {
    const String doc = r'甲$\frac{a}{b}$乙' '\n';
    final String after = _apply(doc, doc.indexOf('b'), doc.indexOf('b') + 1);
    expect(after.contains(r'\frac'), isTrue, reason: '不该把整个公式都删掉：$after');
    expect(_broken(after), isEmpty, reason: after);
  });

  test('③ A 形态不变：起点落在 ^（剩下 f）⇒ 结果仍是 f 的公式 + 行尾 + (n)', () {
    final String doc = '……\n\n$kReal\n\n尾行\n';
    final int s0 = doc.indexOf(kReal);
    // 终点取 `(n)` 之前（= 行尾空白里），与用户 A 那次拖选一致：`(n)` 应当留下
    final String after = _apply(doc, s0 + 2, doc.indexOf('(n)'));
    expect(_broken(after), isEmpty, reason: after);
    expect(after.contains(r'$f$'), isTrue, reason: '实际结果：$after');
    expect(after.contains('(n)'), isTrue, reason: after);
  });
}
