// ★★ 2026-11-03 晚（用户："高亮和选区的判定应该统一"）：
//   **装饰（矩阵括号）按"所属环境"判** —— 环境里的可见字符全在选区内才涂；
//   不许"跟最近的有主盒走"（改前：选了 `+` 就把右边矩阵的左括号一起涂上，
//   而复制/删除只到 `+` —— 用户实测"高亮扩进去了、载荷没有"）。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/hit_map.dart';
import 'package:mathlang/render/leaf_boxes.dart';

import '../support/math_fonts.dart';

const String kTex =
    r'\begin{bmatrix}a&b\\c&d\end{bmatrix}+\begin{bmatrix}e&f\\g&h\end{bmatrix}';

Future<({RenderObject root, List<LeafBox> ink, List<Rect> bands})> _render(
    WidgetTester tester, int from, int to,{String tex = kTex}) async {
  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(MaterialApp(
    home: Center(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Math.tex(tex,
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
  final List<Rect> bands = selectionBands(
      root: root, tex: tex, from: from, to: to, displayStyle: true);
  return (root: root, ink: ink, bands: bands);
}

bool _covered(List<Rect> bands, Rect r) =>
    bands.any((Rect b) => b.inflate(1.0).contains(r.center));

void main() {
  setUpAll(() async => loadMathFonts());

  testWidgets('★ 选中"第一个矩阵 + 加号" ⇒ **不涂**第二个矩阵的括号', (WidgetTester tester) async {
    final int to = kTex.indexOf('+') + 1;
    final r = await _render(tester, 0, to);
    // 第二个矩阵的定界符（`[` 与 `]`）都不许被涂
    final List<LeafBox> rightDelims = r.ink
        .where((LeafBox b) => (b.text ?? '') == r'[' || (b.text ?? '') == r']')
        .toList();
    expect(rightDelims.length, greaterThanOrEqualTo(4), reason: '两个矩阵共 4 个方括号');
    // 前两个属于第一个矩阵（该涂），后两个属于第二个（不许涂）
    final List<LeafBox> lastTwo = rightDelims.sublist(rightDelims.length - 2);
    for (final LeafBox b in lastTwo) {
      expect(_covered(r.bands, b.rect), isFalse,
          reason: '第二个矩阵的括号「${b.text}」被涂了（高亮跨过了选区）');
    }
  });

  testWidgets('整段全选 ⇒ 两个矩阵的括号都要涂', (WidgetTester tester) async {
    final r = await _render(tester, 0, kTex.length);
    final List<LeafBox> delims = r.ink
        .where((LeafBox b) => (b.text ?? '') == r'[' || (b.text ?? '') == r']')
        .toList();
    for (final LeafBox b in delims) {
      expect(_covered(r.bands, b.rect), isTrue,
          reason: '整段选中时括号「${b.text}」应当有底色');
    }
  });
}
