// 反馈 7 守卫：连点/连按上下标不许"套娃"。
//
// 现象（用户原话）：`f` 后面点选下标、又不小心点成下标 ⇒ 公式不完整；
//   而一开始就用快捷键下标，就能一直按，结果是 f 和框越来越小、越来越往下挪。
// 改前必红：①②（`f_{}` 里再按 ⇒ 判"可以插"）与 ⑥（`x^{2}` 末尾按上标）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/script_nest.dart';

void main() {
  group('7 · 再插上下标的判据', () {
    test('① 光标在 `f_{}` 的空下标槽里再按下标 ⇒ 拒绝（套成 `f_{_{}}` 的那一下）', () {
      expect(scriptInsertWouldNest(r'f_{}', 3, sup: false), isTrue);
    });

    test('② 下标槽里有内容时再按下标 ⇒ 也拒绝', () {
      expect(scriptInsertWouldNest(r'f_{x}', 4, sup: false), isTrue);
    });

    test('③ 下标槽里按**上标**、而槽里还没有基座 ⇒ 拒绝（会插出无基座的 `^{}`）', () {
      expect(scriptInsertWouldNest(r'f_{}', 3, sup: true), isTrue);
    });

    test('④ 下标槽里已经有内容 `x` ⇒ 允许给它挂上标', () {
      expect(scriptInsertWouldNest(r'f_{x}', 4, sup: true), isFalse);
    });

    test('⑤ 上标槽里（内容之后）再按上标 ⇒ 拒绝', () {
      expect(scriptInsertWouldNest(r'x^{2}', 4, sup: true), isTrue);
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
  });
}
