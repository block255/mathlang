// ★★ 失焦 normalize 的**同类问题**全域探针 / 守卫（2026-10-17）
//
// 背景（用户实测抓出来的第一批）：`\sum_{i=1}^{n}a_i` 在**失焦**时被 normalize 改写成
// `\sum_{i=1}^na_i`（"单原子脚本参数去花括号"）⇒ "n 之后"与"a 之前"**合并成一格**，
// 锚点落到主行 ⇒ 光标"掉到 ∑ 与 a 之间"，那个位置再也点不进去。
//
// 本探针检查**同一族**风险：对每个数学语言 × **每一个位点**，
// 比较「失焦前（tex, o）的光标矩形」与「失焦后（normalize 之后的 tex', o'）的光标矩形」：
//   · x 必须一致（差 ≤ 1px）
//   · y 区间必须有交集（不许换行/换层）
// 不一致 ⇒ 失焦会让光标**跳走**，用户就会觉得"某处点不到/点了跑到别处"。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/math_caret.dart';
import 'package:mathlang/render/normalize.dart';
import 'package:mathlang/render/slot_marks.dart';

import '../support/math_fonts.dart';

const List<String> _corpus = <String>[
  r'\frac{a}{b}',
  r'\frac{a}{b}+c',
  r'\sqrt{x}',
  r'\sqrt[3]{x}',
  r'\sum_{i=1}^{n}a_i',
  r'\sum_{i=1}^na_i',
  r'\prod_{k=1}^{m}k',
  r'\int_0^1 x',
  r'\lim_{x\to0}f',
  r'x^{2}',
  r'x^{2}_{1}',
  r'x_1^2',
  r'x^2',
  r'a_i',
  r'\sin x',
  r'\hat{x}',
  r'\vec{x}',
  r'\overline{AB}',
  r'\not=',
  r'\textcolor{red}{x}',
  r'\left(\frac{a}{b}\right)',
  r'e^{i\pi}',
  r'a_{i}',
];

/// 位点处竖条的矩形（与生产代码同一条几何路径，避免"帧末量、下帧画"的慢一帧）
Future<Rect?> _bar(WidgetTester tester, String tex, int caretRel) async {
  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: MathWithCaret(
          tex: renderMathTex(tex, caretRel: caretRel),
          showCaret: true,
          mathKey: key,
          mathStyle: MathStyle.display,
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

// ★ 2026-10-17 收窄 normalize 之后：只有 `x^{2}` / `a_{i}` 这种**最简单**的还会被改写，
//   而且**一处固有合并都不剩** ⇒ 白名单已删，这条守卫现在是"纯全域不变量"：
//   任何位点失焦后都不许跳走（x 差 ≤1px、竖直区间至少重叠一半）。

void main() {
  setUpAll(() async => loadMathFonts());

  testWidgets('★★ 全域：失焦 normalize **不许让光标跳走**', (WidgetTester tester) async {
    final List<String> bad = <String>[];
    final List<String> changed = <String>[];
    final List<String> collapsed = <String>[];
    for (final String tex in _corpus) {
      final CaretSiteTable t = buildCaretSites(tex);
      for (final CaretSite site in t.sites) {
        final NormalizeResult nr = normalizeTex(tex, site.offset);
        if (!nr.changed) continue;
        if (!changed.contains(tex)) changed.add(tex);

        final Rect? before = await _bar(tester, tex, site.offset);
        final Rect? after = await _bar(tester, nr.tex, nr.caret);
        if (before == null || after == null) {
          bad.add('「$tex」@${site.offset} ⇒ 有一边没有竖条');
          continue;
        }
        final bool sameX = (before.left - after.left).abs() <= 1.0;
        final double overlap = (before.top < after.bottom && after.top < before.bottom)
            ? (before.bottom < after.bottom ? before.bottom : after.bottom) -
                (before.top > after.top ? before.top : after.top)
            : 0;
        final bool sameRow = overlap >= (before.height < after.height ? before.height : after.height) * 0.5;
        if (!sameX || !sameRow) {
          bad.add('「$tex」@${site.offset} 失焦后光标跳走：'
              '${nr.tex}@${nr.caret} '
              'x ${before.left.toStringAsFixed(1)}→${after.left.toStringAsFixed(1)} '
              'y ${before.top.toStringAsFixed(1)}..${before.bottom.toStringAsFixed(1)}'
              '→${after.top.toStringAsFixed(1)}..${after.bottom.toStringAsFixed(1)}');
        }
      }
    }
    // ignore: avoid_print
    print('[NORM-PROBE] 被改写的公式：${changed.length} 条 ⇒ $changed');
    // ignore: avoid_print
    print('[NORM-PROBE] 固有合并（不是 bug）：$collapsed');
    expect(bad, isEmpty, reason: '失焦会让光标跳走：\n${bad.join('\n')}');
  });
}
