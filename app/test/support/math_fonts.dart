// 测试用：把 flutter_math_fork 的**真实 KaTeX 字体**装进测试引擎。
//
// ★★ 为什么必须有它（2026-10-17 探针实测）：`flutter test` 默认**不加载**包里的数学字体，
//   字形落在回退度量上（每个字形一个方块、行盒 = 1em）⇒ 量到的几何是**另一个世界**：
//
//   | 量什么 | 回退字体 | 真实字体 |
//   |---|---|---|
//   | `x=\frac{-b\pm\sqrt{b^2-4ac}}{}` 的 Math 盒（字号 20） | 271.3 宽 | **184.4 宽** |
//   | `\square` 的 ¶ 盒（字号 20） | 20 × 20 | **15.6 × 31**（1.55em，AMS/回退度量） |
//   | `M` 的 ¶ 盒（字号 20） | 20 × 20 | **19.4 × 21**（1.05em，数学字体度量） |
//
//   ⇒ 凡"量几何"的守卫都要先 `await loadMathFonts()`，否则守的是假世界
//     （2026-10-17 的坑：占位框"偏大"在回退字体下根本复现不出来）。
//
// 用法：`setUpAll(() async => loadMathFonts());`
import 'package:flutter/services.dart';

/// 装载包里声明的 KaTeX 字体族（`packages/flutter_math_fork/KaTeX_*`）
Future<void> loadMathFonts() async {
  const List<String> families = <String>[
    'KaTeX_Main',
    'KaTeX_Math',
    'KaTeX_AMS',
    'KaTeX_Caligraphic',
    'KaTeX_Fraktur',
    'KaTeX_SansSerif',
    'KaTeX_Script',
    'KaTeX_Typewriter',
    'KaTeX_Size1',
    'KaTeX_Size2',
    'KaTeX_Size3',
    'KaTeX_Size4',
  ];
  const List<String> shapes = <String>[
    'Regular',
    'Italic',
    'Bold',
    'BoldItalic',
  ];

  for (final String fam in families) {
    final FontLoader loader = FontLoader('packages/flutter_math_fork/$fam');
    var any = false;
    for (final String shape in shapes) {
      final String key =
          'packages/flutter_math_fork/lib/katex_fonts/fonts/$fam-$shape.ttf';
      try {
        loader.addFont(rootBundle.load(key));
        any = true;
      } catch (_) {
        // 该字重不存在：跳过
      }
    }
    if (!any) continue;
    try {
      await loader.load();
    } catch (_) {
      // 某个字体族装不上不影响其它族
    }
  }
}
