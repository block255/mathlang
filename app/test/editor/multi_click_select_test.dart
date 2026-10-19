// ★★ L4 守卫：**双击 = 同层对象 / 三击 = 整块**（2026-10-19）
//
// 探针发现两个真 bug（用户报"行间块钻不进去选内部"时顺手抓到的）：
//  ① **连击计数用的是"上一按"的位置** —— 父层 `Listener.onPointerDown` 在子层之后才跑，
//     而 `_onPressHit` 从 `_pressAt` 读位置 ⇒ 滞后一按 ⇒ **双击永远只算单击、三击被算成双击**；
//  ② 父层"按下即收起选区"跑在子层之后 ⇒ 刚选好的词/整块**当场被收成光标**。
// 修法：`onTapOffset` 带上**这一按的全局位置**（判据用当次位置）；
//     子层标记 `_multiSelectPress`，父层收起选区时让开。
//
// 覆盖：文字双击选词 · 文字三击选整行 · **行间块里**双击选一个原子 · 三击选整块 ·
//      单击别处仍然收起选区（老 bug 不许回来）· 拖选仍然可用。

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

/// 连击 [times] 次（同一位置、间隔 50 ms < 400 ms 阈值）
Future<void> _click(WidgetTester tester, Offset at, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

/// **内容段落**里某个字的中心（全局坐标）；`mark` 用来认出"就是这个段落"；找不到 ⇒ null
Offset? _charCenter(WidgetTester tester, String mark) {
  // ★ 渲染树里有**多份**同一个段落（单元池里缓存的那几份坐标是 (0,0)），
  //   所以取**位置最靠下、且确实在页内**的那一份（= 真正上屏的那份）。
  Offset? best;
  var bestTop = double.negativeInfinity;
  for (final RenderObject ro in tester.allRenderObjects) {
    if (ro is! RenderParagraph || !ro.attached) continue;
    final String plain = ro.text.toPlainText();
    final int i = plain.indexOf(mark);
    if (i < 0) continue;
    final List<TextBox> bs = ro
        .getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bs.isEmpty) continue;
    final Offset at = ro.localToGlobal(bs.first.toRect().center);
    if (at.dy < 40) continue; // (0,0) 那一族是池里的副本，不上屏
    if (at.dy > bestTop) {
      bestTop = at.dy;
      best = at;
    }
  }
  return best;
}

/// 行间块里某个字形盒的左半（落在它**之前**）
({Offset at, String glyph})? _glyphLeft(WidgetTester tester, String glyph) {
  final RenderBox root = find
      .byType(MathWithCaret)
      .last
      .evaluate()
      .single
      .renderObject! as RenderBox;
  final Iterable<LeafBox> found = scanLeafBoxes(root)
      .eligible
      .where((LeafBox b) => b.text == glyph && b.kind == LeafBoxKind.glyph);
  if (found.isEmpty) return null;
  final Rect r = found.last.rect;
  return (at: root.localToGlobal(Offset(r.left + 1, r.center.dy)), glyph: glyph);
}

void main() {
  setUpAll(() async => loadMathFonts());

  group('⑲ 文字：双击选词 / 三击选整行', () {
    testWidgets('★★ 双击第一个字 ⇒ 选中连在一起的汉字（改前：只落一个光标）',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, '甲乙 丙丁');
      final Offset? at = _charCenter(tester, '甲');
      expect(at, isNotNull, reason: '要能量到第一个字的位置');
      await _click(tester, at!, 2);
      expect(buf.selectionStart, 0,
          reason: '双击选词应当从 0 开始，实际 ${buf.selectionStart}..${buf.selectionEnd}');
      expect(buf.selectionEnd, 2,
          reason: '双击应当选中"甲乙"这两个连续汉字（0..2），'
              '实际 ${buf.selectionStart}..${buf.selectionEnd}'
              '（改前：连击计数滞后一按 ⇒ 只算单击 ⇒ 一个光标）');
    });

    testWidgets('★★ 三击 ⇒ 选中整行（改前：被算成双击 ⇒ 只选一个词）',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, '甲乙 丙丁');
      final Offset? at = _charCenter(tester, '甲');
      await _click(tester, at!, 3);
      expect(buf.selectionStart, 0);
      expect(buf.selectionEnd, 5,
          reason: '三击应当选中整行（0..5），实际 '
              '${buf.selectionStart}..${buf.selectionEnd}');
    });
  });

  group('⑳ 行间块：双击选一个原子 / 三击选整块（用户说的"钻不进去选内部"）', () {
    testWidgets('★★ 块内双击一个字 ⇒ 只选中那一个字（不再是整块）',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, '${r'$$'}\nab+cd\n${r'$$'}');
      final ({Offset at, String glyph})? g = _glyphLeft(tester, 'b');
      expect(g, isNotNull, reason: '要能量到块里的 b');
      await _click(tester, g!.at, 2);
      expect(buf.selectionEnd - buf.selectionStart, 1,
          reason: '块内双击一个字母 ⇒ 只选 1 个字符（一个可见原子），实际 '
              '"${buf.buf.substring(buf.selectionStart, buf.selectionEnd)}"');
      expect(buf.buf.substring(buf.selectionStart, buf.selectionEnd), 'b');
    });

    testWidgets(r'★★ 块内三击 ⇒ 选中整块（含围栏）', (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, '${r'$$'}\nab+cd\n${r'$$'}');
      final ({Offset at, String glyph})? g = _glyphLeft(tester, 'b');
      await _click(tester, g!.at, 3);
      final String sel = buf.buf.substring(buf.selectionStart, buf.selectionEnd);
      expect(sel, contains(r'$$'), reason: '三击行间块 = 整块（含围栏），实际 "$sel"');
      expect(sel, contains('ab+cd'), reason: '整块内容要在选区里，实际 "$sel"');
    });
  });

  group('㉑ 不能回归：单击别处收起选区 / 拖选仍然可用', () {
    testWidgets(r'★★ 有选区时点别处 ⇒ 选区收起（老 bug 不许回来）',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, '甲乙 丙丁 戊己');
      final Offset? at = _charCenter(tester, '甲');
      await _click(tester, at!, 3);
      expect(buf.hasSelection, isTrue, reason: '先要有一个选区');
      final Offset? at2 = _charCenter(tester, '戊');
      await _click(tester, at2!, 1);
      expect(buf.hasSelection, isFalse,
          reason: '单击别处 ⇒ 选区收起、只留光标（实际 '
              '${buf.selectionStart}..${buf.selectionEnd}）');
    });

    testWidgets('★★ 块内按下拖动仍然能选一段（L4 的"钻进去"主用法）',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, '${r'$$'}\nab+cd\n${r'$$'}');
      final ({Offset at, String glyph})? from = _glyphLeft(tester, 'a');
      final ({Offset at, String glyph})? to = _glyphLeft(tester, 'd');
      final TestGesture gs = await tester.startGesture(from!.at,
          kind: PointerDeviceKind.mouse, buttons: kPrimaryButton);
      await gs.moveBy(const Offset(6, 0));
      await tester.pump();
      await gs.moveTo(to!.at);
      await tester.pump();
      await gs.up();
      await tester.pumpAndSettle();
      expect(buf.hasSelection, isTrue, reason: '块内拖选必须能生成选区');
      expect(buf.selectionEnd - buf.selectionStart, greaterThanOrEqualTo(3),
          reason: '从 a 拖到 d 至少 3 个字，实际 '
              '"${buf.buf.substring(buf.selectionStart, buf.selectionEnd)}"');
    });
  });
}
