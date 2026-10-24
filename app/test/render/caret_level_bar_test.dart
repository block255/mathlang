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
//
// ★★★ 2026-10-24（批 16，用户拍板）：**脚本档（`^` / `_` 的内容）要单独变矮**。
//   批 15 把高度的口径统一成"该层字形盒"之后，指数档 10.9 vs 分子档 11.6
//   —— 只差 0.7 px，全靠位置区分（用户原话："一眼看不出我在指数里"）。
//   现行口径：`findLocalRowBox(script: true)` ⇒ `min(行盒 × kLineToGlyph, 字形盒)` = 8.6
//   ⇒ 条高 ≈7.3；非脚本槽照旧 = 字形盒。判据由位点表给（`isScriptSite`），不靠几何猜。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/leaf_boxes.dart';
import 'package:mathlang/render/math_caret.dart';
import 'package:mathlang/render/slot_marks.dart';

import '../support/math_fonts.dart';

const String tex = r'\frac{x^{3}}{y}';

Future<({Rect bar, LeafBoxScan scan, RenderObject root})> probeBar(
    WidgetTester tester, int caretRel,
    {bool script = false}) async {
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
  final Rect? row = findLocalRowBox(root, at, anchor: anchor, script: script);
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
    final scr = await probeBar(tester, 10, script: true);
    expect(num.bar.bottom - scr.bar.bottom, greaterThan(2.5),
        reason: '分子尾底部 12.6 左右、指数尾 9.0 左右（改前两者几乎相同）');
    expect(num.bar.height, greaterThan(scr.bar.height),
        reason: '分子档要比脚本档高（改前 8.8 < 11.0，反了）');
    // ★ 批 16：两档的**高度差**要肉眼可辨（不再只靠位置区分）
    expect(num.bar.height - scr.bar.height, greaterThan(3.0),
        reason: '批 15 之后只差 0.7 px（10.9 vs 11.6）⇒ 用户"一眼看不出我在指数里"');
  });

  testWidgets('★ 指数尾的竖条仍然落在指数那一带（不许被分子行抢走）',
      (WidgetTester tester) async {
    final r = await probeBar(tester, 10, script: true);
    final Rect three =
        r.scan.eligible.firstWhere((LeafBox b) => b.text == '3').rect;
    expect(three.bottom - r.bar.bottom, lessThan(3.0),
        reason: '指数里的 `3` 盒底 10.0 ⇒ 竖条底应在 9 上下');
    // ★★★ 2026-10-24（批 16，用户拍板"变矮"）：脚本槽单独缩回
    //   `min(行盒 × kLineToGlyph, 本层字形盒)` = 8.6 ⇒ 条高 ≈ 7.3。
    //   批 15 时这里是 10.9（= `3` 的字形盒 13.0 × 0.84），与分子档 11.6 只差 0.7 px。
    expect(r.bar.height, lessThan(10.0), reason: '脚本档（改前 10.9）');
    expect(r.bar.height, greaterThan(5.0), reason: '也不许缩成一个小点');
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
