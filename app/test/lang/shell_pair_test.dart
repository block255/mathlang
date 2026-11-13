// 2026-11-13 反馈 ①：**`\left…\right` 是壳**（11-02 §3.1 定稿表里早就写了）。
//
// 改前红：
//   · `isCompleteFragment` 完全不认 `\left/\right` ⇒ `\right|f` 也判"完整"；
//   · 复制/删除切开这对 ⇒ 载荷/剩余只剩半个 `\left`（渲染成 `[公式不完整]`）；
//   · 命令参数也不查 ⇒ `\frac{bxc}+d` 判"完整"（`+` 被当分母吃了）。
//
// oracle 见 `test/support/tex_oracle.dart`（**独立实现**，不复用被测函数）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/clipboard_slice.dart';
import 'package:mathlang/lang/math_spans.dart';
import 'package:mathlang/lang/tex_structure.dart';
import 'package:mathlang/render/caret_sites.dart';

import '../support/tex_oracle.dart';

void main() {
  group('判据：壳表 §3.1 的 \\left / \\right', () {
    test(r'成对 ⇒ 完整；半边 ⇒ 不完整', () {
      expect(isCompleteFragment(r'\left|f\right|'), isTrue);
      expect(isCompleteFragment(r'\left(\left[x\right]\right)'), isTrue);
      expect(isCompleteFragment(r'\left\{a\middle|b\right\}'), isTrue);
      expect(isCompleteFragment(r'\left|f'), isFalse, reason: r'缺 \right');
      expect(isCompleteFragment(r'f\right|'), isFalse, reason: r'缺 \left');
      expect(isCompleteFragment(r'\left(\left[x\right]'), isFalse);
      expect(isCompleteFragment(r'\middle|'), isFalse);
    });

    test('命令参数必须齐（\\frac 被吞掉参数也算坏）', () {
      expect(isCompleteFragment(r'\frac{b}{c}+d'), isTrue);
      expect(isCompleteFragment(r'\frac{bxc}+d'), isFalse,
          reason: 'KaTeX 会把 `+` 当分母吃掉——没有红字，但结构已经错了');
      expect(isCompleteFragment(r'\sqrt{a}'), isTrue);
      expect(isCompleteFragment(r'\sqrt{a}+1'), isTrue);
      expect(isCompleteFragment(r'\sqrt{a'), isFalse);
    });
  });

  group('复制：切开配对 ⇒ 扩到整对', () {
    const String doc =
        r'$a+\left|f^{\prime}(\xi_1)\right|\le c\left|f(\xi_1)\right|+b$';

    test(r'起点在内容里、终点在闭括号之后 ⇒ 补上开头的 \left|', () {
      final int s = doc.indexOf(r'f^{\prime}');
      final int e = doc.lastIndexOf(r'\right|') + r'\right|'.length;
      final ClipboardSlice sl = clipboardSlice(doc, s, e);
      expect(sl.text, r'$\left|f^{\prime}(\xi_1)\right|\le c\left|f(\xi_1)\right|$');
      expect(texProblem(sl.text.substring(1, sl.text.length - 1)), isNull);
    });

    test(r'起点在括号之前、终点在内容里 ⇒ 补上结尾的 \right|', () {
      const String d = r'$a+\left|f\right|+b$';
      final int s = d.indexOf('a');
      final int e = d.indexOf('f') + 1;
      final ClipboardSlice sl = clipboardSlice(d, s, e);
      expect(sl.text, r'$a+\left|f\right|$', reason: '切开的那一对必须补齐');
      expect(texProblem(sl.text.substring(1, sl.text.length - 1)), isNull);
    });
  });

  group('全域：每个位点区间的载荷都必须过独立 oracle（改前红）', () {
    const List<String> docs = <String>[
      r'$a+\left|f^{\prime}(\xi_1)\right|\le c\left|f(\xi_1)\right|+b$',
      r'$a+\left(\left[x\right]\right)+b$',
      r'$a+\frac{b}{c}+d$',
      r'$a+\sqrt[x]{a_{1}}+\sqrt[x]{a_{2}}+b$',
      r'$a+x^{2}+d$',
    ];
    for (final String doc in docs) {
      test(doc, () {
        final List<MathSpan> spans = scanMathSpans(doc);
        expect(spans, isNotEmpty);
        final MathSpan sp = spans.first;
        final int cs = sp.start + (sp.display ? 2 : 1);
        final List<int> sites = <int>[
          for (final CaretSite s in buildCaretSites(sp.tex).sites) cs + s.offset,
        ];
        final List<String> bad = <String>[];
        for (var a = 0; a < sites.length; a++) {
          for (var b = a + 1; b < sites.length; b++) {
            final ClipboardSlice sl = clipboardSlice(doc, sites[a], sites[b]);
            for (final MathSpan run in scanMathSpans(sl.text)) {
              final String? problem = texProblem(run.tex);
              if (problem != null && bad.length < 6) {
                bad.add('选区 [${sites[a]},${sites[b]}) ⇒ <${sl.text}>：$problem');
              }
            }
          }
        }
        expect(bad, isEmpty, reason: bad.join('\n'));
      });
    }
  });
}
