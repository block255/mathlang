// 守卫测试：**包裹型分隔符不可单删**（2026-10-18 用户实测「点删除报错」）
//
// 现象：`\left(2\right)` 里点等号/括号中间按删除，第一次没反应、第二次报
//   `Parser Error: Invalid delimiter type 'EquationRowNode'`。
// 探针实测（修复前）：`rel=5` 退格删掉 `(` ⇒ `\left2\right)`；`rel=8` 删除删掉 `)` ⇒ `\left(2\right`
//   —— 两种都让 KaTeX 直接抛解析错误。
// 判据：分隔符（`\left(` / `\right)` / `\middle|`）**不可单删**；删到它就**整对一起删**
//   （与 §4.6「删除要干脆」同一口径）。内容字符照旧逐字删。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/smart_delete.dart';

String apply(String tex, SmartEdit e) {
  if (e.from == null || e.to == null) return tex;
  return tex.substring(0, e.from!) + tex.substring(e.to!);
}

void main() {
  group('删到分隔符 ⇒ 整对一起删（绝不删出半个）', () {
    for (final String tex in <String>[
      r'\left(2\right)',
      r'\left|2\right|',
      r'\left\{x\right\}',
    ]) {
      test('$tex：任何位置的删除结果都不含半个 \\left/\\right', () {
        final CaretSiteTable t = buildCaretSites(tex);
        for (int rel = 0; rel <= tex.length; rel++) {
          for (final SmartEdit e in <SmartEdit>[
            smartBackspace(t, rel),
            smartDelete(t, rel),
          ]) {
            final String out = apply(tex, e);
            final bool hasLeft = out.contains(r'\left');
            final bool hasRight = out.contains(r'\right');
            expect(hasLeft == hasRight, isTrue,
                reason: 'rel=$rel 删出半个分隔符对 ⇒ KaTeX 会报错：$out');
          }
        }
      });
    }
  });

  group('内容照旧逐字删（别改坏）', () {
    test(r'\left(2\right) 在 2 之后退格 ⇒ 只删 2，括号保留', () {
      final CaretSiteTable t = buildCaretSites(r'\left(2\right)');
      expect(apply(r'\left(2\right)', smartBackspace(t, 7)), r'\left(\right)');
    });
  });
}
