// 注入链唯一入口 `renderMathTex` 的回归测试（2026-10-15）
//
// 这一条链原先散在两个 widget 里各写一遍（`InlineMathText._mathSpan` 与 `DocView`
// 的行间公式分支），而且"到底注了什么"只能靠猜 `Math` 内部的 ast —— 连探针都难写。
// 收成纯函数之后，注入结果**可以直接断言**（不必真渲染）。
//
// ★★ 本文件守的是用户那次实测的正面回归：
//   「粘贴 `$\frac{}{}$` 进去直接消失了」（公式与光标一起消失）。
//   两个成因——"空槽只在光标处才画" + "光标那一格没人认领"——各有一条测试钉着。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/slot_marks.dart';
import 'package:mathlang/render/visible_atoms.dart';

void main() {
  group('★ 空槽必须一直看得见（不管光标在不在这一段里）', () {
    test('caretRel < 0（光标不在这一段）→ 照样注入占位，但不注光标', () {
      final String out = renderMathTex(r'\frac{}{}', caretRel: -1);
      expect(kEmptySlotTex.allMatches(out).length, 2,
          reason: '规格 §6.1：空槽就该看得见 —— 没有"只在光标处画"这条附加条件');
      expect(out, isNot(contains(r'\cursor')), reason: '光标不在这段里，不该画光标');
    });

    test('★ 事故正身：光标停在 **tex 末尾**（= 粘贴后"闭合 \$ 之后那一格"）', () {
      const String tex = r'\frac{}{}';
      final String out = renderMathTex(tex, caretRel: tex.length);
      expect(kEmptySlotTex.allMatches(out).length, 2,
          reason: '★ 这一条就是"粘贴进去消失了"的正面回归 —— '
              '空分数不注入占位只有 3.4 × 10.3 px（实测），肉眼等于没有');
      expect(out, contains(r'\cursor'),
          reason: '★ 光标也必须在（原先它和占位一起被判"不在这段里"而消失）');
    });

    test('光标在空槽里 → 那个槽用"当前槽"样式（蓝），别的槽仍是浅灰', () {
      // `\frac{}{}` = \frac{ } { }：分子槽内容起点 = 6，分母 = 8
      final String inNum = renderMathTex(r'\frac{}{}', caretRel: 6);
      expect(kCurrentSlotTex.allMatches(inNum).length, 1);
      expect(kEmptySlotTex.allMatches(inNum).length, 1, reason: '分母仍是普通空槽');

      final String inDen = renderMathTex(r'\frac{}{}', caretRel: 8);
      expect(kCurrentSlotTex.allMatches(inDen).length, 1);
      expect(kEmptySlotTex.allMatches(inDen).length, 1, reason: '分子仍是普通空槽');
    });

    test('一个空槽都没有 → 不注占位；但光标在这一段里时仍然要注光标', () {
      expect(renderMathTex(r'\frac{a}{b}', caretRel: -1), r'\frac{a}{b}',
          reason: '没有空槽 + 光标不在这段 → 原样返回，一个字节都不加');
      final String withCaret = renderMathTex(r'\frac{a}{b}', caretRel: 3);
      expect(kEmptySlotTex.allMatches(withCaret).length, 0, reason: '没有空槽');
      expect(kCurrentSlotTex.allMatches(withCaret).length, 0);
      expect(withCaret, contains(r'\cursor'),
          reason: '光标确实在这一段里 → 必须画出来（"有没有空槽"与"光标在不在"是两件事）');
    });

    test('降级表（结构不可靠）→ 什么都不做，绝不乱画', () {
      expect(renderMathTex('a}b', caretRel: -1), 'a}b');
    });
  });

  group('★ 守门人：注入后"可见原子数"的增量必须精确（点击定位靠它）', () {
    // 点击定位的不变量是「我们的可见原子数 == 引擎的叶盒数」。
    // 所以注入只能"**每处恰好 +1**"：占位 1 个原子，光标 1 个原子。
    for (final String tex in <String>[
      r'\frac{}{}',
      r'\frac{a}{}',
      r'\sqrt{}',
      r'\frac{}{}\sqrt{}',
      r'\frac{-b\pm\sqrt{b^2-4ac}}{2a}',
    ]) {
      test('tex = $tex', () {
        final int base = lexVisibleAtoms(tex).length;
        final String noCaret = renderMathTex(tex, caretRel: -1);
        final int empties = kEmptySlotTex.allMatches(noCaret).length;
        expect(lexVisibleAtoms(noCaret).length, base + empties,
            reason: '空槽占位各 +1 个原子');

        final String withCaret = renderMathTex(tex, caretRel: 0);
        final int empties2 = kEmptySlotTex.allMatches(withCaret).length +
            kCurrentSlotTex.allMatches(withCaret).length;
        expect(lexVisibleAtoms(withCaret).length, base + empties2 + 1,
            reason: '再 +1 = 光标条那一个原子');
      });
    }
  });
}
