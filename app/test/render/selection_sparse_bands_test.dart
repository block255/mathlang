// ★ 2026-11-03 深夜（用户 ③）：**稀疏矩阵 + 加号**：只选 `+` 时，两边矩阵的括号碎片
// （`⎡ ⎢ ⎣` / `⎤ ⎥ ⎦`）一个都不许被涂。
//
// 现场：稀疏 4×6 矩阵里，`+` 的**配对组**把它的右括号碎片（U+23A4/U+23A5/U+23A6）吃了进去
// （实测组盒区间 `[25,33)`）⇒ 如果按"组内盒全涂"，这半边括号就会跟着蓝。
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/env_cells.dart';
import 'package:mathlang/render/hit_map.dart';
import 'package:mathlang/render/leaf_boxes.dart';

import '../support/math_fonts.dart';

const String kSparse =
    r'\begin{bmatrix}a&b&&&&\\c&d&&&&\\&&&&&\\&&3&&&\end{bmatrix}'
    r'+\begin{bmatrix}a&b\\c&d\\5&4\end{bmatrix}';

void main() {
  setUpAll(() async => loadMathFonts());

  testWidgets('★ 稀疏矩阵 + `+`：只选 `+` ⇒ 所有括号碎片都不被涂',
      (WidgetTester tester) async {
    final GlobalKey key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Math.tex(kSparse,
              key: key,
              mathStyle: MathStyle.display,
              textStyle: const TextStyle(fontSize: 20)),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final RenderObject root = tester.renderObject(find.byKey(key));
    final List<LeafBox> ink = scanLeafBoxes(root)
        .eligible
        .where((LeafBox b) =>
            b.kind != LeafBoxKind.pad && (b.text ?? '').trim().isNotEmpty)
        .toList();
    final int plus = kSparse.indexOf('+');
    final List<Rect> bands = selectionBands(
        root: root, tex: kSparse, from: plus, to: plus + 1, displayStyle: true);
    expect(bands, isNotEmpty, reason: '`+` 自己必须被涂');
    final List<LeafBox> delims = ink
        .where((LeafBox b) =>
            isLeftDelimiterText((b.text ?? '').trim()) ||
            isRightDelimiterText((b.text ?? '').trim()))
        .toList();
    expect(delims.length, greaterThanOrEqualTo(4),
        reason: '这个式子里应当有一堆括号/竖线，否则断言没意义');
    final List<String> painted = <String>[];
    for (final LeafBox b in delims) {
      if (bands.any((Rect r) => r.inflate(1.0).contains(b.rect.center))) {
        painted.add((b.text ?? '').trim());
      }
    }
    expect(painted, isEmpty,
        reason: '只选了 `+`，这些定界符却被涂了：${painted.join(' ')}');
  });
}
