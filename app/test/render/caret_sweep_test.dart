// ★★ "按 → 每一步都要看得见变化"的守门人（2026-10-17，用户用箭头扫出来的三处"没反应"）
//
// 用户原话（从 `∑` 左边开始按 `→`）：
//   「1 i 前面，2 **没反应**，3 i 后面，4 = 后面，5 1 后面，6 n 前面，7 **没反应**，
//     8 a 前面，9 a 与 i 之间，10 **没反应**，11 ai 后面」
//
// 三处"没反应"的根因：**"粘合位点"的注入被挪进了脚本内容开头**（§11.31 的结合中性规则），
// 于是它和"脚本自己的第一个位点"画在**同一根像素**上：
//   位点 4（`\sum` 之后）与 6（下限第一格）· 位点 10 与 12（上限第一格）· 位点 15 与 16（下标第一格）
//
// 修法：位点照旧保留（点击/吸附要用），但**方向键跳过粘合位点**（`CaretSite.glue`）。
//
// 判据（全域）：沿 `nextCaretOffset` 走一遍，**每一步的竖条矩形都必须与上一步不同**；
// 并且竖条高度要落在"一行字"的量级（不许再出现被拉伸行盒导致的 38.6）。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/math_caret.dart';
import 'package:mathlang/render/math_nav.dart';
import 'package:mathlang/render/slot_marks.dart';

import '../support/math_fonts.dart';

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
  // ★ 直接算几何（`findCaretAnchor` + `findLocalRowBox` + `caretBarRect`），不走"帧末量、下帧画"
  //   —— 那样读到的会**慢一帧**（本仓记账里的"自绘竖条晚一帧"），测试里会全体错位一格。
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

void main() {
  setUpAll(() async => loadMathFonts());

  // ★ 竖条高度：**单独两个用例**（每个只渲一次，避免"上一步的值"混进来）
  testWidgets(r'★ `\sum` 的**首位点**竖条不许是"被拉伸行盒"造成的长光标',
      (WidgetTester tester) async {
    final Rect? bar = await _bar(tester, r'\sum_{i=1}^{n}a_i', 0);
    expect(bar, isNotNull);
    expect(bar!.height, lessThan(26),
        reason: '修前是 38.6（`∑` 的行盒 46 × 0.84）；按行高裁之后 ≈15');
  });

  testWidgets(r'★ `\sum` 的**末位点**同理（用户："直接点末尾是长蓝光标"）',
      (WidgetTester tester) async {
    const String tex = r'\sum_{i=1}^{n}a_i';
    final Rect? bar = await _bar(tester, tex, tex.length);
    expect(bar, isNotNull);
    expect(bar!.height, lessThan(26), reason: '修前 38.6');
  });

  testWidgets('★ 金表：`\\sum_{i=1}^{n}a_i` 的 `→` 序列（与用户扫出来的 11 步对齐）',
      (WidgetTester tester) async {
    const String tex = r'\sum_{i=1}^{n}a_i';
    const String source = '\$$tex\$';
    final MathRegion r = mathRegionAt(source, 1)!;
    final List<int> stops = <int>[];
    var caret = r.contentStart;
    for (var k = 0; k < 20; k++) {
      stops.add(caret);
      final int next = nextCaretOffset(source, caret);
      if (next >= r.closeEnd || next <= caret) break;
      caret = next;
    }
    // tex 偏移：0（公式首）→ 6（下限首）→ 7 → 8 → 9 → 12（上限首）→ 13 → 14（主行 `a`）→ 16（下标首）
    // ★ 粘合位点 4 / 10 / 15 不该出现在 `→` 的停靠序列里（`stops` 是绝对偏移 ⇒ 减 contentStart）
    // ★ 16 之后 `→` 就**走出公式**了（17 = tex 末尾那一格按「甲」被跳过 ⇒ 用户看到的是"ai 后面"）
    final List<int> rel = <int>[for (final int o in stops) o - r.contentStart];
    expect(rel, <int>[0, 6, 7, 8, 9, 12, 13, 14, 16],
        reason: '★ 粘合位点 4 / 10 / 15 不该出现在 `→` 的停靠序列里');
  });

  testWidgets('★ 粘合位点仍然在**位点表**里（点击与吸附要用）', (WidgetTester tester) async {
    final CaretSiteTable t = buildCaretSites(r'\sum_{i=1}^{n}a_i');
    expect(t.isSite(4), isTrue);
    expect(t.at(4)!.glue, isTrue);
    expect(t.at(10)!.glue, isTrue);
    expect(t.at(15)!.glue, isTrue);
    expect(t.at(6)!.glue, isFalse);
    expect(t.at(14)!.glue, isFalse);
  });
}
