// ★★ 2026-10-23（批 2 · C/E1）：`cases`（分段函数）/ `aligned`（对齐推导）的**行数**重写。
//
// 用户原话：「目前分段只能分两段」——模板写死 `\begin{cases}&\\&\end{cases}` 两行，
// 而右键改尺寸只服务矩阵/行列式（`envStyleOf` 认不出 cases）⇒ 右键没反应。
//
// 口径：这两类环境**只有行数一个自由度**（列固定两列），所以
//   · `envStyleOf` 要认出它们；
//   · `resizeEnvironment` 保留既有格子、只改行数；
//   · 面板只给一栏（标签「段数」/「行数」），预览不接 `× 数字`。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/env_resize.dart';

const String _cases = r'\begin{cases}1,&x\in Q\\0,&x\notin Q\end{cases}';
const String _aligned = r'\begin{aligned}f(x)&=a\\&=b\end{aligned}';

void main() {
  group('认环境', () {
    test('cases / aligned 都认得出来', () {
      expect(envStyleOf(_cases), EnvStyle.cases);
      expect(envStyleOf(_aligned), EnvStyle.aligned);
    });

    test('它们都是"只有一栏"的环境', () {
      expect(envRowsOnly(EnvStyle.cases), isTrue);
      expect(envRowsOnly(EnvStyle.aligned), isTrue);
      expect(envRowsOnly(EnvStyle.det), isTrue);
      expect(envRowsOnly(EnvStyle.bracket), isFalse);
      expect(envRowsOnly(EnvStyle.paren), isFalse);
    });
  });

  group('重写行数', () {
    test('★ 两段 ⇒ 三段：既有内容一格不动，新行留空', () {
      final String out =
          resizeEnvironment(_cases, rows: 3, cols: 2, style: EnvStyle.cases);
      expect(out, r'\begin{cases}1,&x\in Q\\0,&x\notin Q\\&\end{cases}',
          reason: out);
      expect(splitEnvCells(out).length, 3);
    });

    test('缩到一段：只保留第一行（被切掉的内容由调用方进撤销）', () {
      final String out =
          resizeEnvironment(_cases, rows: 1, cols: 2, style: EnvStyle.cases);
      expect(out, r'\begin{cases}1,&x\in Q\end{cases}', reason: out);
    });

    test('aligned 同样只改行数', () {
      final String out =
          resizeEnvironment(_aligned, rows: 3, cols: 2, style: EnvStyle.aligned);
      expect(splitEnvCells(out).length, 3, reason: out);
      expect(out.startsWith(r'\begin{aligned}'), isTrue);
    });

    test('列数沿用调用方给的当前值（分段函数是两列：值 | 条件）', () {
      final String out =
          resizeEnvironment(_cases, rows: 2, cols: 2, style: EnvStyle.cases);
      expect(splitEnvCells(out).first.length, 2);
    });

    test(r'夹在整段 tex 里（$…$ 内部）也能就地重写，别把外面的东西吃掉', () {
      const String tex = r'\frac{1}{2}+\begin{cases}&\\&\end{cases}';
      final String out =
          resizeEnvironment(tex, rows: 3, cols: 2, style: EnvStyle.cases);
      expect(out.startsWith(r'\frac{1}{2}+'), isTrue, reason: out);
      expect(splitEnvCells(out.substring(out.indexOf(r'\begin{cases}'))).length, 3);
    });

    test(r'★ 矩阵嵌在公式里（A=\begin{bmatrix}…）改尺寸 ⇒ 前缀不许丢', () {
      const String tex = r'A=\begin{bmatrix}1&2\\3&4\end{bmatrix}';
      final String out =
          resizeEnvironment(tex, rows: 3, cols: 3, style: EnvStyle.bracket);
      expect(out.startsWith('A='), isTrue,
          reason: '老实现从头重写整段 tex，会把 `A=` 抹掉：$out');
      expect(out.endsWith(r'\end{bmatrix}'), isTrue, reason: out);
      expect(splitEnvCells(out.substring(out.indexOf(r'\begin{bmatrix}'))).length,
          3);
    });
  });
}
