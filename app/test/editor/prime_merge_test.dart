// ★ 2026-11-04 晚：**撇（导数撇）连打** —— 第二次及以后必须**并进已有上标**。
//
// 现场（用户写作业实测）：`f` 打一个撇、光标停在组后，再打一个撇 ⇒
//   `$f^{\prime}^{\prime}$` ⇒ 同一基座两个上标 ⇒ KaTeX **Double superscript**
//   ⇒ 屏上 `[公式不完整]`。三撇同理。
//
// 口径（2026-11-04 用户拍板）：
//   ① **一律并进"往左最近的那个上标"**（不限于撇）：`x^{2}` + `'` ⇒ `x^{2\prime}`；
//   ② **光标永远停在组之后**（与现状一致）⇒ 之后打 `+`/`(`/`=` 仍落主行，不当成上标内容；
//   ③ 面板 / 快捷键的撇与打字**同一条规则**。
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/tex.dart' show TexParser, TexParserSettings;
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/lang/prime_merge.dart';

TextEditingValue _v(String text) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );

bool _parses(String tex) {
  try {
    TexParser(tex, const TexParserSettings()).parse();
    return true;
  } on Object {
    return false;
  }
}

String _inner(String doc) => doc.trim().replaceAll(r'$', '');

Future<(EditViewState, DocBuffer)> _mount(WidgetTester t, String doc, int caret) async {
  final DocBuffer buf = DocBuffer(doc)..setCaret(caret);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 600,
        child: SingleChildScrollView(child: EditView(buffer: buf)),
      ),
    ),
  ));
  final EditViewState st = t.state<EditViewState>(find.byType(EditView));
  st.focusInput();
  await t.pump();
  return (st, buf);
}

