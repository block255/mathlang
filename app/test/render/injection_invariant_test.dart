// 守门人：**为显示而注入的东西，绝不能改变"可见原子"的数量**
//
// ★ 为什么这条必须有：点击定位靠"引擎叶盒 ↔ 我们的可见原子"一一对应，
//   数量不等时 `hitTestMathTex` 会**静默返回 null**（点公式没反应、且不报错）。
//   2026-10-14 正是这条抓出了现存 bug：
//     注入的 `\textcolor{#1E88E5}{\cursor{}}` 里，颜色名 `#1E88E5` 被算成 **9 个可见原子**，
//     而引擎一个字形都不画 → 含光标那个单元里点公式会失效。
//   修法：`visible_atoms.kNonRenderedArgCount`（跳过不参与渲染的参数）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/visible_atoms.dart';

const List<String> kSamples = <String>[
  r'\frac{a}{b}',
  r'\frac{a}{b}=\sqrt{2}',
  r'x^2+1',
  r'\frac{-b\pm\sqrt{b^2-4ac}}{2a}',
  r'\sum_{i}^{n} a_i',
  r'\sqrt[3]{x}',
  r'\alpha+\beta',
  r'\text{中文}',
  r'\frac{}{}',
  r'f(x)=\begin{cases}1&x>0\\0&x\le 0\end{cases}',
];

void main() {
  group('不参与渲染的参数（颜色名 / 尺寸 / 间距）不算可见原子', () {
    test(r'\textcolor{#1E88E5}{x} → 只有 x', () {
      expect(lexVisibleAtoms(r'\textcolor{#1E88E5}{x}').length, 1);
    });

    test(r'\rule{1em}{0.5em} → 零个', () {
      expect(lexVisibleAtoms(r'\rule{1em}{0.5em}'), isEmpty);
    });

    test(r'\hspace{1em} / \kern 2pt → 零个', () {
      expect(lexVisibleAtoms(r'\hspace{1em}'), isEmpty);
      expect(lexVisibleAtoms(r'\kern 2pt'), isEmpty);
    });

    test(r'光标注入串本身恰好一个原子（就是光标条）', () {
      expect(lexVisibleAtoms(r'\textcolor{#1E88E5}{\cursor{}}').length, 1);
    });

    test(r'\phantom{x} 占位但不画 → 零个原子', () {
      expect(lexVisibleAtoms(r'\phantom{x}'), isEmpty);
    });
  });

  group('★ 在**每一个位点**注入光标后，原子数必须恰好 +1（只多出光标条）', () {
    for (final String tex in kSamples) {
      test('tex = $tex', () {
        final int base = lexVisibleAtoms(tex).length;
        final CaretSiteTable t = buildCaretSites(tex);
        expect(t.offsets, isNotEmpty);
        for (final int off in t.offsets) {
          final String injected = injectCursor(tex, off).tex;
          expect(
            lexVisibleAtoms(injected).length,
            base + 1,
            reason: '在偏移 $off 注入后原子数应恰好 +1（光标条）。\n'
                '不等 ⇒ 有"不参与渲染的参数"被当成了原子 ⇒ 叶盒数与原子数对不上 '
                '⇒ hitTestMathTex 静默返回 null（点公式失效）。\n'
                'tex      = $tex\ninjected = $injected',
          );
        }
      });
    }
  });
}
