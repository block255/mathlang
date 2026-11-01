// ★★★ 2026-11-01（用户实测）：**光标闪烁不许改变排版**。
//
// 现场（用户原话）：「光标在这个位置时，光标闪烁依然会影响排版」——位置是
//   左导数 `f'_{-}` 的**撇之后、下标之前**（粘合位点）。闪烁灭→亮时，屏幕上的东西会动一下。
// 判据（全域，比"某个公式看起来没动"硬）：
//   **同一个位点、同一个 tex，`showCursor: true` 与 `false` 渲染出来的尺寸必须完全相同**
//   —— 闪烁只该切换"画不画那根竖条"，不该改任何排版输入。
//   光标注入物是 `\textcolor{…}{\rule{0pt}{0pt}}`（零尺寸锚点），理论上尺寸中性；
//   本守卫就是钉住"理论上"。
//
// 改前必红：见运行输出的位点。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/slot_marks.dart';

import '../support/math_fonts.dart';

const List<String> kSamples = <String>[
  r"f'_{-}",
  r"f'_{-}\alpha",
  r'f_{-}',
  r'x^{2}',
  r'\frac{a}{b}',
  r'\sqrt{x}',
  r'\sum_{i}^{n}',
];

Future<Size> _size(WidgetTester tester, String tex) async {
  await tester.pumpWidget(MaterialApp(
    home: Center(
      child: Math.tex(tex,
          mathStyle: MathStyle.text,
          textStyle: const TextStyle(fontSize: 20)),
    ),
  ));
  await tester.pump();
  return tester.getSize(find.byType(Math));
}

void main() {
  setUpAll(() async => loadMathFonts());

  group('★ 每一位点：闪烁（showCursor）不得改变渲染尺寸', () {
    for (final String tex in kSamples) {
      testWidgets('tex = $tex', (WidgetTester tester) async {
        final CaretSiteTable t = buildCaretSites(tex);
        expect(t.offsets, isNotEmpty);
        final List<String> bad = <String>[];
        for (final int off in t.offsets) {
          final String on =
              renderMathTex(tex, caretRel: off, showCursor: true);
          final String offTex =
              renderMathTex(tex, caretRel: off, showCursor: false);
          final Size a = await _size(tester, on);
          final Size b = await _size(tester, offTex);
          final double dw = (a.width - b.width).abs();
          final double dh = (a.height - b.height).abs();
          if (dw > 0.5 || dh > 0.5) {
            bad.add('off=$off Δ=${dw.toStringAsFixed(2)}×${dh.toStringAsFixed(2)}'
                ' 亮=${a.width.toStringAsFixed(1)}×${a.height.toStringAsFixed(1)}'
                ' 灭=${b.width.toStringAsFixed(1)}×${b.height.toStringAsFixed(1)}');
          }
        }
        expect(bad, isEmpty, reason: '这些位点闪烁会改排版：\n${bad.join("\n")}');
      });
    }
  });
}
