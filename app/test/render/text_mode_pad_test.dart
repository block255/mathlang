// **文本模式不许注垫子**：`\text{…}` 的参数是 KaTeX 的**文本模式**，里面
// `\rule` / `\square` 都是非法命令 ⇒ 我们给空槽注的宽度垫会把整块打成 `[公式不完整]`。
//
// ★ 现场（用户 2026-10-25 截图，`KaTeX Parse Error: Can't use function '\rule' in text mode`）：
//   在 `(\text{旁注：} …)` 里把内容删空 ⇒ `\text{}` ⇒ 空槽垫 `\textcolor{#FFFFFF}{\square\rule{0.3em}{0pt}}`
//   被注到**文本模式**里 ⇒ 整块 `[公式不完整]`。
//   探针 v60 实测（包在 `\text{…}` 里试）：`\rule` ✗ · `\square` ✗ ·
//   `\phantom{0}` ✓ · `\hspace{0.6em}` ✓ · `\ ` ✓ · `\quad` ✓。
//   ⇒ 口径：**文本模式里不注垫子**（宁可空槽没有点击靶子，也不许整块报错）。
//
// ★ 判据（不信"看起来对"，直接查产物）：`renderMathTex` 之后的 tex 里，
//   **任何 `\text{…}` 参数内部都不许出现 `\rule` / `\square`**；现场那一条还要真引擎能解析。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/slot_marks.dart';

import '../support/math_fonts.dart';

/// 文本模式的命令名（KaTeX 在这些命令的参数里一律按文本模式解析）
const Set<String> _kTextMode = <String>{
  'text', 'textrm', 'textnormal', 'textup', 'textit', 'textbf', 'textsf',
  'texttt', 'mbox', 'hbox',
};

/// tex 里所有 `\text{…}` 参数区间（含嵌套）
List<({int from, int to})> _textArgs(String tex) {
  final List<({int from, int to})> out = <({int from, int to})>[];
  for (final RegExpMatch m
      in RegExp(r'\\([A-Za-z]+)\s*\{').allMatches(tex)) {
    if (!_kTextMode.contains(m.group(1)!)) continue;
    final int open = tex.indexOf('{', m.start);
    final List<int> stack = <int>[open];
    for (var i = open + 1; i < tex.length; i++) {
      if (tex[i] == '{') stack.add(i);
      if (tex[i] == '}') {
        stack.removeLast();
        if (stack.isEmpty) {
          out.add((from: open + 1, to: i));
          break;
        }
      }
    }
  }
  return out;
}

/// 这一份 tex 里"文本模式参数内部含非法命令"的地方
List<String> _illegalInText(String tex) {
  final List<String> out = <String>[];
  for (final ({int from, int to}) r in _textArgs(tex)) {
    final String body = tex.substring(r.from, r.to);
    if (body.contains(r'\rule') || body.contains(r'\square')) {
      out.add('「$body」');
    }
  }
  return out;
}

void main() {
  setUpAll(() async => loadMathFonts());

  group('现场：`\text{}` 删空', () {
    testWidgets(r'★ 空槽垫不许注进文本模式（真引擎必须能解析）', (WidgetTester tester) async {
      // 用户那一行把 `旁注：` 删空之后的样子
      const String tex =
          r'= \lim\limits_{x\to0} b^{x^{2}} (e^{x^2 \ln\frac{a}{b}} - 1) \quad (\text{} x\to0 \text{ 时 } x^2 \ln\frac{a}{b} \to 0)';
      // 光标正好在 `\text{}` 里（= 用户删空后的位置）
      final int inside = tex.indexOf(r'\text{}') + r'\text{'.length;
      for (final int rel in <int>[inside, inside, -1]) {
        final String out = renderMathTex(tex, caretRel: rel);
        expect(_illegalInText(out), isEmpty,
            reason: 'caretRel=$rel 时文本模式里出现了非法命令：${_illegalInText(out)}\n'
                '产物：$out');
      }
      // 真引擎解析（用户看到的 `[公式不完整]` 就是它）
      final String out = renderMathTex(tex, caretRel: inside);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: Math.tex(
              out,
              mathStyle: MathStyle.display,
              textStyle: const TextStyle(fontSize: 16),
              onErrorFallback: (dynamic e) => const Text('PARSE_ERROR'),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(find.text('PARSE_ERROR'), findsNothing,
          reason: '渲染产物解析失败（产物：$out）');
    });
  });

  group('全域：任何光标位点都不许把垫子注进文本模式', () {
    const List<String> texs = <String>[
      r'\text{}',
      r'\text{旁注：}',
      r'\text{旁注：} x\to0',
      r'a = \text{ 时 } b',
      r'\frac{\text{甲}}{\text{}}',
      r'\text{甲}\frac{}{}\text{乙}',
      r'\textbf{粗}\sqrt{}',
      r'\text{$x$} + \text{}',
      r'\begin{cases}\text{a}&\\\text{}&\end{cases}',
      r'\left( \text{旁注：} \right)',
    ];

    test('每个位点 × 光标在/不在里面', () {
      var checked = 0;
      for (final String tex in texs) {
        final CaretSiteTable t = buildCaretSites(tex);
        for (final CaretSite s in t.sites) {
          for (final int rel in <int>[s.offset, -1]) {
            final String out = renderMathTex(tex, caretRel: rel);
            final List<String> bad = _illegalInText(out);
            expect(bad, isEmpty,
                reason: '「$tex」caretRel=$rel 文本模式里出现非法命令 $bad\n产物：$out');
            checked++;
          }
        }
      }
      expect(checked, greaterThanOrEqualTo(40),
          reason: '全域用例太少（只检查了 $checked 次）—— 守卫会变成空转');
    });
  });
}
