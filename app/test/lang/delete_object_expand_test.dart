// 2026-11-13 反馈 ③ + ①：**删除的"最小完整单位"**（11-02 §3.1/§3.3 定稿）。
//
// 判据：删完结构成立 ⇒ 照删；不成立 ⇒ 扩到最小完整单位（对象 / 层）。
//
// 改前红：
//   · 分数线那一带 `}{` ⇒ 只删 `}{`，剩 `\frac{bc}+d`（`+` 被当分母，无红字）；
//   · 半边 `\left|` ⇒ 剩孤立的 `\right|`（红字）；
//   · 修不动时直接落"整段"（`\frac{` ⇒ 整行公式全没）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/delete_range.dart';
import 'package:mathlang/lang/math_spans.dart';
import 'package:mathlang/render/caret_sites.dart';

import '../support/tex_oracle.dart';

String _after(String doc, int s, int e) {
  final DeletePlan p = planDelete(doc, s, e);
  return doc.replaceRange(p.from, p.to, p.replacement);
}

void main() {
  group('分数线那一带（`}{`）⇒ 扩到整个分式', () {
    const String doc = r'$a+\frac{b}{c}+d$';
    test('结果必须是 `a++d`，不许留下 `\\frac{bc}+`', () {
      final String after = _after(doc, 10, 12);
      expect(after, r'$a++d$', reason: '整个分式被替换；实际：$after');
    });

    test('分子内容照旧只删内容（不扩）', () {
      expect(_after(doc, 9, 10), r'$a+\frac{}{c}+d$');
    });
  });

  group(r'半边 `\left|…\right|` ⇒ 扩到整对', () {
    test(r'从内容到右括号之后 ⇒ 整对一起走', () {
      const String doc = r'$a+\left|f\right|+b$';
      final int s = doc.indexOf('f');
      final int e = doc.indexOf(r'\right|') + r'\right|'.length;
      final String after = _after(doc, s, e);
      expect(after, r'$a++b$', reason: after);
      expect(texProblem(scanMathSpans(after).first.tex), isNull);
    });
  });

  group('全域：每个位点区间删完都必须过独立 oracle（改前红）', () {
    const List<String> docs = <String>[
      r'$a+\left|f^{\prime}(\xi_1)\right|\le c\left|f(\xi_1)\right|+b$',
      r'$a+\left(\left[x\right]\right)+b$',
      r'$a+\frac{b}{c}+d$',
      r'$a+\sqrt[x]{a_{1}}+\sqrt[x]{a_{2}}+b$',
      r'$a+x^{2}+d$',
    ];
    for (final String doc in docs) {
      test(doc, () {
        final MathSpan sp = scanMathSpans(doc).first;
        final int cs = sp.start + (sp.display ? 2 : 1);
        final List<int> sites = <int>[
          for (final CaretSite s in buildCaretSites(sp.tex).sites) cs + s.offset,
        ];
        final List<String> bad = <String>[];
        for (var a = 0; a < sites.length; a++) {
          for (var b = a + 1; b < sites.length; b++) {
            final String after = _after(doc, sites[a], sites[b]);
            for (final MathSpan run in scanMathSpans(after)) {
              final String? problem = texProblem(run.tex);
              if (problem != null && bad.length < 6) {
                bad.add('选区 [${sites[a]},${sites[b]}) ⇒ <$after>：$problem');
              }
            }
          }
        }
        expect(bad, isEmpty, reason: bad.join('\n'));
      });
    }
  });
}
