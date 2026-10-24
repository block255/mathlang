// ★★★ 2026-10-24（批 18）：**汉字 / 全角标点 = 断点**（平权 · 推论 ④「围栏不是对象边界」）
//
// 用户 2026-10-24 拍板的四条口径：
//   · 行内公式**顶层**打汉字 ⇒ **拆段**（`$左$` + 文字 + `$右$`），文字在围栏之外；
//   · **结构槽里**（分子 / 指数 / `\text{}` 参数）⇒ 不拆，接受数学字体；
//   · **行间块**里 ⇒ 不拆，接受数学字体；
//   · **边界格**（内容首/末）⇒ 某边为空就不补围栏，字直接落围栏外。
//
// 本文件钉三件事：
//   ① 全域：每个 tex × 每个顶层偏移打「任」，**不许造出行内 `$$`**、不许改到别的字符、
//      汉字必须落在所有 `$…$` 之外；
//   ② 自检：花括号 / `\left` / `\begin` 不配平、或右半以 `^ _ & } ]` 开头 ⇒ **不切**；
//   ③ 层级：结构槽 / 行间块 / 混合载荷 / 跨段选区 ⇒ **不切**（文档逐字节不变）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/break_split.dart';
import 'package:mathlang/lang/math_spans.dart';

const String kHan = '任';

/// 把 [tex] 包成行内段，在内容偏移 [rel] 处打「任」，返回新文档（不该拆时返回原文档）。
String typeHanAt(String doc, int caret, {int? selStart, int? selEnd}) {
  final BreakSplit? plan = planBreakSplit(
    doc: doc,
    caret: caret,
    selStart: selStart ?? caret,
    selEnd: selEnd ?? caret,
    payload: kHan,
  );
  if (plan == null) return doc;
  return doc.replaceRange(plan.from, plan.to, plan.text);
}

/// 去掉所有 `$` 之后的文本（拆段**只许增删 `$`**，不许动别的字符）
String stripDollars(String s) => s.replaceAll(r'$', '');

