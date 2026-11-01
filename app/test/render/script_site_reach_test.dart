// ★★★ 2026-11-01：**脚本参数带不带花括号，决定"对象之后"这一格存不存在**。
//
// 背景（用户 2026-11-01 实测）：`$f_-$`（裸参数）里，"下标末尾"与"对象之后"是**同一个偏移**
// ⇒ 位点表按偏移去重 ⇒ 只剩内层那一个 ⇒ 用户"怎么点、怎么按 →"都到不了 α 之前那一格。
// 根因是 normalize ② 会把 `f_{-}` 拆成 `f_-`（2026-10-17 咬过一次，2026-11-01 第二次）。
// 口径：② 已撤（花括号一律不拆）⇒ **新写的上下标都带花括号 ⇒ 两个位点都在**。
//
// 本文件钉三件事：
//   ① `f_{-}\alpha`：对象之后（`}` 之后）是一个**独立位点**，且 `→` 能停在它上面；
//   ② 它和内层"下标末尾"**不是同一个偏移**（这正是能不能区分的关键）；
//   ③ 老形态 `f_-\alpha`（裸参数）确实只有一个 —— **已知代价**，钉住免得有人以为是 bug。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/math_nav.dart';

List<int> _stops(String tex) {
  final List<int> out = <int>[];
  final String doc = '\$$tex\$';
  int at = 0;
  for (var i = 0; i < 24; i++) {
    final int nx = nextCaretOffset(doc, at + 1);
    final int rel = nx - 1;
    if (rel == at || rel > tex.length) break;
    out.add(rel);
    at = rel;
  }
  return out;
}

void main() {
  test(r'① `f_{-}\alpha`：花括号形式下"对象之后"是独立位点，且 → 能停', () {
    final CaretSiteTable t = buildCaretSites(r'f_{-}\alpha');
    final int afterObj = r'f_{-}'.length; // `}` 之后 = 6
    final CaretSite site = t.snap(afterObj);
    expect(site.offset, afterObj);
    expect(site.path, isEmpty, reason: '它是主行位点（对象之后），不是下标里');
    expect(_stops(r'f_{-}\alpha'), contains(afterObj + 1 - 1),
        reason: '按 → 必须能停在这一格');
  });

  test(r'② "对象之后"与"下标末尾"是两个不同的偏移', () {
    final CaretSiteTable t = buildCaretSites(r'f_{-}\alpha');
    final List<int> offs = t.sites.map((CaretSite s) => s.offset).toList();
    final int inside = r'f_{-}'.length - 1; // `}` 之前（下标内容末）
    final int after = r'f_{-}'.length; // `}` 之后（对象之后）
    expect(offs, contains(inside));
    expect(offs, contains(after));
    expect(inside, isNot(after));
  });

  test(r'③ 已知代价：裸参数 `f_-\alpha` 只剩一个位点（老文档/导入件）', () {
    final CaretSiteTable t = buildCaretSites(r'f_-\alpha');
    final int afterObj = r'f_-'.length; // 3 —— 与下标内容末尾同偏移
    final CaretSite site = t.snap(afterObj);
    expect(site.path, isNotEmpty, reason: '裸参数 ⇒ 只剩内层（下标）那一个位点');
    // 这一格仍然可达，但它**只有内层身份**（`→` 停在它上面时进的是下标）；
    // "对象之后"那个身份在裸参数形态下不存在 —— 记录在案，不是回归。
    expect(_stops(r'f_-\alpha'), contains(afterObj));
  });
}
