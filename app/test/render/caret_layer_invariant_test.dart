// F8 守卫（用户 2026-11-01 实测）：**同一行、同一层的所有位点，竖条必须一样**。
//
// 三种相貌（都是"选行 = 离光标最近的字形"造成的）：
//   ① 行间 `f_{-}` 的"整体之后"：最近字形是下标 `−`（18 高）⇒ 竖条 15.1/5.1（公式首 17.6/0.3）
//   ② 行间 `\frac{x-a}{b}` 的公式末尾：最近字形是分母 `b`
//   ③ `f'_{-}f'_{-}`：两个对象**之间** vs **行尾**：高度相同、纵向差几 px（公式首又不一样）
// 口径：**竖条在哪一行由"光标所在的层"决定（位点表 path），不由"旁边最后一个字形"决定**。
// 探针（2026-11-01）：主行字形盒 **21**、脚本字形盒 **18** —— 层差在几何上是"高一档"。
//
// 改前必红：①③。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/math_caret.dart';

import '../support/math_fonts.dart';

Future<DocBuffer> _pump(WidgetTester tester, String doc) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer(doc);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
  ));
  tester.state<EditViewState>(find.byType(EditView)).focusInput();
  await tester.pumpAndSettle();
  return buf;
}

Rect? _bar(WidgetTester tester) {
  for (final Element e in find.byType(MathWithCaret).evaluate()) {
    final MathWithCaret w = e.widget as MathWithCaret;
    if (!w.showCaret) continue;
    final dynamic st = (e as StatefulElement).state as dynamic;
    return st.debugCaretBar as Rect?;
  }
  return null;
}

Future<Rect?> _at(WidgetTester tester, DocBuffer buf, int at) async {
  buf.setCaret(at);
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
  return _bar(tester);
}

void _p(String s) {
  // ignore: avoid_print
  print(s);
}

/// 同层一致性断言：全部 top / height 与第一个的差 ≤ [tol]
void _expectSameLevel(List<Rect?> bars, List<String> labels, {double tol = 0.6}) {
  final List<String> desc = <String>[];
  for (var i = 0; i < bars.length; i++) {
    final Rect? b = bars[i];
    desc.add('${labels[i]}=${b == null ? "null" : "top ${b.top.toStringAsFixed(1)}/h ${b.height.toStringAsFixed(1)}"}');
  }
  _p('    ');
  final Rect first = bars.first!;
  for (var i = 1; i < bars.length; i++) {
    final Rect b = bars[i]!;
    expect((b.top - first.top).abs(), lessThan(tol),
        reason: '${labels[i]} 与 ${labels[0]} 该同层同高（${desc.join(" · ")}）');
    expect((b.height - first.height).abs(), lessThan(tol),
        reason: '${labels[i]} 与 ${labels[0]} 该同层同高（${desc.join(" · ")}）');
  }
}

void main() {
  setUpAll(() async => loadMathFonts());

  testWidgets('① 行间 `f_{-}`：公式首 / 整体之后 必须同层', (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, '前\n\$\$\nf_{-}\n\$\$\n后');
    final int s = buf.buf.indexOf(r'f_{-');
    final List<Rect?> bars = <Rect?>[
      await _at(tester, buf, s), // 公式首
      await _at(tester, buf, s + 5), // 整体之后（tex 末位）
    ];
    _expectSameLevel(bars, <String>['公式首', '整体之后']);
  });

  testWidgets('② 行间分式：公式首 / 公式末尾 必须同层', (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, '前\n\$\$\n\\frac{x-a}{b}\n\$\$\n后');
    final int s = buf.buf.indexOf(r'\frac');
    final List<Rect?> bars = <Rect?>[
      await _at(tester, buf, s), // 公式首
      await _at(tester, buf, s + 13), // 公式末尾（tex 末位）
    ];
    _expectSameLevel(bars, <String>['公式首', '公式末尾']);
  });

  testWidgets('③ 两个并列对象：公式首 / 之间 / 行尾 必须同层', (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, '前\n\$\$\nf\'_{-}f\'_{-}\n\$\$\n后');
    final int s = buf.buf.indexOf("f'");
    final int mid = s + "f'_{-}".length;
    final int end = mid + "f'_{-}".length;
    final List<Rect?> bars = <Rect?>[
      await _at(tester, buf, s), // 公式首（主行基准）
      await _at(tester, buf, mid),
      await _at(tester, buf, end),
    ];
    _expectSameLevel(bars, <String>['公式首', '两对象之间', '行尾']);
  });

  testWidgets('④ 上划线：公式首 / 末尾 必须同层（防回退）', (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, '前\n\$\$\n\\overline{AB}\n\$\$\n后');
    final int s = buf.buf.indexOf(r'\overline');
    final List<Rect?> bars = <Rect?>[
      await _at(tester, buf, s),
      await _at(tester, buf, s + 13),
    ];
    _expectSameLevel(bars, <String>['公式首', '末尾']);
  });

  testWidgets('⑤ 行内并列：公式首 / 之间 / 行尾 必须同层', (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, "\$f'_{-}f'_{-}\$");
    final int s = buf.buf.indexOf("f'");
    final int mid = s + "f'_{-}".length;
    final int end = mid + "f'_{-}".length;
    final List<Rect?> bars = <Rect?>[
      await _at(tester, buf, s),
      await _at(tester, buf, mid),
      await _at(tester, buf, end),
    ];
    _expectSameLevel(bars, <String>['公式首', '两对象之间', '行尾']);
  });

  testWidgets('⑥ 前后有正文：三处必须同层', (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, "甲\$f'_{-}f'_{-}\$乙");
    final int s = buf.buf.indexOf("f'");
    final int mid = s + "f'_{-}".length;
    final int end = buf.buf.indexOf('\$', s); // 收尾 `$` = 内容末尾
    final List<Rect?> bars = <Rect?>[
      await _at(tester, buf, s),
      await _at(tester, buf, mid),
      await _at(tester, buf, end),
    ];
    _expectSameLevel(bars, <String>['公式首', '两对象之间', '内容末']);
  });

  testWidgets('⑦ 两对象之间隔一个空格：三处必须同层', (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, "\$f'_{-} f'_{-}\$");
    final int s = buf.buf.indexOf("f'");
    final int mid = s + "f'_{-}".length;
    final int end = buf.buf.lastIndexOf('}') + 1; // 第二个对象的收尾 `}`
    final List<Rect?> bars = <Rect?>[
      await _at(tester, buf, s),
      await _at(tester, buf, mid),
      await _at(tester, buf, end),
    ];
    _expectSameLevel(bars, <String>['公式首', '两对象之间', '内容末']);
  });
}
