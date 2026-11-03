// ★ 2026-11-03 深夜（表批 B 的收尾）：三条**现状守卫**（不是改前红 —— 现状已符合口径，
//   这里把它们钉住，防止以后改回去）。
//
//   ① 参差行：复制照实带走；**粘进表内只覆盖载荷里有的格子**（目标剩下的格原样保留）。
//   ② 光标停在"左格末尾"那一位 ⇒ 粘表写进**左格**；停在"右格开头"那一位 ⇒ 写进**右格**。
//      （实测两个位点在屏幕上差 20.9px —— 格与格之间本来就有列间距，不是同一根像素。）
//   ③ 光标**不许**停在 `\begin{…}` / `\end{…}` 里面：位点表里没有这种位点，
//      方向键也走不进去（那种位置不承载任何编辑意义）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/lang/env_table.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/math_nav.dart';

import '../support/math_fonts.dart';

const String kTable = r'\begin{bmatrix}a&b\\c&d\end{bmatrix}';

Future<DocBuffer> _pump(WidgetTester tester, String doc, int caret) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const SizedBox.shrink());
  final DocBuffer buf = DocBuffer(doc)..setCaret(caret);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
  ));
  tester.state<EditViewState>(find.byType(EditView)).focusInput();
  await tester.pumpAndSettle();
  return buf;
}

String _doc(String tex) => '${r'$$'}\n$tex\n${r'$$'}';

String _body(DocBuffer b) =>
    b.buf.endsWith('\n') ? b.buf.substring(0, b.buf.length - 1) : b.buf;

void main() {
  setUpAll(() async => loadMathFonts());

  testWidgets('① 参差行粘进表内：只覆盖载荷里有的格子（其余格保留）',
      (WidgetTester tester) async {
    final String doc = _doc(kTable);
    final DocBuffer buf = await _pump(tester, doc, 3 + kTable.indexOf('a'));
    // 2 行，但第 2 行只有 1 个格
    tester
        .state<EditViewState>(find.byType(EditView))
        .pasteText(r'$\begin{matrix}X&Y\\Z\end{matrix}$');
    await tester.pumpAndSettle();
    final String got = _body(buf);
    expect(got, contains(r'X&Y'), reason: '载荷第 1 行 2 格都写进去；实际「$got」');
    expect(got, contains('Z'), reason: '载荷第 2 行 1 格写进 (1,0)');
    expect(got, contains('d'),
        reason: '载荷第 2 行**没有**第 2 格 ⇒ 目标 (1,1) 的 `d` 必须原样留着；实际「$got」');
  });

  testWidgets('② 光标在"左格末尾"⇒ 写左格；在"右格开头"⇒ 写右格',
      (WidgetTester tester) async {
    final int amp = kTable.indexOf('&');
    // 左格末尾 = `&` 左边那一位
    DocBuffer buf = await _pump(tester, _doc(kTable), 3 + amp);
    tester
        .state<EditViewState>(find.byType(EditView))
        .pasteText(r'$\begin{matrix}Q\end{matrix}$');
    await tester.pumpAndSettle();
    expect(_body(buf), contains(r'Q&b'),
        reason: '`&` 左边的位点 = 左格末尾 ⇒ 写进 (0,0)；实际「${_body(buf)}」');
    // 右格开头 = `&` 右边那一位
    buf = await _pump(tester, _doc(kTable), 3 + amp + 1);
    tester
        .state<EditViewState>(find.byType(EditView))
        .pasteText(r'$\begin{matrix}Q\end{matrix}$');
    await tester.pumpAndSettle();
    expect(_body(buf), contains(r'a&Q'),
        reason: '`&` 右边的位点 = 右格开头 ⇒ 写进 (0,1)；实际「${_body(buf)}」');
  });

  test('③ 光标不许停在 `\\begin{…}` / `\\end{…}` 里面（位点表 + 方向键）', () {
    const String tex = kTable;
    final List<EnvTable> envs = envTablesIn(tex);
    expect(envs.length, 1);
    final EnvTable t = envs.first;
    bool inShell(int o) => (o > t.beginStart && o < t.bodyStart) ||
        (o > t.bodyEnd && o < t.endEnd);

    final List<CaretSite> sites = buildCaretSites(tex).sites;
    final List<int> bad = <int>[
      for (final CaretSite s in sites)
        if (inShell(s.offset)) s.offset,
    ];
    expect(bad, isEmpty, reason: '位点表里不该有停在记账号里的位点：$bad');

    // 方向键从头走到尾
    final String doc = _doc(tex);
    final int shift = 3;
    final List<int> walked = <int>[];
    var o = 0;
    for (var i = 0; i < 300; i++) {
      walked.add(o);
      final int n = nextCaretOffset(doc, o);
      if (n == o) break;
      o = n;
    }
    final List<int> badWalk = <int>[
      for (final int x in walked)
        if (inShell(x - shift)) x,
    ];
    expect(badWalk, isEmpty, reason: '方向键走进了记账号：$badWalk');
  });
}
