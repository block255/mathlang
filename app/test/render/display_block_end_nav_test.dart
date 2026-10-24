// ★★ 2026-10-24（批 9 · H6）：「∑ 的正右边」停不住 —— 行间块的 tex 末位必须停
//
// 用户实测（四张图 + 删除实验）：
//   `\sum_{i=1}^{n}` 打完上限 `n` 按 `→` ⇒ 光标没停在 ∑ 正右边，直接出公式落到"块之后"那一格
//   （竖条贴块底 ⇒ 看着掉到 ∑ 下面），在那里按删除**整块行间公式就没了**。
// 根因：**「tex 末位不停」这条规则对行间块也生效**。它本来是给行内公式定的：
//   `$` 不可见 ⇒ 末位与"公式之后"同一根像素 ⇒ 跳过（这个口径不动）。
//   但行间块的末位是**看得见的**（∑ 的右侧）⇒ 必须停，再按一下才出块。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/math_nav.dart';

void main() {
  const String tex = r'\sum_{i=1}^{n}';

  test('★★ 行间块：从上限 `n` 之后 ⇒ 停在 **tex 末位**（∑ 的正右边）', () {
    final String doc = '\$\$\n$tex\n\$\$';
    final MathRegion r = mathRegionAt(doc, 3)!;
    expect(r.isDisplay, isTrue);
    expect(r.tex, tex);
    final int afterN = r.abs(tex.length - 1); // `n` 之后那一格
    final int next = nextCaretOffset(doc, afterN);
    expect(next, r.abs(tex.length),
        reason: '改前直接出公式（落到块之后 = 竖条贴块底）');
  });

  test('★★ 行间块：停在 tex 末位之后再按一下 ⇒ 才出块', () {
    final String doc = '\$\$\n$tex\n\$\$';
    final MathRegion r = mathRegionAt(doc, 3)!;
    expect(nextCaretOffset(doc, r.abs(tex.length)), r.closeEnd);
  });

  test(r'★ 行内公式**照旧**跳（`$` 不可见，末位与"公式之后"同一根像素）', () {
    final String doc = '\$$tex\$';
    final MathRegion r = mathRegionAt(doc, 1)!;
    expect(r.isDisplay, isFalse);
    expect(nextCaretOffset(doc, r.abs(tex.length - 1)), r.closeEnd,
        reason: '行内这一条是 2026-10-15 拍板的口径，不许被这一轮带偏');
  });

  test('★ 行间块 `\\sum…i^2`：末位照旧停（不许被"末位跳过"吃掉）', () {
    const String t2 = r'\sum_{i=1}^{n}i^2';
    final String doc = '\$\$\n$t2\n\$\$';
    final MathRegion r = mathRegionAt(doc, 3)!;
    expect(nextCaretOffset(doc, r.abs(t2.length - 1)), r.abs(t2.length));
  });
}
