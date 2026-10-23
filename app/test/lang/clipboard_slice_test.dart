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

    test(r'起点在公式内、终点在文字里 ⇒ 起点扩到段边界（$ 成对）', () {
      final int s = doc.indexOf('b^2');
      final int e = doc.indexOf(' 成立');
      final ClipboardSlice sl = clipboardSlice(doc, s, e);
      expect(sl.text, r'$a^2+b^2=c^2$',
          reason: r'改前是 `b^2=c^2$`（缺开头 $）');
      expect(_dollars(sl.text), 2);
    });

    test(r'整条公式被选中 ⇒ 原样（不再多补一层）', () {
      final int s = doc.indexOf(r'$');
      final int e = doc.lastIndexOf(r'$') + 1;
      final ClipboardSlice sl = clipboardSlice(doc, s, e);
      expect(sl.wrapped, isFalse);
      expect(sl.text, r'$a^2+b^2=c^2$');
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

    test(r'括号真不平衡（a}）⇒ 向外扩到平衡（{a}）', () {
      const String doc = r'$\frac{a}{b}$';
      final int s = doc.indexOf('{a}') + 1;
      final int e = s + 2; // `a}`
      final ClipboardSlice sl = clipboardSlice(doc, s, e);
      expect(sl.text, r'${a}$', reason: r'向左扩到配平的 {a}');
      expect(_dollars(sl.text), 2);
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

  group(r'★ 全域：任何选区复制出来的文本，$ 个数必须是偶数', () {
    test('4 份语料 × 每一个 (i, j)', () {
      const List<String> docs = <String>[
        r'设 $a^2+b^2=c^2$ 成立，其中 $a,b,c$ 为正',
        '\$\$\n\\frac{x}{y} = z\n\$\$',
        r'前 $\sqrt{2}$ 后 $\frac{a}{b}$ 尾',
        r'纯文字，一个公式都没有',
      ];
      for (final String doc in docs) {
        for (var i = 0; i <= doc.length; i++) {
          for (var j = i; j <= doc.length; j++) {
            final ClipboardSlice sl = clipboardSlice(doc, i, j);
            expect(sl.start, lessThanOrEqualTo(sl.end));
            expect(_dollars(sl.text).isEven, isTrue,
                reason: '选区 ($i,$j) 给出奇数个 `\$`：${sl.text}');
            if (!sl.wrapped) {
              // 没有补定界符时，剪贴板文本必须就是源区间那一段
              expect(sl.text, doc.substring(sl.start, sl.end));
            }
          }
        }
      }
    });
  });
}
