// ★★ 「光标不影响排版」的守门人（2026-10-17，用户实测抓出）
//
// 用户原话：「其实按道理来说，就是应该是我们之前说的，光标不影响排版吧
//           我们之前其实已经用自绘做过一次优化了来着」—— 对，但**只做了一半**：
//   2026-10-15 那次解决的是"**尺寸**不影响排版"（零尺寸锚点 `\rule{0pt}{0pt}` ＋ 自绘竖条），
//   没有解决"**结合关系**不影响排版"：注入的 `\textcolor{…}{…}` 自带一个组，
//   一旦插在 `\sum` 与它的上下限之间 / `a` 与它的裸参数之间，脚本就**改绑到组上**。
//
// 探针实测（`\sum_{i=1}^{n}a_i`，display，Math 盒基准 48.6 × 58.6）：
//   位点 4（`\sum` 之后）  ⇒ 72.3 × 32.0 ★上下限掉到右边
//   位点 10（下限之后）     ⇒ 58.0 × 46.6 ★上限掉到右边
//   位点 16（`a_i` 的 i 前）⇒ 50.7 × 58.6 ★`i` 变成普通字号（用户："i 被放大了"）
//
// ⇒ 现在的判据就一句：**任何一个位点注入光标之后，渲染出来的 Math 盒必须一模一样**。
//   这一份是全域扫描（不是抽查）：语料 × 2 样式 × **每一个位点**。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/insert_guard.dart';
import 'package:mathlang/render/math_caret.dart';
import 'package:mathlang/render/slot_marks.dart';

import '../support/math_fonts.dart';

/// 覆盖各类结构；★ `\sum` / `\prod` / `\lim` 是这次事故的现场，`a_i` / `x^2` 是裸参数现场
const List<String> _corpus = <String>[
  r'\sum_{i=1}^{n}a_i',
  r'\sum^{n}_{i=1}a_i',
  r'\prod_{k=1}^{m}k',
  r'\lim_{x\to0}\frac{\sin x}{x}',
  r'\int_a^b f(x)\,dx',
  r'\frac{a}{b}',
  r'\frac{}{}',
  r'x^{2}_{1}',
  r'x^2',
  r'a_i',
  r'\sqrt[3]{x}',
  r'\sqrt{}',
  r'x_1x_2=\frac{c}{a}',
  r'\Delta=b^2-4ac',
  r'\left(\frac{a}{b}\right)',
];

Future<Size> _mathSize(
  WidgetTester tester,
  String renderTex,
  MathStyle style, {
  required bool caret,
}) async {
  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: MathWithCaret(
          tex: renderTex,
          showCaret: caret,
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
  return (root as RenderBox).size;
}

void main() {
  setUpAll(() async => loadMathFonts());

  testWidgets('★★ 全域不变量：**每个位点**注入光标后，Math 盒尺寸必须完全不变',
      (WidgetTester tester) async {
    final List<String> bad = <String>[];
    for (final bool display in <bool>[true, false]) {
      final MathStyle style = display ? MathStyle.display : MathStyle.text;
      for (final String tex in _corpus) {
        final Size base = await _mathSize(
          tester,
          renderMathTex(tex, caretRel: -1),
          style,
          caret: false,
        );
        final CaretSiteTable t = buildCaretSites(tex);
        for (final CaretSite s in t.sites) {
          final String rt = renderMathTex(tex, caretRel: s.offset);
          final Size got = await _mathSize(tester, rt, style, caret: true);
          if ((got.width - base.width).abs() > 0.01 ||
              (got.height - base.height).abs() > 0.01) {
            bad.add('「$tex」[${display ? "display" : "text"}] 位点 ${s.offset}'
                '${s.path.isEmpty ? "（主行）" : "（${s.path.map((SlotStep x) => x.label).join(" › ")}）"}：'
                '基准 ${base.width.toStringAsFixed(1)}×${base.height.toStringAsFixed(1)}'
                ' → ${got.width.toStringAsFixed(1)}×${got.height.toStringAsFixed(1)}\n'
                '      注入后 = $rt');
          }
        }
      }
    }
    expect(bad, isEmpty, reason: '光标改变了排版（`\\sum` 一族会整块散架）：\n${bad.join('\n')}');
  });

  group('★ 金表：注入点被挪到"结构内部"（三条规则）', () {
    test(r'① 位点紧跟 `^`/`_` ⇒ 注入进脚本内容开头（`\sum` 的上下限不再散架）', () {
      const String tex = r'\sum_{i=1}^{n}a_i';
      // 位点 4 = `\sum` 之后、`_{` 之前
      final CursorInjection a = injectCursor(tex, 4);
      expect(a.offset, 6, reason: '`_{` 之内的第一格');
      expect(a.tex.contains(r'_{\textcolor'), isTrue, reason: a.tex);
      // 位点 10 = 下限 `}` 之后、`^{` 之前
      final CursorInjection b = injectCursor(tex, 10);
      expect(b.tex.contains(r'^{\textcolor'), isTrue, reason: b.tex);
    });

    test('② 位点在裸参数里 ⇒ **先补花括号**再注入（`a_i` 的 i 不再掉成普通字）', () {
      final CursorInjection c = injectCursor(r'a_i', 2);
      expect(c.tex.startsWith(r'a_{\textcolor'), isTrue, reason: c.tex);
      expect(c.tex.endsWith('i}'), isTrue, reason: c.tex);
      expect(c.offset, 3);
    });

    test('③ 普通位点 ⇒ 就地注入（不补括号、不挪位）', () {
      final CursorInjection c = injectCursor(r'a+b', 1);
      expect(c.offset, 1);
      expect(c.tex, r'a\textcolor{#1E88E5}{\rule{0pt}{0pt}}+b');
    });
  });

  group('★ 插入侧同一条规则（"画在哪 = 插在哪"）', () {
    test(r'`\sum|` 之后打字 ⇒ 落点挪进下限（否则上下限被顶开）', () {
      const String src = r'$\sum_{i=1}^{n}a_i$';
      final InsertPlan p = planInsert(src, 5, 'X'); // 5 = tex 里的 4
      expect(p.moved, isTrue);
      expect(p.wrapBareArg, isNull);
      expect(p.offset, 7, reason: r'= `_{` 之内第一格（tex 6）');
    });

    test('裸参数里打字 ⇒ 先补花括号（区间是源坐标）', () {
      const String src = r'$a_i$';
      // 源：`$`0 `a`1 `_`2 `i`3 `$`4 ⇒ 位点在 i 前 = 3
      final InsertPlan p = planInsert(src, 3, 'X');
      expect(p.moved, isTrue);
      expect(p.wrapBareArg, isNotNull);
      expect(p.wrapBareArg!.start, 3);
      expect(p.wrapBareArg!.end, 4);
      expect(p.offset, 4, reason: '补完括号后 = `{` 之后一格');
    });

    test('普通位置打字 ⇒ 一动不动（不打扰）', () {
      const String src = r'$a+b$';
      expect(planInsert(src, 3, 'X').moved, isFalse); // `+` 之后
      expect(planInsert('纯文本', 2, 'X').moved, isFalse);
    });

    test('换行规则仍然有效（规则没被吞掉）', () {
      const String src = r'文字。$\frac{a}{b}$';
      final InsertPlan p = planInsert(src, src.length - 1, '\n\n');
      expect(p.moved, isTrue);
      expect(p.why, contains('不能跨行'));
    });
  });
}
