// ★★ 矩阵 / 行列式：**右键改尺寸全链路** + **四格各点一次都落在本格**（P6，2026-10-18 晚）
//
// 为什么要有这一份：`resizeEnvironment` / `envCellHitAt` / 尺寸面板各自都有单测，
// 但**"右键 → 面板 → 就地重写 → 一步撤销"**这条链此前只有人工手测过（接线断在哪都没人知道）。
// 用户口径（《界面与布局》§6.9 / PC-5）：
//   · 右键行间块 ⇒ 认出环境族与当前行列 ⇒ 面板带当前值 ⇒ 应用后**左上对齐保留**旧内容；
//   · 行列式**强制方阵**（列数框禁用、列数跟随行数）；
//   · 缩掉/换掉的内容进**一次撤销**；
//   · 光标回到环境开头。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/leaf_boxes.dart';
import 'package:mathlang/render/math_caret.dart';

import '../support/math_fonts.dart';

/// 行间矩阵（LaTeX 的换行 `\\` 用 raw string 写，避免和 Dart 的转义打架）
const String kMatrixTex = r'\begin{pmatrix} A & B \\ C & D \end{pmatrix}';
const String kDetTex = r'\begin{vmatrix} A & B \\ C & D \end{vmatrix}';
const String kMatrixDoc = '${r'$$'}\n$kMatrixTex\n${r'$$'}';
const String kDetDoc = '${r'$$'}\n$kDetTex\n${r'$$'}';

Future<DocBuffer> _pumpEditView(WidgetTester tester, String doc) async {
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer(doc)..setCaret(0);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: EditView(buffer: buf)),
    ),
  ));
  tester.state<EditViewState>(find.byType(EditView)).focusInput();
  await tester.pumpAndSettle();
  return buf;
}

