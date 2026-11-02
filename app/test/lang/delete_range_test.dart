// ★★ 2026-11-02（选择边界与剪贴板批）：**删除查剩余**，不查片段。
//
// 口径（讨论定稿 §3.3）：
//   · 删完结构成立 ⇒ 照删；
//   · 不成立 ⇒ 扩到最小单位（脚本连底、缺参数的命令、孤立的闭壳、环境的另一半）；
//   · **不套用**复制的右向补全（`\frac{a}` 不再被补成整段）。
//
// 改前红（旧 `_deleteRange` 走 `clipboardSlice`）：
//   `a^2` 删 `a` ⇒ 剩 `^2`；`\frac{a}{b}` 删 `\frac{a}` ⇒ 剩 `{b}`（多删）；
//   `\sqrt[x]{a}` 删到 `x]` ⇒ 剩 `x]{a}`（现在整个根号的对象被删掉）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/delete_range.dart';

String _after(String doc, int s, int e) {
  final ({int start, int end}) r = planDeleteRange(doc, s, e);
  return doc.replaceRange(r.start, r.end, '');
}

void main() {
  group('① 脚本：删底要连脚本，删脚本要连标记', () {
    const String doc = r'$a^2$';
    test('删 `a` ⇒ 整个 `a^2` 走（剩 `^2` 不成立）', () {
      expect(_after(doc, 1, 2), r'$$');
    });
    test('删 `2` ⇒ 连 `^` 一起走（剩 `a^` 不成立）', () {
      expect(_after(doc, 3, 4), r'$a$');
    });
  });

  group('② 分式：删参数内容留空槽；删参数组才动命令', () {
    const String doc = r'$\frac{a}{b}$';
    test('删分子内容 `a` ⇒ `\\frac{}{b}`（空槽合法）', () {
      expect(_after(doc, 7, 8), r'$\frac{}{b}$');
    });
    test('删分母内容 `b` ⇒ `\\frac{a}{}`', () {
      expect(_after(doc, 10, 11), r'$\frac{a}{}$');
    });
    test('删整个分子组 `{a}` ⇒ 连 `\\frac` 一起走（留 `{b}` 合法）', () {
      expect(_after(doc, 6, 9), r'${b}$');
    });
  });

  group('③ 根号：删次数留空 `[]`；删 `\\sqrt[x` 要连 `]` 一起走', () {
    const String doc = r'$\sqrt[x]{a}$';
    test('删 `x` ⇒ `\\sqrt[]{a}`（合法）', () {
      expect(_after(doc, 7, 8), r'$\sqrt[]{a}$');
    });
    test('删 `\\sqrt[x` ⇒ 连同孤立的 `]` ⇒ `{a}`', () {
      expect(_after(doc, 1, 8), r'${a}$');
    });
  });

  group('④ 环境：删格内容留空环境；不劈开围栏', () {
    final String doc = '\$\$\\begin{cases}x=1\\\\y=2\\end{cases}\$\$';
    test('删两行内容 ⇒ `\\begin{cases}\\end{cases}`（空环境合法）', () {
      final int s = doc.indexOf('x=1');
      final int e = doc.indexOf('y=2') + 3;
      expect(_after(doc, s, e), r'$$\begin{cases}\end{cases}$$');
    });
  });

  group('⑤ 用户的式子：分子{ 拖到 分母2 ⇒ 整个分式对象走', () {
    const String doc =
        r'11.求极限 $\lim_{x\to+\infty}$ ( $\frac{\sqrt[x]{a_{1}}+\sqrt[x]{a_{2}}}{2}$ ) $^{x}$ ,其中…';
    test('删完只剩 `( \$\$ )`（内容清空，围栏等回收）', () {
      final int s = doc.indexOf('{', doc.indexOf(r'\frac'));
      final int e = doc.indexOf('2', doc.indexOf(r'}{')) + 1;
      expect(_after(doc, s, e), contains(r'( $$ )'));
    });
  });

  group('⑥ 剪切文本 = 实际删掉的那段', () {
    test('在段内 ⇒ 补一对 `\$…\$`', () {
      const String doc = r'$a^2$';
      final r = planDeleteRange(doc, 1, 2);
      expect(clipboardTextForRange(doc, r.start, r.end), r'$a^2$');
    });
    test('跨段/整段 ⇒ 原样（不再包一层）', () {
      const String doc = '前 \$a^2\$ 后';
      final r = planDeleteRange(doc, doc.indexOf(r'$'), doc.indexOf(r'$', 2) + 1);
      expect(clipboardTextForRange(doc, r.start, r.end), r'$a^2$');
    });
  });
}
