// ★★ 2026-10-24（批 3 · 乙口径）：`cases` 模板改成**单列**（逗号分隔，不再用第二个格子对齐条件）。
//
// 用户原话：「正常人写分段都是逗号分割，根本就没人会去用第二个位点来对齐条件」
//   ⇒ 每段只有**一个**格子位点（改前两列 ⇒ 每段两个位点，点起来容易错位）。
//
// 判据：
//   · 库里的 `cases.tex` **不含 `&`**，两行、每行一格；
//   · 插进去还是行间块、光标落在第一段第一格；
//   · 「段数」面板照旧（只改行数）；
//   · `aligned` 不受影响（它就是要靠 `&=` 对齐）。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/env_resize.dart';
import 'package:mathlang/lang/symbol_insert.dart';
import 'package:mathlang/lang/symbol_library.dart';

SymbolLibrary _lib() =>
    SymbolLibrary.fromJson(File('assets/symbols.json').readAsStringSync());

void main() {
  test('★ 分段模板是单列（没有 `&`）、两段', () {
    final SymbolItem cases = _lib().byId('cases')!;
    expect(cases.tex.contains('&'), isFalse,
        reason: '乙口径：逗号分隔，不要第二个格子：${cases.tex}');
    final List<List<String>> rows = splitEnvCells(
      cases.tex.replaceAll(r'\begin{cases}', '').replaceAll(r'\end{cases}', ''),
    );
    expect(rows.length, 2, reason: '模板两段：${cases.tex}');
    for (final List<String> r in rows) {
      expect(r.length, 1, reason: '每段只有一个格子：$r');
    }
  });

  test('★ 插进去仍是行间块，光标落在第一段第一格', () {
    final SymbolItem cases = _lib().byId('cases')!;
    final SymbolInsertResult r = applySymbolInsert(
      doc: '甲乙',
      caret: 1,
      selStart: 1,
      selEnd: 1,
      tex: cases.tex,
      template: cases.isTemplate,
      display: cases.isDisplay,
    );
    expect(r.doc.contains('\$\$\n'), isTrue, reason: r.doc);
    // 光标在 `$$\n` 之后、`\begin{cases}` 之后
    expect(r.caret, r.doc.indexOf(r'\begin{cases}') + r'\begin{cases}'.length,
        reason: r.doc);
  });

  test('★ 段数面板照旧：3 段 ⇒ 3 行、每行一格', () {
    final SymbolItem cases = _lib().byId('cases')!;
    final String out =
        resizeEnvironment(cases.tex, rows: 3, cols: 1, style: EnvStyle.cases);
    final List<List<String>> rows = splitEnvCells(
      out.replaceAll(r'\begin{cases}', '').replaceAll(r'\end{cases}', ''),
    );
    expect(rows.length, 3, reason: out);
    for (final List<String> r in rows) {
      expect(r.length, 1, reason: out);
    }
  });

  test(r'`aligned` 不受影响（照样靠 `&=` 对齐）', () {
    final SymbolItem a = _lib().byId('aligned')!;
    expect(a.tex.contains('&='), isTrue, reason: a.tex);
  });
}
