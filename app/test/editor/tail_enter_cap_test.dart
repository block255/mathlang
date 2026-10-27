// 批 42（2026-10-26）：**Enter 与"点文末空白"同一条口径（甲，只封两种页尾）**。
//
// 用户拍板原话：「甲我们讨论的肯定最后一页的文末空行和分页后原页的文末空行；
//   其他同页间文本行间的空行肯定还是保持可增加」。
//
// 为什么封这两种：它们**不占行盒**（`blank_runs.blankRunFrom` 已把"文末那个位置"
//   排除在"真有行盒的空行"之外）⇒ Enter 加了也**看不见**，只留下"按了像没反应"
//   和"回来要按同样多次 Delete"（用户实测）。
// 为什么中间的不封：中间空行**有行盒**、看得见，且 §11.46 明确定过"能再按 Enter 接着长"。

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

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('★ 最后一页文末：连按 4 次 Enter ⇒ 只保留一行空行', (WidgetTester tester) async {
    const String doc = '甲\n';
    final DocBuffer buf = await _mount(tester, doc, doc.length);
    await _press(tester, LogicalKeyboardKey.enter, 4);
    expect(buf.buf, '甲\n\n', reason: '文末空行封顶一行（改前会变成 `甲\\n\\n\\n\\n\\n`）');
  });

  testWidgets('★ 最后一页文末：回来只要按一次退格', (WidgetTester tester) async {
    const String doc = '甲\n';
    final DocBuffer buf = await _mount(tester, doc, doc.length);
    await _press(tester, LogicalKeyboardKey.enter, 4);
    await _press(tester, LogicalKeyboardKey.backspace, 1);
    expect(buf.buf, '甲', reason: '一次退格就回到文末（改前要按和 Enter 一样多次）');
  });

  testWidgets('★ 分页后**原页**的页尾空行：同样封顶一行（下面是分页符）',
      (WidgetTester tester) async {
    const String doc = '甲\n\n\n<!-- pagebreak -->\n\n乙\n';
    final int blank = 2; // 甲 与分页符之间的第一行空行
    final DocBuffer buf = await _mount(tester, doc, blank);
    await _press(tester, LogicalKeyboardKey.enter, 3);
    expect(buf.buf, doc, reason: '页尾空行封顶：再按 Enter 不再加（改前会越加越多）');
  });

  testWidgets('★ 段落**中间**的空行照旧能按 Enter 接着长（§11.46 不动）',
      (WidgetTester tester) async {
    const String doc = '甲\n\n乙\n';
    final DocBuffer buf = await _mount(tester, doc, 2);
    await _press(tester, LogicalKeyboardKey.enter, 2);
    expect(buf.buf, '甲\n\n\n\n乙\n', reason: '中间的空行看得见，照旧一次加一行');
  });

  testWidgets('★ 分页符行首（视觉上也是空白）按 Enter ⇒ 只补一个换行，与 Delete 1:1',
      (WidgetTester tester) async {
    const String doc = 'bb\n<!-- pagebreak -->\ncc\n';
    final int pb = doc.indexOf('<!--');
    final DocBuffer buf = await _mount(tester, doc, pb);
    await _press(tester, LogicalKeyboardKey.enter, 1);
    expect(buf.buf, 'bb\n\n<!-- pagebreak -->\ncc\n',
        reason: '一次 Enter 只补一个换行（改前补两个 ⇒ 删除要按两次）');
    // 再按一次：上面已经有一行空行 ⇒ 封顶
    await _press(tester, LogicalKeyboardKey.enter, 1);
    expect(buf.buf, 'bb\n\n<!-- pagebreak -->\ncc\n', reason: '页尾空行封顶');
    // 一次退格就回到文末
    await _press(tester, LogicalKeyboardKey.backspace, 1);
    expect(buf.buf, 'bb\n<!-- pagebreak -->\ncc\n', reason: '一次退格就吃掉那一行空行');
  });
}
