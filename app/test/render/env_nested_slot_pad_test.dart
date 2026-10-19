// ★★ L22 守卫：**格子里放"空的结构"时，占位框要和外面一模一样**（2026-10-19 用户实测）
//
// 用户原话：「里面的这些东西的子位点占位框没画出来或者渲染不太对，不能正常地像在外面一样显示，
//   当然输入是可以输入进去的」。
//
// 真根因（与 L20 是**同一个 `any(...)`**）：`slot_marks` 用 `s.path.any(row/col)` 判"这是环境格子"，
//   于是格子里**嵌套的空槽**（`\sqrt{}` 的实参、`x^{}` 的上标、`\frac{}{}` 的分子）也被当成格子：
//   ① `_shouldDrawEmptySlot` 直接 return false ⇒ **不画占位框**；
//   ② 反而注入**格子填充垫** `\rule{1em}{0pt}` ⇒ 根号/上标的宽度被撑成 1em（渲染不对）。
// 修法：判据收进 `SlotSpan.isEnvCell`（只看 `path` 的**最后一步**）。

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/math_caret.dart';
import 'package:mathlang/render/slot_pad.dart';

import '../support/math_fonts.dart';

String _f(double v) => v.toStringAsFixed(1);

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

/// 当前这一帧画出来的**占位垫**（去重：同一份 pads 会挂在 4 个 painter 上）
List<Rect> _pads(WidgetTester tester) {
  final List<Rect> out = <Rect>[];
  for (final RenderObject ro in tester.allRenderObjects) {
    if (ro is RenderCustomPaint && ro.foregroundPainter is MathCaretPainter) {
      for (final SlotPad p in (ro.foregroundPainter! as MathCaretPainter).pads) {
        if (!out.contains(p.rect)) out.add(p.rect);
      }
    }
  }
  return out;
}

String _renderedTex(WidgetTester tester) => tester
    .widget<MathWithCaret>(find.byType(MathWithCaret).last)
    .tex;

/// 把光标放进 `cmd{` 之后的那个空槽里，返回 (渲染 tex, 占位垫矩形)
Future<({String tex, List<Rect> pads})> _insideSlot(
    WidgetTester tester, String mathTex, String cmd) async {
  final String doc = '${r'$$'}\n$mathTex\n${r'$$'}';
  final DocBuffer buf = await _pump(tester, doc);
  buf.setCaret(doc.indexOf('$cmd{') + cmd.length + 2); // `\sqrt{` 之后 = 空实参里
  await tester.pumpAndSettle();
  return (tex: _renderedTex(tester), pads: _pads(tester));
}

void main() {
  setUpAll(() async => loadMathFonts());

  group('⑱ 格子里"空的结构"的占位框（与外面同一套）', () {
    testWidgets('★★ 空 `\\sqrt{}`：格子里也要画出占位框，且**宽度与外面一致**',
        (WidgetTester tester) async {
      final (tex: String outTex, pads: List<Rect> outPads) =
          await _insideSlot(tester, r'\sqrt{}', r'\sqrt');
      final (tex: String inTex, pads: List<Rect> inPads) = await _insideSlot(
          tester, r'\begin{pmatrix} \sqrt{} & \\ & \end{pmatrix}', r'\sqrt');
      expect(outPads, isNotEmpty, reason: '外面必须有占位框（这是对照）');
      expect(inPads, isNotEmpty,
          reason: '格子里必须也有占位框（改前：0 个 —— 被当成了"环境格子"不画）');
      expect(inPads.first.width, closeTo(outPads.first.width, 1.5),
          reason: '格子里 ${_f(inPads.first.width)} vs 外面 ${_f(outPads.first.width)}'
              ' ⇒ 必须一样宽（改前被注入 1em 的格子填充垫 ⇒ 撑宽）');
      expect(inPads.first.height, closeTo(outPads.first.height, 1.5),
          reason: '高度也要一致');
      // ★ 不许把"格子填充垫"注进根号的实参里
      expect(inTex.contains(r'\sqrt{\rule{1em}{0pt}}'), isFalse,
          reason: '根号实参里不该出现格子填充垫（改前正是它 ⇒ 渲染不对）：$inTex');
      expect(outTex.contains(r'M\rule{0.3em}{0pt}'), isTrue,
          reason: '外面的占位垫是 M + 宽度垫');
      expect(inTex.contains(r'M\rule{0.3em}{0pt}'), isTrue,
          reason: '格子里也该是同一套垫子：$inTex');
    });

    testWidgets('★★ 空 `x^{}`：格子里也画，且与外面同尺寸', (WidgetTester tester) async {
      final (tex: _, pads: List<Rect> outPads) =
          await _insideSlot(tester, r'x^{}', r'x^');
      final (tex: String inTex, pads: List<Rect> inPads) = await _insideSlot(
          tester, r'\begin{pmatrix} x^{} & \\ & \end{pmatrix}', r'x^');
      expect(inPads, isNotEmpty, reason: '格子里空上标必须有占位框');
      expect(inPads.first.width, closeTo(outPads.first.width, 1.5),
          reason: '${_f(inPads.first.width)} vs ${_f(outPads.first.width)}');
      expect(inTex.contains(r'^{\rule{1em}{0pt}}'), isFalse,
          reason: '上标里不该出现格子填充垫：$inTex');
    });

    testWidgets('★ 空 `\\frac{}{}`：格子里分子分母**两个**占位框',
        (WidgetTester tester) async {
      final (tex: _, pads: List<Rect> outPads) =
          await _insideSlot(tester, r'\frac{}{}', r'\frac');
      final (tex: _, pads: List<Rect> inPads) = await _insideSlot(
          tester, r'\begin{pmatrix} \frac{}{} & \\ & \end{pmatrix}', r'\frac');
      // 分子（当前槽）+ 分母（同段里也画）
      expect(outPads.length, greaterThanOrEqualTo(2), reason: '外面：分子 + 分母');
      expect(inPads.length, outPads.length,
          reason: '格子里必须和外面一样多（改前 0 个）：${inPads.length} vs ${outPads.length}');
    });

    testWidgets('★★ 对照：**整格空**仍然是"1em 预留 + 格框"，不许退化成普通占位垫',
        (WidgetTester tester) async {
      const String tex = r'\begin{pmatrix} a & \\ & \end{pmatrix}';
      final String doc = '${r'$$'}\n$tex\n${r'$$'}';
      final DocBuffer buf = await _pump(tester, doc);
      buf.setCaret(doc.indexOf('&') + 2); // 第一行第二格
      await tester.pumpAndSettle();
      final String t = _renderedTex(tester);
      expect(t.contains(kEnvCellFillTex), isTrue,
          reason: '空格子的 1em 预留垫必须还在（那是"不改变列宽"的基础）：$t');
      expect(t.contains(r'M\rule{0.3em}{0pt}'), isFalse,
          reason: '整格空的格子**不该**再注普通占位垫（那会改变列宽）：$t');
      final List<Rect> pads = _pads(tester);
      expect(pads, isNotEmpty, reason: '当前格必须画出格框（自绘）');
      expect(pads.first.height, greaterThan(12),
          reason: '格框是一整格高（行距 24 左右），实际 ${_f(pads.first.height)}');
    });
  });
}
