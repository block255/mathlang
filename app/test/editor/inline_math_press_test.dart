// ★★ L10 守卫（2026-10-21）：**行内公式里"一次按下只算一击"**
//
// 用户实测（真实作业文档）：单击公式里的字会变成"选中一个原子"（蓝底），双击变成空选，
// 从公式里起手拖不动；纯拖动时偶尔还会冒出 `[公式不完整]`。
//
// 根因：一次物理按下在行内公式上有**两条上报路径**（文本层粗落点 + 公式层精确落点）
// ⇒ `_onPressHit` 被调两次 ⇒ 第二次「同位置 + <400ms」被当成**第二击**。
//
// 修法：子层只**收着**上报，父层 `Listener.onPointerDown`（祖先，必然最后跑）统一裁决一次。
// 改前必红：本文件里"单击不许有选区""双击选中 a^2""从公式里起手能拖动"都会红。
//
// ★ L24（`\limits` 注入）另见 `test/render/caret_limits_injection_test.dart`。

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/leaf_boxes.dart';
import 'package:mathlang/render/math_caret.dart';

import '../support/math_fonts.dart';

Future<DocBuffer> _pump(WidgetTester tester, String doc) async {
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer(doc);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
  ));
  tester.state<EditViewState>(find.byType(EditView)).focusInput();
  await tester.pumpAndSettle();
  return buf;
}

/// 上屏那份段落里某个字的中心
Offset? _charCenter(WidgetTester tester, String mark) {
  Offset? best;
  var bestTop = double.negativeInfinity;
  for (final RenderObject ro in tester.allRenderObjects) {
    if (ro is! RenderParagraph || !ro.attached) continue;
    final int i = ro.text.toPlainText().indexOf(mark);
    if (i < 0) continue;
    final List<TextBox> bs =
        ro.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bs.isEmpty) continue;
    final Offset at = ro.localToGlobal(bs.first.toRect().center);
    if (at.dy < 40) continue;
    if (at.dy > bestTop) {
      bestTop = at.dy;
      best = at;
    }
  }
  return best;
}

/// 上屏那份数学渲染里某个字形的左半（落在它**之前**）
Offset? _glyphLeft(WidgetTester tester, String glyph) {
  Offset? best;
  var bestDy = double.negativeInfinity;
  for (final Element e in find.byType(MathWithCaret).evaluate()) {
    final RenderObject? ro = e.renderObject;
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) continue;
    final double dy = ro.localToGlobal(Offset.zero).dy;
    if (dy < 40) continue;
    List<LeafBox> boxes;
    try {
      boxes = scanLeafBoxes(ro).eligible.toList();
    } catch (_) {
      continue;
    }
    final Iterable<LeafBox> found =
        boxes.where((LeafBox b) => b.text == glyph && b.kind == LeafBoxKind.glyph);
    if (found.isEmpty) continue;
    final Rect r = found.last.rect;
    if (dy > bestDy) {
      bestDy = dy;
      best = ro.localToGlobal(Offset(r.left + 1, r.center.dy));
    }
  }
  return best;
}

/// 上屏那份数学渲染盒里**最宽**的一个（= 真正那条公式；`$a^2$` 那种小盒会干扰扫点）
RenderBox? _widestMathBox(WidgetTester tester) {
  RenderBox? best;
  var bestW = -1.0;
  for (final Element e in find.byType(MathWithCaret).evaluate()) {
    final RenderObject? ro = e.renderObject;
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) continue;
    if (ro.localToGlobal(Offset.zero).dy < 40) continue;
    if (ro.size.width > bestW) {
      bestW = ro.size.width;
      best = ro;
    }
  }
  return best;
}

/// 某个字的**左缘**（用于"拖到它之前"——拖到字心会落在它之后）
Offset? _charLeftEdge(WidgetTester tester, String mark) {
  Offset? best;
  var bestTop = double.negativeInfinity;
  for (final RenderObject ro in tester.allRenderObjects) {
    if (ro is! RenderParagraph || !ro.attached) continue;
    final int i = ro.text.toPlainText().indexOf(mark);
    if (i < 0) continue;
    final List<TextBox> bs =
        ro.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bs.isEmpty) continue;
    final Rect r = bs.first.toRect();
    final Offset at = ro.localToGlobal(Offset(r.left - 2, r.center.dy));
    if (at.dy < 40) continue;
    if (at.dy > bestTop) {
      bestTop = at.dy;
      best = at;
    }
  }
  return best;
}

