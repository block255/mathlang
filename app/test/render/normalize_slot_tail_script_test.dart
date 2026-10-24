// ★★ 2026-10-24（批 6 · H4 真凶）：**失焦 normalize 不许把"结构槽尾"的脚本花括号拆掉**
//
// 用户给的目标序列（2026-10-24 原话）：
//   「依次按右箭头：3 左边 → 3 右边 → x 三次方的右边（分子尾）→ 分母首」
// 这四步在 `\frac{x^{3}}{…}` 里本来就是四个位点（9 / 10 / 11 / 13）。
// 但 ② 会把 `x^{3}` 拆成 `x^3` ⇒ 指数尾(10) 与 分子尾(11) **并成同一个字节 9**
// ⇒ 用户按下 `→` 时"3 右边之后就掉到分母"。
//
// 口径：(a)(b)(c) 已经写了"拆了会合并位点 ⇒ 不拆"，这里补齐最要紧的那一处 ——
// **脚本是结构槽的最后一项**（后面紧跟 `}` 关外层槽，或 `\\`/`&`/`\end{` 结束一格）。
// 并且**反向补回**（③）：老文档里已经被拆成 `x^3` 的，补成 `x^{3}`。
//
// ★ 段末去括号的既有口径**不动**（`$a=b^2$` 仍可写 `b^2`）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/normalize.dart';

void main() {
  group('②(d)：结构槽尾的花括号**不许拆**', () {
    test(r'\frac{x^{3}}{y} 保持不动（分子尾）', () {
      final NormalizeResult r = normalizeTex(r'\frac{x^{3}}{y}', 0);
      expect(r.tex, r'\frac{x^{3}}{y}',
          reason: '改前会变成 \\frac{x^3}{y} ⇒ 指数尾与分子尾并成一个字节');
    });

    test(r'\frac{a}{x^{2}} 保持不动（分母尾）', () {
      expect(normalizeTex(r'\frac{a}{x^{2}}', 0).tex, r'\frac{a}{x^{2}}');
    });

    test(r'\sqrt{x^{2}} 保持不动（根号内容尾）', () {
      expect(normalizeTex(r'\sqrt{x^{2}}', 0).tex, r'\sqrt{x^{2}}');
    });

    test(r'cases 格子尾也不拆（`x^{2}\\`）', () {
      const String tex = '\\begin{cases}x^{2}\\\\y\\end{cases}';
      expect(normalizeTex(tex, 0).tex, tex);
    });

    test(r'定界符组尾也不拆（`\left(x^{2}\right)`）', () {
      const String tex = r'\left(x^{2}\right)';
      expect(normalizeTex(tex, 0).tex, tex);
    });

    test(r'绝对值组尾也不拆（`\left|{x^{2}}\right|`）', () {
      const String tex = r'\left|{x^{2}}\right|';
      expect(normalizeTex(tex, 0).tex, tex);
    });
  });

  group('③ 反向：槽尾的裸参数**补回**花括号', () {
    test(r'\frac{x^3}{y} ⇒ \frac{x^{3}}{y}', () {
      final NormalizeResult r = normalizeTex(r'\frac{x^3}{y}', 0);
      expect(r.tex, r'\frac{x^{3}}{y}');
      expect(r.changed, isTrue);
    });

    test(r'\frac{a}{x^2} ⇒ \frac{a}{x^{2}}', () {
      expect(normalizeTex(r'\frac{a}{x^2}', 0).tex, r'\frac{a}{x^{2}}');
    });

    test(r'\sqrt{x^2} ⇒ \sqrt{x^{2}}', () {
      expect(normalizeTex(r'\sqrt{x^2}', 0).tex, r'\sqrt{x^{2}}');
    });

    test(r'组尾的裸参数也补回：\left(x^2\right) ⇒ \left(x^{2}\right)', () {
      expect(normalizeTex(r'\left(x^2\right)', 0).tex, r'\left(x^{2}\right)');
    });

    test(r'绝对值组尾同理：\left|{x^2}\right| ⇒ \left|{x^{2}}\right|', () {
      expect(normalizeTex(r'\left|{x^2}\right|', 0).tex, r'\left|{x^{2}}\right|');
    });

    test(r'多原子不补：\frac{x^{n+1}}{y} 不动', () {
      const String tex = r'\frac{x^{n+1}}{y}';
      expect(normalizeTex(tex, 0).tex, tex);
    });
  });

  group('★ 既有口径不许漂', () {
    test(r'段末仍去括号：x^{2} ⇒ x^2', () {
      expect(normalizeTex(r'x^{2}', 1).tex, r'x^2');
    });

    test(r'段中仍去括号：x^{2}+1 ⇒ x^2+1', () {
      expect(normalizeTex(r'x^{2}+1', 1).tex, r'x^2+1');
    });

    test(r'± 多原子不动：x^{2n} 不动', () {
      expect(normalizeTex(r'x^{2n}', 1).tex, r'x^{2n}');
    });

    test(r'连写脚本不动：x^2_1 不动（不补也不拆）', () {
      const String tex = r'x^2_1';
      expect(normalizeTex(tex, 0).tex, tex);
    });
  });

  group('★ 幂等 + 光标不乱跳', () {
    test(r'补完再跑一次不再变（\frac{x^{3}}{y}）', () {
      final NormalizeResult once = normalizeTex(r'\frac{x^3}{y}', 0);
      final NormalizeResult twice = normalizeTex(once.tex, once.caret);
      expect(twice.tex, once.tex);
      expect(twice.changed, isFalse);
    });

    test(r'补花括号后，光标在末尾的跟着右移 2 格', () {
      final NormalizeResult r = normalizeTex(r'\frac{x^3}{y}', 13);
      expect(r.tex, r'\frac{x^{3}}{y}');
      expect(r.caret, 15, reason: '插入了 `{` `}` 两个字符');
    });

    test(r'补花括号不影响"光标在内容之前"', () {
      final NormalizeResult r = normalizeTex(r'\frac{x^3}{y}', 0);
      expect(r.caret, 0);
    });
  });
}
