// 批 29：**删除的产物必须是合法 tex** —— 不许把「控制词」和后面的字母粘成一条不存在的命令。
//
// 用户 2026-10-24 22:29 截图：光标停在 `$\exists x_{0}\in[x_{2}$` 的 `[` 之后，按 Backspace
// ⇒ 页面上出现 `[公式不完整]`。
//
// 探针 v34（同一行各位置对照）：
//   caret 在 `\in` 之后 / `[` 之前 ⇒ 删的是 `\in` ⇒ `\exists x_{0}[x_{2}` **合法**；
//   caret 在 `[` 之后 / `x` 之前 ⇒ 删的是 `[`  ⇒ `\exists x_{0}\inx_{2}` ⇒ **`\inx` 未定义命令**。
//
// 判据：删除区间右侧以字母/数字开头、左侧正好以一条**完整命令**结尾（且删的起点不是字母
// ⇒ 删的是分隔符而不是命令内部的字）⇒ **改删那条命令**，保留分隔符。
// 另一条（全域扫描抓出来的）：`\left` / `\right` 后面那个分隔符被删 ⇒ 命令失去参数
// （`Expected group after \right`）⇒ 按"分隔符不可单删"**整对删**。
//
// ★ 本文件守的是**全域**：一批 tex × 每个位点 × 两个方向，删完都必须还能解析。

import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/smart_delete.dart';

String? _parseErr(String tex) => Math.tex(tex).parseError?.messageWithType;

({String after, String deleted, String? err}) _del(String tex, int rel, bool forward) {
  final CaretSiteTable t = buildCaretSites(tex);
  final SmartEdit e = forward ? smartDelete(t, rel) : smartBackspace(t, rel);
  if (e.from == null || e.to == null) {
    return (after: tex, deleted: '(不删)', err: null);
  }
  final String after = tex.replaceRange(e.from!, e.to!, '');
  return (after: after, deleted: tex.substring(e.from!, e.to!), err: _parseErr(after));
}

void main() {
  group('批 29 · 删除不许把文档弄坏', () {
    test(r'★★ ① 现场：`\in[x` 里 `[` 之后按 Backspace（改前必红）', () {
      const String tex = r'\exists x_{0}\in[x_{2}';
      final int rel = tex.indexOf('[') + 1; // `[` 之后那一格
      final ({String after, String deleted, String? err}) r = _del(tex, rel, false);
      expect(r.after.contains(r'\inx'), isFalse,
          reason: '删完变成了「${r.after}」—— `\\inx` 是未定义命令');
      expect(r.err, isNull, reason: '删完必须能解析：${r.after} ⇒ ${r.err}');
      expect(r.deleted, r'\in',
          reason: '应当改删那条命令（⌫ = 左边最近的墨迹），实测删的是「${r.deleted}」');
    });

    test(r'★ ② 对照：caret 在 `[` **之前**时行为不变（删的就是那条命令）', () {
      const String tex = r'\exists x_{0}\in[x_{2}';
      final int rel = tex.indexOf('[');
      final ({String after, String deleted, String? err}) r = _del(tex, rel, false);
      expect(r.deleted, r'\in');
      expect(r.err, isNull, reason: r.after);
    });

    test(r'★★ ③ 全域：一批 tex × 每个位点 × 两个方向，删完都必须能解析', () {
      const List<String> texs = <String>[
        r'\exists x_{0}\in[x_{2}]',
        r'\sin x+\cos x',
        r'\alpha\beta\mu',
        r'\frac{x^{3}}{y}',
        r'a \le b \le c',
        r'\lim_{n \to \infty} x_{n}=0',
        r'\sqrt[3]{x^{2}}',
        r'\left(x^{2}\right)',
        r'\sum_{i=1}^{n}(x+1)',
        r'\begin{cases}4\\\end{cases}',
        r'\begin{aligned}&=\\&=\end{aligned}',
        r'\text{当}\ x>0',
        r'x_{2}]\ y\in z',
      ];
      var checked = 0;
      for (final String tex in texs) {
        for (var rel = 0; rel <= tex.length; rel++) {
          for (final bool forward in <bool>[false, true]) {
            final ({String after, String deleted, String? err}) r = _del(tex, rel, forward);
            checked++;
            expect(r.err, isNull,
                reason: 'tex=「$tex」 rel=$rel ${forward ? "Delete" : "Backspace"} '
                    '删了「${r.deleted}」⇒「${r.after}」⇒ ${r.err}');
          }
        }
      }
      expect(checked, greaterThan(200), reason: '断言不许空转（实际扫了 $checked 次）');
    });

    test(r'★ ④ `\left(…\right)` 里删掉 `\right` 后面的 `)` ⇒ 整对删（不许留裸 `\right`）', () {
      const String tex = r'\left(x^{2}\right)';
      final int rel = tex.indexOf(r'\right') + r'\right'.length;
      final ({String after, String deleted, String? err}) r = _del(tex, rel, true);
      expect(r.err, isNull, reason: '删完必须能解析：${r.after} ⇒ ${r.err}');
    });
  });
}
