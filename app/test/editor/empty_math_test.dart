// 数语引擎 · **空公式**（§6.1.1）与「不许主动造空壳」的守卫（2026-10-18）
//
// 用户拍板的两条（平权口径，别再重开）：
//   ① **不该支持用户主动打一个空公式壳** —— 数学不是模式，对象由**内容**产生
//      （面板插符号自动建壳 / `/` 成分式 / 词触发成模板 / 粘贴走智能包裹）。
//      ⇒ `Alt+=` 与 `Ctrl+Alt+E` 两个入口**已撤掉**（登记表 45 → 45 条）。
//   ② 但空壳仍会**因为删除**出现（§4.6：删光内容不删定界符）⇒ 它必须**看得见、点得到、能删**
//      （§6.1.1）。这就是 `EmptyMathMark` 那个淡虚线小框。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/core/doc_settings.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/lang/auto_expand.dart';
import 'package:mathlang/lang/math_spans.dart';
import 'package:mathlang/lang/shortcut_registry.dart';
import 'package:mathlang/lang/symbol_insert.dart';
import 'package:mathlang/lang/word_triggers.dart';
import 'package:mathlang/render/empty_math_mark.dart';
import 'package:mathlang/render/inline_math_text.dart';

Future<DocBuffer> _pump(WidgetTester tester, String doc) async {
  final DocBuffer buf = DocBuffer(doc)..setCaret(0);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: EditView(
          buffer: buf,
          settings: DocSettings.defaults,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return buf;
}

/// 文档里有没有"内容全空白"的数学段
bool _hasEmptyMath(String doc) {
  for (final MathSpan s in scanMathSpans(doc)) {
    if (s.tex.trim().isEmpty) return true;
  }
  return false;
}

void main() {
  group('① 没有入口能造出**行内**空公式（平权）', () {
    test('登记表里没有「行内公式」；`Ctrl+Alt+E` 回来但语义是**行间段**', () {
      final Set<String> ids = <String>{
        for (final ShortcutAction a in kShortcutActions) a.id,
      };
      // ★ 行内空壳没有任何入口（用户口径：不接受"行内多项式当成一个整体"）
      expect(ids.contains('mathInline'), isFalse,
          reason: '`Alt+=` 造行内空壳 = 方程域思路，与平权冲突，已撤掉');
      // ★ 行间**段**是一个块：不写内容也成立（空态由 EmptyMathMark 画出来）
      expect(ids.contains('mathDisplay'), isTrue);
      expect(kShortcutActions.length, 48);
    });

    test('★ 符号库每一项（行内插法）都不产生空数学段（全域）', () {
      // 与真实符号库同构的一小组（覆盖符号 / 模板 / 环境 / 上下标）
      const List<String> texes = <String>[
        r'\alpha',
        r'+',
        r'\frac{}{}',
        r'\sqrt{}',
        r'\sqrt[]{}',
        r'^{}',
        r'_{}',
        r'\left|{}\right|',
        r'\begin{cases}&\\&\end{cases}',
        r'\begin{aligned}&=\\&=\end{aligned}',
        r'\sum_{}^{}',
        r'\int_{}^{}',
        r'\binom{}{}',
        r'\vec{}',
        r'\overline{}',
      ];
      for (final String tex in texes) {
        final SymbolInsertResult r = applySymbolInsert(
          doc: 'ab',
          caret: 1,
          selStart: 1,
          selEnd: 1,
          tex: tex,
          template: tex.contains('{}'),
        );
        expect(_hasEmptyMath(r.doc), isFalse, reason: '插入 $tex ⇒ ${r.doc}');
      }
    });

    test('★ 词触发的每一条默认词条都不产生空数学段', () {
      final TriggerSettings t = TriggerSettings.defaults();
      for (var i = 0; i < t.triggers.length; i++) {
        final String word = t.triggers[i].word;
        final AutoExpand? e = planAutoExpand(
          doc: word,
          caret: word.length,
          typed: ' ',
          triggers: t,
        );
        expect(e, isNotNull, reason: '`$word` 应该触发');
        final SymbolInsertResult r = applySymbolInsert(
          doc: '',
          caret: 0,
          selStart: 0,
          selEnd: 0,
          tex: e!.tex,
          template: e.template,
        );
        expect(_hasEmptyMath(r.doc), isFalse, reason: '$word ⇒ ${r.doc}');
      }
    });
  });

  group('② 空公式必须看得见（§6.1.1）', () {
    testWidgets('★ 行内空公式画成一个占位小框（不是零尺寸幽灵）',
        (WidgetTester tester) async {
      await _pump(tester, r'a$$b');
      expect(find.byType(EmptyMathMark), findsOneWidget);
      final Size size = tester.getSize(find.byType(EmptyMathMark));
      expect(size.width, greaterThan(8), reason: '必须有真实宽度（否则点不到）');
      expect(size.height, greaterThan(8));
    });

    testWidgets('★ 光标落在空公式里 ⇒ 占位框里画出竖条（showCaret）',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, r'a$$b');
      buf.setCaret(2); // 两个 `$` 之间 = 空公式的 contentStart
      await tester.pump();
      final EmptyMathMark mark =
          tester.widget<EmptyMathMark>(find.byType(EmptyMathMark));
      expect(mark.showCaret, isTrue);
    });

    testWidgets('★ 点它 ⇒ 光标落进公式里（不是"点了没反应"）',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, r'a$$b');
      buf.setCaret(0);
      await tester.pump();
      final Rect r = tester.getRect(find.byType(EmptyMathMark));
      await tester.tapAt(r.center);
      await tester.pump();
      expect(buf.caret, 2, reason: '空公式唯一的内容位点 = contentStart');
    });

    testWidgets('★ 失焦时也仍然看得见（不依赖光标）',
        (WidgetTester tester) async {
      await _pump(tester, r'a$$b');
      // 没有光标（caret 0，在文字里）⇒ 占位框照样在
      expect(find.byType(EmptyMathMark), findsOneWidget);
      final EmptyMathMark mark =
          tester.widget<EmptyMathMark>(find.byType(EmptyMathMark));
      expect(mark.showCaret, isFalse);
    });

    testWidgets('普通公式不受影响（不画占位框）', (WidgetTester tester) async {
      await _pump(tester, r'a$x$b');
      expect(find.byType(EmptyMathMark), findsNothing);
    });
  });

  group('③ 行内混排投影：空公式也算一个"段"', () {
    testWidgets('纯文字里没有占位框', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: InlineMathText(
            source: 'abc',
            baseOffset: 0,
            mathFontSize: 16,
            textStyle: const TextStyle(fontSize: 16),
          ),
        ),
      ));
      await tester.pump();
      expect(find.byType(EmptyMathMark), findsNothing);
    });
  });

  group('④ 行间公式段（空段）同样看得见、点得到', () {
    testWidgets('★ 空的围栏块画成占位框', (WidgetTester tester) async {
      await _pump(tester, '\$\$\n\n\$\$\n');
      expect(find.byType(EmptyMathMark), findsOneWidget);
      final Size size = tester.getSize(find.byType(EmptyMathMark));
      expect(size.width, greaterThan(8));
      expect(size.height, greaterThan(8));
    });

    testWidgets('★ 点空块 ⇒ 光标落进块里（不是"点了没反应"）',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, '\$\$\n\n\$\$\n');
      buf.setCaret(0);
      await tester.pump();
      final Rect r = tester.getRect(find.byType(EmptyMathMark));
      await tester.tapAt(r.center);
      await tester.pump();
      // 块的内容起点 = 第一道围栏之后那一格（`$$\n` 之后 = 3）
      expect(buf.caret, 3, reason: '空块唯一的内容位点 = renderBase');
    });
  });
}
