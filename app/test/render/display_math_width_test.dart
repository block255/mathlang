// ★★ T-B 修完后留下的守卫（2026-10-20）：N1 行间公式超宽、N2/N3 字体回退
//
// N1：用户实测一条长推导顶出页面右缘、画出 Flutter 溢出条纹（PDF 里也被截断）。
//     ⇒ 行间公式改用 `FittedBox(fit: scaleDown)` **等比缩小到正文宽**；
// N2/N3：KaTeX 字体没有 CJK 字形 ⇒ `\text{中文}` 变豆腐块；正文也缺 ⟺ 这类符号。
//     ⇒ 数学与正文的 TextStyle 都带 `fontFamilyFallback: kCjkFallback`。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/math_caret.dart';
import 'package:mathlang/ui/editor_page.dart';

import '../support/symbol_fixture.dart';

/// 一条**明显超宽**的行间公式（正是用户那份作业里的那条）
const String kWide = r'''
$$
\limsup_{n\to\infty}\{x_n+y_n\}=\lim_{n\to\infty}\left(\sup\{x_n+y_n,x_{n+1}+y_{n+1},\dots\}\right)\le \lim_{n\to\infty}A_n+\lim_{n\to\infty}B_n
$$
''';

Future<void> _pump(WidgetTester tester, String doc, {double width = 1280}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: EditorPage(library: testSymbolLibrary(), buffer: DocBuffer(doc)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('㉚ N1 行间公式超宽 ⇒ 等比缩小（不再溢出）', () {
    testWidgets('★★ 超宽行间公式被 FittedBox 包住，且渲染宽度不超正文宽',
        (WidgetTester tester) async {
      await _pump(tester, kWide);
      final Finder box = find.byType(FittedBox);
      expect(box, findsWidgets, reason: '行间公式必须走 FittedBox(scaleDown)');
      // 公式那一块的宽度必须落在页面内容宽之内（否则就是溢出）
      final Finder math = find.byType(MathWithCaret);
      expect(math, findsWidgets);
      final Size page = tester.getSize(find.byType(EditView));
      final Rect r = tester.getRect(math.first);
      // 公式必须在编辑器宽度之内（等比缩小后）
      expect(r.width, lessThanOrEqualTo(page.width),
          reason: '公式宽度 ${r.width} 超了编辑器宽 ${page.width} ⇒ 又溢出了');
      expect(tester.takeException(), isNull, reason: '不许再有 RenderFlex 溢出');
    });
  });

  group('㉛ N2/N3 字体回退链', () {
    test('★ 回退链里有 CJK 与符号字体', () {
      expect(kCjkFallback, contains('Microsoft YaHei'));
      expect(kCjkFallback, contains('Segoe UI Symbol'));
    });

    testWidgets('★ 公式里带中文 `\text{使}` 不许变成"公式不完整"',
        (WidgetTester tester) async {
      await _pump(tester,
          r'$$\forall x\in[a,b],\ \exists M>0 \text{ 使 } |f(x)|\le M$$');
      expect(find.text('［公式不完整］'), findsNothing,
          reason: '中文 text 不许把整个公式打成错误');
      expect(find.byType(MathWithCaret), findsWidgets);
    });
  });
}