// ★★ 2026-10-23（批 2 · E1/C）：**分段函数 / 对齐推导的右键改行数**（全链路）。
//
// 用户原话：「目前分段只能分两段」——模板写死两行，右键又没反应（`envStyleOf` 认不出 cases）。
// 口径（2026-10-23 拍板）：面板只给一栏「段数」，预览写「3 段」，**不接 `× 数字`**；
//   `aligned` 同理，标签是「行数」。
//
// ★ 这条走的是**真实接线**（右键 → `_resizeEnvAt` → 面板 → 就地重写），
//   所以改前它是红的：右键 cases 两个字——毫无反应。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/math_caret.dart';

import '../support/math_fonts.dart';

const String kCasesTex = r'f(x)=\begin{cases}1&x>0\\0&x\le0\end{cases}';
const String kAlignedTex = r'\begin{aligned}f(x)&=1\\&=2\end{aligned}';
String docOf(String tex) => '${r'$$'}\n$tex\n${r'$$'}';

Future<DocBuffer> _pump(WidgetTester tester, String doc) async {
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

Future<void> _rightClickMath(WidgetTester tester) async {
  final Finder math = find.byType(MathWithCaret).last;
  final GestureDetector gd = tester.widget<GestureDetector>(
    find.ancestor(of: math, matching: find.byType(GestureDetector)).first,
  );
  expect(gd.onSecondaryTapDown, isNotNull, reason: '行间块必须挂着右键回调');
  gd.onSecondaryTapDown!(TapDownDetails(globalPosition: tester.getCenter(math)));
  await tester.pumpAndSettle();
}

/// 文档里那个 `cases` / `aligned` 环境的行数
int _rows(String doc) {
  final int i = doc.indexOf(r'\begin{');
  if (i < 0) return -1;
  final int j = doc.indexOf(r'\end{', i);
  final String body = doc.substring(doc.indexOf('}', i) + 1, j < 0 ? doc.length : j);
  return body.split(r'\\').length;
}

void main() {
  setUpAll(() async => loadMathFonts());

  testWidgets('★ 右键分段函数 ⇒ 面板「段数」⇒ 改成 3 段 ⇒ 前缀 f(x)= 保留',
      (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, docOf(kCasesTex));
    await _rightClickMath(tester);

    expect(find.byKey(const Key('env-size-dialog')), findsOneWidget,
        reason: '改前右键 cases 没有任何反应');
    expect(find.text('分段函数'), findsOneWidget);
    expect(find.text('段数'), findsOneWidget);
    expect(find.byKey(const Key('env-size-cols')), findsNothing,
        reason: '只有一个自由度');
    expect(find.byKey(const Key('env-size-style')), findsNothing,
        reason: '括号由环境自带');
    expect(
        tester.widget<Text>(find.byKey(const Key('env-size-preview'))).data,
        '预览：2 段');

    await tester.enterText(find.byKey(const Key('env-size-rows')), '3');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('env-size-apply')));
    await tester.pumpAndSettle();

    expect(_rows(buf.buf), 3, reason: buf.buf.replaceAll('\n', r'\n'));
    expect(buf.buf.contains(r'f(x)='), isTrue,
        reason: '环境外面的 `f(x)=` 不许被吃掉：${buf.buf}');
    expect(buf.buf.contains(r'1&x>0'), isTrue, reason: '既有段落内容要保留：${buf.buf}');
  });

  testWidgets('★ 一步撤销：改完按一次 undo ⇒ 回到 2 段', (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, docOf(kCasesTex));
    await _rightClickMath(tester);
    await tester.enterText(find.byKey(const Key('env-size-rows')), '4');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('env-size-apply')));
    await tester.pumpAndSettle();
    expect(_rows(buf.buf), 4);

    buf.undo();
    await tester.pumpAndSettle();
    expect(_rows(buf.buf), 2, reason: '一次右键改动 = 一步撤销：${buf.buf}');
  });

  testWidgets('★ 对齐推导 ⇒ 面板「行数」（同一套单栏形态）', (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, docOf(kAlignedTex));
    await _rightClickMath(tester);
    expect(find.byKey(const Key('env-size-dialog')), findsOneWidget);
    expect(find.text('对齐推导'), findsOneWidget);
    expect(find.text('行数'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('env-size-rows')), '3');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('env-size-apply')));
    await tester.pumpAndSettle();
    expect(_rows(buf.buf), 3, reason: buf.buf.replaceAll('\n', r'\n'));
    expect(buf.buf.contains(r'f(x)&=1'), isTrue, reason: buf.buf);
  });

  testWidgets('★ 普通公式右键 ⇒ 仍然不弹面板（别把 cases 的入口开太宽）',
      (WidgetTester tester) async {
    await _pump(tester, docOf(r'x^2+1'));
    await _rightClickMath(tester);
    expect(find.byKey(const Key('env-size-dialog')), findsNothing);
  });
}
