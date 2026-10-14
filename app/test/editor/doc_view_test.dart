// 数语引擎 · S2-4 分页视图测试
//
// 为什么要有它：浏览器自动化在**这台机器上不可靠**（Chrome 遮挡判定 → 页面 hidden → 不产帧），
// widget 测试里帧是同步的、可复现。S2-4 的验收就以这里为准，浏览器只当"肉眼看一眼"。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/core/doc_settings.dart';
import 'package:mathlang/editor/doc_view.dart';

Future<DocViewStats> pumpDoc(
  WidgetTester tester,
  String doc, {
  DocSettings? settings,
  int frames = 6,
}) async {
  final DocBuffer buf = DocBuffer(doc);
  DocViewStats? stats;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: DocView(
          buffer: buf,
          settings: settings ?? DocSettings.defaults,
          onStats: (DocViewStats s) => stats = s,
        ),
      ),
    ),
  ));
  for (var i = 0; i < frames; i++) {
    await tester.pump();
  }
  expect(stats, isNotNull, reason: 'DocView 必须报出分页统计');
  return stats!;
}

void main() {
  testWidgets('短文档 → 1 页', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final s = await pumpDoc(tester, '第一段文字，含一个公式 \$x^2+1\$ 而已。');
    expect(s.pages, 1);
    expect(s.blocks, greaterThanOrEqualTo(1));
    expect(s.units, greaterThanOrEqualTo(1));
    expect(s.overflow, 0);
  });

  testWidgets('★ 手动分页符强制换页 → 2 页', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final s = await pumpDoc(
        tester, '第一页的内容。\n\n<!-- pagebreak -->\n\n第二页的内容。');
    expect(s.pages, 2, reason: '分页符之后必须从新的一页开始');
  });

  testWidgets('★ 高于一页的块：不切断 + 页下告警', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final rows = <String>[for (var i = 1; i <= 120; i++) '$i'];
    final doc = '前言一句。\n\n\$\$\n\\begin{pmatrix}\n'
        '${rows.join(' \\\\ ')}\n'
        '\\end{pmatrix}\n\$\$\n\n后记一句。';
    final s = await pumpDoc(tester, doc);

    expect(s.overflow, greaterThanOrEqualTo(1),
        reason: '120 行的矩阵必然高于一页，必须进告警清单');
    expect(find.textContaining('高于一页'), findsWidgets,
        reason: '原则 5：静默失败必须可见 —— 页下要有黄色告警');
    // 高于一页的块**单独占一页**、不被切断 → 总页数 ≥ 3
    expect(s.pages, greaterThanOrEqualTo(3));
  });

  testWidgets('页眉参与分页高度：开页眉后页数不会变少', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 造一个刚好一页多一点点的文档：开页眉后可用高变小
    final body = List<String>.generate(
      28,
      (int i) => '第 $i 段：设 \$a_{i,j}+b^2 \\ge 0\$，于是 \$\\frac{a}{b}=\\sqrt{2}\$ 成立。',
    ).join('\n\n');
    final noHeader = await pumpDoc(tester, body);
    final withHeader = await pumpDoc(
      tester,
      body,
      settings: DocSettings.defaults.copyWith(headerText: '张三 20230101'),
    );
    expect(withHeader.pages, greaterThanOrEqualTo(noHeader.pages));
    expect(noHeader.units, withHeader.units, reason: '页眉不应改变流单元数量');
  });

  testWidgets('字号变小 → 页数不增加', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final body = List<String>.generate(
      30,
      (int i) => '第 $i 段：含公式 \$x^2+1\$ 与 \$a_{i,j}\$ 的一段文字。',
    ).join('\n\n');
    final big = await pumpDoc(tester, body);
    final small = await pumpDoc(tester, body,
        settings: DocSettings.defaults.copyWith(bodyFontSize: 12));
    expect(small.pages, lessThanOrEqualTo(big.pages));
  });
}
