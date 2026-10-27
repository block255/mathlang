// **文末 / 页尾的 Enter：一次按键 = 一行**（2026-10-27 口径变更）
//
// 取代 `tail_enter_cap_test.dart`（批 42「文末 / 页尾空行封顶」的守卫）——
// 那条口径已被用户撤销：实测（旧版 1.1.1 与开发版 1.1.2 都测过）第二下起**屏幕完全不动**，
// 而基准 [`notes/design/行与段-空行基准.md`](../../../notes/design/行与段-空行基准.md)
// §三 E1 要求"每一按只动一行"、§六 记录了两棵树上的实测。
//
// 依据：封顶原本的理由是"页尾空行不占行盒 ⇒ 加了看不见"。
// 该理由经查不成立（`extraBlankHeight` 只管**块间**，文末那串空行从来没被结算过 —— 缺的是呈现）；
// 本轮补上了文末槽的光标跟随（`docView` 的 `tailK`），所以"加了看不见"不再成立。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';

Future<DocBuffer> _mount(WidgetTester tester, String doc, int caret) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer(doc)..setCaret(caret);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
  ));
  tester.state<EditViewState>(find.byType(EditView)).focusInput();
  await tester.pumpAndSettle();
  return buf;
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key, [int n = 1]) async {
  for (var i = 0; i < n; i++) {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }
}

String _vis(String s) => s.replaceAll('\n', '⏎');

/// 光标条的纵坐标（用来量"看得见的一行"）
double _caretY(WidgetTester tester) {
  final List<double> ys = <double>[];
  for (final Element e in find.byType(Container).evaluate()) {
    final Container w = e.widget as Container;
    final BoxConstraints? c = w.constraints;
    if (c == null || c.minWidth != 1.5 || c.maxWidth != 1.5) continue;
    final RenderObject? ro = e.renderObject;
    if (ro is! RenderBox || !ro.hasSize) continue;
    ys.add(ro.localToGlobal(Offset.zero).dy);
  }
  if (ys.isEmpty) return -1;
  ys.sort();
  return ys.last;
}

void main() {
  // ★★ 2026-10-27 用户实测追加：「分页原页的文末下一个空行，继续按 Enter，光标位置看上去不变，
  //   但退格次数会增加」⇒ 接缝槽原来没有 `caretDy`/`lineOffsets`，光标恒画在槽顶。
  //   修完：每次 Enter 光标**往下走一行**（与末页同一条口径）。
  testWidgets('页尾空行：连按 Enter 光标每次下移一行', (WidgetTester tester) async {
    const String doc = '甲\n\n\n<!-- pagebreak -->\n乙\n';
    final DocBuffer buf = await _mount(tester, doc, 2);
    final List<double> ys = <double>[_caretY(tester)];
    for (var i = 0; i < 3; i++) {
      await _press(tester, LogicalKeyboardKey.enter);
      ys.add(_caretY(tester));
      // ignore: avoid_print
      print('[seam#${i + 1}] y=${ys.last.toStringAsFixed(1)} | ${_vis(buf.buf)}');
    }
    for (var i = 1; i < ys.length; i++) {
      expect(ys[i] - ys[i - 1], greaterThan(10),
          reason: '第 $i 次 Enter 光标要往下走一行（改前一直是同一根位置）');
    }
  });

  testWidgets('文末：连按 4 次 Enter ⇒ 每次多一整行（不再封顶）', (WidgetTester tester) async {
    const String doc = '甲\n';
    final DocBuffer buf = await _mount(tester, doc, doc.length);
    await _press(tester, LogicalKeyboardKey.enter);
    // ignore: avoid_print
    print('[tail#1] ${_vis(buf.buf)}');
    expect(buf.buf, '甲\n\n\n', reason: '第一下就出现一整行（行数 = 尾部换行数 − 2）');
    await _press(tester, LogicalKeyboardKey.enter, 3);
    // ignore: avoid_print
    print('[tail#4] ${_vis(buf.buf)}');
    expect(buf.buf, '甲\n\n\n\n\n\n', reason: '四下 = 四行（改前第二下起封顶 ⇒ 只有 `甲⏎⏎`）');
  });

  testWidgets('页尾（分页符之前那行空行）：每次多一行', (WidgetTester tester) async {
    const String doc = '甲\n\n\n<!-- pagebreak -->\n乙\n';
    final DocBuffer buf = await _mount(tester, doc, 2);
    await _press(tester, LogicalKeyboardKey.enter, 2);
    // ignore: avoid_print
    print('[seam] ${_vis(buf.buf)}');
    expect(buf.buf, '甲\n\n\n\n\n<!-- pagebreak -->\n乙\n',
        reason: '两次 Enter 各加一行（改前封顶 ⇒ 一行都不加）');
  });

  testWidgets('分页符行首（视觉上也是空白）：每次多一行，且不露出编码', (WidgetTester tester) async {
    const String doc = '甲\n<!-- pagebreak -->\n乙\n';
    final int pb = doc.indexOf('<!--');
    final DocBuffer buf = await _mount(tester, doc, pb);
    await _press(tester, LogicalKeyboardKey.enter, 2);
    // ignore: avoid_print
    print('[pbLine] ${_vis(buf.buf)}');
    expect(buf.buf, '甲\n\n\n<!-- pagebreak -->\n乙\n',
        reason: '两次 Enter 各加一行，标记行原样（改前第二下被封顶）');
  });
}
