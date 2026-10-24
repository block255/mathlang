// ★★★ 2026-10-24（批 14）：**打字 `^` / `_`（Shift+6）不许把结构吃坏**
//
// 用户实测（`\left|{x+1+\sqrt[3]{x}}\right|`，光标在根号里 `x` 之后按 Shift+6）：
//   ⇒ 「公式不完整」。
// ★ **Shift+6 与"面板插入上标"不是一条路**：
//   · 面板 / `Ctrl+↑` ⇒ `insertScript` ⇒ `applySymbolInsert` ⇒ `planInsert`
//   · **键盘打 `^`**   ⇒ 文本输入 ⇒ `planAutoExpand` ⇒ `_planScript`（自动展开）
//   我先只修了第一条，所以用户重开之后仍然坏 —— 真凶在第二条。
//
// 根因：`_applyAutoExpand` 做的是 `buf.replaceRange(ex.from, ex.caret, '')`，
//   而 `_planScript` 原来把**用户光标位置**当区间终点。光标停在基座**右边界之后**
//   （`}` 之后那一格、`\right` 之前）时，`[基座, 光标)` 会把中间那个**不可见的 `}`**
//   一起删掉 ⇒ `\sqrt[3]{x^{}` 少一个花括号 ⇒ 解析失败。
//
// 修法：区间终点改成**基座的末尾**（`last.end`），只换掉基座本身。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/auto_expand.dart';
import 'package:mathlang/lang/symbol_insert.dart';
import 'package:mathlang/lang/word_triggers.dart';
import 'package:mathlang/render/math_nav.dart';

/// 复刻 `_applyAutoExpand` 的两步（`replaceRange(from, caret, '')` ＋ 插入）
String applyAutoExpand(String doc, AutoExpand ex) {
  final String trimmed = doc.replaceRange(ex.from, ex.caret, '');
  final SymbolInsertResult r = applySymbolInsert(
    doc: trimmed,
    caret: ex.from,
    selStart: ex.from,
    selEnd: ex.from,
    tex: ex.tex,
    template: ex.template,
  );
  return r.doc;
}

/// 花括号 / 定界符配平
bool balanced(String t) {
  var d = 0;
  for (var i = 0; i < t.length; i++) {
    if (t[i] == r'\') {
      i++;
      continue;
    }
    if (t[i] == '{') d++;
    if (t[i] == '}') d--;
    if (d < 0) return false;
  }
  return d == 0;
}

int countOf(String s, String pat) => RegExp(RegExp.escape(pat)).allMatches(s).length;

final TriggerSettings kTrig = TriggerSettings.defaults();

const List<String> kTex = <String>[
  r'\left|{x+1+\sqrt[3]{x}}\right|',
  r'\left|x+1+\sqrt[3]{x}\right|',
  r'\sqrt[3]{x}',
  r'x^{2}+1',
  r'\frac{x^{3}}{y}',
  r'\sum_{i=1}^{n}i^{2}',
  r'\begin{cases}a\\b\end{cases}',
];

void main() {
  for (final String tex in kTex) {
    for (final String mark in <String>['^', '_']) {
      test('★★ 打字 `$mark` 在**每个偏移**都不许吃坏结构：$tex', () {
        final String doc = '\$$tex\$';
        final MathRegion r = mathRegionAt(doc, 1)!;
        final List<String> bad = <String>[];
        for (var rel = 0; rel <= tex.length; rel++) {
          final int caret = r.contentStart + rel;
          final AutoExpand? ex = planAutoExpand(
            doc: doc,
            caret: caret,
            typed: mark,
            triggers: kTrig,
          );
          if (ex == null) continue;
          final String out = applyAutoExpand(doc, ex);
          final String body = out.substring(1, out.length - 1);
          // 判据：**结构完整性** —— 这才是"公式不完整"的根因
          if (!balanced(out)) {
            bad.add('rel=$rel ⇒ 花括号不配：$body');
            continue;
          }
          if (countOf(body, r'\right') != countOf(tex, r'\right')) {
            bad.add('rel=$rel ⇒ 吃掉了 `\\right`：$body');
            continue;
          }
          if (countOf(body, r'\begin{') != countOf(tex, r'\begin{')) {
            bad.add('rel=$rel ⇒ 吃掉了 `\\begin`：$body');
            continue;
          }
          if (countOf(out, r'$') != 2) bad.add('rel=$rel ⇒ 定界符变了：$body');
        }
        expect(bad, isEmpty, reason: bad.take(4).join('\n'));
      });
    }
  }
}
