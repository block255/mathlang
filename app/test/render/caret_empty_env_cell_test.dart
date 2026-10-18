// 守卫测试：**空的多行环境格子里，光标的行高盒必须来自那一行**（2026-10-18 用户实测）
//
// 现象：`aligned` 里光标停在某行（尤其是空格子）时，蓝色竖条画在**两行之间**。
// 根因：`findLocalRowBox` 要求"候选字形盒竖直含基线"，而空格子里**没有任何字形**
//   ⇒ 几何退路返回 null ⇒ 上层按"整个公式盒居中"画。
// 判据：锚点那一行没有字形时，用**那一行自己的行盒**（RenderLine 的盒子）。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/leaf_boxes.dart';
import 'package:mathlang/render/math_caret.dart';
import 'package:mathlang/render/slot_marks.dart';

Future<RenderBox> _pump(WidgetTester tester, String tex, GlobalKey key) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: Math.tex(tex,
            key: key,
            mathStyle: MathStyle.display,
            textStyle: const TextStyle(fontSize: 16)),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return key.currentContext!.findRenderObject()! as RenderBox;
}

void main() {
  // `\begin{aligned}a&=b\\&=\end{aligned}`：第 2 行左格是空的（内容区间 [21,21)）
  const String base = r'\begin{aligned}a&=b\\&=\end{aligned}';
  testWidgets('空格子里的光标行盒落在那一行，而不是两行之间', (WidgetTester tester) async {
    const int caretInRow2EmptyCell = 21;
    final String tex = renderMathTex(base, caretRel: caretInRow2EmptyCell);
    final GlobalKey key = GlobalKey();
    final RenderBox ro = await _pump(tester, tex, key);

    // 第 2 行的字形盒（`=` 在 y 更靠下的那一组里）
    final LeafBoxScan scan = scanLeafBoxes(ro);
    final List<LeafBox> equals = scan.all.where((LeafBox b) => b.text == '=').toList();
    expect(equals.length, 2, reason: '两行各一个等号');
    equals.sort((LeafBox a, LeafBox b) => a.rect.top.compareTo(b.rect.top));
    final Rect row2 = equals.last.rect;

    final RenderObject? anchor = findCaretAnchor(ro);
    expect(anchor, isNotNull, reason: '注入的光标锚点应当存在');
    final Rect? box = findLocalRowBox(ro, Offset.zero, anchor: anchor);
    expect(box, isNotNull, reason: '空格子也要能确定行（否则上层居中画 ⇒ 落在两行之间）');

    final double dy = (box!.center.dy - row2.center.dy).abs();
    expect(dy, lessThan(row2.height),
        reason: '光标行盒的竖直中心必须贴着第 2 行；实测 dy=${dy.toStringAsFixed(1)}，'
            '第 2 行高=${row2.height.toStringAsFixed(1)}');
  });
}
