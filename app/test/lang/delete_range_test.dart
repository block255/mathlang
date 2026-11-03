// ★★ 2026-11-03（围栏不参与选区）：**删除**的单元判据。
//
// 口径（讨论定稿 §3.3 / §7.3）：
//   · 查剩余：删完结构成立就照删；不成立才扩到最小单位；
//   · `$` 是零宽记账：删可见字符、`$` 留下；内容空了再回收
//     （行间块只剩空白算空；行内只剩空白**不算**空）；
//   · 跨段时不是"删一段"，而是"抹掉可见字符、其余保留"，压成一次替换。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/delete_range.dart';

String _after(String doc, int s, int e) {
  final DeletePlan p = planDelete(doc, s, e);
  return doc.replaceRange(p.from, p.to, p.replacement);
}

String _clip(String doc, int s, int e) => planDelete(doc, s, e).clipboardText;

void main() {
  group('① 脚本：删底要连脚本，删脚本要连标记', () {
    const String doc = r'$a^2$';
    test(r'删 `a` ⇒ 整个 `a^2` 走（剩 `^2` 不成立）', () {
      expect(_after(doc, 1, 2), '');
    });
    test(r'删 `2` ⇒ 连 `^` 一起走（剩 `a^` 不成立）', () {
      expect(_after(doc, 3, 4), r'$a$');
    });
  });

  group('② 分式：删参数内容留空槽；删参数组才动命令', () {
    const String doc = r'$\frac{a}{b}$';
    test(r'删分子内容 `a` ⇒ `\frac{}{b}`（空槽合法）', () {
      expect(_after(doc, 7, 8), r'$\frac{}{b}$');
    });
    test(r'删分母内容 `b` ⇒ `\frac{a}{}`', () {
      expect(_after(doc, 10, 11), r'$\frac{a}{}$');
    });
    test(r'删整个分子组 `{a}` ⇒ 连 `\frac` 一起走（留 `{b}` 合法）', () {
      expect(_after(doc, 6, 9), r'${b}$');
    });
  });

  group('③ 根号：删次数留空 `[]`；删 `\\sqrt[x` 要连 `]` 一起走', () {
    const String doc = r'$\sqrt[x]{a}$';
    test(r'删 `x` ⇒ `\sqrt[]{a}`（合法）', () {
      expect(_after(doc, 7, 8), r'$\sqrt[]{a}$');
    });
    test(r'删 `\sqrt[x` ⇒ 连同孤立的 `]` ⇒ `{a}`', () {
      expect(_after(doc, 1, 8), r'${a}$');
    });
  });

  group('④ 环境：删格内容留空环境；围栏不动', () {
    const String doc = '\$\$\n\\begin{cases}x=1\\\\y=2\\end{cases}\n\$\$';
    test('删一格 ⇒ 环境留着、`\\\\` 留着（结构不是空）', () {
      final int s = doc.indexOf('x=1');
      expect(_after(doc, s, s + 3), '\$\$\n\\begin{cases}\\\\y=2\\end{cases}\n\$\$');
    });
    test('删**全部格** ⇒ 按整表删（连壳），围栏按 §七 回收', () {
      // ★ 2026-11-03（表批）口径：覆盖所有格 ⇒ 整表；这也是"删掉一张表"的唯一入口。
      final int s = doc.indexOf('x=1');
      final int e = doc.indexOf('y=2') + 3;
      expect(_after(doc, s, e), '');
    });
  });

  group(r'⑤ 跨段：`$` 留下，只抹可见字符', () {
    // 用户 T5 的尾巴：两段公式 + 中间的 `-` + 末尾 `)`
    const String doc =
        r'=$\lim_{t\to+\infty}(\frac{\alpha sint}{t^{\alpha-1}}$-$\frac{cost}{t^{\alpha-2}}$)';
    test('从两个分式里选 ⇒ 只抹分式，`\\lim(` 与 `)` 留下', () {
      final int s = doc.indexOf(r'\alpha sint');
      final int e = doc.indexOf('cost') + 2;
      final String after = _after(doc, s, e);
      expect(after.contains(r'\lim'), isTrue, reason: after);
      expect(after.contains(r'\frac'), isFalse, reason: after);
      expect(after.endsWith(')'), isTrue, reason: after);
    });
  });

  group('⑥ 剪切文本 = 实际删掉的可见内容（按 §七 编码）', () {
    test(r'段内 ⇒ 数学 run 包 `$…$`', () {
      expect(_clip(r'$a^2$', 1, 2), r'$a^2$');
    });
    test('纯文字 ⇒ 原样', () {
      expect(_clip(r'前文$x$后', 0, 2), '前文');
    });
    test(r'跨段 ⇒ 每段数学各自包 `$`，中间文字原样', () {
      const String doc = r'$a$-$b$';
      expect(_clip(doc, 1, 6), r'$a$-$b$');
    });
  });
}
