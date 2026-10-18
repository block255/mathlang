// 守卫测试：**多行环境模板插入后，光标必须落在第一格**（`\begin{env}` 之后、第一个 `&` 之前）
//
// 2026-10-18 用户实测：插入「对齐推导」→ 只在第一行等号两边打字 → 两个 `=` 错位。
// 真实 tex（会话文件）是 `\begin{aligned}&a=b\\&=\end{aligned}` —— `a` 落到了 `&` **右边**，
// 而 `&` 右侧是**左对齐列** ⇒ `a` 把该行的 `=` 推右。
// 根因：`firstSlotOffset` 只找空的 `{}`/`[]`，环境里一个都没有 ⇒ 光标被丢到 tex 末尾。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/symbol_insert.dart';

void main() {
  group('环境模板：光标落第一格', () {
    test(r'aligned ⇒ 落在第一个 & 之前', () {
      const String tex = r'\begin{aligned}&=\\&=\end{aligned}';
      final int at = firstSlotOffset(tex);
      expect(tex[at], '&', reason: '光标应在第一个 `&` 的位置（即第一格的末尾）');
      expect(at, r'\begin{aligned}'.length);
    });

    test(r'cases ⇒ 落在第一个 & 之前', () {
      const String tex = r'\begin{cases}&\\&\end{cases}';
      final int at = firstSlotOffset(tex);
      expect(tex[at], '&');
    });
  });

  group('普通模板不受影响', () {
    test(r'\frac{}{} ⇒ 分子', () {
      expect(firstSlotOffset(r'\frac{}{}'), r'\frac{'.length);
    });
    test(r'\sqrt[]{x} ⇒ 空的次数位 `[]` 内', () {
      expect(firstSlotOffset(r'\sqrt[]{x}'), r'\sqrt['.length);
    });
    test('没有空槽 ⇒ 末尾', () {
      expect(firstSlotOffset(r'\alpha'), r'\alpha'.length);
    });
  });
}
