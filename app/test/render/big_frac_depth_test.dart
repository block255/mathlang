// 反馈 18（2026-10-30）守卫：**行内分式加大只许作用于顶层 `\frac`**。
//
// 用户实测（图 18：`ρ=e^{θ/2}`）：指数里的分式几乎和底数一样高。
// 探针（字号 20，量字形盒高）：
//   · 顶层 `\frac{\theta}{2}`      ⇒ θ **14.0**（0.7 档，C1 想要的样子）
//   · 顶层 `\dfrac{\theta}{2}`     ⇒ θ 21.0（1.0 档）
//   · `e^{\frac{\theta}{2}}`        ⇒ θ **10.0**（0.5 档，引擎自己降档正确）
//   · `e^{\dfrac{\theta}{2}}`       ⇒ θ **21.0**（顶到 1.0 档 ⇒ 大两档）
// ⇒ 根因不是引擎降档不够（讨论稿 R5 原写法），而是 **我们自己的 `\dfrac` 注入不分位置**。
//
// 口径：`\frac` → `\dfrac` 只改**顶层**（花括号深度 0，且不是 `^`/`_` 的裸参数），
//   否则指数 / 上下限 / 另一个分式里的分式都会被顶大一档以上。
//
// 改前必红：②③④⑤（改前一律被换成 `\dfrac`）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/tex_fixups.dart';

void main() {
  group('18 · 只换顶层 `\\frac`', () {
    test('① 顶层的照旧换成 `\\dfrac`（C1 的口径不变）', () {
      expect(withBigFractions(r'a+\frac{b}{c}').tex, r'a+\dfrac{b}{c}');
    });

    test('② 指数里的不换（`e^{\\frac}` 必须留在 0.5 档）', () {
      const String t = r'e^{\frac{1}{2}}';
      expect(withBigFractions(t).tex, t);
    });

    test('③ 上下限里的不换（`\\sum_{\\frac}` / `\\lim` 同源）', () {
      const String t = r'\sum_{\frac{1}{2}}^{n}';
      expect(withBigFractions(t).tex, t);
    });

    test('④ 分式内部的不换：只有外层换', () {
      expect(withBigFractions(r'\frac{\frac{a}{b}}{c}').tex,
          r'\dfrac{\frac{a}{b}}{c}');
    });

    test(r'⑤ 裸参数（`e^\frac{a}{b}`）不换', () {
      const String t = r'e^\frac{a}{b}';
      expect(withBigFractions(t).tex, t);
    });

    test(r'⑥ 转义的 `\{` `\}` 不算深度：括号里的顶层分式照换', () {
      expect(withBigFractions(r'\{x\mid \frac{a}{b}\}').tex,
          r'\{x\mid \dfrac{a}{b}\}');
    });

    test('⑦ 多处注入时偏移仍然准', () {
      const String t = r'\frac{a}{b}+\frac{c}{d}';
      final FixedTex f = withBigFractions(t);
      expect(f.tex, r'\dfrac{a}{b}+\dfrac{c}{d}');
      expect(f.mapOffset(0), 0, reason: '第一个插入点之前的偏移不动');
      expect(f.mapOffset(1), 2, reason: '第一个 `d` 插在 `\\` 之后');
      expect(f.mapOffset(12), 13, reason: '第二个命令名之前只吃一次偏移');
      expect(f.mapOffset(13), 15, reason: '两处都插过了');
    });

    test(r'⑧ 没有 `\frac` 就原样返回（同一个串、不产生插入点）', () {
      const String t = r'a+b+c';
      final FixedTex f = withBigFractions(t);
      expect(f.tex, t);
      expect(f.mapOffset(3), 3);
    });
  });
}
