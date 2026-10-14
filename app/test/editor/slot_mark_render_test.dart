// 空槽占位必须**真的能渲染** —— 即引擎认得我们注入的那个字形。
//
// 若引擎不认（例如 `\square` 不在 flutter_math_fork 的符号表里），
// `Math.tex` 会走 `onErrorFallback` → 公式位置出现红字 `❌ Parser Error…`。
// 这条测试就是守这个：**含空槽的公式不许退化成报错块**。
//
// ★ 为什么值得单独守：单元测试只证明了"注入的字符串形状对"，
//   证明不了"引擎画得出来" —— 而后者只能靠真渲染一次才知道（这里就是那一次）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/slot_marks.dart';
import 'package:mathlang/render/visible_atoms.dart';

void main() {
  testWidgets(r'含空槽的公式（行内 + 行间）能正常渲染，不出现 ❌ 回退',
      (WidgetTester tester) async {
    final DocBuffer buf = DocBuffer('\$\$\\frac{}{}\\sqrt{}\$\$\n\n正文 \$. 与 \$\\frac{a}{}\$ 结束');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: EditView(buffer: buf)),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('❌'), findsNothing,
        reason: '未支持的命令会让 Math.tex 走 onErrorFallback → 红字报错块。'
            '若这里挂了，说明占位字形（$kEmptySlotTex）引擎画不出来，要换一个。');
  });

  test('占位字形本身：恰好 1 个可见原子（与引擎 1 个叶盒对齐）', () {
    expect(lexVisibleAtoms(kEmptySlotTex).length, 1);
    expect(lexVisibleAtoms(kCurrentSlotTex).length, 1);
  });
}