void main() {
  group('primeMergeTarget（纯函数）', () {
    test(r'撇组之后 ⇒ 插到它的 `}` 之前', () {
      expect(primeMergeTarget(r'f^{\prime}', 10), (at: 9, text: r'\prime'));
    });
    test(r'撇组 + 下标之后 ⇒ 跳过下标找撇组', () {
      expect(primeMergeTarget(r'f^{\prime}_{+}', 14), (at: 9, text: r'\prime'));
    });
    test(r'普通上标之后 ⇒ 也并（口径①）', () {
      expect(primeMergeTarget(r'x^{2}', 5), (at: 4, text: r'\prime'));
    });
    test(r'只有下标 ⇒ 不并（新开 ^{\prime}）', () {
      expect(primeMergeTarget(r'f_{-}', 5), isNull);
    });
    test(r'光标在撇组内部末尾 ⇒ 就地插', () {
      expect(primeMergeTarget(r'f^{\prime}', 9), (at: 9, text: r'\prime'));
    });
    test(r'裸撇串之后 ⇒ 再接一个裸撇（老文档里那种写法）', () {
      expect(primeMergeTarget(r"f'", 2), (at: 2, text: "'"));
      expect(primeMergeTarget(r"f''", 3), (at: 3, text: "'"));
    });
    test(r'普通字符之后 ⇒ 不并', () {
      expect(primeMergeTarget(r'f', 1), isNull);
    });
    test(r'空公式 `{}` 基座 ⇒ 并进那个撇组', () {
      expect(primeMergeTarget(r'{}^{\prime}', 11), (at: 10, text: r'\prime'));
    });
  });

  group('打字：连打撇', () {
    testWidgets(r'f + 撇 ×3 ⇒ f^{\prime\prime\prime}（合法）',
        (WidgetTester tester) async {
      final (_, DocBuffer buf) = await _mount(tester, r'$f$', 2);
      for (var i = 0; i < 3; i++) {
        tester.testTextInput.updateEditingValue(_v("'"));
        await tester.pump();
      }
      expect(buf.buf.trim(), r"$f^{\prime\prime\prime}$");
      expect(_parses(_inner(buf.buf)), isTrue, reason: '三撇必须能解析');
    });

    testWidgets(r'每按一次，光标都停在**组之后**（不进上标）',
        (WidgetTester tester) async {
      final (_, DocBuffer buf) = await _mount(tester, r'$f$', 2);
      for (var i = 1; i <= 2; i++) {
        tester.testTextInput.updateEditingValue(_v("'"));
        await tester.pump();
        final String doc = buf.buf;
        expect(doc[buf.caret - 1], '}', reason: '第 $i 次撇之后光标应紧跟 `}`');
      }
      // 组之后接着打 `+` ⇒ 落到主行（不是上标里）
      tester.testTextInput.updateEditingValue(_v('+'));
      await tester.pump();
      expect(buf.buf.trim(), r'$f^{\prime\prime}+$');
    });

    testWidgets(r'下标之后再打撇 ⇒ 并进撇组（f^{\prime\prime}_{+}）',
        (WidgetTester tester) async {
      final (_, DocBuffer buf) = await _mount(tester, r'$f^{\prime}_{+}$', 15);
      tester.testTextInput.updateEditingValue(_v("'"));
      await tester.pump();
      expect(buf.buf.trim(), r"$f^{\prime\prime}_{+}$");
      expect(_parses(_inner(buf.buf)), isTrue);
    });

    testWidgets(r'已有普通上标 x^{2} + 撇 ⇒ x^{2\prime}（合法）',
        (WidgetTester tester) async {
      final (_, DocBuffer buf) = await _mount(tester, r'$x^{2}$', 6);
      tester.testTextInput.updateEditingValue(_v("'"));
      await tester.pump();
      expect(buf.buf.trim(), r"$x^{2\prime}$");
      expect(_parses(_inner(buf.buf)), isTrue);
    });

    testWidgets(r'没有基座 `$$` ⇒ 仍是 {}^{\prime}', (WidgetTester tester) async {
      final (_, DocBuffer buf) = await _mount(tester, r'$$', 1);
      tester.testTextInput.updateEditingValue(_v("'"));
      await tester.pump();
      expect(buf.buf.trim(), r"${}^{\prime}$");
    });
  });

  group('老文档里的**裸撇**（用户 2026-11-04 晚："行内还没修"）', () {
    testWidgets(r"行内 $f' 再打撇 ⇒ $f''（合法）", (WidgetTester tester) async {
      final (_, DocBuffer buf) = await _mount(tester, r"$f'$", 3);
      tester.testTextInput.updateEditingValue(_v("'"));
      await tester.pump();
      expect(buf.buf.trim(), r"$f''$");
      expect(_parses(_inner(buf.buf)), isTrue);
    });

    testWidgets(r"行间 $f^{\prime} 与裸撇混用也不炸：裸撇 + 撇 + 撇",
        (WidgetTester tester) async {
      final (_, DocBuffer buf) = await _mount(tester, r"$f'$", 3);
      for (var i = 0; i < 2; i++) {
        tester.testTextInput.updateEditingValue(_v("'"));
        await tester.pump();
      }
      expect(buf.buf.trim(), r"$f'''$");
      expect(_parses(_inner(buf.buf)), isTrue);
    });
  });
  // ★ 2026-11-04 晚（用户真实路径）：**正文里打 f，再连打撇** —— 建壳之后光标落在 `$` 之外，
  //   于是两条入口都走了"不认撇"的支路：面板那条把载荷塞进公式（双上标红字），
  //   键盘那条插成文本撇号。这里钉死"跨 `$` 也要并进那段公式的撇组"。
  group(r'跨 `$` 的撇（正文起手 / 贴公式右侧）', () {
    testWidgets(r'面板撇 ×3（正文 f 起手）⇒ f^{\prime\prime\prime} 可解析',
        (WidgetTester tester) async {
      final (EditViewState st, DocBuffer buf) = await _mount(tester, '甲f', 2);
      for (var i = 0; i < 3; i++) {
        st.insertSymbolTex("'", template: false);
        await tester.pump();
      }
      expect(buf.buf.trim(), r"甲$f^{\prime\prime\prime}$");
      expect(_parses(r'f^{\prime\prime\prime}'), isTrue);
    });

    testWidgets(r'面板撇 + 键盘撇（正文 f 起手）⇒ f^{\prime\prime} 可解析',
        (WidgetTester tester) async {
      final (EditViewState st, DocBuffer buf) = await _mount(tester, '甲f', 2);
      st.insertSymbolTex("'", template: false);
      await tester.pump();
      tester.testTextInput.updateEditingValue(_v("'"));
      await tester.pump();
      expect(buf.buf.trim(), r"甲$f^{\prime\prime}$");
      expect(_parses(r'f^{\prime\prime}'), true);
    });

    testWidgets(r'光标贴在公式右侧（`$` 之后）打撇 ⇒ 并进公式，不产生文本撇号',
        (WidgetTester tester) async {
      // 甲0 $1 f2 ^3 {4 \prime 5..10 }11 $12 乙13 ⇒ 光标 13
      final (_, DocBuffer buf) = await _mount(tester, r'甲$f^{\prime}$乙', 13);
      tester.testTextInput.updateEditingValue(_v("'"));
      await tester.pump();
      expect(buf.buf.trim(), r'甲$f^{\prime\prime}$乙');
      expect(buf.buf.contains("'"), isFalse, reason: '不许在正文里留裸撇号');
    });

    testWidgets(r'先撇再下标、光标移到**整体之后**打撇 ⇒ 落点不动（不许跳到下标前）',
        (WidgetTester tester) async {
      // 甲0 $1 f2 ^3 {4 \5..10 }11 _12 {13 +14 }15 $16 乙17 ⇒ 光标 17（$ 之后那一格）
      final (_, DocBuffer buf) = await _mount(tester, r'甲$f^{\prime}_{+}$乙', 17);
      tester.testTextInput.updateEditingValue(_v("'"));
      await tester.pump();
      expect(buf.buf.trim(), r'甲$f^{\prime\prime}_{+}$乙');
      expect(buf.caret, 23,
          reason: '落点应"跟随用户位置"（17 + 6），而不是贴到撇组后面（18）');
    });
    testWidgets(r'公式里是**裸撇**、光标贴在右侧 ⇒ 接成裸双撇（合法）',
        (WidgetTester tester) async {
      // 甲0 $1 f2 '3 $4 乙5 ⇒ 光标 5
      final (_, DocBuffer buf) = await _mount(tester, r"甲$f'$乙", 5);
      tester.testTextInput.updateEditingValue(_v("'"));
      await tester.pump();
      expect(buf.buf.trim(), r"甲$f''$乙");
      expect(_parses(r"f''"), isTrue);
    });
  });
  group('面板 / 快捷键：同一条规则', () {
    testWidgets(r'面板连点两次撇 ⇒ f^{\prime\prime}（合法）',
        (WidgetTester tester) async {
      final (EditViewState st, DocBuffer buf) = await _mount(tester, r'$f$', 2);
      st.insertSymbolTex("'", template: false);
      await tester.pump();
      st.insertSymbolTex("'", template: false);
      await tester.pump();
      expect(buf.buf.trim(), r"$f^{\prime\prime}$");
      expect(_parses(_inner(buf.buf)), isTrue);
    });
  });
}
