// ★★★ 2026-10-24（批 20 · F2）：**结构记号不许单个删** —— 对齐推导 / 分段函数都中招。
//
// 用户实测：在一格里连按退格，删完内容后**开始啃结构记号**：
//   `\begin{aligned}&=\\&=\end{aligned}` ⇒ `\begin{aligned}&\&\end{aligned}`
//   ⇒ 解析失败 ⇒ 整行源码裸奔（还把后面的 `$$` 一并吃掉）。
//
// 口径（与 D1「空结构整块回收」同一条；平权 ①：结构记号不是内容）：
//   · 环境里**没有用户内容**（只剩 `&` `\\` `&=` 的 `=` 骨架）⇒ 退格 = **整块回收这个环境**；
//   · 还有内容 ⇒ **跳过记号**，去删左边最近的**真内容**原子。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/smart_delete.dart';

const String kAligned = r'\begin{aligned}&=\\&=\end{aligned}';
const String kCases = r'\begin{cases}\\\end{cases}';

/// 从 [rel] 起一直退格，返回每一步的 tex（含起点）
List<String> chain(String tex, int rel, {int max = 20}) {
  final List<String> out = <String>[tex];
  String cur = tex;
  var at = rel;
  for (var i = 0; i < max && cur.isNotEmpty; i++) {
    final SmartEdit e = smartBackspace(buildCaretSites(cur), at);
    if (e.isNone || e.isMove) {
      if (e.isNone) break;
      at = e.caret;
      continue;
    }
    cur = cur.replaceRange(e.from!, e.to!, '');
    at = e.caret;
    out.add(cur);
  }
  return out;
}

void main() {
  group('① 空环境 ⇒ 退格整块回收（一步到底）', () {
    test(r'aligned：任意位置退格都直接删掉整个环境', () {
      for (final int rel in <int>[34, 21, 19, 17, 16, 15]) {
        final List<String> c = chain(kAligned, rel);
        expect(c.length, 2, reason: 'rel=$rel 应该一步删完，实际 $c');
        expect(c.last, '', reason: 'rel=$rel');
      }
    });

    test(r'cases：同样一步删完', () {
      for (final int rel in <int>[26, 16, 15]) {
        final List<String> c = chain(kCases, rel);
        expect(c.length, 2, reason: 'rel=$rel 实际 $c');
        expect(c.last, '', reason: 'rel=$rel');
      }
    });
  });

  group(r'② 结构记号**从不**被单个删掉（不许出现 `&\&` 这种坏形状）', () {
    test(r'整条链上每一步都不许缺 `\begin` / `\end`、不许出现 `&\&`', () {
      const String tex = r'\begin{aligned}rS&=1\\&=2\end{aligned}';
      final List<String> c = chain(tex, tex.length - 1, max: 30);
      for (final String step in c) {
        expect(step.contains(r'&\&'), isFalse, reason: '出现了 `&\\&`：$step');
        expect(r'\begin{'.allMatches(step).length, r'\end{'.allMatches(step).length,
            reason: r'`\begin` / `\end` 数量不等：$step');
        if (step.isNotEmpty) {
          expect(step.contains(r'\begin{aligned}'), isTrue, reason: '环境名被啃了：$step');
        }
      }
    });

    test(r'有内容时退格先删内容，不删记号（`&=1` 末尾 ⇒ 删 `1`）', () {
      const String tex = r'\begin{aligned}rS&=1\\&=\end{aligned}';
      final int end = tex.indexOf('1') + 1;
      final SmartEdit e = smartBackspace(buildCaretSites(tex), end);
      expect(e.deletes, isTrue);
      expect(tex.substring(e.from!, e.to!), '1', reason: '应该删的是内容 `1`，实际 $e');
    });
  });
}
