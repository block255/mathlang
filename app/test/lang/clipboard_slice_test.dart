// ★★ 2026-10-23（批 1 · A1/A2）：剪贴板切片 —— 复制必须得到「自洽片段」。
//
// 用户实测（2026-10-21）：复制行内公式里的一个分式，得到
//     `\frac{x^3}{\lvert \sin x\rvert^{3}}$`
// —— **缺开头 `$`、多结尾 `$`**；粘回去公式后面挂一个裸 `$`。
// 而且"时对时错"：带不带 `$` 只看选区两端各跨没跨过定界符。
//
// 改前必红：第 1 条改前 `text` 是不带定界符的 `\frac{…}{…}`（`wrapped == false`）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/clipboard_slice.dart';
import 'package:mathlang/lang/math_spans.dart';
import 'package:mathlang/lang/tex_structure.dart';

/// 文本里 `$` 的个数
int _dollars(String s) => s.split(r'$').length - 1;

void main() {
  group(r'① 段级配平', () {
    const String doc = r'设 $a^2+b^2=c^2$ 成立';

    test(r'两端都在同一个公式内部 ⇒ 补一对 $…$', () {
      final int s = doc.indexOf('a^2');
      final int e = doc.indexOf('=c^2');
      final ClipboardSlice sl = clipboardSlice(doc, s, e);
      expect(sl.wrapped, isTrue, reason: r'改前这里是裸 substring（没有 $）');
      expect(sl.text, r'$a^2+b^2$');
      expect(_dollars(sl.text).isEven, isTrue);
    });

    test(r'起点在公式内、终点在文字里 ⇒ 只包数学 run，不扩到段首', () {
      // 2026-11-03（围栏不参与选区 · §七）：选区只看可见流；`$` 不进载荷、也不扩。
      // 选 `b^2` → ` 成立` ⇒ 数学 run 只有 `b^2=c^2`（不回到 `a^2` 那段段首）。
      final int s = doc.indexOf('b^2');
      final int e = doc.indexOf(' 成立');
      final ClipboardSlice sl = clipboardSlice(doc, s, e);
      expect(sl.text, r'$b^2=c^2$', reason: 'payload=${sl.text}');
      expect(_dollars(sl.text), 2);
    });

    test(r'整条公式被选中 ⇒ 重新编码，不重复包', () {
      final int s = doc.indexOf(r'$');
      final int e = doc.lastIndexOf(r'$') + 1;
      final ClipboardSlice sl = clipboardSlice(doc, s, e);
      expect(sl.text, r'$a^2+b^2=c^2$');
      expect(_dollars(sl.text), 2);
    });

    test('纯文字选区 ⇒ 原样', () {
      final ClipboardSlice sl = clipboardSlice(doc, 0, 1);
      expect(sl.text, '设');
      expect(sl.wrapped, isFalse);
    });

    test(r'行间块里抠出来的一段，一律补**行内** $…$（片段不是"块"）', () {
      const String block = '\$\$\nx^2+y^2\n\$\$';
      final int s = block.indexOf('x^2');
      final int e = block.indexOf('+y^2');
      final ClipboardSlice sl = clipboardSlice(block, s, e);
      expect(sl.text, r'$x^2$', reason: '片段按行内算：${sl.text}');
    });
  });

  group('② 括号 / 参数配平', () {
    test(r'拖选切在 \frac{a} ⇒ 补成完整结构 \frac{a}{b}', () {
      const String doc = r'$\frac{a}{b}+x$';
      final int s = doc.indexOf(r'\frac');
      final int e = doc.indexOf(r'}', s) + 1; // `\frac{a}`
      final ClipboardSlice sl = clipboardSlice(doc, s, e);
      expect(sl.text, r'$\frac{a}{b}$');
    });

    test(r'切在分子里、只选了一个 a ⇒ 就是 $a$（不替用户放大对象）', () {
      const String doc = r'$\frac{a}{b}$';
      final int s = doc.indexOf('{a}') + 1;
      final int e = s + 1;
      final ClipboardSlice sl = clipboardSlice(doc, s, e);
      expect(sl.text, r'$a$');
    });

    test(r'结构命令缺参数 ⇒ 补成完整结构（\frac{a} ⇒ \frac{a}{b}）', () {
      const String doc = r'$\frac{a}{b}+x$';
      final int s = doc.indexOf(r'\frac');
      final int e = doc.indexOf('}', s) + 1; // `\frac{a}`：括号配平但少一个参数
      final ClipboardSlice sl = clipboardSlice(doc, s, e);
      expect(sl.text, r'$\frac{a}{b}$',
          reason: r'改前 `$\frac{a}$` 单独渲染必报"expected 2 args"');
    });

    test(r'括号真不平衡（a}）⇒ 向外扩到平衡（{a}）；裸组没有主人', () {
      const String doc = r'$x{a}y$';
      final int s = doc.indexOf('{a}') + 1;
      final int e = s + 2; // `a}`
      final ClipboardSlice sl = clipboardSlice(doc, s, e);
      expect(sl.text, r'${a}$', reason: r'向左扩到配平的 {a}');
      expect(_dollars(sl.text), 2);
    });

    test(r'★ a} 切在分式参数里 ⇒ `{` 的主人 \frac 也带走（不是裸组）', () {
      // 2026-11-02（选择边界批 · 定稿 §3.1）：`{` 的主人 = 紧挨在前的命令。
      // 裸组 `{a}` 单独渲染是 `a`，但它**是分式的参数** ⇒ 片段必须是整个分式。
      const String doc = r'$\frac{a}{b}$';
      final int s = doc.indexOf('{a}') + 1;
      final int e = s + 2; // `a}`
      final ClipboardSlice sl = clipboardSlice(doc, s, e);
      expect(sl.text, r'$\frac{a}{b}$',
          reason: r'`{` 的主人 \frac 在选区左；裸 `{a}` 是半截对象');
    });
  });

  group('③ 控制词吸附', () {
    test(r'起点切在 \frac 中间 ⇒ 挪回反斜杠', () {
      const String doc = r'$\frac{a}{b}$';
      final int s = doc.indexOf('frac') + 2; // `fr|ac`
      final int e = doc.indexOf('b') + 1;
      final ClipboardSlice sl = clipboardSlice(doc, s, e);
      expect(sl.text.startsWith(r'$\frac'), isTrue, reason: sl.text);
    });

    test(r'终点切在控制词中间 ⇒ 挪到词尾之后', () {
      const String doc = r'$x+\sqrt{2}$';
      final int s = doc.indexOf('x');
      final int e = doc.indexOf('sqrt') + 2; // `sq|rt`
      final ClipboardSlice sl = clipboardSlice(doc, s, e);
      expect(sl.text.contains(r'\sqrt'), isTrue, reason: sl.text);
      expect(sl.text, r'$x+\sqrt{2}$');
    });
  });

  group(r'★ 全域：任何选区的载荷，`$` 成对、数学 run 结构完整', () {
    test('4 份语料 × 每一个 (i, j)', () {
      const List<String> docs = <String>[
        r'设 $a^2+b^2=c^2$ 成立，其中 $a,b,c$ 为正',
        '\$\$\n\\frac{x}{y} = z\n\$\$',
        r'前 $\sqrt{2}$ 后 $\frac{a}{b}$ 尾',
        r'纯文字，一个公式都没有',
      ];
      for (final String doc in docs) {
        // 源本来就坏的段（如游离的 `^{x}`）：复制不可能把它补好 —— 原样带走即可
        final Set<String> bad = <String>{
          for (final MathSpan sp in scanMathSpans(doc))
            if (!isCompleteFragment(sp.tex)) sp.tex,
        };
        for (var i = 0; i <= doc.length; i++) {
          for (var j = i; j <= doc.length; j++) {
            final ClipboardSlice sl = clipboardSlice(doc, i, j);
            expect(sl.start, lessThanOrEqualTo(sl.end));
            expect(_dollars(sl.text).isEven, isTrue,
                reason: '选区 ($i,$j) 给出奇数个 `\$`：${sl.text}');
            for (final MathSpan run in scanMathSpans(sl.text)) {
              final bool ok =
                  isCompleteFragment(run.tex) || bad.contains(run.tex);
              expect(ok, isTrue,
                  reason: '选区 ($i,$j)：载荷里的数学 run「${run.tex}」不完整：'
                      '${sl.text}');
            }
          }
        }
      }
    });
  });
}
