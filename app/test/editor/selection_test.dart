// ⑤ 选择与剪贴板：高亮 + 拖选 + 连击 + 剪贴板（2026-10-17）
//
// 口径（用户拍板）：
//   · **行内公式按普通文本处理**（拖选是字符级的，高亮按**原子**铺，不套整段框）；
//   · **行间公式块 = 一个整体对象**（选中就铺整块）；
//   · 双击 = 同层对象（文本里连续字母数字 / 数学里一个可见原子）；三击 = 整个单元；
//   · 剪贴板 = **源切片**（同权红利），粘贴走同一条提交链。

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/math_caret.dart';

import '../support/math_fonts.dart';

Future<DocBuffer> _pump(WidgetTester tester, String doc,
    {int a = 0, int b = 0}) async {
  final DocBuffer buf = DocBuffer(doc)
    ..setCaret(a)
    ..setSelection(a, b);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 600,
        child: SingleChildScrollView(child: EditView(buffer: buf)),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return buf;
}

/// 当前所有带底色的 `TextSpan` 文本（= 文本侧高亮）
List<String> _highlightedTexts(WidgetTester tester) {
  final List<String> out = <String>[];
  void walk(InlineSpan s) {
    if (s is TextSpan) {
      if (s.style?.backgroundColor != null && (s.text ?? '').isNotEmpty) {
        out.add(s.text!);
      }
      for (final InlineSpan c in s.children ?? const <InlineSpan>[]) {
        walk(c);
      }
    }
  }

  for (final Text t in tester.widgetList<Text>(find.byType(Text))) {
    walk(t.textSpan ?? const TextSpan());
  }
  for (final RichText t in tester.widgetList<RichText>(find.byType(RichText))) {
    walk(t.text);
  }
  return out;
}

/// 当前 `MathWithCaret` 画笔画出的选区底块
List<Rect> _bands(WidgetTester tester) {
  final List<Rect> out = <Rect>[];
  for (final RenderObject ro in tester.allRenderObjects) {
    if (ro is RenderCustomPaint &&
        ro.foregroundPainter is MathCaretPainter) {
      out.addAll((ro.foregroundPainter! as MathCaretPainter).bands);
    }
  }
  return out;
}

