// 叶盒 ↔ 可见原子 配对的守门人（2026-10-17，旧账第一批）
//
// ★ 为什么必须有这一份：`hitTestMathTex` 原来按**下标 zip** 两列，判据是"两列长度相等"。
//   探针量出两列**天然不等**，而且顺序也会变 ——
//   ① `\sin x` = **4 盒 / 2 原子**（`\sin` 画成 s、i、n 三个字形盒）⇒ 旧判据下**点了没反应**；
//   ② `\sum_{i=1}^{n}a_i`（display）盒序 `[上限n, ∑, 下限i, …]` ≠ 源序 ⇒ 旧判据下**点 A 落 B**；
//   ③ `x^{2}_{1}` 盒序 `[x, 下标1, 上标2]`（引擎 `MultiscriptsNode` 的顺序是 base, sub, sup）；
//   ④ `\sqrt[3]{x}` 的次数画在被开方数**之后**。
//   ⇒ 这一份把"**每个盒对应源码里的哪一段**"钉成金表，并且对全域语料断言"配对完整"。
//
// ★ 数据来源：探针（2026-10-17，真实 KaTeX 字体、字号 20）＋ 引擎源码
//   `_cache\pub\...\flutter_math_fork-0.7.4` 的 `op.dart` / `multiscripts.dart` / `over.dart`。
//   详见 `lib/render/leaf_pairing.dart` 文件头与《位点与结构导航》§11.29。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/hit_map.dart';
import 'package:mathlang/render/injection_map.dart';
import 'package:mathlang/render/leaf_boxes.dart';
import 'package:mathlang/render/leaf_pairing.dart';
import 'package:mathlang/render/slot_marks.dart';

import '../support/math_fonts.dart';

typedef _Probe = ({
  RenderBox root,
  LeafBoxScan scan,
  String renderTex,
  LeafPairing plan,
});

