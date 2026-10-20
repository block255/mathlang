// ★★★ 2026-10-20（T-C 实测 F16）：**导出抓图时不画"编辑辅助"**。
//
// 现场：T-C 导出的 PDF 第 1 页，在标题下面那个**空的行间公式**位置，
// 纸面上出现了一个**虚线小方框**（空槽占位框）。
// 根因：`capturePages` 抓的就是"屏幕上那一层"，而空槽虚线框 / 当前槽淡蓝底 / 光标竖条
//       由 `MathCaretPainter` 画在**同一个渲染层**里 ⇒ 一起被拍进了图。
//
// 修法：`MathWithCaret.showEditingAids`（默认 true）；`DocView._hideForCapture` 时传 false ⇒
//       **一个辅助都不挂**（painter 根本不挂）。
//
// 判据（结构断言，不依赖像素）：抓图态下树里**不许有** `MathCaretPainter`；
// 正常编辑态下**必须有**（否则等于把开关做成永久关）。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/empty_math_mark.dart';
import 'package:mathlang/render/math_caret.dart';
import 'package:mathlang/render/slot_marks.dart';

/// 树里挂着的"编辑辅助"画笔（光标 / 空槽虚线框 / 刻度 / 选区底块 都走这一个 painter）
final Finder _caretPainter = find.byWidgetPredicate(
  (Widget w) => w is CustomPaint && w.foregroundPainter is MathCaretPainter,
  description: 'MathCaretPainter（编辑辅助）',
);

/// 走**真实注入链**（空槽垫子 + 光标锚点都由 `renderMathTex` 注进去）
/// —— 不注垫子就没有空槽框，这条测试会变成"空测"。
final String _tex = renderMathTex(r'\frac{}{}', caretRel: 6, showCursor: true);

Future<void> _pump(WidgetTester tester, {required bool aids}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: MathWithCaret(
          tex: _tex,
          showCaret: true,
          showEditingAids: aids,
          mathKey: GlobalKey(),
          fontSize: 20,
          mathStyle: MathStyle.display,
          textFontSize: 20,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('★ 正常编辑态：空槽虚线框的画笔**在**（这条不许退化）',
      (WidgetTester tester) async {
    await _pump(tester, aids: true);
    expect(_caretPainter, findsOneWidget);
  });

  testWidgets('★ F16：抓图态（showEditingAids=false）⇒ 树里一个编辑辅助画笔都没有',
      (WidgetTester tester) async {
    await _pump(tester, aids: false);
    expect(_caretPainter, findsNothing,
        reason: '改前：虚线框被画进了导出的 PDF / 图片集');
  });

  testWidgets('★ F16：公式本身照旧渲染（不许为了藏辅助把公式也藏了）',
      (WidgetTester tester) async {
    await _pump(tester, aids: false);
    expect(find.byType(Math), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ★ 空公式的虚线小框是**另一个画笔**（`EmptyMathMark`），同一个开关
  testWidgets('★ F16：空公式虚线框 正常态在 / 抓图态不在（尺寸照旧 ⇒ 版面中性）',
      (WidgetTester tester) async {
    Future<Size> pumpMark({required bool aids}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: EmptyMathMark(
              width: 20,
              height: 24,
              showEditingAids: aids,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return tester.getSize(find.byType(EmptyMathMark));
    }

    await pumpMark(aids: true);
    expect(
      find.byWidgetPredicate((Widget w) =>
          w is CustomPaint && w.painter.runtimeType.toString().contains('Empty')),
      findsOneWidget,
      reason: '正常编辑态要画（§6.1.1：空壳必须可见）',
    );

    final Size s = await pumpMark(aids: false);
    expect(
      find.byWidgetPredicate((Widget w) =>
          w is CustomPaint && w.painter.runtimeType.toString().contains('Empty')),
      findsNothing,
      reason: '改前：这个虚线框被画进了导出的 PDF 纸面',
    );
    expect(s, const Size(20, 24), reason: '不画，但**尺寸照旧**（版面中性）');
  });
}
