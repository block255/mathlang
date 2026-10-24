// ★★ 2026-10-24（批 4c · G2）：点在挂件的字形上 ⇒ 落到"对象"那一层
//
// 用户实测两条（原话）：
//   · 「点 `x` 与 `3` 之间，只能点到**指数位 `3` 的左边**，点不到底数位 `x` 的右边」；
//   · 「我想在 `x^{3}` 后面加东西，只能点到 `3` 后面，点不到**这个指数的后面**」。
//
// 口径：挂件是"挂在基座旁边的一小块"，点它两半 = **对象之前 / 对象之后**
//   （与 §4.0'「一个字形 + 它挂的上下标 = 一个对象」同一条）。
//   进挂件里改字仍走 `→` / `↓` / `Tab` —— **位点一个都没删**。
//
// 三条护栏（本文件逐条钉）：
//   ① 只对**脚本**槽生效（`\frac` 分子分母、环境格子不动）；
//   ② 只对**单原子**脚本生效 ⇒ `\sum_{i=1}^{n}` 上下限、`x_{a_i}` 多层挂件照旧能点进去；
//   ③ 外层没有邻居 ⇒ 不接管（返回 null，走原落点）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/caret_sites.dart';

void main() {
  test(r'★ 单原子脚本：点 `3` 左半 ⇒ 底数层（`x` 之后，offset 1）', () {
    final CaretSiteTable t = buildCaretSites(r'x^{3}+1');
    // sites = [0, 1, 3(^), 4(^), 5, 6, 7]
    expect(t.scriptOuterSiteAt(3, rightHalf: false), 1,
        reason: '指数里"3 之前"那一格 ⇒ 对象之前（x 之后）');
  });

  test(r'★ 单原子脚本：点 `3` 右半 ⇒ 对象之后（offset 5，能接着打 `+`）', () {
    final CaretSiteTable t = buildCaretSites(r'x^{3}+1');
    expect(t.scriptOuterSiteAt(4, rightHalf: true), 5,
        reason: '"3 之后"那一格 ⇒ 整个 x^{3} 之后');
  });

  test('护栏②：多原子脚本（`x^{ab}`）不接管 ⇒ 仍能点进去改', () {
    final CaretSiteTable t = buildCaretSites(r'x^{ab}+1');
    expect(t.scriptOuterSiteAt(4, rightHalf: false), isNull);
    expect(t.scriptOuterSiteAt(5, rightHalf: true), isNull);
  });

  test('护栏②：`\\sum_{i=1}^{n}` 的上下限不接管', () {
    final CaretSiteTable t = buildCaretSites(r'\sum_{i=1}^{n}a_i');
    // 下标内容 `i=1` 有 3 个原子 ⇒ 不接管（随便取下标里的一个位点）
    final List<CaretSite> sub = t.sites
        .where((CaretSite s) =>
            s.path.isNotEmpty && s.path.last.command == '_' && s.offset > 0)
        .toList();
    expect(sub, isNotEmpty);
    for (final CaretSite s in sub) {
      expect(t.scriptOuterSiteAt(s.offset, rightHalf: true), isNull,
          reason: '上下限是"可编辑的槽"，不许被 G2 抢走（offset ${s.offset}）');
    }
  });

  test(r'护栏①：`\frac` 的分子分母不是脚本槽 ⇒ 返回 null', () {
    final CaretSiteTable t = buildCaretSites(r'\frac{a}{b}+1');
    for (final CaretSite s in t.sites) {
      if (s.offset == 0) continue;
      expect(t.scriptOuterSiteAt(s.offset, rightHalf: true), isNull,
          reason: 'offset ${s.offset}');
    }
  });

  test(r'★ `x^{3}` 自身末尾：点 `3` 右半 ⇒ 对象之后（= 公式末尾 offset 5）', () {
    final CaretSiteTable t = buildCaretSites(r'x^{3}');
    expect(t.scriptOuterSiteAt(4, rightHalf: true), 5,
        reason: '"公式末尾"就是合法的"对象之后"（x^{3} 之后）');
  });

  test('对照：不在脚本里（普通原子之间）一律返回 null', () {
    final CaretSiteTable t = buildCaretSites(r'a+b');
    for (final CaretSite s in t.sites) {
      expect(t.scriptOuterSiteAt(s.offset, rightHalf: true), isNull);
    }
  });
}
