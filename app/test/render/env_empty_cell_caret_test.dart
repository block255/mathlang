// ★★ 2026-10-24（批 3 · D3 续）：**空格子里的光标锚点要落在格的左缘**（不是垫子右边）。
//
// 用户实测（真实 tex：`f(x)=\begin{cases}x&\\&\\&\end{cases}`）：
//   「第二段正确的位置没有框，后面有一个很奇怪的点击判定位置，有框」「我点的是 `{` 后那一格，点不到」。
//
// 根因：环境空格子恒定注入 `\rule{1em}{0pt}` 垫子撑宽（2026-10-18 定了"预留宽度、版面中性"），
//   但垫子用 `shiftAt: true` 插在格子起点 ⇒ **光标 rel 被 +1em 推后** ⇒ 锚点落到
//   `\rule{1em}{0pt}\textcolor{…}` 的**垫子右边** = 这一格的右缘（数值上就是下一列的左边界）
//   ⇒ 框被画到右边那一列 / 点在格子里反而判不到。
//
// 修法：垫子改 `shiftAt: false`（只有 rel **严格大于**落点才挪）⇒ 锚点落在垫子**之前**。
//   ★ 已经在这格里打了字的情形不受影响（rel > 起点仍然会挪）。
//
// 判据（最直白）：**锚点紧跟在格子边界之后** —— 第二段第一格 ⇒ 前面是 `\\`；
//   第一段第二格 ⇒ 前面是 `&`；第一段第一格 ⇒ 前面是 `\begin{cases}`。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/slot_marks.dart';

const String kTex = r'f(x)=\begin{cases}x&\\&\\&\end{cases}';

int _anchor(String s) => s.indexOf(r'\textcolor{#1E88E5}');

void main() {
  test(r'第二段第一格（空）⇒ 锚点紧跟在 `\\` 之后（格左缘）', () {
    final String injected = renderMathTex(kTex, caretRel: 22, showCursor: true);
    final int a = _anchor(injected);
    expect(a, greaterThan(0), reason: injected);
    expect(injected.substring(a - 2, a), r'\\',
        reason: '改前锚点被 1em 垫子推到这一格右缘：$injected');
  });

  test(r'第一段第二格（空）⇒ 锚点紧跟 `&`（也是格左缘）', () {
    final String injected = renderMathTex(kTex, caretRel: 20, showCursor: true);
    final int a = _anchor(injected);
    expect(a, greaterThan(0), reason: injected);
    expect(injected.substring(a - 1, a), '&', reason: injected);
  });

  test(r'回归：有内容的格子里光标照旧按 rel 落（第一段第一格）', () {
    final String injected = renderMathTex(kTex, caretRel: 18, showCursor: true);
    final int a = _anchor(injected);
    expect(injected.substring(a - 1, a), '}', reason: injected); // `\begin{cases}` 的 `}`
    final int env = injected.indexOf(r'\begin{cases}');
    expect(a, lessThan(injected.indexOf('x', env)),
        reason: '锚点要在 `x` 之前（rel=18 就是这一格的起点）：$injected');
  });
}
