// ★★★ 2026-10-24（批 19 · F1-c）：`aligned` 四个填点的**格框要左右一致**。
//
// 用户实测：「左边两个位置我光标移进去有框，但是右边的位置我光标到那里也没有框」。
// 真因（探针）：`&=\\&=` 的**右格内容就是那个 `=`**（`&=` 的 `=` 属于第 2 列），
//   而旧判据是"格里有字形 ⇒ 不画框" ⇒ 右格永远不画。
// 口径（用户 2026-10-24 定，**窄口径**）：只把**紧贴格左缘的那个 `=`**（对齐记号）排除在外，
//   其余任何字形都算内容 ⇒ 一旦格里填了真东西就不再画框（不做"光标在不在都画"）。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/leaf_boxes.dart';
import 'package:mathlang/render/math_caret.dart';
import 'package:mathlang/render/slot_marks.dart';

import '../support/math_fonts.dart';

const String kTemplate = r'\begin{aligned}&=\\&=\end{aligned}';

/// 把光标放进 [rel] 那一格，返回这一帧算出的**格框垫子**个数
Future<int> boxesAt(WidgetTester tester, String tex, int rel) async {
  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: MathWithCaret(
          tex: renderMathTex(tex, caretRel: rel),
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
  final _MathWithCaretStateProbe probe =
      _MathWithCaretStateProbe(tester.state(find.byType(MathWithCaret)));
  return probe.pads.length;
}

/// 只为读 `debugPads`（`State` 是私有的，用 dynamic 访问）
class _MathWithCaretStateProbe {
  _MathWithCaretStateProbe(this.state);
  final State<MathWithCaret> state;
  List<SlotPad> get pads => (state as dynamic).debugPads as List<SlotPad>;
}

void main() {
  setUpAll(() async => loadMathFonts());

  testWidgets(r'★ 左格（`&` 之前）有框', (WidgetTester tester) async {
    expect(await boxesAt(tester, kTemplate, 15), greaterThan(0));
  });

  testWidgets(r'★ 右格（`=` 之后）**也要有框** —— 改前是 0（`=` 被当成了内容）',
      (WidgetTester tester) async {
    expect(await boxesAt(tester, kTemplate, 17), greaterThan(0),
        reason: r'改前：右格内容就是 `=` ⇒ hasGlyph=true ⇒ 不画框');
  });

  testWidgets(r'★ 第二行两格同样都有框（左右一致）', (WidgetTester tester) async {
    expect(await boxesAt(tester, kTemplate, 19), greaterThan(0));
    expect(await boxesAt(tester, kTemplate, 21), greaterThan(0));
  });

  testWidgets('★ 格里填了真内容 ⇒ 不画框（"不用有字还画"）', (WidgetTester tester) async {
    // `a` 填在第 1 行左格 ⇒ 那一格不该再画框
    expect(await boxesAt(tester, r'\begin{aligned}a&=b\\c&=d\end{aligned}', 16), 0);
  });

  testWidgets(r'★★ 右格的框**不许盖在等号身上**（用户 2026-10-24 四张图）',
      (WidgetTester tester) async {
    final GlobalKey key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: MathWithCaret(
            tex: renderMathTex(kTemplate, caretRel: 17),
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
    final State<MathWithCaret> st = tester.state(find.byType(MathWithCaret));
    final List<SlotPad> pads =
        (st as dynamic).debugPads as List<SlotPad>;
    expect(pads, isNotEmpty, reason: '右格应当有框');
    // 找那个 `=`（对齐记号）的字形盒
    final RenderObject root = key.currentContext!.findRenderObject()!;
    final LeafBox eq = scanLeafBoxes(root)
        .eligible
        .firstWhere((LeafBox b) => (b.text ?? '').trim() == '=');
    expect(pads.first.rect.left, greaterThanOrEqualTo(eq.rect.right),
        reason: '框的左缘必须退到 `=` 右缘之后（改前：框 x=20..35.6，`=` 也是 20..35.6 ⇒ 盖上了）');
  });
}
