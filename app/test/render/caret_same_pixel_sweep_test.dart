// ★★★ 2026-10-24（批 12）：**全域「同像素站位」守卫** —— 每一步都要看得见
//
// 判据（用户一直强调的那条）：沿 `→` / `←` 走一遍，相邻两站的**竖条矩形**
// （x + 上沿 + 下沿，容差 0.5 px）必须互不相同 —— 否则用户看到的是"按了没动"。
//
// 来由：批 1~11 里反复出现的"点两下才到""光标像没动""跳一下"全族问题，
// 每次都是逐个例子修（粘合位点 / `\right` 之前 / 裸参数并位…）。
// 这一份把**全域**钉住：任何结构改动只要造出"同像素两站"，这里当场红。
//
// 改前实测（2026-10-24 普查）：
//   · `\left|{x^2}\right|` 的 `6→7`：中间只有不可见的 `{`
//   · `\text{当}` 的 `0→6`：中间是 `\text` 命令名 + `{`，都不画东西
// 修法：`math_nav._invisibleBetween` —— 两站之间**全是不可见字符**、且**同一容器**时跳过。
//   ★ 同一容器这条不能省：`\sum_{i=1}^{n}` 的"下限尾 → 上限首"中间也只有 `^{`，
//     但那两站一个在下限行、一个在上限行 ⇒ 必须停（2026-10-15 金表）。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/math_caret.dart';
import 'package:mathlang/render/math_nav.dart';
import 'package:mathlang/render/slot_marks.dart';

import '../support/math_fonts.dart';

/// 语料：覆盖每一种有层级/无层级的结构
const List<String> kCorpus = <String>[
  // 脚本（裸参数 vs 花括号、嵌套）
  r'x^{2}+1', r'x^2+1', r'x_{2}+1', r'x_2+1', r'x^{y^{2}}+1',
  // 分式 / 根号 / 组合（含嵌套）
  r'\frac{a}{b}+1', r'\frac{x^{3}}{y}+1', r'\frac{\frac{a}{b}}{c}+1',
  r'\sqrt{x^2}+1', r'\sqrt[3]{x}+1', r'\binom{n}{k}+1',
  // 定界符组（含隐形定界符）
  r'\left(x^2\right)+1', r'\left|{x^2}\right|+1', r'\left\{x\right\}+1',
  r'\left.x\right|+1', r'\left|x\right.+1', r'\left(x\right)+1',
  // 算子（上下限 / 内容 / 函数名）
  r'\sum_{i=1}^{n}i^{2}+1', r'\sum_{i=1}^{n}+1', r'\int_{0}^{1}x\,dx+1',
  r'\sin^{2}x+1', r'\lim_{x\to0}\frac{a}{b}+1',
  // 环境
  r'\begin{cases}a\\b\end{cases}+1', r'\begin{bmatrix}a&b\\c&d\end{bmatrix}+1',
  // accent / 文本 / 堆叠
  r'\hat{x}+1', r'\overline{AB}+1', r'\text{当}+1', r'\text{abc}+1',
  r'\mathrm{abc}+1', r'\operatorname{lcm}+1', r'\vec{a}+1', r'\overset{n}{a}+1',
];

Future<Rect?> _bar(
    WidgetTester tester, String tex, int rel, MathStyle style) async {
  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: MathWithCaret(
          tex: renderMathTex(tex, caretRel: rel),
          showCaret: true,
          mathKey: key,
          mathStyle: style,
          textFontSize: 20,
          fontSize: 20,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  final RenderObject root = key.currentContext!.findRenderObject()!;
  final RenderBox? anchor = findCaretAnchor(root);
  if (anchor == null) return null;
  final Offset at = anchor.localToGlobal(Offset.zero, ancestor: root);
  return caretBarRect(
    at: at,
    localRowBox: findLocalRowBox(root, at, anchor: anchor),
    width: 1.5,
    fontSize: 20,
  );
}

bool _samePixel(Rect? a, Rect? b) {
  if (a == null || b == null) return false;
  return (a.left - b.left).abs() < 0.5 &&
      (a.top - b.top).abs() < 0.5 &&
      (a.bottom - b.bottom).abs() < 0.5;
}

void main() {
  setUpAll(() async => loadMathFonts());

  for (final MathStyle style in <MathStyle>[MathStyle.text, MathStyle.display]) {
    testWidgets('★★ 全域：`→` 每一步竖条都必须动（style=${style.name}）',
        (WidgetTester tester) async {
      final List<String> bad = <String>[];
      for (final String tex in kCorpus) {
        final String doc =
            style == MathStyle.display ? '\$\$\n$tex\n\$\$' : '\$$tex\$';
        final MathRegion? r =
            mathRegionAt(doc, style == MathStyle.display ? 3 : 1);
        if (r == null) continue;
        final List<int> stops = <int>[];
        int cur = r.contentStart;
        for (var k = 0; k < 40; k++) {
          stops.add(cur - r.contentStart);
          final int nx = nextCaretOffset(doc, cur);
          if (nx >= r.closeEnd || nx <= cur) break;
          cur = nx;
        }
        Rect? prev;
        for (final int rel in stops) {
          final Rect? bar = await _bar(tester, tex, rel, style);
          if (_samePixel(prev, bar)) bad.add('$tex ⇒ 与上一站同像素（rel=$rel）');
          prev = bar;
        }
      }
      expect(bad, isEmpty, reason: bad.join(' · '));
    });

    testWidgets('★★ 全域：`←` 每一步竖条都必须动（style=${style.name}）',
        (WidgetTester tester) async {
      final List<String> bad = <String>[];
      for (final String tex in kCorpus) {
        final String doc =
            style == MathStyle.display ? '\$\$\n$tex\n\$\$' : '\$$tex\$';
        final MathRegion? r =
            mathRegionAt(doc, style == MathStyle.display ? 3 : 1);
        if (r == null) continue;
        // 从末尾往里走
        final List<int> stops = <int>[];
        int cur = r.closeEnd;
        for (var k = 0; k < 40; k++) {
          final int pv = prevCaretOffset(doc, cur);
          if (pv <= r.openStart || pv >= cur) break;
          cur = pv;
          final MathRegion? r2 = mathRegionAt(doc, cur);
          if (r2 == null) break;
          stops.add(cur - r2.contentStart);
        }
        Rect? prev;
        for (final int rel in stops) {
          final Rect? bar = await _bar(tester, tex, rel, style);
          if (_samePixel(prev, bar)) bad.add('$tex ⇒ 与上一站同像素（rel=$rel）');
          prev = bar;
        }
      }
      expect(bad, isEmpty, reason: bad.join(' · '));
    });
  }
}
