// ★★ L18 守卫：**行内公式的左边缘命中带**（4 px，用户 2026-10-19 选的方案 B）
//
// 用户报的现象（行内公式在**行首**）："点它左边点不到"。
// 探针实测（光标先在文末，真实指针）：
//   · 点公式左缘 **−2 / −4 / −6 / −10 / −16 px ⇒ 光标一动不动**（那几像素谁都不认领：
//     既不在段落盒里，也不在公式的 `WidgetSpan` 里）；
//   · 点它自己最左 **0 px ⇒ 落进公式内部**（offset 7）。
//   ⇒ 行首公式的"左边"根本没有落点，与"文字左边 = 前一个字之后"**不同权**。
// 而"行中"的公式没这个问题（左边属于前面的文字段）。
//
// 判据（用户拍板：**物理边界**，不是 1/3 比例）：公式左缘 **±4 px** 都算"公式之前"。
// ★ 只改命中层 —— **排版一个像素都不动**。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/math_caret.dart';

import '../support/math_fonts.dart';

/// 行首公式（段落以会话公式开头）
const String kHead = r'$\frac{a}{b}=1$后面的文字';

/// 行中公式（对照：左边属于文字段）
const String kMid = r'甲$\frac{a}{b}=1$乙';

Future<DocBuffer> _pump(WidgetTester tester, String doc) async {
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer(doc)..setCaret(0);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
  ));
  tester.state<EditViewState>(find.byType(EditView)).focusInput();
  await tester.pumpAndSettle();
  return buf;
}

/// 公式（`MathWithCaret`）的全局矩形
Rect _mathRect(WidgetTester tester) {
  final RenderBox b = find
      .byType(MathWithCaret)
      .last
      .evaluate()
      .single
      .renderObject! as RenderBox;
  return b.localToGlobal(Offset.zero) & b.size;
}

/// 从文末出发点一处，回光标偏移
Future<int> _tapFromEnd(WidgetTester tester, DocBuffer buf, Offset at) async {
  buf.setCaret(buf.buf.length);
  await tester.pumpAndSettle();
  await tester.tapAt(at);
  await tester.pumpAndSettle();
  return buf.caret;
}

void main() {
  setUpAll(() async => loadMathFonts());

  group('⑮ 行首公式：左边缘 ±4 px = "公式之前"', () {
    testWidgets('★★ 左缘**外侧** −2 / −4 px ⇒ 落在公式之前（改前：完全落空，光标不动）',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, kHead);
      final Rect r = _mathRect(tester);
      final double y = r.center.dy;
      for (final double dx in <double>[-4, -2]) {
        final int caret = await _tapFromEnd(tester, buf, Offset(r.left + dx, y));
        expect(caret, 0,
            reason: '点公式左缘外侧 ${dx}px ⇒ 必须落在**公式之前**（0），实际 $caret'
                '（改前：整个落空、光标停在文末 ${buf.buf.length}）');
      }
    });

    testWidgets('★★ 左缘**内侧** 0 / +2 px ⇒ 也是公式之前（改前：落进公式内部 offset 7）',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, kHead);
      final Rect r = _mathRect(tester);
      final double y = r.center.dy;
      for (final double dx in <double>[0, 2]) {
        final int caret = await _tapFromEnd(tester, buf, Offset(r.left + dx, y));
        // seg.start = 0；`$` 之后的内容起点是 1 —— 两者是同一根像素（§3.3），都算"公式之前"
        expect(caret, lessThanOrEqualTo(1),
            reason: '点公式最左 ${dx}px ⇒ 必须落在**公式之前 / 段首**（≤1），实际 $caret'
                '（改前：被认成点了公式里的字形 ⇒ 7）');
      }
    });

    testWidgets('★ 带子只有 4 px：−6 px 之外**不**生效（不许把页边距变成大按钮）',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, kHead);
      final Rect r = _mathRect(tester);
      final int caret =
          await _tapFromEnd(tester, buf, Offset(r.left - 6, r.center.dy));
      expect(caret, buf.buf.length,
          reason: '−6px 在带外 ⇒ 仍然落空（改前也落空，这条防"带子越改越宽"），实际 $caret');
    });
  });

  group('⑯ 行中公式（对照）：左边属于前面那段文字，口径不变', () {
    testWidgets('★ 点行中公式左侧 −3 / −6 px ⇒ 落**前一个字之后**（1）',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, kMid);
      final Rect r = _mathRect(tester);
      for (final double dx in <double>[-6, -3]) {
        final int caret = await _tapFromEnd(tester, buf, Offset(r.left + dx, r.center.dy));
        expect(caret, 1,
            reason: '行中公式左侧属于文字段 ⇒ 落在 `甲` 之后（1），实际 $caret');
      }
    });

    testWidgets('★ 点行中公式最左 +2 px ⇒ 段首（2），不再落进公式内部',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, kMid);
      final Rect r = _mathRect(tester);
      final int caret = await _tapFromEnd(tester, buf, Offset(r.left + 2, r.center.dy));
      expect(caret, lessThanOrEqualTo(2),
          reason: '公式左缘内侧也是"公式之前"（≤2 = 段首），实际 $caret');
    });
  });
}
