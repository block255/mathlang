// 注入链唯一入口 `renderMathTex` 的回归测试（2026-10-15）
//
// 这一条链原先散在两个 widget 里各写一遍（`InlineMathText._mathSpan` 与 `DocView`
// 的行间公式分支），而且"到底注了什么"只能靠猜 `Math` 内部的 ast —— 连探针都难写。
// 收成纯函数之后，注入结果**可以直接断言**（不必真渲染）。
//
// ★★ 本文件守的是用户那次实测的正面回归：
//   「粘贴 `$\frac{}{}$` 进去直接消失了」（公式与光标一起消失）。
//   两个成因——"空槽只在光标处才画" + "光标那一格没人认领"——各有一条测试钉着。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/caret_sites.dart';
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
      expect(out, contains(kCursorTex),
          reason: '★ 光标也必须在（原先它和占位一起被判"不在这段里"而消失）'
              '—— 2026-10-15 晚起它是**零尺寸锚点**（`\\rule{0pt}{0pt}`）');
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
      expect(withCaret, contains(kCursorTex),
          reason: '光标确实在这一段里 → 必须画出来（"有没有空槽"与"光标在不在"是两件事）');
    });

    test('降级表（结构不可靠）→ 什么都不做，绝不乱画', () {
      expect(renderMathTex('a}b', caretRel: -1), 'a}b');
    });
  });

  group('★ 守门人：注入后"可见原子数"的增量必须精确（点击定位靠它）', () {
    // 点击定位的不变量是「我们的可见原子数 == 引擎的叶盒数」。
    // 所以注入只能"**每处恰好 +2**"：垫子（字形 ＋ 零高宽度垫）2 个叶盒 ↔ 2 个原子；
    // 光标是零尺寸锚点 ⇒ 0。
    int padCount(String t) =>
        kEmptySlotTex.allMatches(t).length + kCurrentSlotTex.allMatches(t).length;
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
        final int pads = padCount(noCaret);
        expect(lexVisibleAtoms(noCaret).length, base + 2 * pads,
            reason: '每个空槽垫子各 +2 个原子（字形 1 + 宽度垫 1）');

        final String withCaret = renderMathTex(tex, caretRel: 0);
        expect(lexVisibleAtoms(withCaret).length, base + 2 * padCount(withCaret),
            reason: '★ 光标**不再**贡献原子（零尺寸锚点，2026-10-15 晚改）—— '
                '注入后原子数只随空槽垫子变（每个 +2）');
      });
    }
  });

  // ─────────────────────────────────────────────────────────────
  // ★★ 空公式必须画出来（设计稿 §6.1.1，2026-10-15）
  //
  // §4.6 决定"在公式内删到空 → **留空壳**"（有撤回、能接着重打）。
  // 但空 `tex` 原先渲染成**零尺寸** —— 看不见也点不到，成了幽灵
  // （用户实测："按了没反应"，只能再按一次退格清掉）。
  // ⇒ **"留空壳"与"画出来"是一对，不能只做一半。**
  // ─────────────────────────────────────────────────────────────
  group('★ 空公式必须画出来（§6.1.1）', () {
    test('tex 空 / 全白 / 只有换行 → 渲染占位字形（不是空串）', () {
      for (final String empty in <String>['', '   ', '\n', ' \n ']) {
        expect(renderMathTex(empty, caretRel: -1), contains(kSlotPadGlyph),
            reason: 'tex=「$empty」时必须画占位，否则空公式是零尺寸的幽灵'
                '（占位字形 = `$kSlotPadGlyph`；为什么挑它见 slot_pad.dart 的字形表）');
      }
    });

    test('光标在空公式里 → 占位 + 锚点（否则用户不知道停在哪）', () {
      final String out = renderMathTex('', caretRel: 0);
      expect(out, contains(kSlotPadGlyph));
      expect(out, contains(kCursorTex),
          reason: '★ 2026-10-15 晚起光标是**零尺寸锚点**（竖条由 MathWithCaret 自绘上去）');
    });

    test('★ 只兜空公式：非空公式不受影响', () {
      expect(renderMathTex('x', caretRel: -1), isNot(contains(kSlotPadGlyph)));
      expect(renderMathTex(r'\frac{a}{b}', caretRel: -1),
          isNot(contains(kSlotPadGlyph)));
    });

    testWidgets('★ 空公式渲染出来必须有非零宽度（这是"看得见"的客观判据）',
        (WidgetTester t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(child: Math.tex(renderMathTex('', caretRel: -1))),
        ),
      ));
      await t.pump();
      expect(find.textContaining('❌'), findsNothing,
          reason: '占位字形必须是引擎认得的（与空槽占位同一套）');
      expect(t.getSize(find.byType(Math)).width, greaterThan(5),
          reason: '★ 空公式原先渲染成零尺寸 —— 看不见也点不到，只能再按一次退格清掉');
    });
  });
}