void main() {
  setUpAll(() async => loadMathFonts());

  testWidgets('★ 文本：选中两个汉字 ⇒ 有一个带底色的 span（内容正好是那两个）',
      (WidgetTester tester) async {
    await _pump(tester, '甲乙丙', a: 0, b: 2);
    expect(_highlightedTexts(tester), contains('甲乙'),
        reason: '文本高亮应当按选区切成带底色的 span');
  });

  testWidgets('★ 无选区 ⇒ 一个底色 span 都没有', (WidgetTester tester) async {
    await _pump(tester, '甲乙丙');
    expect(_highlightedTexts(tester), isEmpty);
  });

  testWidgets('★★ 行内公式：**部分选中**也只铺被选中的原子（丝滑、不套整段框）',
      (WidgetTester tester) async {
    // `$x+y$` 里选中 `x`（源码偏移 1..3 = `$x`）⇒ 只应有一个原子底块
    final DocBuffer buf = await _pump(tester, r'甲$x+y$', a: 2, b: 3);
    expect(buf.hasSelection, isTrue);
    final List<Rect> bands = _bands(tester);
    expect(bands, isNotEmpty, reason: '行内公式被选中时要有原子底块');
    // 只选一个原子 ⇒ 单块宽度明显小于整段公式（注意：测量树里也有一个 painter，
    // 所以这里看**单块最大值**，不看总和）
    final double w = bands.map((Rect r) => r.width).reduce((a, b) => a > b ? a : b);
    expect(w, lessThan(20), reason: '只选一个字符不该把整段公式铺满（实测单块 $w）');
  });

  testWidgets('★★ 行间公式块：选中 ⇒ 铺整块（按"整体对象"口径）', (WidgetTester tester) async {
    const String doc = '\$\$\nx+y\n\$\$';
    await _pump(tester, doc, a: 0, b: doc.length);
    final List<Rect> bands = _bands(tester);
    expect(bands, isNotEmpty, reason: '行间块被选中要有底块');
    expect(bands.length, greaterThanOrEqualTo(2), reason: '整块 = 所有原子的底块');
  });

  testWidgets('★★ 版面中性：有没有选区，文档高度完全一样', (WidgetTester tester) async {
    final DocBuffer b1 = await _pump(tester, r'甲$x+y$乙');
    final double h1 = tester.getSize(find.byType(EditView)).height;
    final DocBuffer b2 = await _pump(tester, r'甲$x+y$乙', a: 1, b: 3);
    final double h2 = tester.getSize(find.byType(EditView)).height;
    expect(h2, h1, reason: '高亮是纯绘制，绝不许改变版面（否则分页会抖）');
    expect(b1.hasSelection, isFalse);
    expect(b2.hasSelection, isTrue);
  });

  testWidgets('★ 有选区时不画光标（标准编辑器行为）', (WidgetTester tester) async {
    await _pump(tester, '甲乙丙', a: 0, b: 2);
    final Iterable<Rect?> carets = tester
        .allRenderObjects
        .whereType<RenderCustomPaint>()
        .where((RenderCustomPaint p) => p.foregroundPainter is MathCaretPainter)
        .map((RenderCustomPaint p) => (p.foregroundPainter! as MathCaretPainter).rect);
    // 文本段本来就没有 MathCaretPainter；这里守"数学段里也不画"
    expect(carets.where((Rect? r) => r != null).length, 0);
  });

  testWidgets('★★ 拖选：按下→移动→松开 ⇒ 真的生成选区', (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, '甲乙丙丁戊');
    final Rect t0 = tester.getRect(find.textContaining('甲').first);
    final Offset start = t0.centerLeft + const Offset(2, 0);
    final TestGesture g = await tester.startGesture(start);
    await g.moveBy(const Offset(40, 0));
    await tester.pump();
    await g.moveBy(const Offset(30, 0));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(buf.hasSelection, isTrue, reason: '拖过 3px 以上必须生成选区');
    expect(buf.selectionEnd - buf.selectionStart, greaterThan(0));
  });

  testWidgets('★★ 收起选区后**所有行**的高亮都要消失（用户实测：只有最后一排取消）',
      (WidgetTester tester) async {
    // 四行文档全选 ⇒ 每行都该有底色
    const String doc = '第一行\n第二行\n第三行\n第四行';
    final DocBuffer buf = await _pump(tester, doc, a: 0, b: doc.length);
    expect(_highlightedTexts(tester), isNotEmpty, reason: '全选后应当有高亮');
    // 模拟"点了别处" ⇒ 选区收起
    buf.setCaret(2);
    await tester.pumpAndSettle();
    expect(buf.hasSelection, isFalse);
    expect(_highlightedTexts(tester), isEmpty,
        reason: '收起选区后**一个底色 span 都不该留** —— 改前池键不含选区，'
            '不含光标的行会拿回旧 widget，高亮留在屏幕上');
  });

  testWidgets('★★ 有选区时打字 = 一步撤销', (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, '甲乙丙丁', a: 1, b: 3);
    await tester.tap(find.textContaining('甲').first);
    await tester.pumpAndSettle();
    buf.setSelection(1, 3);
    await tester.pumpAndSettle();
    _commitFor(tester, 'X');
    await tester.pumpAndSettle();
    expect(buf.buf, '甲X丁', reason: '选区 [1,3) 被替换：${buf.buf}');
    expect(buf.undo(), isTrue);
    expect(buf.buf, '甲乙丙丁', reason: '一次 Ctrl+Z 就该完全回到原样');
  });

  testWidgets('★★ 剪切 = 一步撤销', (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, '甲乙丙丁', a: 1, b: 3);
    await tester.tap(find.textContaining('甲').first);
    await tester.pumpAndSettle();
    buf.setSelection(1, 3);
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(buf.buf, '甲丁', reason: '剪切删掉选区：${buf.buf}');
    expect(buf.undo(), isTrue);
    expect(buf.buf, '甲乙丙丁', reason: '一次撤销就该回来');
  });
  testWidgets('★★ 单行内拖到**行尾之外** ⇒ 整行都选中（用户实测：会少最后一个字）',
      (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, '甲乙丙丁戊己');
    final Rect r = tester.getRect(find.textContaining('甲乙丙丁戊己').first);
    final TestGesture g = await tester.startGesture(r.centerLeft + const Offset(3, 0));
    await g.moveBy(const Offset(4, 0));
    await tester.pump();
    // 拖到**文字右侧很远**（已经出了这个单元的盒子）
    await g.moveTo(r.centerRight + const Offset(40, 0));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(buf.hasSelection, isTrue);
    expect(buf.selectionEnd, buf.length,
        reason: '拖出行尾也要落到**行末**（改前会停在最后一个字之前）');
  });
  testWidgets('★★ 光标已经在这一行里（段落有零宽光标条）时，拖到行尾也要含最后一个字',
      (WidgetTester tester) async {
    // ★ 之前所有用例的光标都在别处 ⇒ 这一段没有光标条 ⇒ 复现不出来。
    //   真实场景里用户刚点过这一行，光标条就在行内（零宽，但占一个段落格子）。
    final DocBuffer buf = await _pump(tester, '甲乙丙丁戊己庚');
    buf.setCaret(6); // 光标停在行内靠后（让段落里出现光标条）
    await tester.pumpAndSettle();
    // ★ 光标条会把段落文本切开（占位符 U+FFFC）⇒ 用**前缀**找这个 Text，别用整串
    final Rect r = tester.getRect(find.textContaining('甲乙丙').first);
    final TestGesture g = await tester.startGesture(r.centerLeft + const Offset(2, 0));
    await g.moveBy(const Offset(4, 0));
    await tester.pump();
    await g.moveTo(r.centerRight + const Offset(80, 0));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(buf.hasSelection, isTrue);
    expect(buf.selectionEnd, buf.length,
        reason: '行尾最后一个字必须含在选区内（改前会差 1：光标条那一格没被扣掉）');
  });
  testWidgets('★ 退格：有选区 ⇒ 只删那一段', (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, '甲乙丙丁', a: 1, b: 3);
    await tester.tap(find.textContaining('甲').first); // 取焦点
    await tester.pumpAndSettle();
    buf.setSelection(1, 3);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(buf.buf, '甲丁', reason: '选区 [1,3) 应当被整体删掉：${buf.buf}');
  });

  testWidgets('★ Ctrl+A 全选；接着打字 ⇒ 整段被替换', (WidgetTester tester) async {
    final DocBuffer buf = await _pump(tester, '甲乙丙');
    await tester.tap(find.textContaining('甲').first);
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(buf.hasSelection, isTrue, reason: 'Ctrl+A 要全选');
    expect(buf.selectionStart, 0);
    expect(buf.selectionEnd, buf.length);
    _commitFor(tester, 'X');
    await tester.pumpAndSettle();
    expect(buf.buf, 'X', reason: '有选区时打字 = 替换选区');
  });
}

/// 走真实的提交链（与平台通道同一条路）
void _commitFor(WidgetTester tester, String text) {
  tester.testTextInput.enterText(text);
}
