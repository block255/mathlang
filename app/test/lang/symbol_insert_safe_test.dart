// ★★ 符号插入的**参数安全**守卫（全域扫，2026-10-17 用户手验抓到的真缺陷）
//
// 用户报的现象：在公式里点面板符号之后，页面上出现
//   `Parser Error: Expected 'EOF', got '#'` ＋ `Can't use function '$' in math mode`
//   ＋ 行间公式退化成正文。追下去发现**根本不是筛选器的问题**（点「子类」只是触发了一次重建，
//   把已经被打坏的文档重画出来）——真凶在 `applySymbolInsert`：
//
//   ① **落在控制词中间**：`\f|rac` 里插 `\forall` ⇒ `\f\forallrac`（命令当场散架）；
//   ② **与字母粘连**：`\forall` + `x^2` ⇒ `\forallx^2`（TeX 只按字母读命令名 ⇒ 未知命令）；
//   ③ **紧贴"命令名 + `{`"**：`\frac|-b…` 插模板 ⇒ `\frac\frac{}{}{-b…}`（外层命令把新模板吃了）；
//      以及 `…}|{2a}`（新模板被当成下一个参数）。
//
// 修法（`lang/symbol_insert.dart` 三条）：① 词内 ⇒ 挪到控制词**之前**；
//   ② 两侧有字母 ⇒ 补空格分隔；③ 紧贴 `{` ⇒ 挪进那个参数**开头**。
//
// ★ 这条测试是**全域**的（不是抽查）：对样本文档的**每一个可达光标位** × 每种符号，
//   断言"插入后的文档里每一段数学都能被 KaTeX 解析、且没有 `$`/`#` 混进 tex"。
//   改前实测 **146/804** 个落点产出坏文档；修完 **0/159 可达落点**。

import 'package:flutter_math_fork/tex.dart' show TexParser, TexParserSettings;
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/math_spans.dart';
import 'package:mathlang/lang/symbol_insert.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/spike/s3_edit/s3_edit_page.dart' show kEditSample;

/// 这份文档还能不能用：每段数学都能解析、tex 里没有 `$`/`#` 混入
bool docIsSound(String doc) {
  for (final MathSpan s in scanMathSpans(doc)) {
    if (s.tex.contains('#') || s.tex.contains(r'$')) return false;
    if (s.tex.trim().isEmpty) continue;
    try {
      TexParser(s.tex, const TexParserSettings()).parse();
    } catch (_) {
      return false;
    }
  }
  return true;
}

/// **可点到的**光标位：数学段内只取 `caret_sites` 产出的那些（段外每个字缝都可达）
Set<int> reachableOffsets(String doc) {
  final Set<int> out = <int>{for (var i = 0; i <= doc.length; i++) i};
  for (final MathSpan s in scanMathSpans(doc)) {
    final List<CaretSite> sites = buildCaretSites(s.tex).sites;
    final Set<int> inRegion = <int>{s.start + 1, s.end - 1};
    for (final CaretSite c in sites) {
      inRegion.add(s.start + 1 + c.offset);
    }
    for (var i = s.start + 2; i < s.end - 1; i++) {
      if (!inRegion.contains(i)) out.remove(i);
    }
  }
  return out;
}

void main() {
  const List<String> texes = <String>[
    r'\forall',
    r'\frac{}{}',
    r'\hat{}',
    r'+',
    r'\beta',
  ];

  test('★ 全域：每个可达光标位 × 每种符号 ⇒ 文档仍然可解析（bad = 0）', () {
    final Set<int> reachable = reachableOffsets(kEditSample);
    expect(reachable.length, greaterThan(100), reason: '样本要有足够多的落点');

    final List<String> bad = <String>[];
    for (final int caret in reachable) {
      for (final String tex in texes) {
        final SymbolInsertResult r = applySymbolInsert(
          doc: kEditSample,
          caret: caret,
          selStart: caret,
          selEnd: caret,
          tex: tex,
          template: tex.contains('{'),
        );
        if (!docIsSound(r.doc)) bad.add('caret=$caret tex=$tex');
      }
    }
    expect(bad, isEmpty,
        reason: '这些落点插完就坏了（改前 146 个）：${bad.take(8).join(' / ')}');
  });

  group('三条修法的逐个证据', () {
    test(r'① 落在 `\frac` 中间 ⇒ 挪到控制词之前（不散架）', () {
      const String doc = r'$\frac{a}{b}$';
      final int inside = doc.indexOf('rac'); // `\f|rac`
      final SymbolInsertResult r = applySymbolInsert(
          doc: doc,
          caret: inside,
          selStart: inside,
          selEnd: inside,
          tex: r'\forall',
          template: false);
      expect(r.doc, r'$\forall\frac{a}{b}$',
          reason: '落在控制词里 ⇒ 挪到 `\frac` 前面');
      expect(docIsSound(r.doc), isTrue);
    });

    test(r'② `\forall` 后跟字母 ⇒ 补分隔空格', () {
      const String doc = r'$x^2+1$';
      final int at = doc.indexOf('x');
      final SymbolInsertResult r = applySymbolInsert(
          doc: doc,
          caret: at,
          selStart: at,
          selEnd: at,
          tex: r'\forall',
          template: false);
      expect(r.doc, r'$\forall x^2+1$', reason: r'否则 `\forallx` 是未知命令');
      expect(docIsSound(r.doc), isTrue);
    });

    test(r'③ 紧贴 `\frac` 的 `{` ⇒ 挪进参数开头（模板当分子）', () {
      const String doc = r'$\frac{a}{b}$';
      final int at = doc.indexOf('{');
      final SymbolInsertResult r = applySymbolInsert(
          doc: doc,
          caret: at,
          selStart: at,
          selEnd: at,
          tex: r'\hat{}',
          template: true);
      expect(r.doc, r'$\frac{\hat{}a}{b}$',
          reason: '挪进第一个参数里 ⇒ 外层 `\frac` 的参数不受影响；实际=${r.doc}');
      expect(docIsSound(r.doc), isTrue);
    });
  });
}
