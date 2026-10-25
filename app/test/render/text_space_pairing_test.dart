// `\text{…}` 里的**空格**是一个"空格字形盒"，但词法侧不算原子
//   ⇒ 旧配对把它当成"该原子画的那个字" ⇒ **`\text` 之后整份配对失败** ⇒ 那一块点击整体退化。
//
// ★ 为什么必须有这一份（2026-10-24 用户实测，`20261019作业` 两条）：
//   · ① 旁注 `\quad (\text{旁注：当 } …)`：CJK 上有盒、位点表也正常，但点下去落到**别的偏移**
//     （探针：点「旁」⇒ 落 `\ln(` 那一带、点「：」⇒ **点了没反应**）；
//     配对原因串原话：`原子 x[20,21) 期望画 "x"，实际盒是 " "（第 6 个）`。
//   · ③ 行间 `0 < |x-x_0| < \delta \text{ 时 } |\frac{1}{f(x)}| < \varepsilon`：
//     `\text{ 时 }` 有两个空格盒 ⇒ 整块「点了没反应」（探针 v47：x=0/1/2 全无反应）。
//   · 数字：整行 45 盒 vs 38 原子 —— 多出来的 7 个 = 3 个空格盒 + 1 个 `\quad` 垫盒
//     + `\lim` 多 2 个字形盒 + `\ln` 多 1 个（后三个是**正确**的渲染，配对本来就支持）。
//
// ★ 判据只加一条：**纯空白的字形盒不吃"内容盒"名额** ——
//   例外只有一种：**原子自己就是空格**（`\ ` 空格命令，源码里那一个字符是空白）。
//   不许为了变绿把"数量不等"放宽（本仓踩过四次：`hitTestMathTex` 静默返回 null）。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/hit_map.dart';
import 'package:mathlang/render/leaf_boxes.dart';
import 'package:mathlang/render/leaf_pairing.dart';
import 'package:mathlang/render/slot_marks.dart';
import 'package:mathlang/render/visible_atoms.dart';

import '../support/math_fonts.dart';

typedef _Rig = ({
  RenderBox root,
  LeafBoxScan scan,
  String renderTex,
  LeafPairing plan,
});

