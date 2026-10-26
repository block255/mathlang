// ★★ 2026-10-23（批 1）：粘贴的**接线**（走真实的 EditView，不是只测纯函数）。
//
// 验证三件事：
//   ① 粘 `$…$` 进行内公式 ⇒ 缓冲区里**不会**出现嵌套 `$`；
//   ② 多行推导粘进空行间块 ⇒ 仍然**只有一对** `$$`（用户报的 F2：粘完散架 + `[公式不完整]`）；
//   ③ 兜底/归一情况在状态栏**说一句话**（不许"粘了但好像没反应"）。
//      ★ 批 37（2026-10-26）：混合文本改成"归一成 tex 就地插"，所以 ③ 现在守的是
//        "剥掉内部 `$` ⇒ 落在公式里 + 有说明"。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/ui/editor_page.dart';

import '../support/fake_file_gateway.dart';
import '../support/symbol_fixture.dart';

Future<DocBuffer> _pump(WidgetTester tester, String doc, int caret) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer(doc)..setCaret(caret);
  await tester.pumpWidget(MaterialApp(
    home: EditorPage(
      library: testSymbolLibrary(),
      buffer: buf,
      gateway: FakeFileGateway(),
    ),
  ));
  await tester.pumpAndSettle();
  return buf;
}

EditViewState _state(WidgetTester tester) =>
    tester.state<EditViewState>(find.byType(EditView));

int _count(String haystack, String needle) {
  var n = 0;
  var i = 0;
  while (true) {
    final int k = haystack.indexOf(needle, i);
    if (k < 0) return n;
    n++;
    i = k + needle.length;
  }
}

void main() {
  testWidgets('① 粘 `\$\\frac{a}{b}\$` 进行内公式 ⇒ 不带定界符进去', (WidgetTester tester) async {
    const String doc = r'前 $x+y$ 后';
    final DocBuffer buf = await _pump(tester, doc, doc.indexOf('x'));
    _state(tester).pasteText(r'$\frac{a}{b}$');
    await tester.pumpAndSettle();

    expect(buf.buf.contains(r'$\frac{a}{b}$'), isFalse,
        reason: '不许把定界符带进公式里（那会变成嵌套 `\$`）：${buf.buf}');
    expect(buf.buf.contains(r'\frac{a}{b}'), isTrue, reason: buf.buf);
    expect(_count(buf.buf, r'$'), 2, reason: '整篇仍只有那一对 `\$`：${buf.buf}');
  });

  testWidgets('② 多行推导粘进空行间块 ⇒ 仍是一块、不散架',
      (WidgetTester tester) async {
    const String doc = '\$\$\n\n\$\$';
    final DocBuffer buf = await _pump(tester, doc, 3);
    _state(tester).pasteText('f(x)-f(x_0)\n=f(x+x_0-x_0)-f(x_0)\n=f(x-x_0)');
    await tester.pumpAndSettle();

    expect(_count(buf.buf, r'$$'), 2,
        reason: '一个块 = 一对围栏（改前粘完会套出好几层）：${buf.buf}');
    expect(buf.buf.contains(r'=f(x+x_0-x_0)-f(x_0)'), isTrue, reason: buf.buf);
  });

  // ★★ 2026-10-26（批 37，用户 20261026 反馈 A2）**改口径**：
  //   改前（2026-10-23 R6）：混合文本"拆不动" ⇒ 整段推到公式之后。
  //   改后：剥掉内部成对的 `$` 归一成 tex ⇒ **就地在公式里插**（文字本来就能待在数学区里）。
  testWidgets('③ 混合文本粘进公式 ⇒ 归一成 tex 就地插，状态栏有说明',
      (WidgetTester tester) async {
    const String doc = r'前 $x+y$ 后';
    final DocBuffer buf = await _pump(tester, doc, doc.indexOf('x'));
    _state(tester).pasteText(r'见 $a$ 式');
    await tester.pumpAndSettle();

    expect(_count(buf.buf, r'$'), 2, reason: r'tex 里不许出现 `$`：${buf.buf}');
    expect(buf.buf.contains('见 a 式'), isTrue, reason: buf.buf);
    final int open = buf.buf.indexOf(r'$');
    final int close = buf.buf.indexOf(r'$', open + 1);
    final int at = buf.buf.indexOf('见');
    expect(at > open && at < close, isTrue,
        reason: '剥掉定界符之后应当落在**公式里面**：${buf.buf}');
    expect(find.byKey(const Key('paste-note')), findsOneWidget,
        reason: '我们替用户剥了定界符 ⇒ 状态栏必须说一句');
  });
}
