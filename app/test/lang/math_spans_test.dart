// 数语引擎 · 数学段扫描（`lang/math_spans.dart`）守卫
//
// 它是**诊断清单**的数据源：要说清"编辑器替你补了哪几处 `$…$`"，就得先把成对的定界符找出来。
// 判据（全部可证）：
//   ① 成对才产出；落单的 `$` **跳过**而不是整段放弃（后面可能还有成对的）；
//   ② `\$`（转义）不是定界符；
//   ③ 行间 `$$…$$` 优先于行内 `$…$`（同一位置先看两个）；
//   ④ 区间含定界符本体（`[start, end)`），`tex` 只放定界符之间。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/math_spans.dart';

void main() {
  test('行内：两处都找到，区间与 tex 正确', () {
    final List<MathSpan> s = scanMathSpans(r'设 $x^2$ 与 $\frac{1}{2}$ 都是公式');
    expect(s.length, 2);
    expect(s[0].tex, 'x^2');
    expect(s[0].display, isFalse);
    expect(s[0].start, 2);
    expect(s[0].end, 7, reason: r'$x^2$ 占 5 格');
    expect(s[1].tex, r'\frac{1}{2}');
    expect(r'设 $x^2$ 与 $\frac{1}{2}$ 都是公式'.substring(s[1].start, s[1].end),
        r'$\frac{1}{2}$');
  });

  test(r'行间：`$$…$$` 整块（含换行）', () {
    final List<MathSpan> s = scanMathSpans('\$\$\nx=1\n\$\$');
    expect(s.length, 1);
    expect(s.single.display, isTrue);
    expect(s.single.start, 0);
    expect(s.single.end, 9);
    expect(s.single.tex, '\nx=1\n');
  });

  test(r'转义 \$ 不算定界符', () {
    expect(scanMathSpans(r'价格 \$5 不是公式'), isEmpty);
    expect(scanMathSpans(r'\$5 与 $x$').length, 1);
    expect(scanMathSpans(r'\$5 与 $x$').single.tex, 'x');
  });

  test(r'单数个 `$`：未成对的跳过，成对的照常找到', () {
    expect(scanMathSpans(r'孤立的 $ 没有收尾'), isEmpty,
        reason: '只有一个 ⇒ 没有成对的');
    // 三个 `$` ⇒ 前两个配成一对（贪心从左配对，这是常规读法），第三个落单被跳过
    final List<MathSpan> s = scanMathSpans(r'一个$中间$还有$尾');
    expect(s.length, 1);
    expect(s.single.tex, '中间');
  });

  test(r'行内段里遇到 `$$` ⇒ 这一对没配上（不吞掉后面的行间块）', () {
    final List<MathSpan> s = scanMathSpans('\$a \$\$b\$\$');
    expect(s.length, 1);
    expect(s.single.display, isTrue);
    expect(s.single.tex, 'b');
  });

  test('summary 截断并压掉换行（清单里要一行显示）', () {
    final MathSpan long = scanMathSpans(
            r'$\frac{a+b+c+d+e+f+g+h+i+j+k+l+m+n+o+p}$')
        .single;
    expect(long.summary(max: 10).endsWith('…'), isTrue);
    final MathSpan multi = scanMathSpans('\$\$\na\nb\n\$\$').single;
    expect(multi.summary().contains('\n'), isFalse);
  });

  test(r'真实例子的形状：Z$\frac{}{}$ 只有一处，且从 $ 起算', () {
    const String doc = r'Z$\frac{}{}$';
    final MathSpan s = scanMathSpans(doc).single;
    expect(s.start, 1);
    expect(doc.substring(s.start, s.end), r'$\frac{}{}$');
  });
}
