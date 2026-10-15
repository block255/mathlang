// 装饰盒过滤（§11.21.2）：让 accent 家族符合「叶盒数 == 原子数」。
//
// ★ 为什么要有这一条：accent 的**装饰自己就是一个叶盒** ⇒ "叶盒 3 ≠ 原子 2"
//   ⇒ `hitTestMathTex` **静默返回 null** ⇒ **这些结构里点击一直是"点了没反应"**
//   （既有 bug：`leaf_boxes_test.dart` 的语料里没有 accent，所以一直没覆盖）。
//
// 本文件钉住四条判据（数据全部来自 2026-10-15 晚的探针，见设计稿 §11.21.2）：
//   ① 光标条 → 宽度下限（已有）
//   ② 失真矢量图 → 宽度上限（已有）
//   ③ 细线装饰（`\overline` / `\underline` 的 0.6 px 横线）→ **高度下限**（新）
//   ④ 变音字形装饰（`\hat` 的 `^` / `\tilde` 的 `~` / `\dot` 的 `˙` / `\bar` 的 `ˉ`）
//      → **它画的是什么**（新；几何上装饰盒与内容盒**完全重合**，分不开）
//   ★ 同时钉住两件"别改坏"的事：**零高的尾垫必须留下**、**细字形不许被误杀**。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/injection_map.dart';
import 'package:mathlang/render/leaf_boxes.dart';
import 'package:mathlang/render/slot_marks.dart';
import 'package:mathlang/render/visible_atoms.dart';

Future<RenderBox> _pumpMath(WidgetTester tester, String tex, GlobalKey key) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: Math.tex(
          tex,
          key: key,
          mathStyle: MathStyle.display,
          textStyle: const TextStyle(fontSize: 16),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return key.currentContext!.findRenderObject()! as RenderBox;
}

/// 走**同一条注入链**渲染一个 tex，返回（渲染 tex、有效叶盒、命中原子）
Future<({String renderTex, LeafBoxScan scan, List<VisibleAtom> atoms})> _probe(
  WidgetTester tester,
  String tex,
) async {
  final String renderTex = renderMathTex(tex, caretRel: -1);
  final GlobalKey key = GlobalKey();
  final RenderBox ro = await _pumpMath(tester, renderTex, key);
  return (
    renderTex: renderTex,
    scan: scanLeafBoxes(ro),
    atoms: atomsForHitTest(renderTex),
  );
}

