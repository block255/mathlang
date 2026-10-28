// 段落分隔符的守卫（2026-10-28 用户拍板：**段间距不承接字符**）。
//
// 只读基准 `notes/design/只读基准.txt`：
//   6  彻底区分 行 / 段 / 行间距 / 段间距（"无特殊说明的行都是视觉行"）
//   7  点文末下方空白：有 ⇒ 落它 / 没有 ⇒ 向上找 / 都没有 ⇒ 文末下一行
//
// 本文件钉的是**一条判据的三面**：
//   ① `\n\n` 里第二个换行符是**段落分隔符** —— 零高度、不是行、**不是光标位**；
//   ② 方向键 / 点击都不许停在它上面（否则光标只能画进段距 = "段间距当容器行"）；
//   ③ 段距归**下一段**（`leadingGap` 挂在下一段、页首丢弃）⇒ 点它落下一段行首。
//
// 根的来历（实测，2026-10-28）：`A⏎⏎B` 的分隔符偏移被画在 `行盒底 + 3.6`（= 126.2），
// 而下一段在 133.8 —— 差 11.2 = 段距 ⇒ 光标悬在缝里、压着下一行；在那儿打字还会把两段并成一段。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/core/paragraph_break.dart';
import 'package:mathlang/editor/blank_runs.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/math_nav.dart';