Future<_Probe> _pump(
  WidgetTester tester,
  String tex, {
  bool display = true,
}) async {
  // ★ 走**真实注入链**（与 DocView 同一个入口）：尾垫/空槽垫都在 → 配对的账才是真账
  final String renderTex = renderMathTex(tex, caretRel: -1);
  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: Math.tex(
          renderTex,
          key: key,
          mathStyle: display ? MathStyle.display : MathStyle.text,
          textStyle: const TextStyle(fontSize: 20),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  final RenderBox root = key.currentContext!.findRenderObject()! as RenderBox;
  final LeafBoxScan scan = scanLeafBoxes(root);
  return (
    root: root,
    scan: scan,
    renderTex: renderTex,
    plan: buildLeafPairing(
      tex: renderTex,
      boxes: scan.eligible,
      atoms: renderOrderAtoms(renderTex, displayStyle: display),
    ),
  );
}

/// 组在**原始 tex**（未注入）里的源区间
({int start, int end}) _src(_Probe r, PairGroup g) => (
      start: renderToSourceOffset(r.renderTex, g.srcStart),
      end: renderToSourceOffset(r.renderTex, g.srcEnd),
    );

void main() {
  setUpAll(() async => loadMathFonts());

  // -------------------------------------------------------------------------
  // 一、金表：每个盒对应源码里的哪一段（这两种坏法的现场）
  // -------------------------------------------------------------------------

  testWidgets('★ 多字母算子名：`\\sin` = 3 个字形盒，但**一个**原子、一个组',
      (WidgetTester tester) async {
    final _Probe r = await _pump(tester, r'\sin x');
    expect(r.plan.complete, isTrue, reason: '${r.plan.reason}');
    // 4 盒 vs 2 原子 —— 旧判据在这里判"不可靠"，于是点什么都没反应
    expect(r.scan.eligible.length, 4);
    expect(r.plan.groups.length, 2);
    final PairGroup sin = r.plan.groups[0];
    expect(sin.boxTo - sin.boxFrom, 3, reason: '`\\sin` 画成 3 个盒');
    expect(_src(r, sin).start, 0);
    expect(_src(r, sin).end, 4);
    expect(_src(r, r.plan.groups[1]).start, 5, reason: '`x`');
  });

  testWidgets('★ 堆叠上下限（display）：盒序 = [上限, 算子, 下限]',
      (WidgetTester tester) async {
    final _Probe r = await _pump(tester, r'\sum_{i=1}^{n}a_i');
    expect(r.plan.complete, isTrue, reason: '${r.plan.reason}');
    // 第 0 个盒画的是 "n" —— 它是**上限**，源码在 [12,13)
    expect(r.scan.eligible[0].text, 'n');
    expect(_src(r, r.plan.groupOfBox(0)!).start, 12);
    // 第 1 个盒是 ∑ 本身（源码 [0,4)）
    expect(r.scan.eligible[1].text, '∑');
    expect(_src(r, r.plan.groupOfBox(1)!).start, 0);
    expect(_src(r, r.plan.groupOfBox(1)!).end, 4);
    // 第 2 个盒是下限的第一项
    expect(_src(r, r.plan.groupOfBox(2)!).start, 6);
  });

  testWidgets('★ 堆叠上下限（text）：退回脚本位 = [算子, 下限, 上限]',
      (WidgetTester tester) async {
    final _Probe r = await _pump(tester, r'\sum_{i=1}^{n}a_i', display: false);
    expect(r.plan.complete, isTrue, reason: '${r.plan.reason}');
    expect(r.scan.eligible[0].text, '∑');
    expect(_src(r, r.plan.groupOfBox(0)!).start, 0);
    // 行内样式下上限在**后面**（Multiscripts 的 base, sub, sup）
    expect(r.scan.eligible[4].text, 'n');
    expect(_src(r, r.plan.groupOfBox(4)!).start, 12);
  });

  testWidgets('★ 上下标同时存在：盒序 = [基座, 下标, 上标]（与源码谁先写无关）',
      (WidgetTester tester) async {
    final _Probe r = await _pump(tester, r'x^{2}_{1}');
    expect(r.plan.complete, isTrue, reason: '${r.plan.reason}');
    expect(r.scan.eligible[0].text, 'x');
    expect(r.scan.eligible[1].text, '1', reason: '第 2 个盒是**下标**');
    expect(r.scan.eligible[2].text, '2', reason: '第 3 个盒是**上标**');
    expect(_src(r, r.plan.groupOfBox(1)!).start, 7); // `_1` 的 1
    expect(_src(r, r.plan.groupOfBox(2)!).start, 3); // `^2` 的 2
  });

  testWidgets('★ 根号次数画在被开方数**之后**（`\\sqrt[3]{x}`）',
      (WidgetTester tester) async {
    final _Probe r = await _pump(tester, r'\sqrt[3]{x}');
    expect(r.plan.complete, isTrue, reason: '${r.plan.reason}');
    // 盒序：x（被开方数）→ 尾垫 → 3（次数）
    final List<String?> texts = <String?>[
      for (final LeafBox b in r.scan.eligible) b.text,
    ];
    expect(texts.first, 'x');
    expect(texts.last, '3');
    expect(_src(r, r.plan.groupOfBox(r.scan.eligible.length - 1)!).start, 6);
  });

  testWidgets('★ 其余常见结构：配对必须完整（含 `\\lim` / `\\log` / `\\max` / `\\arg`）',
      (WidgetTester tester) async {
    const List<String> texs = <String>[
      r'\lim_{x\to0}\frac{\sin x}{x}',
      r'\log_{2}x',
      r'\max_{x\in S}x',
      r'\arg\max_x f',
      r'\sin^2\theta+\cos^2\theta=1',
      r'\Delta=b^2-4ac',
      r'x=\frac{-b\pm\sqrt{b^2-4ac}}{2a}',
      r'\int_a^b f(x)\,dx',
      r'\prod_{k=1}^{m}k',
      r'\sqrt{x}+\sqrt{y}',
      r'\frac{a}{b}+\frac{c}{d}',
      r'\left(\frac{a}{b}\right)',
      r'\overline{AB}',
      r'\hat{x}',
      r'\text{abc}',
      r'\text{汉字}',
      r'a\neq b',
      r'\frac{}{}',
      r'\frac{}{2}',
      r'\sqrt{}',
      r'\sum_{}^{}',
      r'x_1x_2=\frac{c}{a}',
      r'\alpha+\beta',
    ];
    for (final bool display in <bool>[true, false]) {
      for (final String tex in texs) {
        final _Probe r = await _pump(tester, tex, display: display);
        expect(
          r.plan.complete,
          isTrue,
          reason: '「$tex」(${display ? "display" : "text"}) '
              '盒 ${r.scan.eligible.length} / 原子 ?：${r.plan.reason}',
        );
        // 每个字形盒都必须有归属
        for (var i = 0; i < r.scan.eligible.length; i++) {
          if (r.scan.eligible[i].kind != LeafBoxKind.glyph) continue;
          expect(r.plan.groupOfBox(i), isNotNull,
              reason: '「$tex」第 $i 个盒没配对');
        }
      }
    }
  });

  // -------------------------------------------------------------------------
  // 二、点下去到底落在哪（端到端：点每一个字形盒）
  // -------------------------------------------------------------------------

  testWidgets('★ 点每个字形盒：可靠，且落点就在这一组的源区间里',
      (WidgetTester tester) async {
    const List<String> texs = <String>[
      r'\sin x',
      r'\lim_{x\to0}\frac{\sin x}{x}',
      r'\sum_{i=1}^{n}a_i',
      r'\prod_{k=1}^{m}k',
      r'x^{2}_{1}',
      r'\sqrt[3]{x}',
      r'\log_{2}x',
      r'\int_a^b f(x)\,dx',
      r'\frac{}{}',
      r'\sqrt{}',
    ];
    for (final bool display in <bool>[true, false]) {
      for (final String tex in texs) {
        final _Probe r = await _pump(tester, tex, display: display);
        for (var i = 0; i < r.scan.eligible.length; i++) {
          final LeafBox b = r.scan.eligible[i];
          if (b.kind != LeafBoxKind.glyph || (b.text ?? '').isEmpty) continue;
          final MathHit hit = hitTestMathTex(
            root: r.root,
            localPos: b.rect.center,
            tex: r.renderTex,
            atoms: renderOrderAtoms(r.renderTex, displayStyle: display),
            displayStyle: display,
          );
          expect(hit.reliable, isTrue,
              reason: '「$tex」(${display ? "display" : "text"}) 盒#$i '
                  '"${b.text}"：${hit.pairing?.reason}');
          final PairGroup g = r.plan.groupOfBox(i)!;
          expect(hit.offset, anyOf(g.srcStart, g.srcEnd),
              reason: '「$tex」盒#$i "${b.text}" 落点应在 [$g] 内');
        }
      }
    }
  });

  // -------------------------------------------------------------------------
  // 三、记账：现在还**配不上**的那几类（宁可粗，不许错）
  // -------------------------------------------------------------------------

  testWidgets('★ 记账：这几类目前整份判为不完整 ⇒ 退回结构层落点（不许点 A 落 B）',
      (WidgetTester tester) async {
    // 分段函数：大括号是一个**字形盒**、`cases` 还有列间距盒 ⇒ 还没进配对规则
    // （env 名已不再当原子，见 visible_atoms 的 `begin`/`end`）
    final _Probe cases = await _pump(tester, r'\begin{cases}a&b\\c&d\end{cases}');
    expect(cases.plan.complete, isFalse,
        reason: '若这条变绿 ⇒ 分段函数已经支持，请把它挪进上面的金表并删掉这条记账');

    // overbrace：引擎把上标画在**内容之前**（探针实测 [n, A, B]），还没进渲染顺序表
    final _Probe brace = await _pump(tester, r'\overbrace{AB}^{n}');
    expect(brace.plan.complete, isFalse,
        reason: '若这条变绿 ⇒ overbrace 的顺序规则已经补上，请挪进金表');
  });

  testWidgets('★ 不完整时 `hitTestMathTex` 必须给 null（调用方才知道要退回结构层）',
      (WidgetTester tester) async {
    final _Probe r = await _pump(tester, r'\begin{cases}a&b\\c&d\end{cases}');
    final LeafBox b = r.scan.eligible.firstWhere((LeafBox x) => x.isGlyph);
    final MathHit hit = hitTestMathTex(
      root: r.root,
      localPos: b.rect.center,
      tex: r.renderTex,
      displayStyle: true,
    );
    expect(hit.reliable, isFalse);
    expect(hit.offset, isNull);
  });
}
