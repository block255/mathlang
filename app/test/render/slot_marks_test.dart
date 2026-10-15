// 空槽可视化测试（S3-5 · §6.1）
//
// 状态（2026-10-15）：**已接进渲染**，注入链的唯一入口是 `slot_marks.renderMathTex`
//   （`InlineMathText` 的行内公式与 `DocView` 的行间公式都走它）。
//
// ★ 两条关键不变量（都与点击定位的"叶盒数 == 可见原子数"绑在一起）：
//   1. 占位字形必须是**一个正常字形**（`\square`：1 原子 ↔ 1 叶盒），不能用 `\rule` 那种
//      "词法上是结构命令、引擎却照样给盒"的东西
//   2. 注入后**原子数的增量恰好等于空槽数**（不多不少）

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/slot_marks.dart';
import 'package:mathlang/render/visible_atoms.dart';

void main() {
  group('占位串的选取', () {
    test(r'占位用 `\square`：它天然"1 个可见原子 ↔ 引擎 1 个叶盒"', () {
      expect(kEmptySlotTex.contains(r'\square'), isTrue);
      expect(lexVisibleAtoms(kEmptySlotTex).length, 1,
          reason: '颜色名已被 visible_atoms 跳过 → 只剩 \\square 这一个原子，与叶盒一一对应');
      expect(lexVisibleAtoms(kCurrentSlotTex).length, 1);
    });

    test('当前槽用光标蓝，普通空槽用浅灰', () {
      expect(kCurrentSlotTex.contains('#1E88E5'), isTrue);
      expect(kEmptySlotTex.contains('#B0BEC5'), isTrue);
    });
  });

  group('注入范围：只给空槽、非空槽不画', () {
    test(r'\frac{}{} 两个空槽 → 注入两处', () {
      final SlotMarkResult r = injectSlotMarks(r'\frac{}{}', caretRel: 0);
      expect(kEmptySlotTex.allMatches(r.tex).length, 2);
    });

    test(r'\frac{a}{} 只有分母空 → 只注入一处', () {
      final SlotMarkResult r = injectSlotMarks(r'\frac{a}{}', caretRel: 6);
      expect(kEmptySlotTex.allMatches(r.tex).length, 1);
    });

    test(r'\frac{a}{b} 没有空槽 → 原样返回', () {
      final SlotMarkResult r = injectSlotMarks(r'\frac{a}{b}', caretRel: 6);
      expect(r.tex, r'\frac{a}{b}');
    });

    test('降级表里什么都不做（结构不可靠就别乱画）', () {
      final SlotMarkResult r = injectSlotMarks(r'a}b', caretRel: 1);
      expect(r.tex, r'a}b');
      expect(r.rel, 1);
    });

    test('★ 光标不在这一段（caretRel < 0）→ 照样画空槽，只是没有"当前槽"高亮', () {
      // ★ 2026-10-15 改：这里原先是"**一个都不画**"，理由是"注入会让点击定位失效"
      //   （`hitTestMathTex` 要求叶盒数 == 原子数，数量不等就静默返回 null）。
      //   那个根因当天晚些时候就被根治了（命中改用 `renderTex` + `renderToSourceOffset`），
      //   而这条临时措施留了下来 —— 后果是**用户粘贴 `$\frac{}{}$` 后什么都看不见**：
      //   光标恰好停在闭合 `$` 之后那一格，被判"不在这段里"→ 不注入 → 空分数只有 3.4px 宽。
      //   规格 §6.1 从来没有"只在光标处画占位"这条附加条件：**空槽就该一直看得见**。
      final SlotMarkResult r = injectSlotMarks(r'\frac{}{}', caretRel: -1);
      expect(kEmptySlotTex.allMatches(r.tex).length, 2, reason: '两个空槽都要画');
      expect(kCurrentSlotTex.allMatches(r.tex).length, 0,
          reason: '光标不在里面 → 没有"当前槽"');
      expect(injectSlotMarks(r'\frac{a}{}', caretRel: -1).tex, isNot(r'\frac{a}{}'),
          reason: '分母是空槽 → 必须注入');
      expect(injectSlotMarks(r'\frac{a}{b}', caretRel: -1).tex, r'\frac{a}{b}',
          reason: '一个空槽都没有 → 仍然原样返回');
      expect(injectSlotMarks(r'a}b', caretRel: -1).tex, r'a}b',
          reason: '降级表里同样什么都不做');
    });
  });

  group('当前槽高亮', () {
    test(r'\frac{}{} 光标在分母（偏移 8）→ 分母用当前槽样式', () {
      final SlotMarkResult r = injectSlotMarks(r'\frac{}{}', caretRel: 8);
      expect(kCurrentSlotTex.allMatches(r.tex).length, 1);
      expect(kEmptySlotTex.allMatches(r.tex).length, 1, reason: '分子仍是普通空槽');
    });

    test('注入后光标偏移按插入量右移（否则接着注入光标会错位）', () {
      final SlotMarkResult r = injectSlotMarks(r'\frac{a}{}', caretRel: 10);
      expect(r.rel, 10 + kEmptySlotTex.length);
    });
  });

  group('★ 真正的不变量：注入后"可见原子数"的增量 == 空槽数', () {
    // 点击定位要求「我们的可见原子数 == 引擎叶盒数」。占位是**一个正常字形**（1↔1），
    // 所以原子数会随空槽数一起增加 —— 要守的是"**增量恰好等于空槽数**"（不多不少）。
    for (final String tex in <String>[
      r'\frac{}{}',
      r'\frac{a}{}',
      r'\sqrt{}',
      r'\frac{a}{b}',
      r'\frac{-b\pm\sqrt{b^2-4ac}}{2a}',
    ]) {
      test('tex = $tex', () {
        final SlotMarkResult r = injectSlotMarks(tex, caretRel: 0);
        final int before = lexVisibleAtoms(tex).length;
        final int after = lexVisibleAtoms(r.tex).length;
        final int empties = RegExp(RegExp.escape(kEmptySlotTex))
            .allMatches(r.tex)
            .length;
        expect(after, before + empties,
            reason: '每个空槽恰好 +1 个原子（占位字形）；多一个少一个都会让点击定位错位');
      });
    }

    test('同时注入光标后**原子数不变**（零尺寸锚点 0 个原子）', () {
      const String tex = r'\frac{a}{}';
      final SlotMarkResult m = injectSlotMarks(tex, caretRel: 6);
      final String withCursor = injectCursor(m.tex, m.rel).tex;
      expect(lexVisibleAtoms(withCursor).length, lexVisibleAtoms(tex).length + 1,
          reason: '只有**空槽占位**那 1 个原子；光标是零尺寸锚点（`\\rule{0pt}{0pt}`）'
              '—— 词法 0 个原子、渲染 0×0 盒子（2026-10-15 晚改）');
    });
  });
}
