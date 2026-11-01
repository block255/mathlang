// ★★★ 2026-10-24（批 21）建立：**行间块的边界竖条归谁** —— 不许出现"两个光标"。
// ★★★ 2026-11-01 改写（口径变了，见 `notes/design/位点与结构导航.md` §6.5 与台账 F13/F14）：
//
// ## 改了什么
// 旧口径：块认领 `sliceStart - 1`（块**前面**那一格）＋ 一条"共享格让给左边那块"的特例
//        （`sharesLeftCell`）。
// 新口径：块只认 **它自己占的那一格起**（`acceptFrom = sliceStart` ＝ 自己的 `$$`），
//        于是相邻两块 A=[11,22] / B=[23,34] **不再重叠** ⇒ 特例整条删除。
//
// ## 为什么（三条现场都指向同一个病）
// 那一格在真实文档里只有三种身份，**没有一种该归本块**：
//   · 上一行文字的末尾 ⇒ 归那一行；
//   · 段落分隔符（`\n\n` 的第二个、零高度）⇒ **不是位置**，谁都不该画；
//   · 前一块自己最后一行的行尾 ⇒ 归前一块（`sharesLeftCell` 当年就是在补这一种）。
// 当初加它的理由是"与行内公式两端对称"，而那个对称不成立：
// 行内公式两端是**同一行里的字符间隙**（真实位置），行间块两端是**行 / 段的边界**。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/editor/doc_view.dart';

void main() {
  // 两个**紧贴**的行间块：A 认 [11, 22]，B 认 [23, 34]（A 的行尾是 22，B 的行首是 23）
  const int aFrom = 11;
  const int aTo = 22;
  const int bFrom = 23;
  const int bTo = 34;

  group('blockEdgeClaim（边界那两格）', () {
    test('★ 自己的行首 / 行尾各归本块，别处一概不画', () {
      final ({bool before, bool after}) atFrom = blockEdgeClaim(
          caret: aFrom, acceptFrom: aFrom, acceptTo: aTo);
      expect(atFrom.before, isTrue);
      expect(atFrom.after, isFalse);

      final ({bool before, bool after}) atTo = blockEdgeClaim(
          caret: aTo, acceptFrom: aFrom, acceptTo: aTo);
      expect(atTo.after, isTrue);
      expect(atTo.before, isFalse);

      for (final int caret in <int>[aFrom - 3, aFrom + 1, aTo - 1, aTo + 3]) {
        final ({bool before, bool after}) c =
            blockEdgeClaim(caret: caret, acceptFrom: aFrom, acceptTo: aTo);
        expect(c.before || c.after, isFalse, reason: 'caret=$caret');
      }
      final ({bool before, bool after}) none =
          blockEdgeClaim(caret: null, acceptFrom: aFrom, acceptTo: aTo);
      expect(none.before || none.after, isFalse);
    });

    test('★★★ 紧贴两块**不再共享任何一格**（新口径的核心）', () {
      // 旧口径下 aTo == bFrom（同一格两块各画一根）；新口径两者差 1。
      expect(bFrom, aTo + 1, reason: 'B 的行首紧接在 A 的行尾之后，且**不是同一格**');
      for (var caret = aFrom; caret <= bTo; caret++) {
        final ({bool before, bool after}) a =
            blockEdgeClaim(caret: caret, acceptFrom: aFrom, acceptTo: aTo);
        final ({bool before, bool after}) b =
            blockEdgeClaim(caret: caret, acceptFrom: bFrom, acceptTo: bTo);
        final int n = (a.before || a.after ? 1 : 0) + (b.before || b.after ? 1 : 0);
        expect(n <= 1, isTrue, reason: 'caret=$caret 被 $n 个块同时画');
      }
    });
  });

  group('blockShowsCaret（要不要画整根）', () {
    test('★ 闭区间：两端都归本块，外面一概不画', () {
      expect(blockShowsCaret(caret: aFrom, acceptFrom: aFrom, acceptTo: aTo), isTrue);
      expect(blockShowsCaret(caret: aTo, acceptFrom: aFrom, acceptTo: aTo), isTrue);
      expect(blockShowsCaret(caret: aFrom + 5, acceptFrom: aFrom, acceptTo: aTo),
          isTrue);
      // 批 25：光标不在这块的区间里 ⇒ 一律 false（改前只判 `caret != null`）
      for (final int caret in <int>[aFrom - 1, aTo + 1, 0, 999]) {
        expect(
            blockShowsCaret(caret: caret, acceptFrom: aFrom, acceptTo: aTo),
            isFalse,
            reason: 'caret=$caret 在 [11,22] 之外');
      }
      expect(blockShowsCaret(caret: null, acceptFrom: aFrom, acceptTo: aTo),
          isFalse);
    });

    test('★★★ 全域：任意偏移上，紧贴两块最多只有一个声称"光标在我这儿"', () {
      for (var caret = aFrom; caret <= bTo; caret++) {
        final bool a =
            blockShowsCaret(caret: caret, acceptFrom: aFrom, acceptTo: aTo);
        final bool b =
            blockShowsCaret(caret: caret, acceptFrom: bFrom, acceptTo: bTo);
        expect(a && b, isFalse, reason: 'caret=$caret 两块都声称 ⇒ 屏幕两根');
      }
    });
  });
}