Future<void> _click(WidgetTester tester, Offset at, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

String _selected(DocBuffer b) =>
    b.buf.substring(b.selectionStart, b.selectionEnd);

void main() {
  setUpAll(() async => loadMathFonts());

  group('① 单击行内公式 = 放光标（不许变成"选中一个原子"）', () {
    testWidgets(r'单击 $a^2$ 里的 a ⇒ 无选区、光标在公式内', (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, r'甲乙 $a^2$ 丙丁');
      final Offset? a = _glyphLeft(tester, 'a');
      expect(a, isNotNull, reason: '要能量到公式里的 a');
      await _click(tester, a!, 1);
      expect(buf.hasSelection, isFalse,
          reason: '单击不许有选区（改前：第二次上报被当成第二击 ⇒ 选中一个原子）。'
              '实际选中 "${_selected(buf)}"');
      expect(buf.caret, inInclusiveRange(3, 7),
          reason: '光标应落在这段公式里（3..7），实际 ${buf.caret}');
    });

    testWidgets(r'单击公式两端都不产生选区（`$a^2$` 盒只有 ~15px，取两端两点）',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, r'甲乙 $a^2$ 丙丁');
      final RenderBox? box = _widestMathBox(tester);
      expect(box, isNotNull);
      final Rect r = box!.localToGlobal(Offset.zero) & box.size;
      for (final double x in <double>[r.left + 1, r.right - 1]) {
        await _click(tester, Offset(x, r.center.dy), 1);
        expect(buf.hasSelection, isFalse,
            reason: '落点 x=${x.toStringAsFixed(1)} 单击后不该有选区 '
                '（实际 "${_selected(buf)}"）');
        await tester.pump(const Duration(milliseconds: 500)); // 让连击计数过期
      }
    });
  });

  group('② 双击 = 一个渲染节点（乙口径）', () {
    testWidgets(r'双击 $a^2$ 里的 a ⇒ 选中 a^2 整体', (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, r'甲乙 $a^2$ 丙丁');
      final Offset? a = _glyphLeft(tester, 'a');
      await _click(tester, a!, 2);
      expect(_selected(buf), r'a^2',
          reason: '双击 = 字形 + 它挂的上标 ⇒ a^2（改前为空选）。实际 "${_selected(buf)}"');
    });

    testWidgets(r'双击 \frac{a}{b} 的分子 ⇒ 选中整个分式', (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, r'甲乙 $\frac{a}{b}$ 丙丁');
      final Offset? a = _glyphLeft(tester, 'a');
      await _click(tester, a!, 2);
      expect(_selected(buf), r'\frac{a}{b}', reason: '实际 "${_selected(buf)}"');
    });
  });

  group('③ 三击 = 整行', () {
    testWidgets('三击公式里的字 ⇒ 选中整行', (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, r'甲乙 $a^2$ 丙丁');
      final Offset? a = _glyphLeft(tester, 'a');
      await _click(tester, a!, 3);
      expect(_selected(buf), r'甲乙 $a^2$ 丙丁');
    });
  });

  group('④ 从公式里起手拖选 = 能拖出去（改前：拖不动）', () {
    testWidgets('a 起手拖到「丁」⇒ 选区覆盖到行尾', (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, r'甲乙 $a^2$ 丙丁');
      final Offset? a = _glyphLeft(tester, 'a');
      final Offset? ding = _charCenter(tester, '丁');
      final TestGesture gs = await tester.startGesture(a!,
          kind: PointerDeviceKind.mouse, buttons: kPrimaryButton);
      await gs.moveBy(const Offset(8, 0));
      await tester.pump();
      await gs.moveTo(ding!);
      await tester.pump();
      await gs.up();
      await tester.pumpAndSettle();
      expect(buf.hasSelection, isTrue, reason: '必须生成选区');
      expect(buf.selectionEnd, buf.buf.length,
          reason: '拖到「丁」⇒ 选区应到文末（改前停在公式里那一个原子）');
    });

    testWidgets('a 起手往左拖到「甲」左缘 ⇒ 选区覆盖到行首', (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, r'甲乙 $a^2$');
      final Offset? a = _glyphLeft(tester, 'a');
      final Offset? jia = _charLeftEdge(tester, '甲');
      final TestGesture gs = await tester.startGesture(a!,
          kind: PointerDeviceKind.mouse, buttons: kPrimaryButton);
      await gs.moveBy(const Offset(8, 0));
      await tester.pump();
      await gs.moveTo(jia!);
      await tester.pump();
      await gs.up();
      await tester.pumpAndSettle();
      expect(buf.selectionStart, 0,
          reason: '拖到「甲」左缘 ⇒ 选区应从文首开始，实际 ${buf.selectionStart}');
    });
  });
}
