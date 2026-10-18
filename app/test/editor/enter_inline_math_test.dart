// 守卫测试：**行内数学里按 Enter ⇒ 在光标处断栅栏**（PC-1b，2026-10-18 用户拍板）
//
// 规则按"层"分（不按"是不是公式"分）：
//   · 行内段里、且**不在任何结构内部**（一串平铺原子之间）⇒ 就地断：`$左$` + 断行 + `$右$`，原子不动；
//   · **结构内部**（`\frac{}{}` 的分子里）⇒ 不切，交给 insert_guard 推到块之后；
//   · 行间块内部 ⇒ 同上（display 是块级单元）。
// 断完光标落在**右段内容开头**（乙案：与记事本一致）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';

Future<DocBuffer> _mount(WidgetTester tester, String doc, int caret) async {
  final DocBuffer buf = DocBuffer(doc)..setCaret(caret);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 600,
        child: SingleChildScrollView(child: EditView(buffer: buf)),
      ),
    ),
  ));
  final EditViewState st = tester.state<EditViewState>(find.byType(EditView));
  st.focusInput();
  buf.setCaret(caret);
  await tester.pump();
  return buf;
}

Future<void> _enter(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pump();
}

void main() {
  testWidgets('原子之间按 Enter ⇒ 就地在光标处断开（两侧各补一对栅栏）',
      (WidgetTester tester) async {
    //           0123456789
    final DocBuffer buf = await _mount(tester, r'a $x+y$ b', 5);
    await _enter(tester);
    expect(buf.buf, '\$a \$x+\$\n\n\$y\$ b\$'.substring(1).substring(0, buf.buf.length),
        reason: '两侧各补一对栅栏：实际=${buf.buf}');
    expect(buf.buf, contains('\n\n'), reason: '断点处是一个新块');
    expect(buf.buf.startsWith(r'a $x+$'), isTrue, reason: '左段应被关闭：${buf.buf}');
    expect(buf.buf.endsWith(r'$y$ b'), isTrue, reason: '右段应被重新打开：${buf.buf}');
    expect(buf.caret, 8, reason: '光标落在右段内容开头（乙案）');
  });

  testWidgets('结构内部按 Enter ⇒ 不切（换行被推到块之后）',
      (WidgetTester tester) async {
    final String doc = r'a $\frac{1}{2}$ b';
    // 光标落在分子 `1` 之后
    final int caret = doc.indexOf('1') + 1;
    final DocBuffer buf = await _mount(tester, doc, caret);
    await _enter(tester);
    expect(buf.buf.contains(r'$\frac{1}{2}$'), isTrue,
        reason: '结构内部不该被行切断：${buf.buf}');
    expect(buf.buf.split('\n').length, greaterThan(1), reason: '换行仍要发生（推到块之后）');
  });

  testWidgets('数学段末尾按 Enter ⇒ 不切段（交给 insert_guard）',
      (WidgetTester tester) async {
    final DocBuffer buf = await _mount(tester, r'a $x$ b', 4);
    await _enter(tester);
    expect(buf.buf.contains(r'$x$'), isTrue, reason: '段尾不应被切开：${buf.buf}');
  });
}
