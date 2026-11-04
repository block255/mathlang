// ★ 2026-11-04 晚（用户写作业实测）：**环境里子位点的竖条**。
//
// 现象（截图 + 用户原话）：
//   · 矩阵里 `A^{2}`，光标点在 `2` **后面** ⇒ 竖条"对标 A 而不是 2"，
//     比指数那个槽框**下面出头一截**；退格删掉 2 之后仍然如此。
//   · 环境外同一个 `A^{2}` 的同一个位置，竖条是**脚本行高**（实测 1.5×10.2）。
//
// 根因：`math_caret._measure` 里"格几何接管竖条"那条（2026-10-19 为"点不同行光标与占位框分离"立的）
//   **无条件**生效 ⇒ 把按层级算好的 `findLocalRowBox` 结果丢掉：
//     · 空格子 ⇒ `envBox`（格填区，行带高）
//     · 非空格子 ⇒ `caretBand`（最近的行带）
//   两条都不看位点层级 ⇒ 子位点（上标/下标/分母/次数/底数）全被画成"那一格"。
//
// 口径（2026-11-04 用户拍板）：`caretDepth ≤ 1`（格级）保留格几何接管；
//   `≥ 2`（子位点）竖条回到**那一行**。本文件钉住两侧：
//   ① 子位点 ⇒ 脚本行高（< 16）；② 格级位点 ⇒ 仍是行带高（≥ 18），防回退。
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/math_caret.dart';

import '../support/math_fonts.dart';

/// 读**真正画出来的**竖条（`MathCaretPainter.rect`），以及当前空槽垫的矩形。
({Rect? bar, List<Rect> pads}) _painted(WidgetTester tester) {
  Rect? bar;
  final List<Rect> pads = <Rect>[];
  for (final RenderObject ro in tester.allRenderObjects) {
    if (ro is RenderCustomPaint && ro.foregroundPainter is MathCaretPainter) {
      final MathCaretPainter p = ro.foregroundPainter! as MathCaretPainter;
      if (p.caretVisible) bar = p.rect;
      for (final SlotPad s in p.pads) {
        pads.add(s.rect);
      }
    }
  }
  return (bar: bar, pads: pads);
}

Future<DocBuffer> _mount(WidgetTester tester, String tex, int rel) async {
  tester.view.physicalSize = const Size(1400, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final String doc = '${r'$$'}\n$tex\n${r'$$'}';
  final DocBuffer buf = DocBuffer(doc)..setCaret(3 + rel);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
  ));
  tester.state<EditViewState>(find.byType(EditView)).focusInput();
  await tester.pumpAndSettle();
  return buf;
}

void main() {
  setUpAll(() async => loadMathFonts());

  testWidgets(r'矩阵里 A^{2}，光标在 2 后面 ⇒ 竖条是脚本行高（不是整格）',
      (WidgetTester tester) async {
    const String tex = r'\begin{bmatrix}a&b&A^{2}\\c&d&e\end{bmatrix}';
    await _mount(tester, tex, tex.indexOf('^{2}') + 3); // `2` 之后（组内、`}` 之前）
    final ({Rect? bar, List<Rect> pads}) got = _painted(tester);
    expect(got.bar, isNotNull, reason: '应该画出竖条');
    // ignore: avoid_print
    print('CHILD bar=${got.bar} pads=${got.pads}');
    expect(got.bar!.height, lessThan(16),
        reason: '子位点竖条必须是脚本行高（整格行带 ≈ 24）');
  });

  testWidgets(r'矩阵里 A^{□}（退格后）⇒ 同样按脚本行画',
      (WidgetTester tester) async {
    const String tex = r'\begin{bmatrix}a&b&A^{}\\c&d&e\end{bmatrix}';
    await _mount(tester, tex, tex.indexOf('^{}') + 2); // 空槽里
    final ({Rect? bar, List<Rect> pads}) got = _painted(tester);
    expect(got.bar, isNotNull);
    // ignore: avoid_print
    print('CHILD empty bar=${got.bar} pads=${got.pads}');
    expect(got.bar!.height, lessThan(16),
        reason: '空的上标槽也是子位点 ⇒ 竖条不该用整格行带');
  });

  testWidgets(r'格级位点（整格末尾）⇒ 仍然贴行带（老口径不许回退）',
      (WidgetTester tester) async {
    // 整行都空的一格：光标落在格首 ⇒ 格级位点
    const String tex = r'\begin{bmatrix}a&b\\c&d\end{bmatrix}';
    await _mount(tester, tex, tex.indexOf(r'\end') - 0); // 末格之后（格级）
    final ({Rect? bar, List<Rect> pads}) got = _painted(tester);
    // ignore: avoid_print
    print('CELL bar=${got.bar} pads=${got.pads}');
    expect(got.bar, isNotNull);
    expect(got.bar!.height, greaterThan(16),
        reason: '格级位点要保留"贴格/行带"的老口径');
  });
}
