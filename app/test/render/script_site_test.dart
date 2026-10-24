// ★★ 2026-10-24（批 16）：**脚本槽判据**（竖条变矮的依据）
//
// 为什么需要它：批 15 把竖条高度统一成"该层字形盒"之后，指数档 10.9 / 分子档 11.6
// —— 只差 0.7 px，用户"一眼看不出我在指数里"⇒ 拍板让脚本档重新变矮。
// 判据必须来自**位点表**（`snap().path.last.command ∈ {^, _}`），
// **不能**用"盒有多矮"去猜（分母也矮，会把分母误伤）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/math_nav.dart';

void main() {
  // 位点（`caret_level_bar_test` 的探针实测）：0 / 6 / 7(glue) / 9 / 10 / 11 / 13 / 14 / 15
  const String tex = r'\frac{x^{3}}{y}';

  test('★ 指数内容里的两格（9 = `3` 之前、10 = `3` 之后）都算脚本槽', () {
    expect(isScriptSite(tex, 9), isTrue);
    expect(isScriptSite(tex, 10), isTrue);
  });

  test('★ 主行 / 分子外 / 对象之后 / 分母 / 段末 都不算脚本槽', () {
    for (final int rel in <int>[0, 6, 7, 11, 13, 14, 15]) {
      expect(isScriptSite(tex, rel), isFalse, reason: 'rel=$rel 不该算脚本槽');
    }
  });

  test('★ 分母里的指数也算（层级不只看第一层）', () {
    const String t = r'\frac{a}{b^{2}}';
    // `b` 在分母；`2` 是分母里那个指数
    final Set<int> script = <int>{
      for (int rel = 0; rel <= t.length; rel++)
        if (isScriptSite(t, rel)) rel,
    };
    expect(script, isNotEmpty);
    // 分母里的 `2` 之前那一格一定在集合里（位置由位点表定，这里只钉"非空且不含 0"）
    expect(script.contains(0), isFalse, reason: '主行首格不是脚本槽');
  });

  test('★ 越界一律 false（调用方不必先夹）', () {
    expect(isScriptSite(tex, -1), isFalse);
    expect(isScriptSite(tex, tex.length + 1), isFalse);
    expect(isScriptSite('', 0), isFalse);
  });
}
