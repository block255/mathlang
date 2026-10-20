// ★★★ 2026-10-20（T-C 实测 F13，导入真实作业 md 时抓到的）：**不该包的绝不包**。
//
// 现场：`test_data\homework20261014-answer.md` 导入后被智能包裹改坏两处 ——
//   · 行首引用标记 `> 素材：…` ⇒ `>` 被包成 `$>$`（引用块被破坏，页面上出现"数学盒子里的 >"）
//   · 行内代码 `` `test_data\homework20261014\` `` ⇒ 路径里的 `\` 被当成 LaTeX 命令包成 `$…$`
//     ⇒ KaTeX 报 `\h` 不认识 ⇒ 页面上红字 `[公式不完整]`
//
// 三条收紧（都朝"宁可少包"的方向，符合原则①）：
//   1. **行内代码 `` `…` `` 一律不碰**（里面是字面量：路径 / 命令名 / 文件名）；
//   2. **行首引用标记 `>` 像列表标记一样跳过**（跳完什么都不剩 ⇒ 这一行没有数学）；
//   3. **只有运算符的段不包**：除"有证据"外还必须**含字母/数字**（`>`、`<`、`+` 都不算数学段）。
//
// 反例同时钉住：真该包的（`a_n` / `x>0` / `\sin x` / `a_n = (-1)^n`）一个都不许漏。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/smart_wrap.dart';

void main() {
  group('★ F13-1 行内代码不碰', () {
    test('路径 `` `test_data\\homework20261014\\` `` ⇒ 一处都不包', () {
      const String src = r'> 素材：`test_data\homework20261014\` 六张手写稿。';
      final SmartWrapPlan p = planSmartWrap(src);
      expect(p.isEmpty, isTrue,
          reason: '被包的区间：$p ⇒ 路径里的 \\h 会让 KaTeX 报错（红字[公式不完整]）');
    });

    test('行内代码里的真 LaTeX 也是字面量 ⇒ 不包', () {
      const String src = r'写作 `\frac{a}{b}` 表示分式。';
      expect(planSmartWrap(src).isEmpty, isTrue);
    });

    test('★ 不误伤：代码后面的**真**数学照旧包', () {
      const String src = r'记 `x` 为变量，则 a_n 有界。';
      final String out = applySmartWrap(src, planSmartWrap(src));
      expect(out, r'记 `x` 为变量，则 $a_n$ 有界。');
    });
  });

  group('★ F13-2 引用标记不参与包裹', () {
    test('`> 素材：…` 整行 ⇒ 只有 `>` 时一处都不包', () {
      const String src = '> 素材：六张手写稿（第 1、4 题在此转写）。';
      expect(planSmartWrap(src).isEmpty, isTrue,
          reason: r'改前：`>` 被包成 `$>$`，引用块没了');
    });

    test('引用行里的数学部分**照旧**包（标记本身不包）', () {
      const String src = '> 注意 a_n 单调。';
      final String out = applySmartWrap(src, planSmartWrap(src));
      expect(out, r'> 注意 $a_n$ 单调。');
    });

    test('整行只有 `>` ⇒ 不包', () {
      expect(planSmartWrap('>').isEmpty, isTrue);
      expect(planSmartWrap('>> 引用').isEmpty, isTrue);
    });
  });

  group('★ F13-3 只有运算符的段不算数学', () {
    test('孤立的 `>` / `<` / `+` ⇒ 不包', () {
      for (final String s in <String>['a 大于 b >', '前 < 后', '甲 + 乙']) {
        expect(planSmartWrap(s).isEmpty, isTrue, reason: s);
      }
    });

    test('★ 不误伤：真公式一个都不许漏', () {
      const List<String> good = <String>[
        r'所以 a_n = (-1)^n 有界',
        r'当 x > 0 时成立',
        r'于是 \sin x 连续',
        r'取 \varepsilon > 0',
        r'$\frac{a}{b}$ 已经是数学',
      ];
      for (final String src in good) {
        final String out = applySmartWrap(src, planSmartWrap(src));
        // 已经有 `$…$` 的那句原样返回
        if (src.startsWith(r'$')) {
          expect(out, src, reason: src);
        } else {
          expect(out.contains(r'$'), isTrue, reason: '$src ⇒ $out');
        }
      }
    });
  });
}