/// 右键行间公式块。
///
/// ★ 为什么直接调 `onSecondaryTapDown` 而不是发一个鼠标右键事件：
///   编辑面自己有一套指针处理（拖选），测试里"右键"会先进那个手势竞技场，
///   这里的 `TapGestureRecognizer` 不一定赢 ⇒ 会变成"测手势"而不是"测接线"。
///   本文件要守的是**接线**：DocView 右键 → EditView `_resizeEnvAt` → 面板 → 重写 → 撤销。
///   （真实鼠标右键已在实例上人工验过；命中判定归 Flutter。）
Future<void> _rightClickMath(WidgetTester tester) async {
  final Finder math = find.byType(MathWithCaret).last;
  final GestureDetector gd = tester.widget<GestureDetector>(
    find.ancestor(of: math, matching: find.byType(GestureDetector)).first,
  );
  expect(gd.onSecondaryTapDown, isNotNull,
      reason: '行间块必须挂着右键回调（接线断了这里就该红）');
  gd.onSecondaryTapDown!(TapDownDetails(globalPosition: tester.getCenter(math)));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async => loadMathFonts());

  group('① 右键改尺寸（全链路）', () {
    testWidgets('★ 右键 2×2 矩阵 ⇒ 面板带当前尺寸 ⇒ 改成 3×3 ⇒ 左上保留',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pumpEditView(tester, kMatrixDoc);
      final String before = buf.buf;
      await _rightClickMath(tester);

      expect(find.byKey(const Key('env-size-dialog')), findsOneWidget,
          reason: '右键矩阵必须弹出尺寸面板（接线断过就只有手测能发现）');
      expect(find.textContaining('2 × 2'), findsOneWidget,
          reason: '面板要带**当前**行列（不是每次从 2×2 开始猜）');

      await tester.enterText(find.byKey(const Key('env-size-rows')), '3');
      await tester.enterText(find.byKey(const Key('env-size-cols')), '3');
      await tester.pump();
      await tester.tap(find.byKey(const Key('env-size-apply')));
      await tester.pumpAndSettle();

      expect(
          buf.buf,
          contains(
              r'\begin{pmatrix} A & B &\\ C & D &\\&&\end{pmatrix}'),
          reason: '3×3：旧内容**左上对齐**保留，新格留空（实际：${buf.buf}）');
      // 一步撤销 ⇒ 完全回到原样
      expect(buf.undo(), isTrue);
      expect(buf.buf, before, reason: '改尺寸只算**一次**编辑，一步就该撤销');
    });

    testWidgets('★ 行列式：列数不可改，改行数 ⇒ 方阵', (WidgetTester tester) async {
      final DocBuffer buf = await _pumpEditView(tester, kDetDoc);
      await _rightClickMath(tester);
      expect(find.byKey(const Key('env-size-dialog')), findsOneWidget);
      final TextField cols =
          tester.widget(find.byKey(const Key('env-size-cols'))) as TextField;
      expect(cols.enabled, isFalse, reason: '行列式强制方阵');
      await tester.enterText(find.byKey(const Key('env-size-rows')), '3');
      await tester.pump();
      await tester.tap(find.byKey(const Key('env-size-apply')));
      await tester.pumpAndSettle();
      expect(buf.buf,
          contains(r'\begin{vmatrix} A & B &\\ C & D &\\&&\end{vmatrix}'));
    });

    testWidgets('★ 缩到 1×1 ⇒ 只留左上那一个格子', (WidgetTester tester) async {
      final DocBuffer buf = await _pumpEditView(tester, kMatrixDoc);
      await _rightClickMath(tester);
      await tester.enterText(find.byKey(const Key('env-size-rows')), '1');
      await tester.enterText(find.byKey(const Key('env-size-cols')), '1');
      await tester.pump();
      await tester.tap(find.byKey(const Key('env-size-apply')));
      await tester.pumpAndSettle();
      expect(buf.buf, contains(r'\begin{pmatrix} A \end{pmatrix}'),
          reason: '1×1 是合法退化（只剩左上格），不是"删掉环境"');
    });

    testWidgets('★ 越界（99）⇒ 面板不关、文档不变', (WidgetTester tester) async {
      final DocBuffer buf = await _pumpEditView(tester, kMatrixDoc);
      final String before = buf.buf;
      await _rightClickMath(tester);
      await tester.enterText(find.byKey(const Key('env-size-rows')), '99');
      await tester.pump();
      await tester.tap(find.byKey(const Key('env-size-apply')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('env-size-dialog')), findsOneWidget,
          reason: '越界只报错，不关面板');
      expect(buf.buf, before);
    });

    testWidgets('★ 取消 ⇒ 一个字都不改', (WidgetTester tester) async {
      final DocBuffer buf = await _pumpEditView(tester, kMatrixDoc);
      final String before = buf.buf;
      await _rightClickMath(tester);
      await tester.tap(find.byKey(const Key('env-size-cancel')));
      await tester.pumpAndSettle();
      expect(buf.buf, before);
    });

    testWidgets('★ 普通公式（非多行环境）右键 ⇒ **不弹面板**',
        (WidgetTester tester) async {
      final String plain = r'$$' '\n' r'x+1' '\n' r'$$';
      final DocBuffer buf = await _pumpEditView(tester, plain);
      await _rightClickMath(tester);
      expect(find.byKey(const Key('env-size-dialog')), findsNothing,
          reason: '只有矩阵/行列式能改尺寸');
      expect(buf.buf, plain);
    });
  });

  group('② 矩阵四格：点哪一格落在哪一格', () {
    testWidgets('★★ 四个格子各点一次 ⇒ 光标都落在本格的字母上',
        (WidgetTester tester) async {
      // 用**不与环境名冲突**的大写字母，才能用 indexOf 精确算期望偏移
      final DocBuffer buf = await _pumpEditView(tester, kMatrixDoc);
      // ★ 只扫**可见的那一份**：`DocView` 里还有一棵离屏测量树（Offstage），
      //   它的叶盒也会被 `scanLeafBoxes` 扫到 ⇒ 从 `MathWithCaret` 自己的渲染盒起扫。
      final Finder math = find.byType(MathWithCaret).last;
      final RenderBox root = math.evaluate().single.renderObject! as RenderBox;
      final List<LeafBox> boxes = scanLeafBoxes(root).eligible;
      expect(
          boxes
              .where((LeafBox b) =>
                  <String>['A', 'B', 'C', 'D'].contains(b.text))
              .length,
          4,
          reason: '矩阵四个字母各是一个叶盒（P4 修好外框盒之后）');

      for (final String letter in <String>['A', 'B', 'C', 'D']) {
        final LeafBox target = boxes.firstWhere((LeafBox b) => b.text == letter);
        // 点**左半边** ⇒ 落在该原子之前 = 该字母的源偏移
        final Offset local = target.rect.centerLeft + const Offset(1, 0);
        await tester.tapAt(root.localToGlobal(local));
        await tester.pumpAndSettle();
        final int want = buf.buf.indexOf(letter);
        // ★ 判据是"**落在本格**"，不是"精确到字母前那一格"：
        //   格子里本来就有空格（` A `），位点吸附把落点吸到空格上也是本格。
        expect(buf.caret, inInclusiveRange(want - 1, want + 1),
            reason: '点 `$letter` 应当落在**本格**（期望 ±1 of $want、实际 ${buf.caret}）；'
                '落错格（比如落到别的字母上）就会差很多');
      }
    });
  });
}