Future<_Rig> _pump(WidgetTester tester, String tex,
    {required bool display}) async {
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

bool _isSpaceText(LeafBox b) => (b.text ?? '').trim().isEmpty;

/// 纯空白字形盒（`\text{…}` 里的空格：有宽度、有字形盒，但没有字）
List<int> _spaceBoxes(LeafBoxScan scan) => <int>[
      for (var i = 0; i < scan.eligible.length; i++)
        if (scan.eligible[i].kind == LeafBoxKind.glyph &&
            _isSpaceText(scan.eligible[i]))
          i,
    ];

void main() {
  setUpAll(() async => loadMathFonts());

  // -------------------------------------------------------------------------
  // 一、全域：带 `\text{…}` 空格的 tex 必须**配对完整**（两种样式都跑）
  // -------------------------------------------------------------------------

  testWidgets('★ `\\text{…}` 里的空格不占"内容盒"名额 ⇒ 配对必须完整',
      (WidgetTester tester) async {
    const List<String> texs = <String>[
      // ★ 用户实测的两条（探针现场）
      r'\quad (\text{旁注：当 } x\to+\infty \text{ 时 } -\frac{1}{x+1}\to0)',
      r'= \lim_{x\to+\infty} (x+1)\ln(1-\frac{1}{x+1}) \quad (\text{旁注：当 } x\to+\infty \text{ 时 } -\frac{1}{x+1}\to0)',
      r'0 < |x-x_0| < \delta \text{ 时 } |\frac{1}{f(x)}| < \varepsilon',
      // 基本形
      r'\text{a b}',
      r'\text{ 时 }',
      r'\text{旁注：当 }',
      r'x+\text{当 }y',
      r'\frac{1}{M} < \varepsilon',
      // 空格命令与 `\text` 混用（这一条是**反向**守卫：`\ ` 有墨迹、必须占一个盒）
      r'a\ b',
      r'\text{甲} \text{乙}',
    ];
    for (final bool display in <bool>[true, false]) {
      for (final String tex in texs) {
        final _Rig r = await _pump(tester, tex, display: display);
        expect(
          r.plan.complete,
          isTrue,
          reason: '「$tex」(${display ? "display" : "text"}) 盒 ${r.scan.eligible.length} '
              '/ 原子 ${renderOrderAtoms(r.renderTex, displayStyle: display).length}：'
              '${r.plan.reason}',
        );
      }
    }
  });

  // -------------------------------------------------------------------------
  // 二、每个**有字**的字形盒都要有归属（空白盒除外 —— 它没有字，点是"旁边的空白"）
  // -------------------------------------------------------------------------

  testWidgets('★ 有字的叶盒必须都有配对组（空白盒允许无主）',
      (WidgetTester tester) async {
    const List<String> texs = <String>[
      r'\quad (\text{旁注：当 } x\to+\infty \text{ 时 } -\frac{1}{x+1}\to0)',
      r'0 < |x-x_0| < \delta \text{ 时 } |\frac{1}{f(x)}| < \varepsilon',
      r'\text{a b}',
      r'a\ b',
    ];
    for (final bool display in <bool>[true, false]) {
      for (final String tex in texs) {
        final _Rig r = await _pump(tester, tex, display: display);
        final List<int> spaces = _spaceBoxes(r.scan);
        for (var i = 0; i < r.scan.eligible.length; i++) {
          final LeafBox b = r.scan.eligible[i];
          if (b.kind != LeafBoxKind.glyph) continue;
          if (spaces.contains(i)) continue;
          expect(r.plan.groupOfBox(i), isNotNull,
              reason: '「$tex」(${display ? "display" : "text"}) 第 $i 个盒 '
                  '"${b.text}" 没配上原子（空白盒下标 $spaces）');
        }
      }
    }
  });

  // -------------------------------------------------------------------------
  // 三、端到端：点在「旁注：当」这四个字上 ⇒ 可靠命中，且落点就在这个字的区间里
  // -------------------------------------------------------------------------

  testWidgets('★ 点旁注里的每个 CJK 字 ⇒ 可靠命中，落点就在该字区间内',
      (WidgetTester tester) async {
    const String tex =
        r'\quad (\text{旁注：当 } x\to+\infty \text{ 时 } -\frac{1}{x+1}\to0)';
    final _Rig r = await _pump(tester, tex, display: true);
    final List<String> cjk = <String>['旁', '注', '：', '当', '时'];
    for (final String ch in cjk) {
      final int idx =
          r.scan.eligible.indexWhere((LeafBox b) => b.text == ch);
      expect(idx, greaterThanOrEqualTo(0), reason: '「$ch」连叶盒都没有？');
      final MathHit hit = hitTestMathTex(
        root: r.root,
        localPos: r.scan.eligible[idx].rect.center,
        tex: r.renderTex,
        atoms: renderOrderAtoms(r.renderTex, displayStyle: true),
        displayStyle: true,
      );
      expect(hit.reliable, isTrue,
          reason: '点「$ch」必须可靠（${hit.pairing?.reason}）');
      final PairGroup g = r.plan.groupOfBox(idx)!;
      expect(hit.offset, anyOf(g.srcStart, g.srcEnd),
          reason: '点「$ch」落点应在 [$g] 内，实际 ${hit.offset}');
    }
  });

  testWidgets('★ ③ 行间那块：点 `x` 两侧与 `\\delta` 都要可靠（用户报"x 两侧点不到"）',
      (WidgetTester tester) async {
    const String tex =
        r'0 < |x-x_0| < \delta \text{ 时 } |\frac{1}{f(x)}| < \varepsilon';
    final _Rig r = await _pump(tester, tex, display: true);
    final List<VisibleAtom> atoms =
        renderOrderAtoms(r.renderTex, displayStyle: true);
    // 点每一个**有字**的叶盒
    final List<int> spaces = _spaceBoxes(r.scan);
    for (var i = 0; i < r.scan.eligible.length; i++) {
      final LeafBox b = r.scan.eligible[i];
      if (b.kind != LeafBoxKind.glyph || spaces.contains(i)) continue;
      final MathHit hit = hitTestMathTex(
        root: r.root,
        localPos: b.rect.center,
        tex: r.renderTex,
        atoms: atoms,
        displayStyle: true,
      );
      expect(hit.reliable, isTrue,
          reason: '盒#$i "${b.text}"：${hit.pairing?.reason}');
    }
  });

  // -------------------------------------------------------------------------
  // 五、④ 的收口：**带 `\text{…}` 空格的块里**，分式的分子/分母也必须点得到
  //
  // ★ 用户 2026-10-25 的话："④ 似乎在前一批被一起修掉了" —— 复核成立：
  //   他报"④ 分式子位点点不到"的现场，是 `0 < |x-x_0| < \delta \text{ 时 } |\frac{1}{f(x)}| < \varepsilon`
  //   那一块里的**分式**；而那一块因为空格盒整体配对失败 ⇒ 分式当然也点不到。
  //   单独拿出来测 `\frac{1}{M}`（配对本来就完整）永远测不出来 —— 这就是前一天
  //   "④ 不是配对"的判断为什么对不上现场：**判据对了，场景取窄了**。
  // -------------------------------------------------------------------------

  testWidgets(r'★ ④：`\text{ 时 }` 块里的分式，分子/分母每个原子都要点得到',
      (WidgetTester tester) async {
    const String tex =
        r'0 < |x-x_0| < \delta \text{ 时 } |\frac{1}{f(x)}| < \varepsilon';
    final _Rig r = await _pump(tester, tex, display: true);
    final List<VisibleAtom> atoms =
        renderOrderAtoms(r.renderTex, displayStyle: true);
    // 那个分式的源码范围 `\frac{1}{f(x)}`
    final int frac = r.renderTex.indexOf(r'\frac');
    expect(frac, greaterThanOrEqualTo(0));
    final int open1 = r.renderTex.indexOf('{', frac);
    final int close1 = matchBrace(r.renderTex, open1);
    final int open2 = close1 + 1;
    final int close2 = matchBrace(r.renderTex, open2);
    // 落在分式里的每一个原子：点它所在组的**外框中心** ⇒ 必须可靠，且落点在这一组里
    var checked = 0;
    for (final PairGroup g in r.plan.groups) {
      if (g.srcStart <= frac || g.srcEnd > close2) continue;
      checked++;
      final MathHit hit = hitTestMathTex(
        root: r.root,
        localPos: g.hull(r.scan.eligible).center,
        tex: r.renderTex,
        atoms: atoms,
        displayStyle: true,
      );
      expect(hit.reliable, isTrue,
          reason: '分式里的 ${g.atom.kind}[${g.srcStart},${g.srcEnd}) 点不到'
              '（${hit.pairing?.reason}）');
      expect(hit.offset, anyOf(g.srcStart, g.srcEnd),
          reason: '分式里 ${g.atom.kind} 的落点应在 [$g] 内，实际 ${hit.offset}');
    }
    expect(checked, greaterThanOrEqualTo(3),
        reason: '分式里至少要检查到 1 / f / x 三个原子（实际只查到 $checked 个）');
  });
}
