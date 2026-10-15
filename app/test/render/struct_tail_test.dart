// 结构尾垫（§11.18）：让"里面式子的末尾"与"根号整体末尾"分成两根像素。
//
// ★ 为什么必须有这条：`\sqrt{2}` 的横线**不超出**被开方数 ⇒ 结构右缘 == 内容右缘 ⇒
//   两个位点（内容末尾 / 结构末尾）落在**同一根像素**上，光标也长得一样，
//   用户点哪儿都分不清、删了 `2` 才发现整个根号一起走（2026-10-15 用户实测）。
//   分式没有这个问题：分数线两头**超出**分子分母，天然有"结构专属像素"。
//
// 做法：给根号内容末尾塞一段**看不见但占宽**的 `\rule`（`kStructTailTex`）⇒
//   横线跟着变长 ⇒ 内容末尾（`2` 右缘）与结构末尾（横线末端）**相距约 5 px**。
//
// ⚠️ 两个坑都在本文件里钉住（都是踩过的）：
//   ① 尾垫多出一个**叶盒** ⇒ 命中表必须补一个**合成原子**，否则 `hitTestMathTex`
//      因"叶盒数 ≠ 原子数"**静默返回 null**（公式内点击全废）
//   ② 尾垫宽度必须是**绝对单位**：`em` 在小字号下会被 `kMinLeafWidth = 2.0` 过滤掉 ⇒ 同上

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/hit_map.dart';
import 'package:mathlang/render/injection_map.dart';
import 'package:mathlang/render/leaf_boxes.dart';
import 'package:mathlang/render/slot_marks.dart';
import 'package:mathlang/render/visible_atoms.dart';

/// 挂上编辑面（照 `edit_view_test` 的做法）
Future<EditViewState> _mountEdit(WidgetTester tester, DocBuffer buf) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: EditView(buffer: buf)),
    ),
  ));
  final EditViewState st = tester.state<EditViewState>(find.byType(EditView));
  st.focusInput();
  await tester.pump();
  return st;
}

/// `\overline{AB}` —— §11.21 那组用例里反复出现（用 raw 常量避开"多余转义"的 lint）
const String kOverlineTex = r'\overline{AB}';

