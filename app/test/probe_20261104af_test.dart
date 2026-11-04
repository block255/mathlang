// ★ 一次性探针 v35（2026-11-04，第十二轮）—— **只读，跑完即删**。
// 用户的问题：`←/→` 到底会不会停在 `&` 上？
// 做法：拿一个 2×2 矩阵，从 tex 开头一路按 →（再一路 ←），把每一步的 caret 与
// "该 caret 位置上的字符"打出来 —— 看 `&` 有没有被跳过。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';

import 'support/math_fonts.dart';

void _p(String tag, String msg) {
  // ignore: avoid_print
  print('PROBE|$tag|$msg');
}

String _at(String s, int i) {
  if (i < 0 || i >= s.length) return i >= s.length ? 'EOF' : 'OOR';
  final String c = s[i];
  return c == '\n' ? r'\n' : c;
}

Future<DocBuffer> _mount(WidgetTester t, String doc, int caret) async {
  await t.pumpWidget(const SizedBox.shrink());
  final DocBuffer buf = DocBuffer(doc)..setCaret(caret);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 900,
        child: SingleChildScrollView(
          child: SizedBox(width: 793.7, child: EditView(buffer: buf)),
        ),
      ),
    ),
  ));
  t.state<EditViewState>(find.byType(EditView)).focusInput();
  await t.pumpAndSettle();
  return buf;
}

void main() {
  setUpAll(() async {
    await loadMathFonts();
  });

  const String doc = r'$\begin{matrix}a&b\\c&d\end{matrix}$';

  testWidgets('一路向右', (WidgetTester t) async {
    final DocBuffer b = await _mount(t, doc, 0);
    final List<String> seq = <String>['0'];
    for (var i = 0; i < 40; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pumpAndSettle();
      final String s = '${b.caret}(${_at(b.buf, b.caret)})';
      if (seq.isNotEmpty && seq.last == s) break; // 不动了
      seq.add(s);
    }
    _p('→', seq.join(' '));
    // 有没有任何一步停在 `&` 上？
    final bool onAmp = seq.any((String s) => s.contains('(&)'));
    _p('→', '停在 & 上过？$onAmp');
  });

  testWidgets('一路向左', (WidgetTester t) async {
    final DocBuffer b = await _mount(t, doc, doc.length);
    final List<String> seq = <String>['${doc.length}(EOF)'];
    for (var i = 0; i < 40; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.pumpAndSettle();
      final String s = '${b.caret}(${_at(b.buf, b.caret)})';
      if (seq.isNotEmpty && seq.last == s) break;
      seq.add(s);
    }
    _p('←', seq.join(' '));
    final bool onAmp = seq.any((String s) => s.contains('(&)'));
    _p('←', '停在 & 上过？$onAmp');
  });
}
