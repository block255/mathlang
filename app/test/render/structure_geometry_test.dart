// 结构几何（② 组的地基表）：源码对象表 · 与渲染节点的对齐 · 三条全域不变量 P1/P2/P3。
//
// ★ 为什么这三条要"全域"而不是抽查：本仓 7 个 bug 里 6 个是"某个偏移没人管"漏出来的
//   （《编辑地基与手感》§三）。几何表也一样 —— 漏一个结构，那个结构就点不到 / 选不中。
//
// 数据来源：2026-10-15 晚三批探针（`_cache\probe_structure.log` / `probe2.log` / `probe3.log`），
// 结论已写进 `structure_geometry.dart` 文件头与设计稿 §11.24。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/slot_marks.dart';
import 'package:mathlang/render/structure_geometry.dart';
import 'package:mathlang/render/visible_atoms.dart';

/// 语料：覆盖"每种结构 × 有/无节点 × 嵌套 × 样式敏感"。
const List<String> kCorpus = <String>[
  r'\frac{a}{b}',
  r'\frac{a}{b}+\frac{c}{d}',
  r'\sqrt{2}',
  r'\sqrt[3]{x}',
  r'x^{2}',
  r'x_i^2',
  r'x_{a_i}',
  r'\frac{\sqrt{2}}{x}',
  r'\frac{a}{\frac{b}{c}}',
  r'\sqrt{\frac{a}{b}}',
  r'x^{\frac{1}{2}}',
  r'\overline{AB}',
  r'\underline{AB}',
  r'\hat{x}',
  r'\bar{x}',
  r'\vec{a}',
  r'\widehat{xy}',
  r'\overbrace{AB}',
  r'\overline{AB}+\hat{x}',
  r'\sum_{i=1}^{n}a_i',
  r'\int_a^b f(x)\,dx',
  r'\lim_{x\to0}\frac{\sin x}{x}',
  r'\prod_{k=1}^{m}k',
  r'\sin x',
  r'\sin^2 x',
  r'\left(\frac{a}{b}\right)',
  r'\begin{cases}a&b\\c&d\end{cases}',
  r'\begin{aligned}a&=b\\c&=d\end{aligned}',
  r'\begin{pmatrix}a&b\\c&d\end{pmatrix}',
  r'\frac{a}{b}=\sqrt{2}',
  r'x=\frac{-b\pm\sqrt{b^2-4ac}}{2a}',
  r'\overline{\frac{a}{b}}',
  r'\frac{}{}',
  r'\sqrt{}',
  // ★ 探路：`kOpaqueCommands` 里那些"还没量过"的装饰命令 ——
  //   它们渲染上到底有没有结构节点？语料放进来自动回答（对不上就会红）
  r'\boxed{x}',
  r'\cancel{x}',
  r'\fbox{x}',
  r'\pmb{x}',
  r'\angl{x}',
  r'\overset{a}{b}',
  r'\underset{a}{b}',
  r'\stackrel{a}{b}',
  r'\substack{a\\b}',
  r'\overbracket{AB}',
  r'\underbracket{AB}',
  r'\overleftarrow{AB}',
  r'\xrightarrow{AB}',
  r'\operatorname{sin}',
  r'\mathrm{d}',
  r'\text{汉}',
  r'\left\{\frac{a}{b}\right.',
];

Future<RenderBox> _pump(WidgetTester tester, String renderTex, MathStyle style) async {
  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: Math.tex(renderTex,
            key: key, mathStyle: style, textStyle: const TextStyle(fontSize: 16)),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return key.currentContext!.findRenderObject()! as RenderBox;
}

Future<StructureGeometry> _geo(WidgetTester tester, String tex, MathStyle style) async {
  final String renderTex = renderMathTex(tex, caretRel: -1);
  final RenderBox ro = await _pump(tester, renderTex, style);
  return buildStructureGeometry(tex: tex, renderTex: renderTex, mathRoot: ro);
}

