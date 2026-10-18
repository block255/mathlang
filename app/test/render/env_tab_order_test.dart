// 守卫测试：多行环境的 `Tab` 必须**按行逐格**走，不能因为某格非空就跳过（2026-10-18 用户实测）
//
// 现象：`aligned` 里从"第 1 行等号左侧"按 Tab ⇒ 跳到"第 2 行等号左侧" ⇒ 再跳回"第 1 行等号右侧"。
// 根因：`tabForward` 的规则是"**下一个空槽**"（为 `\frac{}{}` 跳过可选槽而设），
//   而 `=` 所在格子永远非空 ⇒ 被跳过 ⇒ 走位跨行。
// 修法：环境格子**一律算停靠点**，且落点取**格子内容末尾**（从左边过去正好接在 `=` 后写右式）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/site_adjacency.dart';

void main() {
  // `\begin{aligned}&=\\&=\end{aligned}`
  //   格 r0c0=[15,15) 空 · r0c1=[16,17)=`=` · r1c0=[19,19) 空 · r1c1=[20,21)=`=`
  const String tex = r'\begin{aligned}&=\\&=\end{aligned}';

  group('aligned：Tab 按行逐格', () {
    test('第 1 行左格 → 第 1 行等号之后（写右式）', () {
      expect(tabForward(buildCaretSites(tex), 15), 17);
    });
    test('第 1 行等号之后 → 第 2 行左格', () {
      expect(tabForward(buildCaretSites(tex), 17), 19);
    });
    test('第 2 行左格 → 第 2 行等号之后', () {
      expect(tabForward(buildCaretSites(tex), 19), 21);
    });
    test('Shift+Tab 反向对称', () {
      expect(tabBackward(buildCaretSites(tex), 21), 19);
      expect(tabBackward(buildCaretSites(tex), 19), 17);
      expect(tabBackward(buildCaretSites(tex), 17), 15);
    });
  });

  group('普通结构不受影响（可选槽仍被跳过）', () {
    test(r'\sqrt[]{x}：从左到右只停在空的次数位', () {
      final CaretSiteTable t = buildCaretSites(r'\sqrt[]{x}');
      // 次数位 `[]` 是空的 ⇒ 停；被开方数非空 ⇒ 不额外停
      final int? at = tabForward(t, 0);
      expect(at, isNotNull);
      expect(at, greaterThan(0));
    });
  });
}
