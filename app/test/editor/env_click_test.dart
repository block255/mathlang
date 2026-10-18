// ★★ 环境（矩阵 / 行列式）**内部**的落点与右键（P6.1，2026-10-18 晚 · 用户实测后修）
//
// 用户三条原话：
//  ①「右键必须右键到矩阵的**括号**才能判定到，右键内部没反应」
//  ②「矩阵括号里面我鼠标**完全点不到**，点了一定会落在括号外面」
//  ③「如果那一行没有数的话，我鼠标根本**点不到那一行**」
//
// 探针（穿过 EditView，真实指针）定位到两个真根因：
//  · 右键：`GestureDetector` 用默认 `deferToChild` ⇒ **格子之间的空白没有子节点认领**
//    ⇒ 手势不在命中路径上 ⇒ 那里右键什么都不发生（括号/字形上有墨迹 ⇒ 能认领 ⇒ 能弹）。
//    修：`HitTestBehavior.opaque`（整块公式都归它）。
//  · 左键：`envCellOffset` 的 `atEnd` 直接返回**槽区间末尾**，而环境格子槽**含两侧填充空格**
//    （`\begin{pmatrix} A & B` 的第一格是 `[16,18)`、18 正好是 `&`）⇒ 光标停在**分隔符**上，
//    视觉上就像"落在格子外面"。修：返回**去掉首尾空白后的内容边界**。
//  · 空行：行带只由有墨迹的格子并出来 ⇒ 整行空的那行没有带 ⇒ 永远点不到。
//    修：缺的行按"邻行 + 行高"补一条带。

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/leaf_boxes.dart';
import 'package:mathlang/render/math_caret.dart';

import '../support/math_fonts.dart';

const String kTex = r'\begin{pmatrix} A & B \\ C & D \end{pmatrix}';
const String kDetTex = r'\begin{vmatrix} A & B \\ C & D \end{vmatrix}';
const String kEmptyRowTex = r'\begin{pmatrix} A & B \\ & \end{pmatrix}';

String _doc(String tex) => '${r'$$'}\n$tex\n${r'$$'}';

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

({RenderBox root, List<LeafBox> boxes}) _rig() {
  final RenderBox root =
      find.byType(MathWithCaret).last.evaluate().single.renderObject! as RenderBox;
  return (root: root, boxes: scanLeafBoxes(root).eligible);
}

Future<void> _leftClick(WidgetTester tester, RenderBox root, Offset local) async {
  await tester.tapAt(root.localToGlobal(local));
  await tester.pumpAndSettle();
}

Future<bool> _rightClick(WidgetTester tester, RenderBox root, Offset local) async {
  final TestGesture g = await tester.startGesture(root.localToGlobal(local),
      kind: PointerDeviceKind.mouse, buttons: kSecondaryButton);
  await g.up();
  await tester.pumpAndSettle();
  final bool open = find.byKey(const Key('env-size-dialog')).evaluate().isNotEmpty;
  if (open) {
    await tester.tap(find.byKey(const Key('env-size-cancel')));
    await tester.pumpAndSettle();
  }
  return open;
}

void main() {
  setUpAll(() async => loadMathFonts());

  group('① 左键：矩阵**内部**点哪落哪（不许停在 `&` 上）', () {
    testWidgets('★ 点 A 的中心 ⇒ 落在 A 之后（不是分隔符 `&` 上）',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, _doc(kTex));
      final ({RenderBox root, List<LeafBox> boxes}) r = _rig();
      final Rect a = r.boxes.firstWhere((LeafBox b) => b.text == 'A').rect;
      await _leftClick(tester, r.root, a.center);
      // tex: `\begin{pmatrix} ` 之后 A 在 16，`&` 在 18 ⇒ 文档里 A=19、&=21
      final int aAt = buf.buf.indexOf('A');
      expect(buf.caret, aAt + 1,
          reason: '点 A 中心 ⇒ 落在 A **之后**（${aAt + 1}），不许停在 `&`（${aAt + 2}）上；'
              '实际 ${buf.caret}');
    });

    testWidgets('★ 点 A 的右半边 ⇒ 同样落在 A 之后', (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, _doc(kTex));
      final ({RenderBox root, List<LeafBox> boxes}) r = _rig();
      final Rect a = r.boxes.firstWhere((LeafBox b) => b.text == 'A').rect;
      await _leftClick(tester, r.root, Offset(a.right - 2, a.center.dy));
      expect(buf.caret, buf.buf.indexOf('A') + 1);
    });

    testWidgets('★ 点 B 的中心 ⇒ 落在 B 之后（第二列也对）',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, _doc(kTex));
      final ({RenderBox root, List<LeafBox> boxes}) r = _rig();
      final Rect b = r.boxes.firstWhere((LeafBox leaf) => leaf.text == 'B').rect;
      await _leftClick(tester, r.root, b.center);
      expect(buf.caret, buf.buf.indexOf('B') + 1, reason: '实际 ${buf.caret}');
    });

    testWidgets('★ 行列式：点 A 中心 ⇒ 落在 A 之后（不是竖线、不是外部）',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, _doc(kDetTex));
      final ({RenderBox root, List<LeafBox> boxes}) r = _rig();
      final Rect a = r.boxes.firstWhere((LeafBox b) => b.text == 'A').rect;
      await _leftClick(tester, r.root, a.center);
      expect(buf.caret, buf.buf.indexOf('A') + 1, reason: '实际 ${buf.caret}');
    });

    testWidgets('★★ 整行都空的第二行：点它 ⇒ 光标落进**那一行**',
        (WidgetTester tester) async {
      // 用户原话："如果那一行没有数的话，我鼠标根本点不到那一行"
      final DocBuffer buf = await _pump(tester, _doc(kEmptyRowTex));
      final ({RenderBox root, List<LeafBox> boxes}) r = _rig();
      final Rect a = r.boxes.firstWhere((LeafBox b) => b.text == 'A').rect;
      // 第二行在第一行下面约一个行高（实测 24 px）
      await _leftClick(tester, r.root, Offset(a.center.dx, a.center.dy + 24));
      final int rowSep = buf.buf.indexOf(r'\\');
      expect(buf.caret, greaterThan(rowSep),
          reason: '点空行 ⇒ 光标必须在**行分隔符之后**（那一行里）；实际 ${buf.caret}、分隔符 $rowSep');
    });
  });

  group('② 右键：整块都算（含格子之间的空白）', () {
    testWidgets('★★ 三个位置右键**都要弹面板**（改前：只有字形/括号能弹）',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, _doc(kTex));
      final ({RenderBox root, List<LeafBox> boxes}) r = _rig();
      final Rect a = r.boxes.firstWhere((LeafBox b) => b.text == 'A').rect;
      final Rect d = r.boxes.firstWhere((LeafBox b) => b.text == 'D').rect;
      final Rect paren = r.boxes.firstWhere((LeafBox b) => b.text == '(').rect;
      expect(await _rightClick(tester, r.root, a.center), isTrue,
          reason: '字形上');
      expect(
          await _rightClick(tester, r.root,
              Offset(a.center.dx, (a.bottom + d.top) / 2)),
          isTrue,
          reason: '★ 两个格子之间的**空白**（用户报的就是这里没反应）');
      expect(await _rightClick(tester, r.root, paren.center), isTrue,
          reason: '括号上');
      expect(buf.buf, _doc(kTex), reason: '右键本身不改文档');
    });
  });
}