void main() {
  // ─────────────────────────────────────────────────────────────
  // 一、③ 细线装饰：`\overline` / `\underline` 的横线不算原子
  // ─────────────────────────────────────────────────────────────
  group('③ 高度下限：细线装饰（0.6 px 横线）不是原子', () {
    for (final String tex in <String>[r'\overline{AB}', r'\underline{AB}']) {
      testWidgets('$tex：横线在 `all` 里、但**不在** `eligible` 里', (WidgetTester tester) async {
        final ({String renderTex, LeafBoxScan scan, List<VisibleAtom> atoms}) r =
            await _probe(tester, tex);

        // 那条 0.6 px 的横线确实存在（否则这条测试是假通过）
        expect(
          r.scan.all.any((LeafBox b) =>
              b.rect.height > 0 && b.rect.height < kMinLeafHeight),
          isTrue,
          reason: '实测：$tex 有一条矮横线叶盒。全部叶盒：'
              '${r.scan.all.map((LeafBox b) => b.rect.height.toStringAsFixed(1)).toList()}',
        );
        // 但它被摘掉了 ⇒ 数量对上
        expect(r.scan.eligible.length, r.atoms.length,
            reason: '有效叶盒 ${r.scan.eligible.length} vs 原子 ${r.atoms.length}');
        expect(r.scan.eligible.length, 3,
            reason: 'A + B + 尾垫（`$tex` 现在也在 `kTailCommands` 里）');
      });
    }

    testWidgets('★ 零高的**尾垫必须留下**（判据是"严格正的极小高度"）',
        (WidgetTester tester) async {
      final ({String renderTex, LeafBoxScan scan, List<VisibleAtom> atoms}) r =
          await _probe(tester, r'\sqrt{2}');
      final LeafBox tail = r.scan.eligible.last;
      expect(tail.rect.height, 0.0, reason: '尾垫是零高 —— 正是它躲开高度下限的原因');
      expect(r.scan.eligible.length, r.atoms.length);
      expect(r.atoms.last.kind, 'tail');
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 二、④ 变音字形装饰：几何上与内容**完全重合** ⇒ 只能看它画的是什么
  // ─────────────────────────────────────────────────────────────
  group(r'④ 变音字形的装饰盒（`\hat` `\tilde` `\dot` `\ddot` `\bar`）不算原子', () {
    const Map<String, String> cases = <String, String>{
      r'\hat{x}': '^',
      r'\tilde{x}': '~',
      r'\dot{x}': '˙',
      r'\ddot{x}': '¨',
      r'\bar{x}': 'ˉ',
    };

    cases.forEach((String tex, String glyph) {
      testWidgets('$tex：装饰 ¶"$glyph" 在 `all` 里、不在 `eligible` 里',
          (WidgetTester tester) async {
        final ({String renderTex, LeafBoxScan scan, List<VisibleAtom> atoms}) r =
            await _probe(tester, tex);
        expect(r.scan.all.length, greaterThan(r.scan.eligible.length),
            reason: '装饰盒必须先被扫到（否则测试假通过）');
        expect(r.scan.eligible.length, r.atoms.length,
            reason: '有效叶盒 ${r.scan.eligible.length} vs 原子 ${r.atoms.length}；'
                '渲染 tex = ${r.renderTex}');
      });
    });

    testWidgets('★ `\\bar{AB}`：装饰 ¶ 被**拉伸到 32.8 宽**，仍然不算原子',
        (WidgetTester tester) async {
      final ({String renderTex, LeafBoxScan scan, List<VisibleAtom> atoms}) r =
          await _probe(tester, r'\bar{AB}');
      expect(r.scan.eligible.length, r.atoms.length,
          reason: '有效叶盒 ${r.scan.eligible.length} vs 原子 ${r.atoms.length}');
      expect(r.scan.eligible.length, 3, reason: 'A + B + 尾垫（`\bar` 的装饰会跟着变长）');
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 三、别改坏：细字形 / 上标 / 普通公式一个都不许被误杀
  // ─────────────────────────────────────────────────────────────
  group('★ 高度下限不许误杀真原子（引擎给的是**行高盒**，不是墨迹盒）', () {
    const List<String> texs = <String>[
      '-', '=', r'\cdot', r'\alpha', r'\sum', r'\int',
      r'x^2', r'x^{-2}', r'a-b=c', r'\alpha+\beta',
    ];
    for (final String tex in texs) {
      testWidgets(tex, (WidgetTester tester) async {
        final ({String renderTex, LeafBoxScan scan, List<VisibleAtom> atoms}) r =
            await _probe(tester, tex);
        expect(r.scan.eligible.length, r.atoms.length,
            reason: '$tex：有效叶盒 ${r.scan.eligible.length} vs 原子 ${r.atoms.length}');
      });
    }
  });

  // ─────────────────────────────────────────────────────────────
  // 四、★★ 守门人（全域）：accent 全家族 × 3 种光标态
  // ─────────────────────────────────────────────────────────────
  group('★★ 守门人：accent 家族的「叶盒数 == 命中原子数」', () {
    const List<String> texs = <String>[
      r'\overline{AB}', r'\underline{AB}', r'\overline{AB}+C',
      r'\hat{x}', r'\tilde{x}', r'\dot{x}', r'\ddot{x}', r'\bar{x}', r'\bar{AB}',
      r'\vec{a}', r'\overrightarrow{AB}', r'\widehat{xyz}', r'\widetilde{AB}',
      r'\overbrace{AB}', r'\underbrace{AB}',
      r'\hat{x}+\overline{AB}', r'-\frac{a}{b}=\sqrt{2}',
      r'\overline{\frac{a}{b}}',
    ];

    testWidgets('每个 tex × 光标态（-1 / 段首 / 段末）', (WidgetTester tester) async {
      for (final String tex in texs) {
        for (final int caretRel in <int>[-1, 0, tex.length]) {
          final String renderTex = renderMathTex(tex, caretRel: caretRel);
          final GlobalKey key = GlobalKey();
          final RenderBox ro = await _pumpMath(tester, renderTex, key);
          final LeafBoxScan scan = scanLeafBoxes(ro);
          final List<VisibleAtom> atoms = atomsForHitTest(renderTex);
          expect(scan.eligible.length, atoms.length,
              reason: '「$tex」caretRel=$caretRel → `$renderTex`：'
                  '叶盒 ${scan.eligible.length} vs 原子 ${atoms.length}'
                  '（原始叶盒 ${scan.rawCount}）');
        }
      }
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 五、词法侧的同一个 bug 家族：幻影原子（`\widehat` / `\overbrace` 曾被当成一个原子）
  // ─────────────────────────────────────────────────────────────
  group(r'结构命令表：`\widehat` / `\widetilde` / `\overbrace` / `\underbrace`', () {
    test('它们**不贡献**原子（原先各贡献 1 个幻影原子 ⇒ 点击静默失效）', () {
      expect(lexVisibleAtoms(r'\widehat{AB}').length, 2);
      expect(lexVisibleAtoms(r'\widetilde{AB}').length, 2);
      expect(lexVisibleAtoms(r'\overbrace{AB}').length, 2);
      expect(lexVisibleAtoms(r'\underbrace{AB}').length, 2);
    });

    test(r'★ 带上下限时照常算：`\overbrace{AB}^{n}` → A B n', () {
      expect(lexVisibleAtoms(r'\overbrace{AB}^{n}').length, 3);
    });

    test(r'命中表里也不再有幻影原子（`\widehat{AB}` → A + B + 尾垫）', () {
      final String t = renderMathTex(r'\widehat{AB}', caretRel: -1);
      final List<VisibleAtom> atoms = atomsForHitTest(t);
      expect(atoms.length, 3, reason: '实际：${atoms.map((VisibleAtom a) => a.kind).toList()}');
      expect(atoms.last.kind, 'tail');
    });
  });
}
