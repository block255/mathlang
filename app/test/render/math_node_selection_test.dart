// ★★ 双击单位 = 「乙」（2026-10-21 用户拍板）：**字形 + 它挂的上下标 / 结构 + 它的全部参数**
//
// 用户原话：「我们是平权，多项式不是整体，所以一般来说行内公式里的 `a` 是没有意义的」
// ⇒ `a` 单独**不是**可选对象；`a^2` / `x_n` / `\frac{a}{b}` / `\sum_{i=1}^{n}` 各算**一个**。
//
// 改前必红（旧实现按"一个可见原子"选）：本文件里凡是期望"整体"的断言都会红。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/selection_range.dart';

/// 在 [src] 的 [at] 处双击会选中什么（原样子串）
String _picked(String src, int at) {
  final ({int start, int end}) r = wordRangeAt(src, at);
  return src.substring(r.start, r.end);
}

void main() {
  group('① 字形 + 上下标 = 一个对象', () {
    test(r'$a^2$ 双击 a ⇒ 整个 a^2（不是 a）', () {
      expect(_picked(r'$a^2$', 1), r'a^2');
      expect(_picked(r'$a^2$', 2), r'a^2', reason: '点在 ^ 上也算它');
    });

    test(r'$x_n$ 双击 x ⇒ 整个 x_n', () {
      expect(_picked(r'$x_n$', 1), r'x_n');
      expect(_picked(r'$x_n$', 3), r'x_n', reason: '点在脚标里也算整个 x_n');
    });

    test(r'$a^2+b^2$ 双击第一个 a ⇒ 只有 a^2（不许吃 + 或 b^2）', () {
      expect(_picked(r'$a^2+b^2$', 1), r'a^2');
      expect(_picked(r'$a^2+b^2$', 5), r'b^2');
    });

    test(r'裸参数写法 $x^2$（normalize 后会去花括号）也成立', () {
      expect(_picked(r'$x^2$', 1), r'x^2');
    });
  });

  group('② 结构 + 全部参数 = 一个对象（参数归主人，不深入）', () {
    test(r'$\frac{a}{b}$ 双击分子 ⇒ 整个分式', () {
      const String src = r'$\frac{a}{b}$';
      expect(_picked(src, 7), r'\frac{a}{b}');
      expect(_picked(src, 10), r'\frac{a}{b}', reason: '分母也一样');
    });

    test(r'$\sqrt{x+1}$ 双击被开方数 ⇒ 整个根号', () {
      const String src = r'$\sqrt{x+1}$';
      expect(_picked(src, 7), r'\sqrt{x+1}');
    });

    test(r'$\sum_{i=1}^{n}$ 双击脚标 ⇒ 整个 ∑ 节点（上下限都包进来）', () {
      const String src = r'$\sum_{i=1}^{n}$';
      final String got = _picked(src, 7);
      expect(got, r'\sum_{i=1}^{n}');
    });

    test(r'$\liminf\limits_{n\to\infty}$ 双击脚标 ⇒ 整个算子节点', () {
      const String src = r'$\liminf\limits_{n\to\infty}$';
      final String got = _picked(src, 20);
      expect(got, r'\liminf\limits_{n\to\infty}',
          reason: '脚标属于算符 ⇒ 选整个节点，实际 "$got"');
    });
  });

  group('③ 平权边界：不该被当成整体的地方', () {
    test(r'$a+b$ 双击 a ⇒ 只有 a', () {
      expect(_picked(r'$a+b$', 1), r'a');
      expect(_picked(r'$a+b$', 3), r'b');
    });

    test(r'相邻两个节点不许被并成一个：$x_n y_m$ ⇒ 各自独立', () {
      expect(_picked(r'$x_n y_m$', 1), r'x_n');
      expect(_picked(r'$x_n y_m$', 5), r'y_m');
    });

    test('文本（非公式）里的双击仍然是"连续字母数字"', () {
      expect(_picked('甲乙 丙丁', 0), '甲乙');
      expect(_picked('abc def', 1), 'abc');
    });
  });

  group('④ 全覆盖：任何偏移选出来的区间都必须"非空且落在 source 内"', () {
    const List<String> corpus = <String>[
      r'$a^2$',
      r'$x_n$',
      r'$\frac{a}{b}$',
      r'$\sum_{i=1}^{n}$',
      r'$\liminf\limits_{n\to\infty}\{x_n\}$',
      r'$\sqrt[3]{x^2+1}$',
      r'$\{x_n\}$ 与 $L$',
      r'文字 $a$ 文字',
    ];
    test('每个偏移都不越界、不返回倒序', () {
      for (final String src in corpus) {
        for (var at = 0; at <= src.length; at++) {
          final ({int start, int end}) r = wordRangeAt(src, at);
          expect(r.start, greaterThanOrEqualTo(0), reason: '$src @$at');
          expect(r.end, lessThanOrEqualTo(src.length), reason: '$src @$at');
          expect(r.start, lessThanOrEqualTo(r.end), reason: '$src @$at');
        }
      }
    });
  });
}
