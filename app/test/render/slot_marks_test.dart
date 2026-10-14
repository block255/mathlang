// 空槽可视化测试（S3-5 · §6.1）
//
// ⚠️ **本模块已写好但暂时没有接进渲染**：注入占位会虚增"可见原子"，而点击定位
//   靠"叶盒 ↔ 可见原子"一一对应 → 数量不等时 `hitTestMathTex` 会**静默返回 null**。
//   要接上必须先修 `visible_atoms.dart`：跳过**不参与渲染的参数**
//   （`\textcolor`/`\color` 的颜色名、`\rule`/`\hspace`/`\kern` 的尺寸）。
//   ★ 那条修法同时也修掉**现存**的 `\cursor{}` 注入问题（它现在就在虚增原子）。
//   见交接快照 §十二。

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
      final SlotMarkResult r = injectSlotMarks(r'\frac{}{}', caretRel: -1);
      expect(kEmptySlotTex.allMatches(r.tex).length, 2);
    });

    test(r'\frac{a}{} 只有分母空 → 只注入一处', () {
      final SlotMarkResult r = injectSlotMarks(r'\frac{a}{}', caretRel: -1);
      expect(kEmptySlotTex.allMatches(r.tex).length, 1);
    });

    test(r'\frac{a}{b} 没有空槽 → 原样返回', () {
      final SlotMarkResult r = injectSlotMarks(r'\frac{a}{b}', caretRel: -1);
      expect(r.tex, r'\frac{a}{b}');
    });

    test('降级表里什么都不做（结构不可靠就别乱画）', () {
      final SlotMarkResult r = injectSlotMarks(r'a}b', caretRel: 1);
      expect(r.tex, r'a}b');
      expect(r.rel, 1);
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
        final SlotMarkResult r = injectSlotMarks(tex, caretRel: -1);
        final int before = lexVisibleAtoms(tex).length;
        final int after = lexVisibleAtoms(r.tex).length;
        final int empties = RegExp(RegExp.escape(kEmptySlotTex))
            .allMatches(r.tex)
            .length;
        expect(after, before + empties,
            reason: '每个空槽恰好 +1 个原子（占位字形）；多一个少一个都会让点击定位错位');
      });
    }

    test('同时注入光标后也是"每处 +1"（光标条 1 个原子）', () {
      const String tex = r'\frac{a}{}';
      final SlotMarkResult m = injectSlotMarks(tex, caretRel: 6);
      final String withCursor = injectCursor(m.tex, m.rel).tex;
      expect(lexVisibleAtoms(withCursor).length, lexVisibleAtoms(tex).length + 2,
          reason: '1 个空槽占位 + 1 个光标条');
    });
  });
}
