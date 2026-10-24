// ★★ 2026-10-24（批 7 · A1）：**竖条要跟"同层的字"底部对齐，并且两档明显不同**
//
// 用户实测（2026-10-24 的三张图）：
//   「图 1 是在指数后面的……可是对比一下指数位后面的光标，存在视觉差别过小的问题；
//     而且光标底部明显跟 x 底部不对齐」
// 改前实测（`\frac{x^{3}}{y}`，20 px，text 样式）：
//   · 分子尾（rel 11）：竖条 `0.8..9.6`（h=8.8），而分子里的 `x` 盒是 `−0.2..13.8`
//     ⇒ **底部悬空 4.2 px**
//   · 指数尾（rel 10）：竖条 `−2.0..9.0`（h=11.0）⇒ **比分子尾还高**，两档看不出差别
//
// 批 7 的判据：锚点所在行的盒底 = 本层基线；只取"自己那层行的盒底与它对得上的（≤1.2 px）"
// 字形盒；高度 = min(行盒 → 字形盒, 本层字形盒)，**底边贴字形盒底**。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/leaf_boxes.dart';
import 'package:mathlang/render/math_caret.dart';
import 'package:mathlang/render/slot_marks.dart';

import '../support/math_fonts.dart';

const String tex = r'\frac{x^{3}}{y}';

Future<({Rect bar, LeafBoxScan scan, RenderObject root})> probeBar(
    WidgetTester tester, int caretRel) async {
  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: MathWithCaret(
          tex: renderMathTex(tex, caretRel: caretRel),
          showCaret: true,
          mathKey: key,
          mathStyle: MathStyle.text,
          textFontSize: 20,
          fontSize: 20,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  final RenderObject root = key.currentContext!.findRenderObject()!;
  final RenderBox? anchor = findCaretAnchor(root);
  expect(anchor, isNotNull);
  final Offset at = anchor!.localToGlobal(Offset.zero, ancestor: root);
  final Rect? row = findLocalRowBox(root, at, anchor: anchor);
  final Rect bar =
      caretBarRect(at: at, localRowBox: row, width: 1.5, fontSize: 20);
  return (bar: bar, scan: scanLeafBoxes(root), root: root);
}

void main() {
  setUpAll(() async => loadMathFonts());

  // 位点（探针实测）：0 / 6 / 7(glue) / 9 / 10 / 11 / 13 / 14 / 15
  testWidgets('★★ 分子尾的竖条**底部与同层的 `x` 对齐**', (WidgetTester tester) async {
    final r = await probeBar(tester, 11);
    final Rect xBox =
        r.scan.eligible.firstWhere((LeafBox b) => b.text == 'x').rect;
    expect(xBox.bottom - r.bar.bottom, lessThan(2.0),
        reason: '改前底部悬空 4.2 px（竖条 9.6 vs `x` 盒 13.8）');
    expect(r.bar.height, greaterThan(11.0),
        reason: '改前只有 8.8（拿的是行盒）');
  });

  testWidgets('★★ 分子尾必须**明显高于**指数尾（两档不许看不出差别）',
      (WidgetTester tester) async {
    final num = await probeBar(tester, 11);
    final scr = await probeBar(tester, 10);
    expect(num.bar.bottom - scr.bar.bottom, greaterThan(2.5),
        reason: '分子尾底部 12.6 左右、指数尾 9.0 左右（改前两者几乎相同）');
    expect(num.bar.height, greaterThan(scr.bar.height),
        reason: '分子档要比脚本档高（改前 8.8 < 11.0，反了）');
  });

  testWidgets('★ 指数尾的竖条仍然落在指数那一带（不许被分子行抢走）',
      (WidgetTester tester) async {
    final r = await probeBar(tester, 10);
    final Rect three =
        r.scan.eligible.firstWhere((LeafBox b) => b.text == '3').rect;
    expect(three.bottom - r.bar.bottom, lessThan(3.0),
        reason: '指数里的 `3` 盒底 10.0 ⇒ 竖条底应在 9 上下');
    // ★ 高度按"脚本那一层的行盒"（6.4×1.35 = 8.6），**不是**分子那一档的 13.8 ——
    //   这正是"两档看得出差别"的来源；竖条比字形矮一点是正常的（光标不画到字顶上）。
    expect(r.bar.height, lessThan(10.0), reason: '脚本档要明显矮于行档（13.8）');
  });

  testWidgets('★ 分母那一档也有自己的行高（不跟着分子走）', (WidgetTester tester) async {
    final r = await probeBar(tester, 14);
    final Rect y = r.scan.eligible.firstWhere((LeafBox b) => b.text == 'y').rect;
    expect(y.bottom - r.bar.bottom, lessThan(2.5),
        reason: '分母竖条底部要贴 `y` 的盒底（28.6）');
  });

  testWidgets('★ 对照：主行竖条照旧（不被这轮改动带偏）', (WidgetTester tester) async {
    final r = await probeBar(tester, 0);
    expect(r.bar.height, greaterThan(9.0));
    expect(r.bar.height, lessThan(30.0));
  });
}
