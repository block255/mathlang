// ★★★ 2026-10-20（T-A 实测 F8，用户拍板"乙"）：**光标还落在里面的空结构不许回收**。
//
// 实测现场（用状态栏实时字符数量的）：
//   · 空文档点面板「分式」⇒ `$\frac{}{}$`（**11 字符**，光标在第一个空槽里，7 = tex 内 6）；
//   · 点一下搜索框（编辑器失焦 = normalize 的提交点）⇒ 只剩 `$$`（**2 字符**）。
//   ⇒ 用户看到的是"**我刚插进去的模板凭空没了**"。
//
// 口径（用户 2026-10-20）：只保住**光标所在的那一个**空结构；别处的空壳照样回收。
// 判据用闭区间（`u.start <= caret <= u.end`）—— 光标贴着结构末尾（按过 `→` 出槽）也算"还在它身上"。
//
// 另一条既有口径不许退化：**多行环境**（`\begin{aligned}…` / `cases`）永远不回收（2026-10-18）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/normalize.dart';

void main() {
  group('★ F8：光标所在的空结构不回收', () {
    test('`\\frac{}{}` + 光标在空槽里 ⇒ 一个字都不动（改前被整段删成空串）', () {
      const String tex = r'\frac{}{}';
      final int caret = 6; // `\frac{` | `}` ← 第一个空槽的内容起点
      final NormalizeResult r = normalizeTex(tex, caret);
      expect(r.changed, isFalse, reason: '刚插进来的模板不许被提交点吞掉');
      expect(r.tex, tex);
      expect(r.caret, caret);
    });

    test('`\\sqrt{}` 光标在里面 / 贴着末尾 ⇒ 都保住', () {
      const String tex = r'\sqrt{}';
      for (final int caret in <int>[6, 7]) {
        expect(normalizeTex(tex, caret).tex, tex, reason: 'caret=$caret');
      }
    });

    test('★ 只保住"光标所在的那个"：另一个空壳照样回收', () {
      const String tex = r'\sqrt{}\frac{}{}'; // 第一个空结构 [0,7)，第二个 [7,16)
      final NormalizeResult r = normalizeTex(tex, 1); // 光标在第一个里
      expect(r.tex, r'\sqrt{}', reason: '第二个空壳（光标不在里面）应当被回收');
      final NormalizeResult r2 = normalizeTex(tex, 12); // 光标在第二个里
      expect(r2.tex, r'\frac{}{}', reason: '第一个空壳应当被回收');
    });

    test('★ 不误伤：光标不在任何空结构里 ⇒ 全空结构照旧回收', () {
      // 光标在 `+` 后面（结构之外）
      final NormalizeResult r = normalizeTex(r'\frac{}{}+x', 11);
      expect(r.tex, r'+x');
    });

    test('多行环境仍不回收（2026-10-18 的既有口径不许退化）', () {
      const String env = r'\begin{aligned}&=\\&=\end{aligned}';
      expect(normalizeTex(env, 0).tex, env);
      expect(normalizeTex(env, env.length).tex, env);
    });

    test('幂等 + 光标不越界（全域）', () {
      const List<String> corpus = <String>[
        r'\frac{}{}',
        r'\sqrt{}',
        r'\sqrt{}\frac{}{}',
        r'x^{\ }',
        r'\frac{a}{}',
        r'^{}',
        r'\begin{cases}&\end{cases}',
        r'\frac{}{}+\frac{}{}',
      ];
      for (final String tex in corpus) {
        for (var c = 0; c <= tex.length; c++) {
          final NormalizeResult a = normalizeTex(tex, c);
          expect(a.caret, inInclusiveRange(0, a.tex.length),
              reason: '"$tex" @$c ⇒ ${a.tex} @${a.caret}');
          final NormalizeResult b = normalizeTex(a.tex, a.caret);
          expect(b.tex, a.tex, reason: '幂等："$tex" @$c');
        }
      }
    });
  });
}
