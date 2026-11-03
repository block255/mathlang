// 2026-11-03「表」批：**矩形复制**（`clipboardSlice` 的表分支）。
//
// 口径（`notes/handover/20261102-选择边界与剪贴板.md` §3.2 / §3.6）：
//   · 选区落在表体内、且**跨格** ⇒ 扩成整格矩形；
//   · 局部表 ⇒ 中性 `bmatrix`；整表 ⇒ 保留原类型（`vmatrix` 还是 `vmatrix`）；
//   · `cases` / `aligned` ⇒ **整行**，壳沿用原类型；
//   · 只压在一格里（不跨格）⇒ 照旧复制那一格的内容（§3.5「不扩」）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/clipboard_slice.dart';
import 'package:mathlang/lang/env_table.dart';
import 'package:mathlang/lang/math_spans.dart';

import 'table_test_pos.dart';

const String _pm = '\$\$\n\\begin{pmatrix}a&b\\\\c&d\\end{pmatrix}\n\$\$';
const String _vm = '\$\$\n'
    '\\begin{vmatrix}a&b&c\\\\d&e&f\\\\g&h&i\\end{vmatrix}'
    '\n\$\$';
const String _cases = '\$\$\n\\begin{cases}a\\\\b\\\\c\\end{cases}\n\$\$';
const String _aligned = '\$\$\n\\begin{aligned}&=1\\\\&=2\\\\&=3\\end{aligned}\n\$\$';

/// 载荷里的 `&` / `\\` 必须都在**环境里**（否则贴出去就是坏源码）。
void _expectSeparatorsInsideEnv(String payload, String label) {
  for (final MathSpan sp in scanMathSpans(payload)) {
    final String tex = sp.tex;
    final List<int> units = tex.codeUnits.toList();
    for (final EnvTable t in envTablesIn(tex)) {
      for (var i = t.beginStart; i < t.endEnd && i < units.length; i++) {
        units[i] = 0x20; // 环境整段盖掉
      }
    }
    final String rest = String.fromCharCodes(units)
        .replaceAll(r'\&', '  ') // 转义的字面量 `&` 不算分隔符
        .replaceAll(r'\\', '  '); // 行分隔符
    expect(rest.contains('&'), isFalse,
        reason: '$label：载荷里的 `&` 不在环境里 ⇒ 「$payload」');
    expect(rest.contains(r'\\'), isFalse,
        reason: '$label：载荷里的 `\\\\` 不在环境里 ⇒ 「$payload」');
  }
}

void main() {
  group('矩阵', () {
    test('只压在一格里 ⇒ 复制那一格的内容（不扩）', () {
      final int s = cellPos(_pm, 'a');
      final ClipboardSlice sl = clipboardSlice(_pm, s, s + 1);
      expect(sl.text, r'$a$', reason: sl.text);
    });

    test('一行两格 ⇒ 中性 bmatrix（源是 pmatrix 也不带）', () {
      final int s = cellPos(_pm, 'a');
      final int e = cellPos(_pm, 'b') + 1;
      final ClipboardSlice sl = clipboardSlice(_pm, s, e);
      expect(sl.text, r'$\begin{matrix}a&b\end{matrix}$', reason: sl.text);
      _expectSeparatorsInsideEnv(sl.text, '一行两格');
    });

    test('整表 ⇒ 保留原类型', () {
      final int s = cellPos(_pm, 'a');
      final int e = cellPos(_pm, 'd') + 1;
      final ClipboardSlice sl = clipboardSlice(_pm, s, e);
      expect(sl.text, r'$\begin{pmatrix}a&b\\c&d\end{pmatrix}$', reason: sl.text);
    });

    test('行列式的局部块 ⇒ bmatrix（不是方阵就不是行列式）', () {
      final int s = cellPos(_vm, 'a');
      final int e = cellPos(_vm, 'f') + 1;
      final ClipboardSlice sl = clipboardSlice(_vm, s, e);
      expect(sl.text, r'$\begin{matrix}a&b&c\\d&e&f\end{matrix}$',
          reason: sl.text);
      _expectSeparatorsInsideEnv(sl.text, '行列式局部');
    });

    test('不从第一列起 ⇒ 矩形只带那几列', () {
      const String doc = '\$\$\n\\begin{bmatrix}a&b&c\\\\d&e&f\\end{bmatrix}\n\$\$';
      final int s = cellPos(doc, 'b');
      final int e = cellPos(doc, 'c') + 1;
      final ClipboardSlice sl = clipboardSlice(doc, s, e);
      expect(sl.text, r'$\begin{matrix}b&c\end{matrix}$', reason: sl.text);
    });

    test('横跨两行 ⇒ **高亮那一带**（不碰没选中的 `a`、`f`）', () {
      // ★ 2026-11-03 用户更正：拖选是线性的 ⇒ 高亮 = b,c + d,e；外接矩形会多拿 a、f。
      const String doc = '\$\$\n\\begin{bmatrix}a&b&c\\\\d&e&f\\end{bmatrix}\n\$\$';
      final int s = cellPos(doc, 'b');
      final int e = cellPos(doc, 'e') + 1;
      final ClipboardSlice sl = clipboardSlice(doc, s, e);
      expect(sl.text, r'$\begin{matrix}b&c\\d&e\end{matrix}$',
          reason: sl.text);
    });
  });

  group('行单位', () {
    test('cases 选两行 ⇒ 整行、壳沿用 cases', () {
      final int s = cellPos(_cases, 'a');
      final int e = cellPos(_cases, 'b') + 1;
      final ClipboardSlice sl = clipboardSlice(_cases, s, e);
      expect(sl.text, r'$\begin{cases}a\\b\end{cases}$', reason: sl.text);
      _expectSeparatorsInsideEnv(sl.text, 'cases 两行');
    });

    test('aligned 选两行 ⇒ `&` 原样留在整行里', () {
      final int s = _aligned.indexOf('=1');
      final int e = _aligned.indexOf('=2') + 2;
      final ClipboardSlice sl = clipboardSlice(_aligned, s, e);
      expect(sl.text, r'$\begin{aligned}&=1\\&=2\end{aligned}$', reason: sl.text);
      _expectSeparatorsInsideEnv(sl.text, 'aligned 两行');
    });
  });

  group('★ 全域：载荷里的分隔符永远在环境里', () {
    test('4 份语料 × 每一个 (i, j)', () {
      for (final String doc in <String>[_pm, _vm, _cases, _aligned]) {
        for (var i = 0; i <= doc.length; i++) {
          for (var j = i; j <= doc.length; j++) {
            final ClipboardSlice sl = clipboardSlice(doc, i, j);
            _expectSeparatorsInsideEnv(sl.text, '($i,$j)');
          }
        }
      }
    });
  });
}
