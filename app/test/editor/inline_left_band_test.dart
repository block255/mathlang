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
import 'package:mathlang/render/leaf_boxes.dart';
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

    // ★ 2026-10-21（L10）：原来 0 / +2 两个落点写在**同一个测试**里连点两次 ——
    //   而两点只差 2 px、真实时间只差几毫秒 ⇒ 产品会（正确地）判成**双击**并选中整个节点，
    //   于是第二个断言读到的是选区末尾。连点不是本组要验的东西 ⇒ 拆成两次独立按下。
    for (final double dx in <double>[0, 2]) {
      testWidgets('★★ 左缘**内侧** ${dx}px ⇒ 也是公式之前（改前：落进公式内部 offset 7）',
          (WidgetTester tester) async {
        final DocBuffer buf = await _pump(tester, kHead);
        final Rect r = _mathRect(tester);
        final int caret =
            await _tapFromEnd(tester, buf, Offset(r.left + dx, r.center.dy));
        // seg.start = 0；`$` 之后的内容起点是 1 —— 两者是同一根像素（§3.3），都算"公式之前"
        expect(caret, lessThanOrEqualTo(1),
            reason: '点公式最左 ${dx}px ⇒ 必须落在**公式之前 / 段首**（≤1），实际 $caret'
                '（改前：被认成点了公式里的字形 ⇒ 7）');
      });
    }

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

  // -------------------------------------------------------------------------
  // ⑰ ★★ 2026-10-25：**左缘带只对空白生效**（墨迹优先）
  //
  // 来由（用户 2026-10-25 追问"这个左缘带是 `\lim` 下面 x 的左边那一块是吧"）：
  // 带子是**贯穿整盒高度的一条 4px 竖带**（只看 `localPos.dx < 4`，不看 y）。
  // 而 `\lim\limits_{x\to x_0}…` 的**下限 x 恰好画在盒子最左边**（探针实测盒内 x≈3.2）
  // ⇒ 它的左半截被这条带判成"点公式之前"（落段首），**一块墨迹没有主人**。
  // 探针 v52（整篇 11 个控件 / 119 个字形盒各点一次）里，这是**唯一**一处点不到的墨迹。
  //
  // 口径：**一像素一个主人** —— 点在字形上就是那个字形；带子只救"没有字形"的那几像素
  // （公式盒**外面** −4..0，用户 2026-10-19 报的"点它左边点不到"）。外面那几像素照旧。
  // -------------------------------------------------------------------------

  group('⑰ 左缘带只对空白生效（墨迹优先）', () {
    /// 下限画在盒子最左边的极限（`\lim\limits` 的下限 x 就在最左）
    const String kLimit = r'$\lim\limits_{x\to x_0}\frac{1}{f(x)}=0$';

    testWidgets(r'★ 点下限那个 x（盒内 x<4）⇒ 必须落进下限，不许被判成"公式之前"',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, kLimit);
      await tester.pumpAndSettle();
      final RenderBox box =
          find.byType(MathWithCaret).last.evaluate().single.renderObject! as RenderBox;
      final List<LeafBox> glyphs = scanLeafBoxes(box)
          .eligible
          .where((LeafBox b) => b.kind == LeafBoxKind.glyph)
          .toList();
      // 最左边那个字形盒 = 画在 `lim` 正下方的下限 `x`
      final LeafBox leftmost = glyphs.reduce(
          (LeafBox a, LeafBox b) => a.rect.left <= b.rect.left ? a : b);
      expect(leftmost.rect.left, lessThan(4),
          reason: '这条守卫的前提是"下限就画在左缘带里"，实际 left='
              '${leftmost.rect.left.toStringAsFixed(1)}（若已不在带内，这条要换个式子）');
      final int caret =
          await _tapFromEnd(tester, buf, box.localToGlobal(leftmost.rect.center));
      expect(caret, greaterThanOrEqualTo(2),
          reason: '点下限「${leftmost.text}」必须落进**下限里**（tex 偏移 ≥2），'
              '实际 $caret（= 段首，说明还在被左缘带抢走）');
      expect(caret, lessThan(buf.buf.length),
          reason: '也不许落到公式之后，实际 $caret');
    });

    testWidgets('★ 对照：公式盒**外面** −2px（没有墨迹）⇒ 仍然是"公式之前"',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, kLimit);
      final Rect r = _mathRect(tester);
      final int caret = await _tapFromEnd(tester, buf, Offset(r.left - 2, r.center.dy));
      expect(caret, 0,
          reason: '盒外左侧没有墨迹 ⇒ 带子照旧生效（公式之前 = 0），实际 $caret');
    });
  });
}