Future<RenderBox> _pumpMath(WidgetTester tester, String tex, GlobalKey key) async {  await tester.pumpWidget(MaterialApp(
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

void main() {
  // ─────────────────────────────────────────────────────────────
  // 一、注入本身（纯函数）
  // ─────────────────────────────────────────────────────────────
  group('§11.18 尾垫注入：只给**有内容的包裹型结构**，且塞在**花括号之内**', () {
    test(r'\sqrt{2} → 一个尾垫，插在内容末尾、收尾 `}` 之前', () {
      final String t = renderMathTex(r'\sqrt{2}', caretRel: -1);
      expect(t, '\\sqrt{2$kStructTailTex}',
          reason: '尾垫必须在**花括号之内** —— 装饰（横线）才会跟着变长');
    });

    test(r'\sqrt{} 空槽 → **不注尾垫**（占位方框已经在槽里了）', () {
      final String t = renderMathTex(r'\sqrt{}', caretRel: -1);
      expect(t.contains(kStructTailTex), isFalse, reason: '实际：$t');
      expect(t.contains(kEmptySlotTex), isTrue, reason: '空槽仍要有占位：$t');
    });

    test(r'分式**不注**尾垫（分数线本来就超出分子分母）', () {
      final String t = renderMathTex(r'\frac{a}{b}', caretRel: -1);
      expect(t.contains(kStructTailTex), isFalse, reason: '实际：$t');
    });

    test('★ 两个光标因此分开：内容末尾在尾垫**之前**、结构末尾在**之后**', () {
      const String tex = r'\sqrt{2}';
      expect(renderMathTex(tex, caretRel: 7), '\\sqrt{2$kCursorTex$kStructTailTex}',
          reason: '内容末尾（rel 7）的光标要贴在式子右缘 ⇒ 在尾垫**之前**');
      expect(renderMathTex(tex, caretRel: tex.length),
          '\\sqrt{2$kStructTailTex}$kCursorTex',
          reason: '结构末尾（tex 末尾）的光标要落在横线末端 ⇒ 在尾垫**之后**');
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 二、命中表（纯函数）：尾垫要算**一个**原子，且点它回到**结构末尾**
  // ─────────────────────────────────────────────────────────────
  group('§11.18 命中映射：尾垫 = 合成原子 + 落在结构末尾', () {
    test('尾垫在命中原子表里**恰好算一个**原子（顺序在渲染序上）', () {
      final String t = renderMathTex(r'\sqrt{2}', caretRel: -1);
      final List<VisibleAtom> atoms = atomsForHitTest(t);
      expect(atoms.length, 2, reason: '`2` + 尾垫。实际：$atoms');
      expect(atoms.last.kind, 'tail');
      expect(t.substring(atoms.last.start, atoms.last.end), kStructTailTex);
    });

    test(r'点尾垫 → **结构末尾**（`\sqrt{2}` 的 tex 末尾 = 8）', () {
      final String t = renderMathTex(r'\sqrt{2}', caretRel: -1);
      final int at = t.indexOf(kStructTailTex);
      expect(renderToSourceOffset(t, at + 1), 8, reason: '尾垫内部 = 结构末尾');
      expect(renderToSourceOffset(t, at + kStructTailTex.length), 8);
    });

    test(r'★ 尾垫的**起点**仍是内容末尾（= `2` 的右边界，7）', () {
      final String t = renderMathTex(r'\sqrt{2}', caretRel: -1);
      final int at = t.indexOf(kStructTailTex);
      expect(renderToSourceOffset(t, at), 7,
          reason: '点式子的右半边必须仍能落到"内容末尾"——否则那一位点就再也点不到了');
    });

    test(r'裸参数 `\sqrt2`：内容末尾 == 结构末尾，尾垫不 +1', () {
      final String t = renderMathTex(r'\sqrt2', caretRel: -1);
      final int at = t.indexOf(kStructTailTex);
      expect(at >= 0, isTrue, reason: '实际：$t');
      expect(renderToSourceOffset(t, at), r'\sqrt2'.length,
          reason: '没有收尾 `}` ⇒ 插入点就是结构末尾');
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 三、★ 守门人：注入之后的「叶盒数 == 命中原子数」（不等就静默失效）
  // ─────────────────────────────────────────────────────────────
  group('★★ 守门人：注入 tex 的叶盒数 == 命中原子数（尾垫 / 占位 / 光标都在场）', () {
    const List<String> texs = <String>[
      r'\sqrt{2}',
      r'\sqrt{2}+1',
      r'\sqrt[3]{x}',
      r'x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}',
      r'\sqrt{}',
      r'\frac{}{}',
      r'\frac{a}{} + \sqrt{2}',
      r'\sqrt{\frac{a}{b}}',
      // ★ accent 家族（2026-10-15 晚修好装饰盒过滤之后加进来；
      //    更全的一组在 `decoration_boxes_test.dart` 的守门人里）
      r'\overline{AB}',
      r'\hat{x}',
      r'\bar{x}',
      r'\overrightarrow{AB}',
      r'\overbrace{AB}',
    ];

    testWidgets('每个 tex × 几种光标态', (WidgetTester tester) async {
      for (final String tex in texs) {
        for (final int caretRel in <int>[-1, 0, tex.length]) {
          final String renderTex = renderMathTex(tex, caretRel: caretRel);
          final GlobalKey key = GlobalKey();
          final RenderBox ro = await _pumpMath(tester, renderTex, key);
          final LeafBoxScan scan = scanLeafBoxes(ro);
          final List<VisibleAtom> atoms = atomsForHitTest(renderTex);
          expect(scan.eligible.length, atoms.length,
              reason: '「$tex」caretRel=$caretRel → `$renderTex`：'
                  '叶盒 ${scan.eligible.length} vs 命中原子 ${atoms.length}'
                  '（原始叶盒 ${scan.rawCount}）');
        }
      }
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 四、★ 端到端：点尾垫 = 结构末尾；点式子右缘 = 内容末尾
  // ─────────────────────────────────────────────────────────────
  group('§11.18 点击落点：尾垫 / 式子右缘 → 两个不同的位点', () {
    testWidgets('点尾垫**右半边** → 结构末尾；点 `2` 的右半边 → 内容末尾',
        (WidgetTester tester) async {
      const String tex = r'\sqrt{2}';
      final String renderTex = renderMathTex(tex, caretRel: -1);
      final GlobalKey key = GlobalKey();
      final RenderBox ro = await _pumpMath(tester, renderTex, key);
      final LeafBoxScan scan = scanLeafBoxes(ro);
      final List<VisibleAtom> atoms = atomsForHitTest(renderTex);
      expect(scan.eligible.length, atoms.length, reason: '守门人先过');

      // 尾垫 = 渲染序上的最后一个盒；点它的**右半边** = 指整个根号
      final Rect tail = scan.eligible.last.rect;
      final MathHit hitTail = hitTestMathTex(
        root: ro,
        localPos: Offset(tail.right - 1, tail.center.dy),
        tex: renderTex,
        atoms: atoms,
      );
      expect(hitTail.offset, isNotNull, reason: '点尾垫不该"没反应"');
      expect(renderToSourceOffset(renderTex, hitTail.offset!), tex.length,
          reason: '★ 点横线的那一截 = 指**整个根号**（结构末尾）');

      // 式子（`2`）的右半边 = 指根号**里面**
      final Rect digit = scan.eligible.first.rect;
      final MathHit hitDigit = hitTestMathTex(
        root: ro,
        localPos: Offset(digit.right - 1, digit.center.dy),
        tex: renderTex,
        atoms: atoms,
      );
      expect(renderToSourceOffset(renderTex, hitDigit.offset!), tex.length - 1,
          reason: '★ 点式子右缘 = 指**根号里面**（内容末尾）');

      // ★ 两者必须是**不同**的落点（这就是"像素区分"的可断言形态）
      expect(renderToSourceOffset(renderTex, hitTail.offset!),
          isNot(renderToSourceOffset(renderTex, hitDigit.offset!)));
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 五、★ **线型 / 拉伸 accent 家族**：同一个尾垫机制（2026-10-15 晚**已就位**）
  //
  //   前置条件原先没满足（所以这组曾是 `skip`）：accent 的**装饰自己就是一个叶盒**
  //     · `\overline{AB}` 的横线 = `[0..32.8 × 0..0.6]`（32.8 × **0.6 px**）
  //     · `\hat{x}` / `\tilde{x}` 更甚：装饰盒与字形盒**完全重合**（16 × 16）
  //   ⇒ 叶盒数 ≠ 原子数 ⇒ `hitTestMathTex` 静默返回 null（**既有 bug**：点不动）
  //
  //   ★ 2026-10-15 晚**已修**：`leaf_boxes.dart` 补两条判据（§11.21.2）——
  //     ③ **高度下限**（`0 < h < 2`）摘掉 0.6 px 的横线；④ **变音字形**（`^ ~ ˙ ¨ ˉ`）
  //     摘掉 accent 那"一个字"（几何上分不开，只能看它画的是什么）。
  //     据此 `kTailCommands` 收进**装饰墨迹跟着内容变长**的那几个（实测表见 §11.21.3）：
  //       `sqrt` `overline` `underline` `bar` `widehat` `widetilde` `overrightarrow`
  //     而**固定宽度标记**（`hat` `tilde` `dot` `ddot` `vec`）不加 —— 尾垫只撑盒、墨迹不动，
  //     加了也看不见（要"看得见"只能自绘，低优先；见 §11.21 结论第 2 条）。
  // ─────────────────────────────────────────────────────────────
  group('§11.21.3 线型 / 拉伸 accent 家族：同一个尾垫机制', () {
    test(r'\overline{AB} → 尾垫插在花括号之内（横线跟着变长）', () {
      expect(renderMathTex(r'\overline{AB}', caretRel: -1),
          '\\overline{AB$kStructTailTex}');
    });

    test(r'★ 两个光标分开：内容末尾在尾垫**之前**、结构末尾在**之后**', () {
      const String tex = r'\overline{AB}'; // 长度 13；内容末尾 12、结构末尾 13
      expect(renderMathTex(tex, caretRel: 12),
          '\\overline{AB$kCursorTex$kStructTailTex}');
      expect(renderMathTex(tex, caretRel: tex.length),
          '\\overline{AB$kStructTailTex}$kCursorTex');
    });

    test(r'★ 点尾垫 → **结构末尾**（`\overline{AB}` 的 tex 末尾 = 13）', () {
      final String t = renderMathTex(r'\overline{AB}', caretRel: -1);
      final int at = t.indexOf(kStructTailTex);
      expect(renderToSourceOffset(t, at), 12);
      expect(renderToSourceOffset(t, at + 1), 13);
    });

    test('★ 名单：**装饰的墨迹跟着内容变长**的才加尾垫（实测表见设计稿 §11.21.3）', () {
      for (final String cmd in <String>[
        'sqrt', 'overline', 'underline',
        'widehat', 'widetilde', 'overrightarrow',
      ]) {
        expect(renderMathTex('\\$cmd{AB}', caretRel: -1), '\\$cmd{AB$kStructTailTex}',
            reason: '`\\$cmd` 的装饰会跟着内容变长 ⇒ 应当在 kTailCommands 里');
      }
      // 反面：**定宽字形**的 accent 不加 —— 尾垫只撑盒、墨迹不动 ⇒ 加了也看不见
      // ★ `bar` 原先在正面名单里，2026-10-15 晚读引擎源码后**移到反面**
      //   （它 ∈ `nonStretchyAccents`；那次探针只看盒宽，误当成拉伸字形）
      for (final String cmd in <String>['hat', 'tilde', 'dot', 'ddot', 'vec', 'bar']) {
        expect(renderMathTex('\\$cmd{AB}', caretRel: -1), '\\$cmd{AB}',
            reason: '`\\$cmd` 是**定宽字形** ⇒ 不加尾垫（它的内容末尾另有专门规则，'
                '见 render/attachment.dart 的 kFixedShapeAccents）');
      }
      // 分式也不需要：分数线本来就超出分子分母
      expect(renderMathTex(r'\frac{a}{b}', caretRel: -1), r'\frac{a}{b}');
    });

    testWidgets(r'★ 端到端：点横线那一截 + `⌫` ⇒ **整个 \overline{AB} 走**（留空壳）',
        (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer(r'$\overline{AB}$尾');
      await _mountEdit(tester, buf);
      await tester.pumpAndSettle();

      final Offset tl = tester.getTopLeft(find.byType(Math));
      final RenderObject root =
          tester.renderObject<RenderObject>(find.byType(Math));
      final LeafBoxScan scan = scanLeafBoxes(root);
      final Rect tail = scan.eligible.last.rect;
      await tester.tapAt(tl + Offset(tail.right - 1, tail.center.dy));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      expect(buf.buf, r'$$尾',
          reason: '★ 点横线末端 + ⌫ 应当删掉**整个 `$kOverlineTex`**；实际：${buf.buf}');
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 五、★★ 端到端（用户看得见的那一步）：
  //    点横线那一截 + `⌫` = **整个根号走**；点式子右缘 + `⌫` = **只删 `2`**
  // ─────────────────────────────────────────────────────────────
  group('§11.18 端到端：两个像素 → 两种删除结果', () {
    /// 找到当前 Math 的两个盒：`2`（第一个）与尾垫（最后一个）
    ({Rect digit, Rect tail}) boxes(WidgetTester tester) {
      final RenderObject root =
          tester.renderObject<RenderObject>(find.byType(Math));
      final LeafBoxScan scan = scanLeafBoxes(root);
      return (digit: scan.eligible.first.rect, tail: scan.eligible.last.rect);
    }

    testWidgets('点尾垫（横线那一截）→ 整个根号消失，留下空壳', (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer(r'$\sqrt{2}$尾');
      await _mountEdit(tester, buf);
      await tester.pumpAndSettle();

      final Offset tl = tester.getTopLeft(find.byType(Math));
      final ({Rect digit, Rect tail}) b = boxes(tester);
      await tester.tapAt(tl + Offset(b.tail.right - 1, b.tail.center.dy));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      expect(buf.buf, r'$$尾',
          reason: '★ 点横线末端 + ⌫ 应当删掉**整个根号**（结构层）');
    });

    testWidgets('点式子右缘 → 只删 `2`，根号还在（出现空位框）',
        (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer(r'$\sqrt{2}$尾');
      await _mountEdit(tester, buf);
      await tester.pumpAndSettle();

      final Offset tl = tester.getTopLeft(find.byType(Math));
      final ({Rect digit, Rect tail}) b = boxes(tester);
      await tester.tapAt(tl + Offset(b.digit.right - 1, b.digit.center.dy));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      expect(buf.buf, r'$\sqrt{}$尾',
          reason: '★ 点式子右缘 + ⌫ 应当只删内容（内容层），根号留着');
    });
  });
}
