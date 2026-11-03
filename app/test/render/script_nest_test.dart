// 反馈 7（2026-10-30）+ 反馈 A3（2026-11-04）守卫：再插一次上下标的判据。
//
// 口径（2026-11-04 改）：**空槽才挡、有基座放行**。
//   旧口径①"同种脚本 ⇒ 一律拒"把合法的 `x^{y^{2}}` 一起挡死（用户："打不出指数的指数"）。
//   ★ 这条**取代**了 2026-10-30 的"同种脚本一律拒"：同一个动作按**光标所在层**定语义——
//     要给"整个 `x^{2}`"再加一层，把光标移到 `}` 之后按（那是对象层）。
//
// 改前必红：②（`f_{x}` + 下标）、⑤（`x^{2}` + 上标）、⑨⑩（`insert_guard` 不再搬走）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/insert_guard.dart';
import 'package:mathlang/render/script_nest.dart';

void main() {
  group('7 · 再插上下标的判据', () {
    test('① 光标在 `f_{}` 的空下标槽里再按下标 ⇒ 拒绝（套成 `f_{_{}}` 的那一下）', () {
      expect(scriptInsertWouldNest(r'f_{}', 3, sup: false), isTrue);
    });

    test('② 下标槽里**已有内容**时再按下标 ⇒ 放行（`f_{x}` + `_` ⇒ `f_{x_{2}}`）', () {
      expect(scriptInsertWouldNest(r'f_{x}', 4, sup: false), isFalse,
          reason: '槽里有基座 `x` ⇒ 合法的下标的下标（改前：一律拒）');
    });

    test('③ 下标槽里按**上标**、而槽里还没有基座 ⇒ 拒绝（会插出无基座的 `^{}`）', () {
      expect(scriptInsertWouldNest(r'f_{}', 3, sup: true), isTrue);
    });

    test('④ 下标槽里已经有内容 `x` ⇒ 允许给它挂上标', () {
      expect(scriptInsertWouldNest(r'f_{x}', 4, sup: true), isFalse);
    });

    test('⑤ 上标槽里（内容之后）再按上标 ⇒ 放行（`x^{2}` + `^` ⇒ `x^{2^{}}`）', () {
      expect(scriptInsertWouldNest(r'x^{2}', 4, sup: true), isFalse,
          reason: '槽里有基座 `2`（改前：一律拒）');
    });

    test('⑥ 光标在 `x` 之后（还没脚本）⇒ 放行', () {
      expect(scriptInsertWouldNest(r'x', 1, sup: true), isFalse);
      expect(scriptInsertWouldNest(r'x', 1, sup: false), isFalse);
    });

    test('⑦ 在分式槽里按上下标 ⇒ 放行（那是另一个结构，不是脚本槽）', () {
      expect(scriptInsertWouldNest(r'\frac{}{}', 6, sup: false), isFalse);
      expect(scriptInsertWouldNest(r'\frac{a}{b}', 7, sup: true), isFalse);
    });

    test('⑧ 在正文里（裸 tex 无结构）⇒ 放行', () {
      expect(scriptInsertWouldNest('', 0, sup: true), isFalse);
      expect(scriptInsertWouldNest('x+y', 3, sup: false), isFalse);
    });

    test('⑨ `scriptSlotHasBase`：同一条判据本体', () {
      expect(scriptSlotHasBase(r'x^{y}', 4), isTrue);
      expect(scriptSlotHasBase(r'x^{}', 3), isFalse);
      expect(scriptSlotHasBase('x', 1), isFalse);
    });
  });

  group('A3 · 插入守门人：纯脚本载荷不再搬出"有基座的槽"', () {
    test(r'⑩ `$x^{y|}$` 按 `^` ⇒ **原地**套一层（不搬出脚本）', () {
      // `$x^{y}$` 的内容从 1 起；`y` 之后 = 1 + 4
      final InsertPlan p = planInsert(r'$x^{y}$', 5, '^{}');
      expect(p.moved, isFalse, reason: p.why);
      expect(p.offset, 5);
    });

    test(r'⑪ `$x^{|}$`（空槽）按 `^` ⇒ 仍然搬到对象之后', () {
      final InsertPlan p = planInsert(r'$x^{}$', 4, '^{}');
      expect(p.moved, isTrue, reason: '空槽里再嵌一层会解析失败');
      expect(p.offset, 5, reason: r'`$x^{}$` 里 `}` 之后那一格');
    });
  });
}
