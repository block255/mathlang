// 2026-11-13 反馈 ②：**行间段的复制载荷**。
//
// 定稿（本批）：单块 = **单行片段** `$…$`（块格式换行压成空格；aligned/matrix 行内可渲染）；
// 跨 2+ 个块 = 完整段出 `$$…$$`、首尾片段出 `$…$`。
//
// 改前红：
//   · 单个分行格式的块 ⇒ 载荷 `$⏎tex⏎$`（黏出来的 `$` 独占一行，粘到哪儿都爆源码）；
//   · 跨块 ⇒ 同上，一串 `$` 行；
//   · 单行围栏写法本来就好（`$…$`）——这条要保住，不许改坏。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/clipboard_slice.dart';
import 'package:mathlang/lang/math_spans.dart';

import '../support/tex_oracle.dart';

String _join(List<String> lines) => lines.join('\n');

void main() {
  group('单个行间块 ⇒ 单行片段', () {
    test('分行格式（围栏各占一行；选区含首尾换行）', () {
      final String doc = _join(<String>[r'$$', 'f(x)=x', r'$$', '']);
      final int s = doc.indexOf(r'$$') + 2; // 内容起点（换行之前）
      final int e = doc.lastIndexOf(r'$$'); // 内容终点（换行之后）
      expect(doc.substring(s, e).contains('\n'), isTrue, reason: '这个选区确实带换行');
      final ClipboardSlice sl = clipboardSlice(doc, s, e);
      expect(sl.text, r'$f(x)=x$');
      expect(sl.text.contains('\n'), isFalse, reason: '载荷里不许有换行');
    });

    test('aligned（多行结构）压成单行', () {
      final String doc = _join(<String>[
        r'$$',
        r'\begin{aligned}a&=b\\c&=d\end{aligned}',
        r'$$',
        '',
      ]);
      final int s = doc.indexOf(r'$$') + 2;
      final int e = doc.lastIndexOf(r'$$');
      final ClipboardSlice sl = clipboardSlice(doc, s, e);
      expect(sl.text, r'$\begin{aligned}a&=b\\c&=d\end{aligned}$');
      expect(sl.text.contains('\n'), isFalse);
      expect(texProblem(sl.text.substring(1, sl.text.length - 1)), isNull,
          reason: r'`\\` 是环境自己的行分隔，压掉格式换行不影响它');
    });

    test('单行围栏写法保住（改前就好，不许改坏）', () {
      final String doc = _join(<String>[r'$$f(x)=x$$', '']);
      final int s = doc.indexOf('f(x)');
      final ClipboardSlice sl = clipboardSlice(doc, s, s + 'f(x)=x'.length);
      expect(sl.text, r'$f(x)=x$');
    });
  });

  group('跨块 ⇒ 完整段是块、片段是片段', () {
    final String doc = _join(<String>[
      r'$$',
      'A=1',
      r'$$',
      r'$$',
      'B=2',
      r'$$',
      '',
    ]);
    final int s = doc.indexOf('A=1');
    final int e = doc.indexOf('B=2') + 'B=2'.length;

    test(r'整两段 ⇒ 两块、无孤立 `$` 行', () {
      final ClipboardSlice sl = clipboardSlice(doc, s, e);
      final List<MathSpan> spans = scanMathSpans(sl.text);
      expect(spans.where((MathSpan x) => x.display).length, 2,
          reason: '载荷里应当是两个完整的行间段：<${sl.text}>');
      for (final String line in sl.text.split('\n')) {
        expect(line.trim() == r'$', isFalse,
            reason: '出现了孤立的 `\$` 行：<${sl.text}>');
      }
    });

    test('只覆盖首段一部分 ⇒ 那一段是片段', () {
      final ClipboardSlice sl = clipboardSlice(doc, s, doc.indexOf('B=2') + 1);
      final List<MathSpan> spans = scanMathSpans(sl.text);
      expect(spans.where((MathSpan x) => !x.display).length, greaterThanOrEqualTo(1),
          reason: '首段只选了一半 ⇒ 应当是行内片段：<${sl.text}>');
      expect(sl.text.contains('B'), isTrue);
    });
  });
}
