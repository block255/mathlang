// 智能包裹（S4-a）的守卫：**保守优先** —— 宁可不包，不许错包。
//
// 语料就是真实场景：`test_data\作业辅导1.md`（DeepSeek 辅导微积分时的原话，LaTeX 是**裸的**）

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/smart_wrap.dart';

/// 行间块的期望文本（`$$` 在 Dart 普通串里要转义，raw 串里又不能写 `\n` ⇒ 拼一下）
String _display(String body) => '\$\$\n$body\n\$\$';

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

  group('★★ B\'：整行一个式子 ⇒ 行间块 `\$\$…\$\$`（用户 2026-10-17 拍板）', () {
    // 为什么要有这一条：n 元算子的上下限**只在 display 样式下堆叠** ——
    //   `\sum_{k=1}^n` 包成行内会画成右边的小上下标（用户实测："求和画到右边去了"）。
    //   而"整行只有一个式子"在作业答案里几乎总是**推导**，天生该居中成块。
    test('整行是推导（含 `=`）⇒ 行间', () {
      const String src = r'a_n = (-1)^n';
      final SmartWrapPlan p = planSmartWrap(src);
      expect(p.runs.length, 1);
      expect(p.runs.first.display, isTrue);
      expect(applySmartWrap(src, p), _display('a_n = (-1)^n'));
    });

    test(r'整行含 `\sum` ⇒ 行间（上下限才会堆叠）', () {
      const String src = r'\sum_{k=1}^n a_k';
      final SmartWrapPlan p = planSmartWrap(src);
      expect(p.runs.first.display, isTrue);
      expect(applySmartWrap(src, p), _display(r'\sum_{k=1}^n a_k'));
    });

    test('夹在文字里的同一段式子 ⇒ **仍是行内**（同权：数学是这一行的对象）', () {
      const String src = r'比如 a_n = (-1)^n 有界';
      final SmartWrapPlan p = planSmartWrap(src);
      expect(p.runs.first.display, isFalse);
      expect(applySmartWrap(src, p), r'比如 $a_n = (-1)^n$ 有界');
    });

    test('★★ 批 37（改口径）：整行一个裸符号 + **自成一段** ⇒ 行间', () {
      // 改前（2026-10-17 B'）：`a_n` 没有"显示证据" ⇒ 一律行内。
      // 改后（2026-10-26 用户拍板 B）：判据换成**结构**判据 —— 这一行在源文里自成一段
      // （上下是空行 / 文首 / 文末）就说明排版意图是"独立一段"，与它里面写了什么无关。
      // 用户原话：「不管是 AI 抄写的还是我手打的，审美上都没有理由出现一（段/行）就一个裸符号」。
      const String src = r'a_n';
      expect(applySmartWrap(src, planSmartWrap(src)), _display('a_n'));
    });

    test('★ 但整行式子**不自成一段**（上下紧邻非空行）⇒ 照旧按内容证据判行内', () {
      const String src = '甲\nx^2\n乙';
      expect(applySmartWrap(src, planSmartWrap(src)), '甲\n\$x^2\$\n乙');
    });

    test('缩进的整行式子也算"整行"（缩进留在块外面）', () {
      const String src = '  x = 1  ';
      expect(applySmartWrap(src, planSmartWrap(src)), '  ${_display('x = 1')}  ');
    });
  });

  // ★★ 2026-10-26（批 37，用户 20261026 反馈 A1）：**命令写的关系符也算显示倾向**。
  //
  // 实测缺口：`\le |\sqrt{x} - \sqrt{x_0}|` 与 `≤ |x-y|` 是**同一语义**，
  // 但 `_wantsDisplayBlock` 只认字面 `≤`，于是只有后者被判行间 ⇒ 用户粘 AI 抄写稿时
  // 三处「行间段变成了行内段」里有一处就是这个。
  group(r'★ 批 37：`\le \ge \ne \to …` 与字面 `≤ ≥ ≠ →` 同待遇', () {
    test(r'`\le |\sqrt{x}-\sqrt{x_0}|` 整行 ⇒ 行间', () {
      const String src = r'\le |\sqrt{x} - \sqrt{x_0}|';
      expect(applySmartWrap(src, planSmartWrap(src)),
          _display(r'\le |\sqrt{x} - \sqrt{x_0}|'));
    });

    test(r'`\ge` / `\ne` / `\to` / `\Rightarrow` / `\approx` 同样', () {
      for (final String src in <String>[
        r'\ge |x|',
        r'a \ne b',
        r'x \to 0',
        r'A \Rightarrow B',
        r'x \approx 1.414',
      ]) {
        expect(applySmartWrap(src, planSmartWrap(src)), _display(src),
            reason: '$src 应判行间');
      }
    });

    test(r'★ 不许误伤：夹在文字里的同一段 ⇒ 仍是行内', () {
      const String src = r'当 \le x 时有界';
      expect(applySmartWrap(src, planSmartWrap(src)), r'当 $\le x$ 时有界');
    });
  });

  // ★★ 2026-10-26（批 37）：**自成一段 ⇒ 行间**（结构判据）。
  group('★ 批 37（B）：自成一段 ⇒ 行间，与里面写了什么无关', () {
    test('上下都是空行的整行式子 ⇒ 行间（这一行没有任何"显示证据"）', () {
      const String src = r'''前文

|\sin\sqrt{x} - \sin\sqrt{x_0}|

后文''';
      expect(applySmartWrap(src, planSmartWrap(src)),
          '前文\n\n${_display(r'|\sin\sqrt{x} - \sin\sqrt{x_0}|')}\n\n后文');
    });

    test('文首 / 文末也算自成一段', () {
      const String src = r'|\sin x|';
      expect(applySmartWrap(src, planSmartWrap(src)), _display(r'|\sin x|'));
    });

    test('★ 不许误伤：列表行里的式子 ⇒ 不升格（`- ` 标记还在）', () {
      const String src = '- 求极限 x^2';
      expect(applySmartWrap(src, planSmartWrap(src)), r'- 求极限 $x^2$');
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
