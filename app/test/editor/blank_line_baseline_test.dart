// **行为基准守卫**：`notes/design/只读基准.txt` 第 1/3/4/6/7 条。
//
// 只读基准（用户撰写、AI 只读）原文要点：
//   1  文末行尾 Enter ⇒ 光标到"文末下一行这个空行"；退格一次返航；点文末下方空白 ⇒ 落那一行
//   3  文末下一行这个空行**永不被退格删掉**（要保证它永远能承接光标）
//   4  那一行在**第一次 Enter 之前**就能承接光标，且**末页 / 分页原页一致**
//   6  彻底区分 行 / 段 / 行间距 / 段间距
//   7  点文末下方空白：有 ⇒ 落那一行；没有 ⇒ 向上找最下面存在的空行；都没有 ⇒ 文末下一行
//
// 本文件钉的是**一把尺子**（2026-10-27 探针实测）：
//   行盒 = 字号 × 行距 ≈ 27.2；段间距 ≈ 11.2；一行 = 38.4；
//   光标在行盒里垂直居中 ⇒ 行顶(y) = 槽顶 + 段间距 + k × 38.4 + (行盒 − 光标高)/2。
//   探针现场（改前）：`甲⏎` 偏移 2 的光标画在 122.6，而"在该行打出来的字"在 137.2 —— 差 14.8。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/editor/page_sheet.dart';

const double _row = 38.4; // 一行（行盒 + 段间距）
const double _eps = 0.6;

TextEditingValue _v(String text, [int? sel]) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: sel ?? text.length),
      composing: TextRange.empty,
    );

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

List<double> _caretYs(WidgetTester tester) {
  final List<double> ys = <double>[];
  for (final Element e in find.byType(Container).evaluate()) {
    final Container w = e.widget as Container;
    final BoxConstraints? c = w.constraints;
    if (c == null || c.minWidth != 1.5 || c.maxWidth != 1.5) continue;
    final RenderObject? ro = e.renderObject;
    if (ro is! RenderBox || !ro.hasSize) continue;
    ys.add(ro.localToGlobal(Offset.zero).dy);
  }
  ys.sort();
  return ys;
}

double _caretY(WidgetTester tester) {
  final List<double> ys = _caretYs(tester);
  return ys.isEmpty ? -1 : ys.last;
}

Rect _page0(WidgetTester tester) {
  for (final Element e in find.byType(PageSheet).evaluate()) {
    final RenderObject? ro = e.renderObject;
    if (ro is RenderBox && ro.hasSize) {
      return ro.localToGlobal(Offset.zero) & ro.size;
    }
  }
  return Rect.zero;
}