void main() {
  // ─────────────────────────────────────────────────────────────
  // 一、源码侧结构对象表（纯 Dart）
  // ─────────────────────────────────────────────────────────────
  group('源码侧：结构对象表', () {
    test(r'`\frac{a}{b}` → 一个分式，区间 [0,10)（含收尾 `}`）', () {
      final List<StructureObject> o = structureObjectsFor(r'\frac{a}{b}');
      expect(o.length, 1);
      expect(o.single.kind, StructureKind.frac);
      expect(o.single.command, 'frac');
      expect(o.single.start, 0);
      expect(o.single.end, r'\frac{a}{b}'.length);
      expect(o.single.nodeBacked, isTrue);
      expect(o.single.parent, isNull);
    });

    test(r'`\sqrt[3]{x}` → 一个根号（次数槽包含在内）', () {
      final List<StructureObject> o = structureObjectsFor(r'\sqrt[3]{x}');
      expect(o.length, 1);
      expect(o.single.kind, StructureKind.sqrt);
      expect(o.single.end, r'\sqrt[3]{x}'.length);
    });

    test(r'★ `x_i^2` → **一个**脚本对象（同一基座上的两个脚本合并）', () {
      final List<StructureObject> o = structureObjectsFor(r'x_i^2');
      expect(o.length, 1, reason: '实测：渲染侧也只有一个 `_ScriptPos`');
      expect(o.single.kind, StructureKind.script);
      expect(o.single.start, 0, reason: '基座 `x` 是对象的一部分');
      expect(o.single.end, 5, reason: r'`x_i^2`.length == 5');
    });

    test(r'★ `x_{a_i}` → 两个（外层脚本 + 内层脚本，**不能**合并）', () {
      final List<StructureObject> o = structureObjectsFor(r'x_{a_i}');
      expect(o.length, 2);
      expect(o[0].kind, StructureKind.script);
      expect(o[0].start, 0);
      expect(o[1].kind, StructureKind.script);
      expect(o[1].parent, isNotNull, reason: '内层脚本在外层脚本的槽里 ⇒ 有父');
      expect(o[1].start, 3, reason: '内层基座是 `a`（下标里那个）');
    });

    test(r'★ `\sum_{i=1}^{n}a_i` → **算子（含上下限）+ `a_i` 脚本** = 2 个', () {
      final List<StructureObject> o = structureObjectsFor(r'\sum_{i=1}^{n}a_i');
      expect(o.length, 2,
          reason: '★ 算子的两个上下限折进算子（实测：display 下渲染侧只 1 个节点）；'
              '实际：$o');
      expect(o[0].kind, StructureKind.operator);
      expect(o[0].command, 'sum');
      expect(o[0].nodeBacked, isTrue, reason: '带上下限 ⇒ 有专属节点');
      expect(o[1].kind, StructureKind.script);
    });

    test(r'★ `\sin x` → 一个算子对象，但 **nodeBacked = false**（渲染侧没有节点）', () {
      final List<StructureObject> o = structureObjectsFor(r'\sin x');
      expect(o.length, 1);
      expect(o[0].kind, StructureKind.operator);
      expect(o[0].nodeBacked, isFalse, reason: '没有上下限 ⇒ 渲染上只是字形并置，没有结构节点');
      expect(o[0].end, r'\sin x'.length, reason: '作用域内容算在对象里（§4.7）');
    });

    test(r'★ `\sin^2 x` → 有上下限 ⇒ nodeBacked = true', () {
      final List<StructureObject> o = structureObjectsFor(r'\sin^2 x');
      expect(o.length, 1, reason: '`^2` 折进算子，不另算脚本；实际：$o');
      expect(o.single.nodeBacked, isTrue);
    });

    test(r'`\overline{AB}` → 一个 accent（accent 没有槽，靠内容项枚举）', () {
      final List<StructureObject> o = structureObjectsFor(r'\overline{AB}');
      expect(o.length, 1);
      expect(o.single.kind, StructureKind.accent);
      expect(o.single.command, 'overline');
    });

    test(r'`\begin{cases}a&b\\c&d\end{cases}` → 一个环境对象', () {
      final List<StructureObject> o = structureObjectsFor(r'\begin{cases}a&b\\c&d\end{cases}');
      expect(o.length, 1);
      expect(o.single.kind, StructureKind.env);
      expect(o.single.command, 'begin');
      expect(o.single.end, r'\begin{cases}a&b\\c&d\end{cases}'.length);
    });

    test('嵌套的父指针：`\\frac{a}{\\frac{b}{c}}` 内层分式的父是外层', () {
      final List<StructureObject> o = structureObjectsFor(r'\frac{a}{\frac{b}{c}}');
      expect(o.length, 2);
      expect(o[0].start, 0);
      expect(o[1].parent, same(o[0]));
    });

    test('降级位点表 ⇒ 空表（结构树不可靠时不猜几何）', () {
      expect(buildCaretSites(r'a}b').degraded, isTrue);
      expect(structureObjectsFor(r'a}b'), isEmpty);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 二、对齐：源码对象（有节点的子序列）↔ 渲染节点
  // ─────────────────────────────────────────────────────────────
  group('★ 对齐（数量 + 类型相容）', () {
    for (final MathStyle style in <MathStyle>[MathStyle.display, MathStyle.text]) {
      testWidgets('语料 ${kCorpus.length} 条 × ${style.name}', (WidgetTester tester) async {
        final List<String> bad = <String>[];
        for (final String tex in kCorpus) {
          final StructureGeometry g = await _geo(tester, tex, style);
          if (!g.aligned) bad.add('「$tex」→ ${g.mismatch}');
        }
        expect(bad, isEmpty, reason: '对齐失败：\n${bad.join('\n')}');
      });
    }
  });

  // ─────────────────────────────────────────────────────────────
  // 三、P1 完备 / P2 包含 / P3 顺序（全域）
  // ─────────────────────────────────────────────────────────────
  group('★★ 全域不变量', () {
    testWidgets('P1 完备：**有节点的**结构对象都有矩形；P2 包含：子 ⊆ 父',
        (WidgetTester tester) async {
      const double tol = 0.5;
      final List<String> p1 = <String>[];
      final List<String> p2 = <String>[];

      for (final String tex in kCorpus) {
        for (final MathStyle style in <MathStyle>[MathStyle.display, MathStyle.text]) {
          final StructureGeometry g = await _geo(tester, tex, style);
          for (var i = 0; i < g.objects.length; i++) {
            final StructureObject o = g.objects[i];
            final Rect? r = g.rectAt(i);
            // ★ P1 的**精确条件**（不粉饰）：有节点的对象**必须**有矩形；
            //   没有节点的对象本版**允许 null** —— 它要"叶盒并集"，
            //   而并集卡在"一原子多盒"（`\sin` = 1 原子 3 盒）这个既有缺陷上，
            //   所以 `\sin x` / `\left(…\right)` / `\overbracket{}` 暂时拿不到矩形。
            //   见文件末尾「已知缺口」那组测试。
            if (!o.nodeBacked) {
              expect(r, isNull,
                  reason: '没有节点的对象本版应当返回 null（否则说明并集悄悄生效了）：「$tex」$o → $r');
              continue;
            }
            if (r == null || r.width <= 0 || r.height <= 0) {
              p1.add('「$tex」[${style.name}] $o → $r');
              continue;
            }
            final StructureObject? p = o.parent;
            if (p == null) continue;
            final Rect? pr = g.rectOf(p);
            if (pr == null) continue;
            final bool inside = r.left >= pr.left - tol &&
                r.right <= pr.right + tol &&
                r.top >= pr.top - tol &&
                r.bottom <= pr.bottom + tol;
            if (!inside) {
              p2.add('「$tex」[${style.name}] 子 $o $r\n        父 $p $pr');
            }
          }
        }
      }
      expect(p1, isEmpty, reason: 'P1 完备性被破坏：\n${p1.join('\n')}');
      expect(p2, isEmpty, reason: 'P2 包含性被破坏：\n${p2.join('\n')}');
    });

    testWidgets('P3 顺序：同级结构要么水平分离、要么竖直分离（主轴不重叠）',
        (WidgetTester tester) async {
      const double tol = 0.5;
      final List<String> bad = <String>[];

      for (final String tex in kCorpus) {
        for (final MathStyle style in <MathStyle>[MathStyle.display, MathStyle.text]) {
          final StructureGeometry g = await _geo(tester, tex, style);
          for (var i = 0; i < g.objects.length; i++) {
            for (var j = i + 1; j < g.objects.length; j++) {
              final StructureObject a = g.objects[i];
              final StructureObject b = g.objects[j];
              if (!identical(a.parent, b.parent)) continue; // 只查同级
              final Rect? ra = g.rectAt(i);
              final Rect? rb = g.rectAt(j);
              if (ra == null || rb == null) continue;
              // 源码顺序必须与几何顺序一致（主轴：这里按"先出现的在左/上"）
              final bool horizontal = ra.right <= rb.left + tol;
              final bool vertical = ra.bottom <= rb.top + tol;
              if (!horizontal && !vertical) {
                bad.add('「$tex」[${style.name}] 同级重叠：\n  $a $ra\n  $b $rb');
              }
              if (b.end <= a.end) {
                bad.add('「$tex」[${style.name}] 顺序错：$a / $b');
              }
            }
          }
        }
      }
      expect(bad, isEmpty, reason: 'P3 被破坏：\n${bad.join('\n')}');
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 四、几何锚点：矩形的"位置"必须真的对得上屏幕
  // ─────────────────────────────────────────────────────────────
  group('几何锚点（矩形落在该落的地方）', () {
    testWidgets(r'`\frac{a}{b}` 的**引擎节点盒**：宽 19.8（含 2×1.9 内边距）、高 28.7',
        (WidgetTester tester) async {
      final StructureGeometry g = await _geo(tester, r'\frac{a}{b}', MathStyle.display);
      expect(g.aligned, isTrue, reason: g.mismatch);
      final Rect r = g.nodeRectAt(0)!;
      expect(r.width, closeTo(19.8, 0.5), reason: '实测：`_FracPos` = 19.8 宽');
      expect(r.height, closeTo(28.7, 0.5), reason: '实测：`_FracPos` = 28.7 高');
      expect(r.left, closeTo(0.0, 0.5));
      // ★ 对外用的矩形（节点盒 ∪ 叶盒并集）**必须包含**节点盒：
      //    数学字形本来就会画出根盒之外（实测 `a` 的 ¶ 盒 y -5.1..10.9）
      final Rect u = g.rectAt(0)!;
      expect(u.left, lessThanOrEqualTo(r.left + 0.01));
      expect(u.right, greaterThanOrEqualTo(r.right - 0.01));
      expect(u.top, lessThanOrEqualTo(r.top + 0.01));
      expect(u.bottom, greaterThanOrEqualTo(r.bottom - 0.01));
    });

    testWidgets(r'`\frac{a}{b}+\frac{c}{d}`：两个分式的盒**水平分离**且顺序正确',
        (WidgetTester tester) async {
      final StructureGeometry g = await _geo(tester, r'\frac{a}{b}+\frac{c}{d}', MathStyle.display);
      expect(g.objects.length, 2);
      final Rect r0 = g.rectAt(0)!;
      final Rect r1 = g.rectAt(1)!;
      expect(r0.right, lessThanOrEqualTo(r1.left));
      expect(g.nodeRectAt(0)!.left, closeTo(0.0, 0.5));
      expect(g.nodeRectAt(1)!.right, closeTo(62.8, 0.5));
    });

    testWidgets(r'★ 带上下限的算子：节点盒**只含算子与上下限**（不含被作用的内容）',
        (WidgetTester tester) async {
      final StructureGeometry g = await _geo(tester, r'\sum_{i=1}^{n}a_i', MathStyle.display);
      expect(g.aligned, isTrue, reason: g.mismatch);
      final StructureObject op = g.objects.firstWhere(
          (StructureObject o) => o.kind == StructureKind.operator);
      final Rect r = g.nodeRectOf(op)!;
      final StructureObject script =
          g.objects.firstWhere((StructureObject o) => o.kind == StructureKind.script);
      final Rect rs = g.nodeRectOf(script)!;
      expect(r.right, lessThanOrEqualTo(rs.left + 0.5),
          reason: '算子的节点盒不含 `a_i`（实测：33.6 vs 36.3）');
    });

    testWidgets(r'环境：`cases` 的盒含两行（高度 ≈ 38.4）', (WidgetTester tester) async {
      final StructureGeometry g =
          await _geo(tester, r'\begin{cases}a&b\\c&d\end{cases}', MathStyle.display);
      expect(g.aligned, isTrue, reason: g.mismatch);
      final Rect r = g.nodeRectAt(0)!;
      expect(r.height, greaterThan(30.0), reason: '两行 ⇒ 高；实际 $r');
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 五、★ 已知缺口（**带精确条件**记账，不是"以后再修"）
  // ─────────────────────────────────────────────────────────────
  group('★ 已知缺口：没有节点的结构拿不到矩形', () {
    testWidgets(r'`\sin x`：nodeBacked = false ⇒ rectAt = null（并集卡在"一原子多盒"）',
        (WidgetTester tester) async {
      final StructureGeometry g = await _geo(tester, r'\sin x', MathStyle.display);
      expect(g.aligned, isTrue, reason: g.mismatch);
      final StructureObject o = g.objects.single;
      expect(o.kind, StructureKind.operator);
      expect(o.nodeBacked, isFalse);
      expect(g.rectAt(0), isNull);
      // ★ 精确条件：一旦"一原子多盒"的配对修好（或换成别的配对通道），这条会变红 ⇒
      //   那时把 `\sin x` / `\left(…\right)` / `\overbracket{}` 的并集补上，
      //   并把 P1 的"有节点的"限定去掉。
      expect(g.diagnostics, isNotEmpty, reason: '退化原因必须写进诊断');
    });

    test('★ 既有缺陷（不在本组修）：`\\sin` 是 **1 个原子**却有 **3 个字形盒**', () {
      // 这条是"命中配对"的缺陷证据：`hitTestMathTex` 要求"叶盒数 == 原子数"，
      // 不成立就**静默不可靠** ⇒ 含 `\sin` / `\lim` / `\log` 这类**多字母算子名**的公式
      // 点击定位会退化（与 §11.21.2 的 accent 装饰盒是同一个 bug 家族）。
      expect(lexVisibleAtoms(r'\sin x').length, 2,
          reason: r'`\sin` 是 1 个可见原子（删一次删光）、`x` 是 1 个');
      expect(lexVisibleAtoms(r'\sin x').first.kind, r'\sin');
    });
  });
}
