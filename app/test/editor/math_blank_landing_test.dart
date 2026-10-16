// ③-B 端到端：**公式外侧 / 装饰区的点击**必须落到"结构那一层"，不许落进分子分母。
//
// 对手感的意义（用户实测 ①）：
//   · 行间块：点公式**左右两侧的留白** ⇒ 现在是"就近字形"（右 ⇒ 落进公式里 / 左 ⇒ 也一样）
//   · 行内：点分式**右端的装饰区**（分数线那一带）⇒ 现在落进**分母**
// 目标（§5.2 归属表）：结构盒内 ⇒ 左半=结构之前、右半=结构之后；盒外 ⇒ 公式之前 / 之后。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/math_caret.dart';
import 'package:mathlang/render/slot_marks.dart';
import 'package:mathlang/render/structure_geometry.dart';

Future<void> _mount(WidgetTester tester, DocBuffer buf) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
  ));
  tester.state<EditViewState>(find.byType(EditView)).focusInput();
  await tester.pumpAndSettle();
}

void main() {
  group('③-B 行间块：公式两侧的留白 → 公式之前 / 之后', () {
    testWidgets('左侧留白 ⇒ 公式之前；右侧留白 ⇒ 公式之后（不再落进公式内部）',
        (WidgetTester tester) async {
      const String doc = '前\n\n\$\$\nx=\\frac{a}{b}\n\$\$\n\n后\n';
      const String tex = r'x=\frac{a}{b}';
      final DocBuffer buf = DocBuffer(doc);
      await _mount(tester, buf);

      final int texStart = doc.indexOf('x=');
      final Rect f = tester.getRect(find.byType(MathWithCaret).first);
      debugPrint('块公式盒 = $f（tex 在源里 [$texStart,${texStart + tex.length})）');

      // 左侧留白（公式左边 100px，仍在整块命中盒内）
      buf.setCaret(0);
      await tester.pump();
      await tester.tapAt(Offset(f.left - 100, f.center.dy));
      await tester.pump();
      expect(buf.caret, texStart,
          reason: '点公式左侧留白 ⇒ 应当落到**公式之前**（$texStart），实际 ${buf.caret}');

      // 右侧留白
      buf.setCaret(0);
      await tester.pump();
      await tester.tapAt(Offset(f.right + 100, f.center.dy));
      await tester.pump();
      expect(buf.caret, texStart + tex.length,
          reason: '点公式右侧留白 ⇒ 应当落到**公式之后**（${texStart + tex.length}），'
              '实际 ${buf.caret}（若落在区间内 = 就近字形把点抢走了）');
    });
  });

  group('③-B 行内：点公式右侧的空白 ⇒ 不许落进公式内部', () {
    testWidgets(r'`AB$\frac{c}{d}+e$CD`：Math 盒右侧的段落空白 ⇒ 公式之后', (WidgetTester tester) async {
      const String doc = r'AB$\frac{c}{d}+e$CD';
      const String tex = r'\frac{c}{d}+e';
      final DocBuffer buf = DocBuffer(doc);
      await _mount(tester, buf);
      buf.setCaret(0);
      await tester.pump();

      final RenderBox box =
          tester.renderObject(find.byType(MathWithCaret).first) as RenderBox;
      final StructureGeometry g = buildStructureGeometry(
        tex: tex,
        renderTex: renderMathTex(tex, caretRel: -1),
        mathRoot: box,
      );
      expect(g.aligned, isTrue, reason: g.mismatch);
      final Rect fr = g.rectAt(0)!;
      debugPrint('分式盒 = $fr  （Math 盒 = ${box.size}）');

      // ★ 实测记账：行内的**小分式**里，Math 盒几乎被"字形盒 ± 2px 外扩"铺满
      //   （分式盒 15×22.8，而分子/分母的字形盒各 16 高 + 外扩 2 ⇒ 中线带也被吃掉）
      //   ⇒ 行内根本**没有"字形之外"的装饰带**可点；"点公式右侧"实际发生在
      //   **Math 盒之外**（段落里）⇒ 由 ③-A + 段落排版器负责（落点 = 公式之后）。
      final int segEnd = doc.indexOf(r'$', doc.indexOf(r'$') + 1); // 闭合 `$` 的位置
      final Offset right = box.localToGlobal(Offset(box.size.width + 40, box.size.height / 2));
      await tester.tapAt(right);
      await tester.pump();
      expect(buf.caret, greaterThanOrEqualTo(segEnd),
          reason: '点行内公式**右侧的空白** ⇒ 不许落进公式内部（tex 末尾 = $segEnd），'
              '实际 ${buf.caret}');
    });
  });
}
