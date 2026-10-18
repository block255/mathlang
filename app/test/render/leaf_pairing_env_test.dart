// ★★ 叶盒配对：**环境外框**不该让整份配对判死（2026-10-18 晚）
//
// 用户报：「一串行内符号之间点不进去（… + **矩阵那一行**）」。
// 探针（真实 KaTeX 字体、字号 20）：
//   `\begin{pmatrix} a & b \\ c & d \end{pmatrix}`
//     atoms=4（a b c d） boxes=6（`(` a b c d `)`）⇒ 第一遍配对在
//     "原子 a 期望画 a、实际盒是 `(`" 处直接判死 ⇒ `reliable=false`
//     ⇒ 点矩阵里任何一个格子都退化成"结构之前/之后"。
//   `\begin{cases} … \end{cases}` 同理（外框 `{`）。
//   `\ `（空格命令）：引擎画**空格字形盒**，旧代码把这个原子当成"无墨"跳过
//     ⇒ 后面每个原子往前错一格 ⇒ 整份不完整（实测 16 原子/16 盒却报"还剩 □"）。
//
// 判据：**源码里没有的盒**（外框定界符）跳过；**纯空白字形盒**不算剩盒。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/leaf_boxes.dart';
import 'package:mathlang/render/leaf_pairing.dart';
import 'package:mathlang/render/slot_marks.dart';

import '../support/math_fonts.dart';

typedef _Rig = ({RenderBox root, LeafBoxScan scan, String tex});

Future<_Rig> _pump(WidgetTester tester, String tex, {bool display = true}) async {
  final String rt = renderMathTex(tex, caretRel: -1);
  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: Math.tex(rt,
            key: key,
            mathStyle: display ? MathStyle.display : MathStyle.text,
            textStyle: const TextStyle(fontSize: 20)),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  final RenderBox root = key.currentContext!.findRenderObject()! as RenderBox;
  return (root: root, scan: scanLeafBoxes(root), tex: rt);
}

LeafPairing _pair(_Rig r, {bool display = true}) => buildLeafPairing(
      tex: r.tex,
      boxes: r.scan.eligible,
      atoms: renderOrderAtoms(r.tex, displayStyle: display),
    );

void main() {
  setUpAll(() async => loadMathFonts());

  testWidgets('★ 矩阵：外框括号没有源码对应 ⇒ **仍然配对完整**（改前：不完整）',
      (WidgetTester tester) async {
    final _Rig r = await _pump(tester, r'\begin{pmatrix} a & b \\ c & d \end{pmatrix}');
    final LeafPairing p = _pair(r);
    expect(p.complete, isTrue, reason: '原因：${p.reason}');
    expect(p.groups.length, 4, reason: '四个字母各一组（括号不占组）');
    // 每一组的盒必须**只是那个字**：`a` 那一组的盒文本应该是 'a'
    final PairGroup ga = p.groups.first;
    expect(r.scan.eligible.sublist(ga.boxFrom, ga.boxTo).map((LeafBox b) => b.text),
        <String>['a']);
  });

  testWidgets('★ 矩阵（行内）：同样完整', (WidgetTester tester) async {
    final _Rig r =
        await _pump(tester, r'\begin{pmatrix} a & b \\ c & d \end{pmatrix}', display: false);
    final LeafPairing p = _pair(r, display: false);
    expect(p.complete, isTrue, reason: '原因：${p.reason}');
  });

  testWidgets('★ cases：外框 `{` 跳过 ⇒ 完整', (WidgetTester tester) async {
    final _Rig r =
        await _pump(tester, r'\begin{cases} x & x>0 \\ -x & x\le 0 \end{cases}');
    final LeafPairing p = _pair(r);
    expect(p.complete, isTrue, reason: '原因：${p.reason}');
  });

  testWidgets('★ 命令形式的一串符号（含 `\\ ` 空格）：完整（改前：还剩 □）',
      (WidgetTester tester) async {
    final _Rig r = await _pump(
        tester,
        r'\Rightarrow\Leftrightarrow\Leftrightarrow\mapsto\ \infty\partial\nabla\angle\triangle\perp\parallel\bigcirc\because\therefore\square',
        display: false);
    final LeafPairing p = _pair(r, display: false);
    expect(p.complete, isTrue, reason: '原因：${p.reason}');
    expect(p.groups.length, 16, reason: '16 个原子各一组（含那个空格）');
  });

  testWidgets('★ `\\left(…\\right)` **不受影响**：括号有源码 ⇒ 照样要参与配对',
      (WidgetTester tester) async {
    final _Rig r = await _pump(tester, r'\left( x+1 \right)', display: false);
    final LeafPairing p = _pair(r, display: false);
    expect(p.complete, isTrue, reason: '原因：${p.reason}');
    // 括号必须是"被认领的盒"，不能被当成外框跳过
    final List<String> texts = <String>[
      for (final PairGroup g in p.groups)
        for (var i = g.boxFrom; i < g.boxTo; i++) r.scan.eligible[i].text ?? '',
    ];
    expect(texts, contains('('));
    expect(texts, contains(')'));
  });

  testWidgets('★ 用户原样那串（unicode）本来就完整 —— 别被这轮改动弄坏',
      (WidgetTester tester) async {
    final _Rig r = await _pump(
        tester,
        '\u21d2\u21d4\u21d4\u21a6 \u221e\u2202\u2207\u2220\u25b3\u22a5\u2225\u25cb\u2235\u2234\u25a1',
        display: false);
    final LeafPairing p = _pair(r, display: false);
    expect(p.complete, isTrue, reason: '原因：${p.reason}');
  });
}
