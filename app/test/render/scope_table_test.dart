// 算子作用域表（§4.7）：`\sin` / `\log` / `\sum` / `\int` 这类"接值才成整体"的算子，
// **它的内容到哪结束**。
//
// 判据不是我们编的：**数学的结合力**（写出来的运算记号 = 主运算 = 断点；并置 = 同一个项）
// + **引擎的原子类别**（Op / Bin / Rel / Punct…）。逐条对照见设计稿 §4.7.1 / §4.7.2。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/scope_table.dart';
import 'package:mathlang/render/site_adjacency.dart';
import 'package:mathlang/render/visible_atoms.dart';

/// 取**指定命令**的那个作用域（用例里可能有嵌套算子，如 `\sin\log x`）
OpScope _op(String tex, String cmd) {
  final List<OpScope> s = operatorScopes(tex)
      .where((OpScope x) => x.command == cmd)
      .toList();
  expect(s.length, 1, reason: '「$tex」应当只有一个 \\$cmd 作用域，实际 $s');
  return s.first;
}

void main() {
  // ─────────────────────────────────────────────────────────────
  // 一、§4.7.2 的例子表（逐条钉住）
  // ─────────────────────────────────────────────────────────────
  group('§4.7.2 例子：作用域到哪结束', () {
    void expectArg(String tex, String cmd, String arg) {
      final OpScope s = _op(tex, cmd);
      expect(tex.substring(s.limitsEnd, s.argEnd), arg,
          reason: '「$tex」参数应为 `$arg`，实际 $s');
    }

    test(r'★ `\sin x\cdot y` → 参数只有 `x`（显式乘号 = 主运算 = 断点）', () {
      final OpScope s = _op(r'\sin x\cdot y', 'sin');
      expect(r'\sin x\cdot y'.substring(s.start, s.end), r'\sin x');
    });

    test(r'★ `\sin x\cos y` → 两个对象（并置的算子型整体 = 相乘，不是嵌套）', () {
      final List<OpScope> ss = operatorScopes(r'\sin x\cos y');
      expect(ss.length, 2, reason: '$ss');
      expect(ss[0].command, 'sin');
      expect(ss[1].command, 'cos');
      expect(r'\sin x\cos y'.substring(ss[0].start, ss[0].end), r'\sin x');
      expect(r'\sin x\cos y'.substring(ss[1].start, ss[1].end), r'\cos y');
    });

    test(r'`\sin 2x` → 参数 `2x`（并置乘法是一个项）',
        () => expectArg(r'\sin 2x', 'sin', ' 2x'));
    test(r'`\sin x+y` → 参数 `x`（不含加减）',
        () => expectArg(r'\sin x+y', 'sin', ' x'));
    test(r'`\sin(x+y)` → 参数 `(x+y)`（括号 = 显式声明）',
        () => expectArg(r'\sin(x+y)', 'sin', '(x+y)'));
    test(r'`\sin\left(x+y\right)` → 参数是整个 `\left…\right`', () {
      final OpScope s = _op(r'\sin\left(x+y\right)', 'sin');
      expect(r'\sin\left(x+y\right)'.substring(s.limitsEnd, s.argEnd),
          r'\left(x+y\right)');
    });
    test(r'`\sin\log x` → 参数是嵌套的 `\log x`（同时 `\log` 自己也有作用域）', () {
      expectArg(r'\sin\log x', 'sin', r'\log x');
      expectArg(r'\sin\log x', 'log', ' x');
    });
    test(r'`\sin^2 x` → `^2` 归算子，参数是 `x`',
        () => expectArg(r'\sin^2 x', 'sin', ' x'));
    test(r'`\log_2 x` → `_2` 归算子（底数），参数是 `x`',
        () => expectArg(r'\log_2 x', 'log', ' x'));
    test(r'`\sum_{i=1}^{n}a_i b_i` → 参数 `a_i b_i`',
        () => expectArg(r'\sum_{i=1}^{n}a_i b_i', 'sum', 'a_i b_i'));
    test(r'`\int_a^b f(x)\,dx` → 参数 `f(x)\,dx`（`\,` 是间距，不破）',
        () => expectArg(r'\int_a^b f(x)\,dx', 'int', r' f(x)\,dx'));
    test(r'`\int_a^b f(x)\,dx+c` → 到 `+` 为止',
        () => expectArg(r'\int_a^b f(x)\,dx+c', 'int', r' f(x)\,dx'));
    test(r'`\lim_{x\to0}\frac{\sin x}{x}` → 参数是那个分式（里面的 `\to` 在花括号里，不破外层）', () {
      final OpScope s = _op(r'\lim_{x\to0}\frac{\sin x}{x}', 'lim');
      expect(r'\lim_{x\to0}\frac{\sin x}{x}'.substring(s.limitsEnd, s.argEnd),
          r'\frac{\sin x}{x}');
    });
    test(r'`\gcd(a,b)` → 参数 `(a,b)`（括号里的 `,` 不外溢）',
        () => expectArg(r'\gcd(a,b)', 'gcd', '(a,b)'));
    test(r'`2\sin x` → 只有 `\sin x` 是操作对象（`2` 不进来）', () {
      final OpScope s = _op(r'2\sin x', 'sin');
      expect(s.start, 1, reason: '从 `\\sin` 起');
      expect(r'2\sin x'.substring(s.start, s.end), r'\sin x');
    });
    test(r'`\sin` 后面没值 → `hasArg == false`，作用域就是算子自己', () {
      final OpScope s = _op(r'\sin', 'sin');
      expect(s.hasArg, isFalse);
      expect(s.argEnd, s.limitsEnd);
      expect(s.start, 0);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 二、§4.7.3 不变量（全域断言，不逐例抽查）
  // ─────────────────────────────────────────────────────────────
  group('§4.7.3 不变量 P1–P6', () {
    const List<String> corpus = <String>[
      r'\sin x',
      r'\sin 2x',
      r'\sin x+y',
      r'\sin(x+y)',
      r'\sin x\cos y',
      r'\sin^2 x+\cos^2 x',
      r'\sin\log x',
      r'2\sin x\cos y',
      r'\log_2 x',
      r'\sum_{i=1}^{n}a_i b_i',
      r'\sum_{i=1}^{n}\frac{a_i}{b_i}',
      r'\int_a^b f(x)\,dx',
      r'\int f(x)\,dx',
      r'\lim_{x\to0}\frac{\sin x}{x}',
      r'\gcd(a,b)=1',
      r'\sin',
      r'\frac{\sin x}{x}+\cos y',
      r'\sin(\alpha+\beta)\cos(\alpha-\beta)',
      r'\sin\left(x+y\right)',
    ];

    test('P1 每个算子实例**恰好一个**作用域，且起点确实是那个命令名', () {
      for (final String tex in corpus) {
        final Set<int> starts = <int>{};
        for (final OpScope s in operatorScopes(tex)) {
          expect(starts.add(s.start), isTrue, reason: '「$tex」有重复起点：$s');
          expect(tex.substring(s.start), startsWith('\\${s.command}'),
              reason: '「$tex」$s');
        }
      }
    });

    test('P2 作用域内**不含同层的**二元 / 关系 / 分隔记号', () {
      const Set<String> binLike = <String>{
        r'\pm', r'\mp', r'\cdot', r'\times', r'\div', r'\ast',
      };
      for (final String tex in corpus) {
        for (final OpScope s in operatorScopes(tex)) {
          final String arg = tex.substring(s.limitsEnd, s.argEnd);
          var depth = 0;
          for (var i = 0; i < arg.length; i++) {
            final String c = arg[i];
            if (c == '{' || c == '(' || c == '[') depth++;
            if (c == '}' || c == ')' || c == ']') depth--;
            if (depth != 0) continue;
            if (c == r'\') {
              // 跳过 `\cmd` 或 `\,` 这类单字符转义（间距命令是**黏结**的）
              var j = i + 1;
              if (j < arg.length && RegExp(r'[A-Za-z]').hasMatch(arg[j])) {
                while (j < arg.length && RegExp(r'[A-Za-z]').hasMatch(arg[j])) {
                  j++;
                }
              } else {
                j++;
              }
              final String tok = arg.substring(i, j);
              expect(binLike.contains(tok), isFalse,
                  reason: '「$tex」$s 的参数里出现了 $tok（应当在此断开）：`$arg`');
              i = j - 1;
              continue;
            }
            expect('+-*/=<>,;'.contains(c), isFalse,
                reason: '「$tex」$s 的参数里出现了 `$c`（应当在此断开）：`$arg`');
          }
        }
      }
    });

    test(r'P3 有值时参数里**至少一个**可见原子（"无值"单列）', () {
      for (final String tex in corpus) {
        for (final OpScope s in operatorScopes(tex)) {
          if (!s.hasArg) continue;
          final int n = lexVisibleAtoms(tex)
              .where((VisibleAtom a) =>
                  a.start >= s.limitsEnd && a.end <= s.argEnd)
              .length;
          expect(n, greaterThan(0), reason: '「$tex」$s');
        }
      }
    });

    test('P4 同层作用域**要么不相交、要么严格包含**（嵌套）', () {
      for (final String tex in corpus) {
        final List<OpScope> ss = operatorScopes(tex);
        for (var i = 0; i < ss.length; i++) {
          for (var j = i + 1; j < ss.length; j++) {
            final OpScope a = ss[i], b = ss[j];
            if (a.start == b.start) continue; // 同一个（P1 已守）
            final bool disjoint = a.end <= b.start || b.end <= a.start;
            final bool nested = (a.start <= b.start && b.end <= a.end) ||
                (b.start <= a.start && a.end <= b.end);
            expect(disjoint || nested, isTrue,
                reason: '「$tex」作用域相交：$a 与 $b');
          }
        }
      }
    });

    test('P5 不跨层级边界（整个作用域仍在**它所在那个区域**里）', () {
      for (final String tex in corpus) {
        final CaretSiteTable t = buildCaretSites(tex);
        for (final OpScope s in operatorScopes(tex)) {
          if (!s.hasArg) continue;
          final TexRegion? reg = innermostRegionAt(t, s.start);
          expect(reg, isNotNull, reason: '「$tex」$s');
          expect(s.start, greaterThanOrEqualTo(reg!.start), reason: '「$tex」$s');
          expect(s.end, lessThanOrEqualTo(reg.end),
              reason: '「$tex」$s 越出了所在区域 [${reg.start},${reg.end})');
        }
      }
    });

    test('P6 上下限只吃**紧跟算子名**的 `^`/`_`', () {
      for (final String tex in corpus) {
        for (final OpScope s in operatorScopes(tex)) {
          final int opEnd = s.opStart + 1 + s.command.length;
          final String between = tex.substring(opEnd, s.limitsEnd);
          expect(
              between.isEmpty ||
                  between.startsWith('^') ||
                  between.startsWith('_'),
              isTrue,
              reason: '「$tex」$s 的上下限区间是 `$between`（只该是 `^`/`_` 开头的脚本）');
        }
      }
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 三、给删除侧用的两个查询（§4.0「算子 + 作用域 = 一个对象」）
  // ─────────────────────────────────────────────────────────────
  group('§4.0 用法：作用域端点 → 整个操作对象', () {
    test(r'`\sin 2x` 末尾 → 整个 `\sin 2x`', () {
      final OpScope? s = scopeEndingAt(r'\sin 2x', r'\sin 2x'.length);
      expect(s, isNotNull);
      expect(s!.command, 'sin');
      expect(r'\sin 2x'.substring(s.start, s.end), r'\sin 2x');
    });

    test(r'`\sin 2x+y` 里 `2x` 之后（作用域末尾）也算它的右端', () {
      final OpScope? s = scopeEndingAt(r'\sin 2x+y', 7);
      expect(s, isNotNull, reason: '7 = `2x` 之后');
      expect(s!.command, 'sin');
    });

    test(r'嵌套：`\sin\log x` 末尾取**最外层**（最长）那个', () {
      final OpScope? s = scopeEndingAt(r'\sin\log x', r'\sin\log x'.length);
      expect(s, isNotNull);
      expect(s!.command, 'sin');
      expect(s.end - s.start, r'\sin\log x'.length);
    });

    test(r'无值算子**不算**（删的是算子自己，不是"整个作用域"）', () {
      expect(scopeEndingAt(r'\sin', 4), isNull);
    });

    test(r'`Delete` 方向：作用域**起点** → 整个操作对象', () {
      final OpScope? s = scopeStartingAt(r'2\sin x', 1);
      expect(s, isNotNull);
      expect(r'2\sin x'.substring(s!.start, s.end), r'\sin x');
    });
  });
}
