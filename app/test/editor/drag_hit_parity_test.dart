// 2026-11-01（反馈 19 续）：**拖选与点击必须用同一套命中**。
//
// ## 现场
// 用户两个动作：
//   ① 在分子 `D(x)` 的 `D` 左端按下、拖到同一个 `D` 的右端松手 ⇒ **选中了左边的 `\lim` 整体**；
//   ② 在同一处按下、拖到 `D(0)` 的 `)` 右边松手 ⇒ **整个分式被选中**（他只想选分子）。
//
// ## 根因（两套命中）
// · **点击**走公式自己的手势（`InlineMathText` → `_onMathTap` → `hitTestMathTex`）⇒ 精确到字形；
// · **拖选**走 `DocView.offsetAtGlobal` ⇒ 文字段只有"段落排版器"一条路，而段落里
//   行内公式被**整段删掉**（`_plainTextOf`）⇒ 点在公式内部只能吸到公式**边界**。
//   探针实测：`D` 上按下 ⇒ 偏移 **1**（= `$`）；拖到分子末尾 ⇒ 偏移 **14**（= `\frac` 起点）。
//
// ## 修法
// `InlineMathText.onMathLayout` 把每段公式的「key ＋ 渲染 tex」登记进 `DocView`；
// `_offsetAt` 的文字分支**先问公式自己的叶盒**（`_mathTapTexOffset`，与点击同一个函数），
// 命中就返回；没命中才回落到段落排版器。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/core/doc_settings.dart';
import 'package:mathlang/editor/doc_view.dart';
import 'package:mathlang/render/leaf_boxes.dart';
import 'package:mathlang/render/math_caret.dart';

const String kDoc =
    r'而$\lim_{x\to0}\frac{D(x)-D(0)}{x-0}$=$\lim_{x\to0}\frac{D(x)-1}{x}$'
    '\n';

Future<({RenderBox root, List<LeafBox> inks})> _mount(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer(kDoc);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: DocView(buffer: buf, settings: DocSettings.defaults),
      ),
    ),
  ));
  for (var i = 0; i < 8; i++) {
    await tester.pump();
  }
  final Element math = find.byType(MathWithCaret).evaluate().first;
  final RenderBox root = math.renderObject! as RenderBox;
  final List<LeafBox> inks = scanLeafBoxes(root)
      .eligible
      .where((b) => b.kind != LeafBoxKind.pad && (b.text ?? '').isNotEmpty)
      .toList();
  return (root: root, inks: inks);
}

void main() {
  testWidgets('★★★ 在分子里的 `D` 上点/拖 ⇒ 落点必须是 `D` 本身，不是公式边界',
      (WidgetTester tester) async {
    final ({RenderBox root, List<LeafBox> inks}) m = await _mount(tester);
    final LeafBox d = m.inks.firstWhere((b) => b.text == 'D');
    // 点 `D` 的**左端**（用户按下那个位置）
    final Offset inside =
        m.root.localToGlobal(Offset(d.rect.left + 2, d.rect.center.dy));
    final DocViewState st = tester.state<DocViewState>(find.byType(DocView));
    final int? off = st.offsetAtGlobalForDrag(inside);
    expect(off, isNotNull);
    // `D` 在 tex 里是第 1 个（`\lim_{x\to0}\frac{` 之后）⇒ 文档偏移应是 19 附近
    final int dAbs = kDoc.indexOf('D');
    expect(off, closeTo(dAbs, 1),
        reason: r'★ 改前：这里返回 1（= 那个美元符）⇒ 拖选把左边的 lim 整段选中');
  });

  testWidgets('★★ 点在公式外侧（真正的空白）⇒ 仍然交给段落', (WidgetTester tester) async {
    final ({RenderBox root, List<LeafBox> inks}) m = await _mount(tester);
    final DocViewState st = tester.state<DocViewState>(find.byType(DocView));
    final Offset leftOfMath = m.root.localToGlobal(const Offset(-10, 10));
    final int? off = st.offsetAtGlobalForDrag(leftOfMath);
    // 不要求具体值，只要求"不是公式内部那些偏移"
    expect(off == null || off < kDoc.indexOf(r'$\lim'), isTrue,
        reason: '公式外侧不属于公式');
  });
}
