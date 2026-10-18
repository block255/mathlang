// 守卫：多行环境的尺寸/风格重写（PC-5 地基）
//
// 判据（用户 2026-10-18 对 PC-5 的期望）：
//   · 矩阵：行列都可改（2–6），括号风格可选 `[]` / `()`；
//   · 行列式：**强制方阵**（列数 = 行数）；
//   · 既有内容按**左上对齐**保留，新增格子留空。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/env_resize.dart';

void main() {
  group('识别', () {
    test(r'bmatrix / pmatrix / vmatrix 各认各的', () {
      expect(envStyleOf(r'\begin{bmatrix}a\end{bmatrix}'), EnvStyle.bracket);
      expect(envStyleOf(r'\begin{pmatrix}a\end{pmatrix}'), EnvStyle.paren);
      expect(envStyleOf(r'\begin{vmatrix}a\end{vmatrix}'), EnvStyle.det);
      expect(envStyleOf(r'\frac{a}{b}'), isNull);
    });
  });

  group('切格子', () {
    test(r'2x2 按 & 和 \\ 切开', () {
      expect(splitEnvCells(r'a&b\\c&d'),
          <List<String>>[<String>['a', 'b'], <String>['c', 'd']]);
    });

    test(r'花括号里的 & 不算分隔符', () {
      expect(splitEnvCells(r'{a&b}&c'), <List<String>>[<String>['{a&b}', 'c']]);
    });
  });

  group('放大：既有内容保留、新格留空', () {
    test(r'2x2 → 3x3', () {
      final String out = resizeEnvironment(
        r'\begin{bmatrix}a&b\\c&d\end{bmatrix}',
        rows: 3,
        cols: 3,
      );
      expect(out, r'\begin{bmatrix}a&b&\\c&d&\\&&\end{bmatrix}');
    });
  });

  group('缩小：按左上角切', () {
    test(r'2x2 → 1x1 只剩 a', () {
      final String out = resizeEnvironment(
        r'\begin{bmatrix}a&b\\c&d\end{bmatrix}',
        rows: 1,
        cols: 1,
      );
      expect(out, r'\begin{bmatrix}a\end{bmatrix}');
    });
  });

  group('行列式强制方阵', () {
    test(r'要 2 行 3 列 ⇒ 实际 2x2', () {
      final String out = resizeEnvironment(
        r'\begin{vmatrix}a&b\\c&d\end{vmatrix}',
        rows: 2,
        cols: 3,
      );
      expect(out, contains(r'\begin{vmatrix}'));
      expect('&'.allMatches(out).length, 2, reason: '2x2 每行一个 & ⇒ 共 2 个');
    });
  });

  group('换括号风格', () {
    test(r'bmatrix → pmatrix（内容不变）', () {
      final String out = resizeEnvironment(
        r'\begin{bmatrix}a&b\\c&d\end{bmatrix}',
        rows: 2,
        cols: 2,
        style: EnvStyle.paren,
      );
      expect(out, r'\begin{pmatrix}a&b\\c&d\end{pmatrix}');
    });
  });
}
