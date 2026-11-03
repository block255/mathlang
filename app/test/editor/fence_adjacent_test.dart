// ★ 2026-11-03 深夜（新口径，见讨论文档 §10.3）：**行内段可以紧贴行内段**。
//
//   `$a$` + `$b$` ⇒ `$a$$b$` 是**合法**形态（切段 2 段行内、渲染两个行内公式），
//   所以：① 粘到收尾 `$` 之后 **不许**再补换行；② 那个换行**删得掉**（合并后仍合法）。
//
// 改前：① `insert_guard` 规则 ⑤ 一律补换行（用户看到内容掉到下一行行首）；
//       ② `_fenceBrokenByDelete` 一律拒绝（行首退格"死按"）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';

import '../support/math_fonts.dart';

Future<DocBuffer> _pump(WidgetTester tester, String doc) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const SizedBox.shrink());
  final DocBuffer buf = DocBuffer(doc)..setCaret(0);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
  ));
  tester.state<EditViewState>(find.byType(EditView)).focusInput();
  await tester.pumpAndSettle();
  return buf;
}

/// 去掉文末补的 `\n`（`ensureDocumentEol` 会给每份文档补一个行终止符）
String _body(DocBuffer b) => b.buf.endsWith('\n')
    ? b.buf.substring(0, b.buf.length - 1)
    : b.buf;

void main() {
  setUpAll(() async => loadMathFonts());

  testWidgets('① 粘 `\$b\$` 到收尾 `\$` 之后 ⇒ 直接拼接成 `\$a\$\$b\$`（不补换行）',
      (WidgetTester tester) async {
    const String doc = r'甲 $a$ 乙'; // 收尾 `$` 在 4，之后那一格是 5
    final DocBuffer buf = await _pump(tester, doc);
    buf.setCaret(5);
    await tester.pumpAndSettle();
    tester.state<EditViewState>(find.byType(EditView)).pasteText(r'$b$');
    await tester.pumpAndSettle();
    expect(_body(buf), r'甲 $a$$b$ 乙',
        reason: '两个行内段相邻是合法形态，不许再插换行；'
            '实际「${buf.buf.replaceAll('\n', r'\n')}」');
  });

  testWidgets('② 行首退格：把补出来的那一行接回去（两个行内段合并）',
      (WidgetTester tester) async {
    const String doc = '甲 \$a\$\n\$b\$ 乙';
    final DocBuffer buf = await _pump(tester, doc);
    final int lineStart = doc.indexOf('\n') + 1;
    buf.setCaret(lineStart);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(_body(buf), r'甲 $a$$b$ 乙',
        reason: '合并后是合法的两段行内公式，退格必须能删掉那个换行；'
            '实际「${buf.buf.replaceAll('\n', r'\n')}」');
  });

  testWidgets('③ 行首退格：`\$a\$` + 行间围栏 `\$\$b\$\$` ⇒ 仍然拒绝（会造出 `\$\$\$`）',
      (WidgetTester tester) async {
    const String doc = '甲 \$a\$\n\$\$b\$\$';
    final DocBuffer buf = await _pump(tester, doc);
    final int lineStart = doc.indexOf('\n') + 1;
    buf.setCaret(lineStart);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(_body(buf), contains('\n'),
        reason: '行间围栏必须独占一行；把它的 `\$\$` 拼到行内段后面就是 `\$\$\$`'
            '（实测切段当场切坏）⇒ 这一下应当**不生效**');
  });
}