Future<DocBuffer> _mount(WidgetTester tester, String doc, int caret) async {
  tester.view.physicalSize = const Size(900, 1600);
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

/// 光标竖条（`Container(width: 1.5)` 那一族）的全局位置
List<Offset> _bars(WidgetTester tester) {
  final List<Offset> out = <Offset>[];
  for (final Element e in find.byType(Container).evaluate()) {
    final Widget w = e.widget;
    if (w is! Container) continue;
    final BoxConstraints? c = w.constraints;
    if (c == null || c.minWidth != 1.5 || c.maxWidth != 1.5) continue;
    final RenderObject? ro = e.renderObject;
    if (ro is RenderBox && ro.hasSize) {
      out.add(ro.localToGlobal(Offset.zero));
    }
  }
  out.sort((Offset a, Offset b) => a.dy.compareTo(b.dy));
  return out;
}

void main() {
  group('判据 · isParagraphSeparator', () {
    test('段与段之间：第二个 `\\n` 是分隔符', () {
      expect(isParagraphSeparator('甲\n\n乙\n', 2), isTrue);
    });

    test('文末没有分隔符（文末每个空行都是真行）', () {
      expect(isParagraphSeparator('甲\n\n', 2), isFalse, reason: '文末后面没有下一段来用掉它');
      expect(isParagraphSeparator('甲\n\n\n', 2), isFalse);
      expect(isParagraphSeparator('甲\n\n\n', 3), isFalse);
    });

    test('文首没有分隔符（文首每个空行都占一整行）', () {
      expect(isParagraphSeparator('\n\n甲\n', 1), isFalse);
      expect(isParagraphSeparator('\n\n甲\n', 2), isFalse);
    });

    test('一串三换行里只有第一个是分隔符，第二个是真行', () {
      expect(isParagraphSeparator('甲\n\n\n乙\n', 2), isTrue);
      expect(isParagraphSeparator('甲\n\n\n乙\n', 3), isFalse, reason: '这是真空段的行首');
    });

    test('行末 / 行首那些换行符不是分隔符', () {
      expect(isParagraphSeparator('甲\n\n乙\n', 1), isFalse);
      expect(isParagraphSeparator('甲\n乙\n', 2), isFalse, reason: '段内软换行');
    });
  });

  group('判据 · blankRowStart', () {
    test('两段之间从第 1 个起才是行；文首文末从第 0 个起', () {
      expect(blankRowStart(atDocStart: false, atDocEnd: false), 1);
      expect(blankRowStart(atDocStart: true, atDocEnd: false), 0);
      expect(blankRowStart(atDocStart: false, atDocEnd: true), 0);
    });
  });

  group('方向键 · 不许停在分隔符上', () {
    test('`→` 从上一行行末跨过分隔符，落到下一段行首', () {
      expect(nextCaretOffset('甲\n\n乙\n', 1), 3);
    });

    test('`←` 从下一段行首跨过分隔符，回到上一行行末', () {
      expect(prevCaretOffset('甲\n\n乙\n', 3), 1);
    });

    test('多空行：跨过分隔符，但停在真空段行首（那是真行）', () {
      // `甲⏎⏎⏎乙⏎`：偏移 1 = 甲行末、2 = 分隔符、3 = 真空段行首、4 = 乙行首
      expect(nextCaretOffset('甲\n\n\n乙\n', 1), 3);
      expect(prevCaretOffset('甲\n\n\n乙\n', 3), 1);
    });
  });

  group('渲染 · 分隔符偏移一根竖条都没有', () {
    testWidgets('`甲⏎⏎乙⏎` 的偏移 2（分隔符）不画光标', (WidgetTester tester) async {
      await _mount(tester, '甲\n\n乙\n', 2);
      expect(_bars(tester), isEmpty, reason: '分隔符不是位置；画出来就只能画进段距');
    });

    testWidgets('上一行行末 / 下一段行首各有一根，且差正好一行',
        (WidgetTester tester) async {
      await _mount(tester, '甲\n\n乙\n', 1);
      final List<Offset> a = _bars(tester);
      expect(a, hasLength(1));
      await _mount(tester, '甲\n\n乙\n', 3);
      final List<Offset> b = _bars(tester);
      expect(b, hasLength(1));
      expect(b.first.dy - a.first.dy, closeTo(38.4, 0.6),
          reason: '段与段之间只让开一个段距 ⇒ 差一行（实测 '
              '${(b.first.dy - a.first.dy).toStringAsFixed(1)}）');
    });
  });

  group('点击 · 段距归下一段', () {
    testWidgets('点两段之间的空隙 ⇒ 落下一段行首（不是分隔符）',
        (WidgetTester tester) async {
      final DocBuffer buf = await _mount(tester, '甲\n\n乙\n', 1);
      final Offset bar = _bars(tester).first;
      // 段距那一格：上一行行盒底再往下 3.4（行盒 27.2 ⇒ 光标 y + 27 落在段距里）
      await tester.tapAt(Offset(bar.dx + 80, bar.dy + 27));
      await tester.pumpAndSettle();
      expect(buf.caret, 3, reason: '段距是下一段的段前距 ⇒ 点它落下一段行首');
    });
  });

  group('Shift+Enter · 只在光标两侧都有字时成立（只读基准 6）', () {
    Future<void> shiftEnter(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
    }

    Future<void> enter(WidgetTester tester) async {
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
    }

    testWidgets('行内 ⇒ 行尾两空格（R8 硬换行），仍属同一段',
        (WidgetTester tester) async {
      final DocBuffer buf = await _mount(tester, '甲乙\n', 1);
      await shiftEnter(tester);
      expect(buf.buf, '甲  \n乙\n');
      expect(buf.caret, 4, reason: '光标落到新的一行行首');
    });

    testWidgets('行尾 ⇒ 等价 Enter', (WidgetTester tester) async {
      final DocBuffer a = await _mount(tester, '甲\n', 1);
      await enter(tester);
      final String byEnter = a.buf;
      final DocBuffer b = await _mount(tester, '甲\n', 1);
      await shiftEnter(tester);
      expect(b.buf, byEnter, reason: '行尾 Shift+Enter 与 Enter 写出来的必须一模一样');
    });

    testWidgets('行首 ⇒ 等价 Enter', (WidgetTester tester) async {
      final DocBuffer a = await _mount(tester, '甲乙\n', 2);
      await enter(tester);
      final String byEnter = a.buf;
      final DocBuffer b = await _mount(tester, '甲乙\n', 2);
      await shiftEnter(tester);
      expect(b.buf, byEnter, reason: '行首 Shift+Enter 与 Enter 写出来的必须一模一样');
    });
  });
}
