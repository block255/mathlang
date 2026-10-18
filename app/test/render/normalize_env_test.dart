// 守卫测试：**多行环境的空格子不许被 normalize 当"全空结构"回收**（2026-10-18 用户实测）。
//
// 现象：插入「对齐推导 / 分段」后还没填，切窗口（失焦 = 提交点）⇒ 整段变空壳。
// 根因：`normalize` 的"① 全空结构 ⇒ 整段删"把 `\begin{aligned}&=\\&=\end{aligned}` 也算了进去
//   （探针：修复前 `normalizeTex(...)` 返回 `""`）。
// 判据：环境的骨架是模板本身，不是用户留下的空结构 ⇒ **永不回收**；
//   而真正的空结构（`\frac{}{}`、`^{}`）照旧回收。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/normalize.dart';

void main() {
  group('多行环境不回收', () {
    for (final String tex in <String>[
      r'\begin{aligned}&=\\&=\end{aligned}',
      r'\begin{cases}&\\&\end{cases}',
      r'\begin{aligned}a&=b\\&=\end{aligned}',
    ]) {
      test('$tex 失焦后保持原样', () {
        for (final int caret in <int>[0, 12, 16, 18, 22]) {
          final NormalizeResult r = normalizeTex(tex, caret);
          expect(r.tex, tex, reason: '插入的模板骨架不能被提交点吞掉（caret=$caret）');
          expect(r.changed, isFalse);
        }
      });
    }
  });

  group('真正的空结构照旧回收（别改坏）', () {
    test(r'\frac{}{} ⇒ 删空', () {
      expect(normalizeTex(r'\frac{}{}', 0).tex, '');
    });
    test(r'a+\sqrt{} ⇒ 只剩 a+', () {
      expect(normalizeTex(r'a+\sqrt{}', 4).tex, r'a+');
    });
  });
}
