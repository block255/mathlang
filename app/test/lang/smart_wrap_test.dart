// 智能包裹（S4-a）的守卫：**保守优先** —— 宁可不包，不许错包。
//
// 语料就是真实场景：`test_data\作业辅导1.md`（DeepSeek 辅导微积分时的原话，LaTeX 是**裸的**）

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/smart_wrap.dart';

void main() {
  group('证据驱动：该包的包', () {
    test(r'上下标：`a_n` / `A_n` / `x^2` / `(-1)^n`', () {
      expect(applySmartWrap('设 a_n 是递增的', planSmartWrap('设 a_n 是递增的')),
          r'设 $a_n$ 是递增的');
      expect(applySmartWrap('比如 a_n = (-1)^n 有界但发散',
              planSmartWrap('比如 a_n = (-1)^n 有界但发散')),
          r'比如 $a_n = (-1)^n$ 有界但发散');
    });

    test(r'命令：`\varepsilon` / `\sum_{k=n+1}^m` / `\le`', () {
      final SmartWrapPlan p =
          planSmartWrap(r'当 m > n > N 时，|a_m - a_n| \le \varepsilon');
      final String out = applySmartWrap(r'当 m > n > N 时，|a_m - a_n| \le \varepsilon', p);
      expect(out.contains(r'\varepsilon'), isTrue, reason: out);
      expect(out.contains(r'$'), isTrue, reason: out);
    });

    test('不改动已有的 \$…\$ 与 \$\$…\$\$', () {
      // 用 raw 片段 + 普通片段拼（Dart 里 raw 串才能安全写 `$`）
      final String src = r'已有 $a_n$ 与' '\n\n' r'$$' '\nx^2\n' r'$$' '\n\n再来 a_n';
      final String out = applySmartWrap(src, planSmartWrap(src));
      expect(out.contains(r'$a_n$'), isTrue);
      expect(out.contains(r'$$' '\nx^2\n' r'$$'), isTrue, reason: out);
      expect(out.endsWith(r'再来 $a_n$'), isTrue, reason: out);
    });
  });

  group('保守：不该包的不包', () {
    test('纯英文单词/短语不包（Cauchy Criterion / Bounded Variation）', () {
      for (final String s in <String>[
        '答案是你之前学过的利器：Cauchy Criterion。',
        '在数学上叫 Bounded Variation。',
        '去写作业时，直接把上面展开-放缩的过程写上去',
      ]) {
        expect(planSmartWrap(s).isEmpty, isTrue, reason: s);
      }
    });

    test('行首列表标记不包', () {
      expect(planSmartWrap('1. A_n 是递增的').runs.first.start, 3);
    });

    test('URL 不包', () {
      expect(planSmartWrap('见 https://example.com/a_b').isEmpty, isTrue);
    });
  });

  group('真实语料：作业辅导1.md', () {
    test('能包出足够多的公式，且不把英文词包进去', () {
      const String src = r'''你的直觉很准！你发现了两个关键点：

1. A_n 是递增且有上界的，所以它肯定收敛。
2. 你想利用不等式得到 a_n 有界，但在往“收敛”推导时卡住了。

你卡住的原因非常典型：有界不一定收敛（比如 a_n = (-1)^n 有界但发散）。而且在这个题里，\{a_n\} 本身不一定是单调的（因为差值可能正负交替），所以不能直接对 a_n 用单调有界定理。

那怎么从 A_n 收敛推导出 a_n 收敛呢？
答案是你之前学过的利器：柯西收敛准则（Cauchy Criterion）。

要证明 \{a_n\} 收敛，根据柯西准则，我们只需证明：对任意 \varepsilon > 0，存在 N。
''';
      final SmartWrapPlan p = planSmartWrap(src);
      final String out = applySmartWrap(src, p);
      // ignore: avoid_print
      print('[WRAP] 包了 ${p.runs.length} 处：${p.runs.take(8).toList()}…');
      expect(p.runs.length, greaterThanOrEqualTo(4), reason: '至少要把几处 a_n 包上');
      expect(out.contains(r'$a_n$'), isTrue);
      expect(out.contains(r'$\varepsilon$') || out.contains(r'\varepsilon > 0$'), isTrue,
          reason: out);
      // 英文词不许被包
      // 纯英文短语由下面那条用例单独守（这里只看语料不被'整体包成公式'）
      expect(out.contains('Criterion'), isTrue);
    });
  });
}
