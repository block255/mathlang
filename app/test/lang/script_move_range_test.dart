// 口径 §3.4 附（2026-11-01）守卫：**搬家范围 ≠ 对象范围**。
//
// 用户实测：「`sin` 后面打 Shift+6，现在只有 `n` 变成数学斜体，看起来怪」。
// 口径：**搬家**按"视觉连续的一段"（整串 ASCII 字母数字一起搬 ⇒ `$sin^{}$`）；
//   **删除**仍按对象（公式里 `s`/`i`/`n` 三个原子）。
// ★ 汉字不参与这一串（批 18：汉字 = 断点）；单个汉字/希腊字符仍按旧口径当基座。
//
// 改前必红：第 1 条（改前只搬 `n`）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/auto_expand.dart';
import 'package:mathlang/lang/word_triggers.dart';

AutoExpand? _plan(String doc, String typed) => planAutoExpand(
      doc: doc,
      caret: doc.length,
      typed: typed,
      triggers: TriggerSettings.defaults(),
    );

void main() {
  test('① 正文 `sin` + `^` ⇒ 整串搬走（不是只搬 n）', () {
    final AutoExpand ex = _plan('sin', '^')!;
    expect(ex.from, 0, reason: '搬运起点要回到整串字母的开头（改前是 2 ⇒ 只有 n）');
    expect(ex.tex, r'sin^{}');
  });

  test('② 正文 `lnx` + `_` ⇒ 整串搬走', () {
    final AutoExpand ex = _plan('lnx', '_')!;
    expect(ex.from, 0);
    expect(ex.tex, r'lnx_{}');
  });

  test('③ 单个字母 / 数字照旧', () {
    expect(_plan('x', '^')!.tex, r'x^{}');
    expect(_plan('2', '^')!.from, 0);
    expect(_plan('x', '^')!.from, 0);
  });

  test('④ 汉字不参与这一串（批 18：汉字 = 断点）', () {
    final AutoExpand ex = _plan('中文x', '^')!;
    expect(ex.from, 2, reason: '只搬 x，不许把汉字拖进数学字体');
    expect(ex.tex, r'x^{}');
    // 单个汉字仍可按旧口径当基座
    expect(_plan('甲', '^')!.from, 0);
  });

  test('⑤ 前面不是字母数字 ⇒ 仍然不展开（字面 `^`）', () {
    expect(_plan('合E={(-1)', '^'), isNull);
    expect(_plan('a + ', '^'), isNull);
  });

  test('⑥ 已有数学段里的 `sin`：基座仍是最后一个原子（公式里本来就是数学字体）', () {
    const String doc = r'$sin$';
    final AutoExpand? ex = planAutoExpand(
      doc: doc,
      caret: 4, // tex 末尾（`sin` 之后）
      typed: '^',
      triggers: TriggerSettings.defaults(),
    );
    expect(ex, isNotNull);
    expect(ex!.tex, r'n^{}');
  });
}