void main() {
  group('① 断点字符的判据', () {
    test('汉字 / 全角标点 = 断点；半角与英文不是', () {
      expect(isBreakChar('任'), isTrue);
      expect(isBreakChar('意'), isTrue);
      expect(isBreakChar('，'), isTrue);
      expect(isBreakChar('。'), isTrue);
      expect(isBreakChar('（'), isTrue);
      expect(isBreakChar('「'), isTrue);
      expect(isBreakChar('、'), isTrue);
      expect(isBreakChar('—'), isTrue);
      expect(isBreakChar('…'), isTrue);
      for (final String ch in <String>['a', 'Z', '0', ' ', '+', ',', '.', r'$', r'\']) {
        expect(isBreakChar(ch), isFalse, reason: '「$ch」不该算断点');
      }
    });

    test('混合载荷不算"全断点"（一律不切）', () {
      expect(isAllBreakChars('任意'), isTrue);
      expect(isAllBreakChars('，'), isTrue);
      expect(isAllBreakChars('abc中def'), isFalse);
      expect(isAllBreakChars('中 '), isFalse);
      expect(isAllBreakChars(''), isFalse);
    });
  });

  group('② 顶层 ⇒ 拆段', () {
    test(r'α 与 β 之间打「任」⇒ `$\alpha$任$\beta$`', () {
      const String doc = r'$\alpha\beta$';
      final int caret = doc.indexOf(r'\beta'); // = 7
      expect(caret, 7);
      expect(typeHanAt(doc, caret), r'$\alpha$任$\beta$');
    });

    test('拆完光标落在**汉字之后**（普通文本偏移，不是公式里）', () {
      const String doc = r'$\alpha\beta$';
      final BreakSplit plan = planBreakSplit(
        doc: doc,
        caret: 7,
        selStart: 7,
        selEnd: 7,
        payload: kHan,
      )!;
      expect(plan.caret, plan.from + plan.text.indexOf(kHan) + 1);
      expect(plan.text[plan.text.indexOf(kHan) + 1], r'$',
          reason: r'汉字后面紧跟右段的开 `$` ⇒ 光标就停在围栏外');
    });

    test(r'`a+b` 的任意位置都能拆，且 `$` 只增 2 个', () {
      const String doc = r'$a+b$';
      for (final int rel in <int>[1, 2]) {
        final String out = typeHanAt(doc, 1 + rel);
        expect(r'$'.allMatches(out).length, 4, reason: 'rel=$rel ⇒ $out');
        expect(out.contains(kHan), isTrue);
      }
      expect(typeHanAt(doc, 1 + 1), r'$a$任$+b$');
      expect(typeHanAt(doc, 1 + 2), r'$a+$任$b$');
    });

    test('全角标点同样拆', () {
      const String doc = r'$\alpha\beta$';
      final BreakSplit? plan = planBreakSplit(
        doc: doc,
        caret: 7,
        selStart: 7,
        selEnd: 7,
        payload: '，',
      );
      expect(plan, isNotNull);
      expect(plan!.text, r'$\alpha$，$\beta$');
    });
  });

  group(r'③ 边界格 ⇒ 不补空围栏（绝不造行内 `$$`）', () {
    test('内容首打「任」⇒ 字落在围栏外，不留空段', () {
      const String doc = r'$\alpha\beta$';
      final String out = typeHanAt(doc, 1); // 内容首（$ 之后）
      expect(out, r'任$\alpha\beta$');
      expect(inlineDoubleDollarLines(out), isEmpty);
    });

    test('内容末打「任」⇒ 字落在围栏外', () {
      const String doc = r'$\alpha\beta$';
      final String out = typeHanAt(doc, doc.length - 1);
      expect(out, r'$\alpha\beta$任');
      expect(inlineDoubleDollarLines(out), isEmpty);
    });

    test(r'整段删空后打「任」⇒ 只剩文字（不留 `$$`）', () {
      const String doc = r'$x$';
      // 选区把这个段的内容全选中（内容首..内容末）
      final String out = typeHanAt(doc, 1, selStart: 1, selEnd: 2);
      expect(out, kHan);
      expect(inlineDoubleDollarLines(out), isEmpty);
    });
  });

  group('④ 结构槽里 / 行间块里 ⇒ 不切（文档逐字节不变）', () {
    const List<String> texs = <String>[
      r'\frac{a}{b}',
      r'x^{2}',
      r'x_1',
      r'\sqrt{x}',
      r'\text{当}',
      r'\left(x\right)',
      r'\left|{x^{2}}\right|',
      r'\sum_{i=1}^{n}',
      r'\begin{aligned}a&=b\\c&=d\end{aligned}',
    ];
    for (final String tex in texs) {
      test('「$tex」里每一格打汉字都**不拆**', () {
        final String doc = '\$$tex\$';
        for (var rel = 0; rel <= tex.length; rel++) {
          final String out = typeHanAt(doc, 1 + rel);
          final int dollarGain = r'$'.allMatches(out).length - 2;
          expect(dollarGain, 0,
              reason: 'rel=$rel 处拆了段（新增 $dollarGain 个 `\$`）：$out');
        }
      });
    }

    test('行间块里打汉字 ⇒ 不拆', () {
      const String doc = '\$\$\na+b\n\$\$';
      final int caret = doc.indexOf('+') + 1;
      expect(typeHanAt(doc, caret), doc);
    });

    test('混合载荷 ⇒ 不拆', () {
      const String doc = r'$\alpha\beta$';
      final BreakSplit? plan = planBreakSplit(
        doc: doc,
        caret: 7,
        selStart: 7,
        selEnd: 7,
        payload: 'abc任',
      );
      expect(plan, isNull);
    });
  });

  group('⑤ 自检：切了会坏的位置一律不切', () {
    test(r'裸花括号组内部（`a{b+c}d` 的 2–5）⇒ 不切', () {
      const String tex = r'a{b+c}d';
      const String doc = '\$$tex\$';
      for (final int rel in <int>[2, 3, 4, 5]) {
        expect(typeHanAt(doc, 1 + rel), doc, reason: 'rel=$rel 不许切');
      }
      // 组外仍要能切
      expect(typeHanAt(doc, 1 + 1), r'$a$任${b+c}d$');
      expect(typeHanAt(doc, 1 + 6), r'$a{b+c}$任$d$');
    });

    test(r'`x^{2}` 的 `^` 之前（右半会变成裸 `^{2}`）⇒ 不切', () {
      const String doc = r'$x^{2}$';
      expect(typeHanAt(doc, 2), doc); // 内容偏移 1 = x 与 ^ 之间
    });

    test(r'`\left(x\right)` 组内部 ⇒ 不切', () {
      const String doc = r'$\left(x\right)$';
      for (final int rel in <int>[5, 6]) {
        expect(typeHanAt(doc, 1 + rel), doc, reason: 'rel=$rel');
      }
    });

    test(r'`\begin{cases}` 的 `\begin` 之前可以切（两半自洽）', () {
      const String tex = r'f(x)=\begin{cases}1&\\0&\end{cases}';
      final String doc = '\$$tex\$';
      final String out = typeHanAt(doc, 1 + 4);
      expect(r'$'.allMatches(out).length, 4, reason: '应该切成两段：$out');
      // 两半都要能解析：左边 `f(x)`、右边 `=\begin{cases}…\end{cases}`
      expect(out, r'$f(x)$任$=\begin{cases}1&\\0&\end{cases}$');
    });
  });

  group('⑥ 选区替换：同一段顶层 ⇒ 拆；跨段 ⇒ 不拆', () {
    test(r'选中 `+` 打「任」⇒ `$\alpha$任$\beta$`', () {
      const String doc = r'$\alpha+\beta$';
      final int plus = doc.indexOf('+');
      expect(typeHanAt(doc, plus, selStart: plus, selEnd: plus + 1),
          r'$\alpha$任$\beta$');
    });

    test('选区跨出本段 ⇒ 不拆', () {
      const String doc = r'$\alpha$ x $\beta$';
      final int a = doc.indexOf(r'\alpha');
      final int b = doc.indexOf(r'\beta') + 1;
      expect(typeHanAt(doc, a, selStart: a, selEnd: b), doc);
    });

    test('选区落在结构槽里 ⇒ 不拆', () {
      const String doc = r'$\frac{a}{b}$';
      final int a = doc.indexOf('a');
      expect(typeHanAt(doc, a, selStart: a, selEnd: a + 1), doc);
    });
  });

  group('⑦ 全域普查：拆完的文档必须仍"干净"', () {
    const List<String> texs = <String>[
      r'\alpha\beta',
      r'a+b-c',
      r'a{b+c}d',
      r'x^{2}',
      r'\sqrt{x}',
      r'\frac{a}{b}',
      r'\text{当}',
      r'\left(x\right)',
      r'\left|{x^{2}}\right|',
      r'\sum_{i=1}^{n}',
      r'f(x)=\begin{cases}1&\\0&\end{cases}',
      r'\begin{aligned}a&=b\\c&=d\end{aligned}',
    ];
    test(r'每个 tex × 每个偏移：不许造行内 `$$`、不许改别的字符、汉字在围栏外', () {
      var splits = 0;
      for (final String tex in texs) {
        final String doc = '\$$tex\$';
        for (var rel = 0; rel <= tex.length; rel++) {
          final String out = typeHanAt(doc, 1 + rel);
          final bool changed = out != doc;
          if (changed) splits++;
          expect(inlineDoubleDollarLines(out), isEmpty,
              reason: '「$tex」rel=$rel ⇒ 造出了行内 `\$\$`：$out');
          expect(stripDollars(out).replaceFirst(kHan, ''), stripDollars(doc),
              reason: '「$tex」rel=$rel ⇒ 拆段改动了非 `\$` 的字符：$out');
          for (final MathSpan s in scanMathSpans(out)) {
            expect(s.tex.contains(kHan), isFalse,
                reason: '「$tex」rel=$rel ⇒ 汉字被包进了数学段：$out');
          }
        }
      }
      expect(splits, greaterThan(10), reason: '普查必须真的切过若干处（否则断言空转）');
    });
  });
}
