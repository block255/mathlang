// ★★ L24 守卫（2026-10-21）：**`\limits`/`\nolimits` 前面不许有光标注入点**
//
// 用户实测（真实作业文档）：「从公式里开始拖，拖动过程中偶尔出现红字 [公式不完整]，没按任何键」。
// 根因：位点表把「`\liminf` 之后、`\limits` 之前」当成合法位点 ⇒ 注入光标后变成
//   `\liminf\textcolor{#1E88E5}{\rule{0pt}{0pt}}\limits_{…}`
// ⇒ `\limits` 不再紧跟算符 ⇒ KaTeX 解析失败 ⇒ 那一帧画兜底文字。**文档内容没被改**，
// 所以表现为"偶发"（只有落在那 2–3px 区间才中）。
//
// 本文件两层守卫：
//   ① 位点表：`\liminf\limits` 的位点里**不许**出现 `\liminf` 末尾那个偏移；
//   ② 全域：**每一个位点**注入光标后，tex 都必须仍能被渲染（不触发兜底）——
//      这一条直接封死"注入物改变语法"这一族 bug（含 `withOperandLimits` 自动插 `\limits` 的情形）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/math_caret.dart';
import 'package:mathlang/render/slot_marks.dart';

import '../support/math_fonts.dart';

/// 这一段 tex 在**所有位点**注入光标后，哪些位置渲染失败（返回 `(位点, 注入后的 tex)`）。
///
/// 判据用 `MathWithCaret.onErrorFallback`（与 App 里"红字兜底"**同一条路径**）——
/// 只要它被调用过，就说明这一帧的 tex 非法。
Future<List<({int at, String tex})>> brokenInjections(
    WidgetTester tester, String tex) async {
  final List<({int at, String tex})> broken = <({int at, String tex})>[];
  final List<int> sites = buildCaretSites(tex).offsets;
  for (final int at in sites) {
    final String injected = renderMathTex(tex, caretRel: at);
    var failed = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MathWithCaret(
            tex: injected,
            showCaret: true,
            mathKey: GlobalKey(),
            fontSize: 16,
            onErrorFallback: (error) {
              failed = true;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    ));
    await tester.pump();
    if (failed) broken.add((at: at, tex: injected));
    await tester.pumpWidget(const SizedBox.shrink()); // 换一棵树，避免 key 复用
  }
  return broken;
}

void main() {
  setUpAll(() async => loadMathFonts());

  group('① 位点表：算符与 `\\limits` 之间不是位点', () {
    test(r'`\liminf\limits` 的位点里没有"算符末尾"那个偏移', () {
      final int opEnd = r'\liminf'.length; // 7
      final CaretSiteTable t = buildCaretSites(r'\liminf\limits_{n\to\infty}');
      expect(t.offsets, isNot(contains(opEnd)),
          reason: '这里注入会把 `\\limits` 与算符拆开 ⇒ KaTeX 报错。位点=${t.offsets}');
    });

    test(r'`\sum\nolimits` 同理', () {
      final int opEnd = r'\sum'.length; // 4
      final CaretSiteTable t = buildCaretSites(r'\sum\nolimits_{i=1}^{n}');
      expect(t.offsets, isNot(contains(opEnd)), reason: '位点=${t.offsets}');
    });

    test('并进去之后位点表不退化，且仍然首尾齐全', () {
      final CaretSiteTable t = buildCaretSites(r'\liminf\limits_{n\to\infty}');
      expect(t.degraded, isFalse);
      expect(t.offsets.first, 0);
      expect(t.offsets.last, greaterThan(r'\liminf\limits'.length));
    });
  });

  group('② 全域：每个位点注入后都必须仍能渲染', () {
    testWidgets('改前：`\\liminf\\limits` 这一族必红', (WidgetTester tester) async {
      const List<String> corpus = <String>[
        r'\liminf\limits_{n\to\infty}\{x_n\}=\limsup\limits_{n\to\infty}\{x_n\}',
        r'\limsup_{n\to\infty}x_n', // 会被 withOperandLimits **自动**插 \limits
        r'\liminf_{n\to\infty}x_n',
        r'\sum_{i=1}^{n}a_i',
        r'\sum\limits_{i=1}^{n}a_i',
        r'\frac{a}{b}+\sqrt{x^2+1}',
        r'a^2+x_n',
        r'\text{中文}\alpha',
      ];
      final List<String> problems = <String>[];
      for (final String tex in corpus) {
        for (final ({int at, String tex}) b in await brokenInjections(tester, tex)) {
          problems.add('$tex @${b.at} ⇒ ${b.tex}');
        }
      }
      expect(problems, isEmpty,
          reason: '这些位点注入后 tex 非法（屏幕上会画 [公式不完整]）：\n${problems.join('\n')}');
    });
  });
}