void main() {
  group('基准 4 · 文末下一行在**第一次 Enter 之前**就能承接光标', () {
    testWidgets('末页：光标画在文末下面**一行**，不是文末的行末', (WidgetTester tester) async {
      // `甲⏎`：偏移 1 = 甲的行末，偏移 2 = 下一行行首（EOF）。
      await _mount(tester, '甲\n', 1);
      final double atEnd = _caretY(tester);
      await _mount(tester, '甲\n', 2);
      final double atNext = _caretY(tester);
      expect(atEnd, greaterThan(0), reason: '文末行末应有光标');
      expect(atNext - atEnd, closeTo(_row, _eps),
          reason: '光标在"文末下一行"上，应正好比文末行末低一行（实测差 '
              '${(atNext - atEnd).toStringAsFixed(1)}）');
    });

    testWidgets('末页：光标 y == 在这一行打出来的字的 y（同一把尺子）',
        (WidgetTester tester) async {
      final DocBuffer buf = await _mount(tester, '甲\n', 2);
      final double before = _caretY(tester);
      tester.testTextInput.updateEditingValue(_v('x'));
      await tester.pumpAndSettle();
      expect(buf.buf, '甲\n\nx\n',
          reason: '在"文末下一行"上打字 = **开一个新段**（那一行是段，不是上一段的段内行）');
      final double after = _caretY(tester);
      expect((after - before).abs(), lessThan(_eps),
          reason: '字的 y=$after 与原来光标的 y=$before 必须同高（差 '
              '${(after - before).toStringAsFixed(1)}）');
    });

    testWidgets('分页原页：那一行 = **分页符行的行首**，与末页同一把尺子',
        (WidgetTester tester) async {
      // `A⏎⏎<!-- pagebreak -->⏎⏎B⏎`：偏移 1 = A 行末、2 = 空行首、3 = 分页符行首。
      const String doc = 'A\n\n<!-- pagebreak -->\n\nB\n';
      await _mount(tester, doc, 1);
      final double atEnd = _caretY(tester);
      await _mount(tester, doc, 3); // 分页符行首
      final double atPb = _caretY(tester);
      expect(atPb - atEnd, closeTo(_row, _eps),
          reason: '分页原页的"下一行"应正好在 A 下面一行（实测差 '
              '${(atPb - atEnd).toStringAsFixed(1)}）');
    });
  });

  group('基准 1 · 点文末下方空白 ⇒ 落文末下一行', () {
    testWidgets('点末页底部空白：光标落在**最下面那一行**并画出来',
        (WidgetTester tester) async {
      final DocBuffer buf = await _mount(tester, '甲\n', 1);
      final Rect page = _page0(tester);
      // 点到**正文区**的下半部分（页面底部 30px 落在下页边距里，那里不属于正文）
      await tester.tapAt(Offset(page.center.dx, page.top + page.height * 0.6));
      await tester.pumpAndSettle();
      expect(buf.caret, 2, reason: '点底部空白 ⇒ 落"文末下一行"（偏移 2 = EOF）');
      final List<double> ys = _caretYs(tester);
      expect(ys.length, 1, reason: '只能有一根光标（不能文末行末与下一行各画一根）：$ys');
      expect(ys.single, closeTo(_caretY(tester), _eps));
    });

    // 〔用户〕只读基准 7：三级在"文末下一行是**常驻行**"（基准 4）下**合并成一条** ——
    //   它就是最下面那一条空行 ⇒ "向上找"永远有答案，就是它（② 与 ③ 是同一件事）。
    testWidgets('★ 点在所有行下面 ⇒ 落**最下面那一行**（末页 = 文末下一行）',
        (WidgetTester tester) async {
      // `甲⏎⏎乙⏎`：文末下方没有空行；最下面那一行 = 偏移 5（EOF）
      final DocBuffer buf = await _mount(tester, '甲\n\n乙\n', 3);
      final Rect page = _page0(tester);
      await tester.tapAt(Offset(page.center.dx, page.top + page.height * 0.6));
      await tester.pumpAndSettle();
      expect(buf.caret, 5,
          reason: '落最下面那一行（= 文末下一行，偏移 5）；2026-10-28 用户纠正：'
              '常驻行本身就是一条空行、而且是最下面那一条');
      expect(_caretYs(tester).length, 1, reason: '一根光标');
    });

    testWidgets('★ 第 1 级：文末本来就有空行 ⇒ 落**最下面那一行**（不是倒数第二个）',
        (WidgetTester tester) async {
      // `甲⏎⏎⏎`：屏幕上是两行空行（偏移 3 与 4）；点更下面的空白 ⇒ 落最后那一行（4）
      // ★ 2026-10-28 用户第二次手验：「我造了多个空行，点更下面，光标落在倒数第二个空行」
      final DocBuffer buf = await _mount(tester, '甲\n\n\n', 1);
      final Rect page = _page0(tester);
      await tester.tapAt(Offset(page.center.dx, page.top + page.height * 0.6));
      await tester.pumpAndSettle();
      expect(buf.caret, 4, reason: '文末已有空行 ⇒ 落最下面那一行（偏移 4 = 文末下一行）');
    });
  });

  group('基准 1/3 · Enter 与退格在文末 1:1，且永久行删不掉', () {
    testWidgets('文末连按 Enter：每一下正好一行（38.4），不多不少',
        (WidgetTester tester) async {
      final DocBuffer buf = await _mount(tester, '甲\n', 1);
      double prev = _caretY(tester);
      for (var i = 1; i <= 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        final double now = _caretY(tester);
        expect(now - prev, closeTo(_row, _eps),
            reason: '第 $i 下 Enter 走了 ${(now - prev).toStringAsFixed(1)}px');
        prev = now;
      }
      expect(buf.buf, '甲\n\n\n\n\n', reason: '一下 Enter = 一个换行符');
    });

    // ★★ 2026-10-28（用户复现过的缺陷，本批修掉）：光标**已经站在**"文末下一行"那一格上时，
    //   再按 Enter 必须真的多一行、光标下移一行（改前：行表 skip 第一个空行 ⇒ 原地不动）。
    testWidgets('★ 站在文末下一行上按 Enter ⇒ 真的多一行、光标下移一行（不再原地不动）',
        (WidgetTester tester) async {
      final DocBuffer buf = await _mount(tester, '甲\n', 2); // 偏移 2 = 文末下一行
      final double before = _caretY(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(buf.buf, '甲\n\n', reason: '一下 Enter = 一个换行符');
      expect(buf.caret, 3);
      final double after = _caretY(tester);
      expect(after - before, closeTo(_row, _eps),
          reason: '光标必须真的下移一行（实测走了 ${(after - before).toStringAsFixed(1)}px）');
      // 退格是逆操作：一下收掉这一行（1:1）
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();
      expect(buf.buf, '甲\n');
      expect(buf.caret, 2);
      expect(_caretY(tester), closeTo(before, _eps), reason: '退格回到原来那一格');
    });

    testWidgets('永久行上退格：只回文末行末，**不改字节**', (WidgetTester tester) async {
      final DocBuffer buf = await _mount(tester, '甲\n', 2);
      final double before = _caretY(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();
      expect(buf.buf, '甲\n', reason: '文末下一行这个空行永不被退格删掉');
      expect(buf.caret, 1, reason: '退格只把光标退回文末行末尾');
      expect(_caretY(tester), lessThan(before), reason: '光标要**看得见地**回到上一行');
    });
  });

  group('基准 3 · 空行上 Shift+Enter', () {
    Future<void> shiftEnter(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
    }

    testWidgets('空行没有"行尾两空格"的宿主 ⇒ Shift+Enter 等价 Enter',
        (WidgetTester tester) async {
      final DocBuffer buf = await _mount(tester, '甲\n', 2); // 在永久行（空行）上
      await shiftEnter(tester);
      expect(buf.buf, '甲\n\n',
          reason: '空行上 Shift+Enter 应像 Enter 一样造出下一个空行（基准 3 第一句）');
    });

    // ★★★ 2026-10-28（用户拍板，只读基准 6 已补句）：
    //   「shift enter 换的是**段内的行**（光标两侧有文字时可以，否则等价 enter）」。
    //   原来的断言是 `甲  \n\n` —— 那在缓冲区里是"两空格 + 两个换行"，
    //   而两个换行之间那个空行**是段分隔符（零高度）**，于是光标被放进段距里，
    //   打字还会把两段并成一段。行尾没有"段内的空行"这种东西（md 表达不了）⇒ 等价 Enter。
    testWidgets('行尾 Shift+Enter = Enter（段内空行在 md 里不存在）',
        (WidgetTester tester) async {
      final DocBuffer buf = await _mount(tester, '甲\n', 1);
      await shiftEnter(tester);
      expect(buf.buf, '甲\n\n',
          reason: '行尾没有"段内的空行"可造 ⇒ 与 Enter 完全一致（基准 6）');
    });
  });

  group('不变量 · 非空文档永远以换行符收尾', () {
    test('打字之后补上行终止符；撤销**精确**回到空文档', () {
      final DocBuffer b = DocBuffer('');
      b.replace(0, 0, '甲');
      expect(b.buf, '甲\n', reason: '文末行要有行终止符，否则"文末行末"与"下一行"是同一个偏移');
      expect(b.caret, 1, reason: '光标在甲之后、换行符之前');
      expect(b.undo(), isTrue);
      expect(b.buf, '', reason: '撤销必须精确回到**空文档**，不能留下一个空行');
      expect(b.redo(), isTrue);
      expect(b.buf, '甲\n');
    });

    test('连续打字仍然合并成一步撤销（不被行终止符打断）', () {
      final DocBuffer b = DocBuffer('');
      b.replace(0, 0, '甲', coalesce: true);
      b.replace(1, 1, '乙', coalesce: true);
      b.replace(2, 2, '丙', coalesce: true);
      expect(b.buf, '甲乙丙\n');
      expect(b.undo(), isTrue);
      expect(b.buf, '', reason: '三个字应合并成**一步**撤销');
    });

    test('打开没有尾换行的文件 ⇒ 补一个；已有的不重复补', () {
      final DocBuffer b = DocBuffer('');
      b.loadDocument('甲');
      expect(b.buf, '甲\n');
      b.loadDocument('甲\n');
      expect(b.buf, '甲\n');
      b.loadDocument('');
      expect(b.buf, '');
    });
  });
}
