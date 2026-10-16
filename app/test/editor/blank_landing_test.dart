// ③-A 守卫（《编辑地基与手感》§7.3）：**点"行末之后的空白"必须落到行末**——
// 与"这一行是什么块类型"无关（段落 / 标题 / 列表项 / 带行内公式…一视同仁）。
//
// ★ 为什么写这条：2026-10-16 用户实测发现「标题行和第一行不会，下面三行（列表项）会」——
//   根因是列表项的内容被包在 `Row[标记, Expanded(内容)]` 里、命中盒成了**满栏宽**，
//   而标题 / 普通段落的盒只有**内容宽** ⇒ 同样的空白落在盒外 ⇒ 没人处理（落空）。
//   ⇒ 这是**实现细节泄漏成了行为差异**：同一段文字因块类型不同而地位不同。
//
// ★ 纪律：本条**先验红**（改 `_UnitHitBox` 之前必须是红的）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/inline_math_text.dart';

Future<void> _mount(WidgetTester tester, DocBuffer buf) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
  ));
  tester.state<EditViewState>(find.byType(EditView)).focusInput();
  await tester.pumpAndSettle();
}

/// 同一段文字 × 五种块类型（内容一模一样，只有"块类型"不同）
const Map<String, String> kCases = <String, String>{
  '甲 普通段落': 'abcdef',
  '乙 标题': '# abcdef',
  '丙 列表项': '- abcdef',
  '丁 列表项 + 行内公式': r'- abcdef $x_1x_2=\frac{c}{a}$',
  '戊 普通段落 + 行内公式': r'abcdef $x_1x_2=\frac{c}{a}$',
};

void main() {
  group('③-A 点行末之后的空白 → 落到行末（与块类型无关）', () {
    kCases.forEach((String label, String doc) {
      testWidgets(label, (WidgetTester tester) async {
        final DocBuffer buf = DocBuffer(doc);
        await _mount(tester, buf);

        final Finder text = find.byType(InlineMathText);
        expect(text, findsWidgets);
        final Rect r = tester.getRect(text.last);
        final Rect view = tester.getRect(find.byType(EditView));

        // ★ 固定的"行末之后的空白列"：本视图（800×600、A4 页被压到 793.7 宽）里
        //   文本栏右缘 ≈ 725.7（由列表项那个满栏宽的段落实测得来）⇒ 取 x=700 作那一列。
        //   五种块类型的**文字都够短**，所以这一列对本例都是"行末之后的空白"。
        const double x = 700;
        // 五行都够短：起点 ≤ 95、每字符 ≤ 16px ⇒ 文字右缘 ≤ 95 + 27×16 = 527 < 700 ✓
        expect(95 + doc.length * 16, lessThan(x),
            reason: '这一列必须在文字右端之后（本行 ${doc.length} 字符）');
        expect(x, lessThan(view.right - 20), reason: '这一列必须在页面内');

        // ★ 哨兵法：先把光标放到一个"不可能是答案"的位置
        buf.setCaret(0);
        await tester.pump();
        await tester.tapAt(Offset(x, r.center.dy));
        await tester.pump();

        expect(buf.caret, buf.length,
            reason: '「$label」点行末之后的空白 ⇒ 光标应当落到**行末**（${buf.length}），'
                '实际 ${buf.caret}；若为 0 说明这一列**没人处理**（命中盒不够宽）');
      });
    });
  });
}
