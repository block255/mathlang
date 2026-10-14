// 空槽可视化测试（S3-5 · §6.1）
//
// ⚠️ **本模块已写好但暂时没有接进渲染**：注入占位会虚增"可见原子"，而点击定位
//   靠"叶盒 ↔ 可见原子"一一对应 → 数量不等时 `hitTestMathTex` 会**静默返回 null**。
//   要接上必须先修 `visible_atoms.dart`：跳过**不参与渲染的参数**
//   （`\textcolor`/`\color` 的颜色名、`\rule`/`\hspace`/`\kern` 的尺寸）。
//   ★ 那条修法同时也修掉**现存**的 `\cursor{}` 注入问题（它现在就在虚增原子）。
//   见交接快照 §十二。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/slot_marks.dart';
import 'package:mathlang/render/visible_atoms.dart';

void main() {
  group('占位串的选取', () {
    test(r'占位用 `\rule`（结构命令），不是 `\square`（那是可见原子）', () {
      expect(kEmptySlotTex.contains(r'\rule'), isTrue);
      expect(kEmptySlotTex.contains(r'\square'), isFalse);
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

  group('★ 接进渲染的前置条件（当前**未满足**，所以还没接）', () {
    test('注入前后可见原子数必须一致', () {
      final SlotMarkResult r = injectSlotMarks(r'\frac{}{}', caretRel: -1);
      expect(lexVisibleAtoms(r.tex).length, lexVisibleAtoms(r'\frac{}{}').length,
          reason: '★ 数量不等 → hitTestMathTex 静默返回 null（点公式失效且不报错）');
    }, skip: '占位串里的颜色名 `#B0BEC5` 被词法器当成可见原子 —— '
        '要先修 visible_atoms.dart：跳过不参与渲染的参数。'
        '同一条修法也会修掉现存的 `\\cursor{}` 注入问题。');
  });
}
