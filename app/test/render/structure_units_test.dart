// 结构实例枚举的守门人（旧账 2026-10-17）
//
// ★ 为什么必须有这一份：`structureUnits` 是 **normalize（提交点回收）** 的唯一输入。
//   它原来的实例身份 = 「父路径 + 命令 + 行列」，而同层两个 `\frac` 的槽路径**完全一样**
//   （`SlotStep` 只有命令 + 参数号，不含位置）⇒
//
//   | tex | 改前 | 改后 |
//   |---|---|---|
//   | `\frac{a}{b}+\frac{c}{d}` | **1 个实例**，而且横跨 [0,23) ⇒ 回收会把中间的 `+` 一起删 | 2 个 |
//   | `\sqrt{x}+\sqrt{y}` | 1 个，横跨 [0,17) | 2 个 |
//   | `\int_{0}^{1}f+\int_{2}^{3}g` | 2 个，但范围串到了对方身上 | 2 个，各管自己 |
//   | `\sqrt[3]{x}` | **0 个**（次数槽前面是 `[`，反查命令失败） | 1 个 |
//   | `\begin{cases}…\end{cases}` | **0 个**（`cases` 前面是 `\begin{`） | 1 个，盖到 `\end{cases}` |
//
// 数据与结论见《位点与结构导航》§11.24 六①、§11.30。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/normalize.dart';
import 'package:mathlang/render/smart_delete.dart';

List<({int start, int end})> _units(String tex) => <({int start, int end})>[
      for (final StructureUnit u in structureUnits(buildCaretSites(tex)))
        (start: u.start, end: u.end),
    ];

void main() {
  group('★ 实例身份 = **源码起点**（同层两个同种结构必须是两个实例）', () {
    test(r'`\frac{a}{b}` ⇒ 1 个（两个参数算同一个调用）', () {
      expect(_units(r'\frac{a}{b}'), <({int start, int end})>[(start: 0, end: 11)]);
    });

    test(r'`\frac{a}{b}+\frac{c}{d}` ⇒ **2 个**，各自管自己（不再合成一个跨 `+` 的）', () {
      final List<({int start, int end})> u = _units(r'\frac{a}{b}+\frac{c}{d}');
      expect(u.length, 2, reason: '$u');
      expect(u[0].start, 0);
      expect(u[0].end, 11);
      expect(u[1].start, 12);
      expect(u[1].end, 23);
    });

    test(r'三个分式 ⇒ 3 个', () {
      expect(_units(r'\frac{a}{b}+\frac{c}{d}+\frac{e}{f}').length, 3);
    });

    test(r'`\sqrt{x}+\sqrt{y}` ⇒ 2 个（原来是 1 个跨到对方身上）', () {
      final List<({int start, int end})> u = _units(r'\sqrt{x}+\sqrt{y}');
      expect(u.length, 2, reason: '$u');
      expect(u[0], (start: 0, end: 8));
      expect(u[1], (start: 9, end: 17));
    });

    test(r'嵌套分式仍是 2 个（父路径本来就不同）', () {
      final List<({int start, int end})> u = _units(r'\frac{\frac{a}{b}}{c}');
      expect(u.length, 2, reason: '$u');
    });

    test(r'`x^{2}+y_{1}` ⇒ 2 个（`^` 与 `_` 的命令名不同）', () {
      expect(_units(r'x^{2}+y_{1}').length, 2);
    });
  });

  group('★ 起点反查：三种"参数与命令之间夹着东西"的写法都要认', () {
    test(r'`\sqrt[3]{x}` ⇒ 1 个（次数槽前面是 `[`，2026-10-17 起会跳过方括号）', () {
      final List<({int start, int end})> u = _units(r'\sqrt[3]{x}');
      expect(u.length, 1, reason: '$u');
      expect(u[0].start, 0);
      expect(u[0].end, 11);
    });

    test(r'`\begin{cases}a&b\\c&d\end{cases}` ⇒ 1 个，范围盖到 `\end{cases}`', () {
      const String tex = r'\begin{cases}a&b\\c&d\end{cases}';
      final List<({int start, int end})> u = _units(tex);
      expect(u.length, 1, reason: '$u');
      expect(u[0].start, 0);
      expect(u[0].end, tex.length,
          reason: '★ 必须含 `\\end{cases}`，否则回收会留下孤儿 `\\end`');
    });
  });

  group('★ 消费者（normalize）的可见收益：两个空分式都要回收，`+` 留着', () {
    test(r'`\frac{}{}+\frac{}{}` ⇒ `+`', () {
      final NormalizeResult r = normalizeTex(r'\frac{}{}+\frac{}{}', 0);
      expect(r.tex, '+', reason: '改前：整个式子（含 `+`）被当成一个实例一起删掉');
      expect(r.changed, isTrue);
    });

    test(r'只有一个空分式时只删它（`1+\frac{}{}+2` ⇒ `1++2`）', () {
      final NormalizeResult r = normalizeTex(r'1+\frac{}{}+2', 0);
      expect(r.tex, '1++2');
    });

    test('幂等：同一份 tex 再跑一次不变', () {
      final NormalizeResult a = normalizeTex(r'\frac{}{}+\frac{}{}', 0);
      final NormalizeResult b = normalizeTex(a.tex, 0);
      expect(b.changed, isFalse);
    });
  });
}
