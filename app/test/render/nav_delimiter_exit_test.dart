// ★★ 2026-10-24（批 3 · D2）：`→` 从**定界符组**里出来要"一下走到组外"。
//
// 用户原话：「我在打完绝对值里面最后一个字符后要点**两下**右箭头才能出去」
// （期望的"两下" = 一下出组、一下出公式；改前是"三下、且第一下屏幕上看不出动"）。
//
// 实测根因（`\frac{x^{3}}{\left|{sinx}\right|^{3}}`，19 个位点）：
//   · `x` 之后那一格 → `}` 与 `\right|` 之间那一格：**同一根像素**（`}` 不可见）⇒ 白按一下；
//   · 组后面还挂着 `^{3}`：那两格是**挂件**（乙口径：字形 + 挂件 = 一个对象）。
//
// 口径（2026-10-24）：`→` 到"`\right` 之前"就**跳过**（同一根像素）；挂着 `\right` 的脚标
// 按**挂件**跳过（`→` 一步出组）。想改脚标：点它、或从右边按 `←` 进来、或用 `Tab` 走槽。
// ★ **不许漂的**：`x^2` 的指数、`\sum_{i=1}^{n}` 的上下限仍然逐格停（2026-10-15 的"金表"）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/math_nav.dart';

void main() {
  group('D2：定界符组 + 挂件', () {
    const String tex = r'\frac{x^{3}}{\left|{sinx}\right|^{3}}';
    const String doc = '\$$tex\$';

    test('从绝对值里最后一个 x 之后：一下出组、两下出公式', () {
      // `{sinx}` 的 `}` 之前那一格 = 打完 x 的位置
      final int afterX = doc.indexOf('{sinx}') + 6;
      final int afterScript = doc.indexOf(r'\right|') + 7 + 4; // `\right|` + `^{3}`
      final int step1 = nextCaretOffset(doc, afterX);
      expect(step1, afterScript,
          reason: '一下就要跨过 `}`/`\\right|`/`^{3}` 这一串（改前停在 `\\right|` 前面，屏幕上看不出动）');
      expect(nextCaretOffset(doc, step1), doc.length,
          reason: '第二下出公式（closeEnd）');
    });

    test(r'`\left(a\right)^2` 同样：一下出组（这里出组 = 出公式，因为脚标是最后一项）', () {
      const String d = r'$\left(a\right)^2$';
      final int afterA = d.indexOf('a') + 1;
      final int step1 = nextCaretOffset(d, afterA);
      expect(step1, d.length,
          reason: '`\\right)^2` 整体算一个对象 ⇒ 一步到公式之后：$step1');
    });
  });

  group('★ 不许漂：别的脚标仍然逐格停', () {
    test(r'`x^2`：从 x 之后还要能走进指数里', () {
      const String d = r'$x^2$';
      final int afterX = d.indexOf('x') + 1;
      final int step1 = nextCaretOffset(d, afterX);
      expect(step1, lessThan(d.length - 1),
          reason: '指数不是"挂件"⇒ 必须停在里面（不然改脚标只能点）');
    });

    test(r'`\sum_{i=1}^{n}a_i`：金表里那 9 步不许变', () {
      const String d = r'$\sum_{i=1}^{n}a_i$';
      final List<int> rel = <int>[];
      var c = 1;
      for (var i = 0; i < 12; i++) {
        rel.add(c - 1);
        final int n = nextCaretOffset(d, c);
        if (n <= c || n >= d.length - 1) break;
        c = n;
      }
      expect(rel, <int>[0, 6, 7, 8, 9, 12, 13, 14, 16],
          reason: '与 `caret_sweep_test` 的金表同源（这里再钉一条）');
    });
  });
}
