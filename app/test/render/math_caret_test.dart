// ★★ 光标 = **零尺寸锚点 + 自绘竖条**（2026-10-15 晚，用户拍板「高度可控 + 不参与排版」）
//
// 为什么要改（用户实测抓出的"跳"）：
//   引擎自带的 `\cursor{}` 是一根 **1.5 × 14 px** 的实心竖条，它**真的参与排版** ——
//   实测 `\hat{x}`：Math 盒 16.00 × 11.11 → **17.50 × 18.22**、里面那个 `x` 下移 **5.4 px**，
//   而 accent 的装饰**不跟着走** ⇒ 看起来"帽子跟字脱开、跳了一下"。
//
// 本文件钉住三条：
//   ① ★★ **不变量：光标一个像素的版面都不占**（Math 盒尺寸 + 除锚点外**所有叶盒**逐个相同）；
//   ② 竖条**在**（光标在这段里）/ **不在**（光标不在这段里），且与文本侧同高同色；
//   ③ 锚点在渲染树里**认得出来**（认不出来 ⇒ 竖条就没位置 ⇒ 这条守卫会当场红）。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/leaf_boxes.dart';
import 'package:mathlang/render/math_caret.dart';
import 'package:mathlang/render/slot_marks.dart';

const double kFontSize = 16;

Future<void> _pump(WidgetTester tester, String tex, {required bool caret}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: MathWithCaret(
          tex: tex,
          showCaret: caret,
          mathKey: GlobalKey(),
          fontSize: kFontSize,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// 所有叶盒（含 0×0 的锚点）
List<Rect> _leaves(WidgetTester tester) {
  final RenderObject root = tester.renderObject<RenderObject>(find.byType(Math));
  final List<Rect> out = <Rect>[];
  void walk(RenderObject o) {
    var hasChild = false;
    o.visitChildren((RenderObject c) {
      hasChild = true;
      walk(c);
    });
    if (!hasChild && o is RenderBox && o.hasSize) {
      out.add(o.localToGlobal(Offset.zero, ancestor: root) & o.size);
    }
  }

  walk(root);
  return out;
}

/// 竖条 = 我们画的那条：**直接包着 `Math` 的那个 `CustomPaint`** 的 foregroundPainter
/// （框架自己也会用 CustomPaint ⇒ 必须精确认我们自己那一个）
bool _hasBar(WidgetTester tester) {
  for (final CustomPaint p in tester.widgetList<CustomPaint>(
      find.byType(CustomPaint))) {
    if (p.child is Math) return p.foregroundPainter != null;
  }
  return false;
}

void main() {
  // ─────────────────────────────────────────────────────────────
  // 一、★★ 不变量：光标**不参与排版**
  // ─────────────────────────────────────────────────────────────
  group('★★ 不变量：光标不参与排版（一个像素都不占）', () {
    const List<String> texs = <String>[
      r'\hat{x}',
      r'\bar{y}',
      r'x^2',
      r'\frac{a}{b}',
      r'\sqrt{2}',
      r'\overline{AB}',
      r'\sum_{i=1}^{n}a_i',
    ];

    testWidgets('Math 盒尺寸 + 除锚点外的所有叶盒：无光标 vs 有光标**逐个相同**',
        (WidgetTester tester) async {
      for (final String tex in texs) {
        // 无光标（caretRel = -1 ⇒ 不注锚点）
        await _pump(tester, renderMathTex(tex, caretRel: -1), caret: false);
        final Size noCaret = tester.getSize(find.byType(Math));
        final List<Rect> noLeaves = _leaves(tester);

        // 有光标（注在**内容各种位置**：段首 / 段中 / 段末）
        for (final int rel in <int>[0, tex.length ~/ 2, tex.length]) {
          final String rt = renderMathTex(tex, caretRel: rel);
          if (!rt.contains(kCursorTex)) continue; // 该偏移没注（例如降级）
          await _pump(tester, rt, caret: true);
          expect(tester.getSize(find.byType(Math)), noCaret,
              reason: '「$tex」rel=$rel：光标**不许**改变 Math 盒尺寸'
                  '（这就是"跳"的根因：引擎那根 14 px 光标条把 `\\hat{x}` 从 16×11.11 撑成 17.5×18.22）');
          // 叶盒：锚点（0×0）会多出来一个，其余必须**逐个**对上
          final List<Rect> withLeaves = _leaves(tester)
              .where((Rect r) => r.width != 0 || r.height != 0)
              .toList();
          expect(withLeaves.length, noLeaves.length,
              reason: '「$tex」rel=$rel：除锚点外的叶盒**个数**不许变');
          for (var i = 0; i < noLeaves.length; i++) {
            // ⚠️ 位置容差 1px：**定宽 accent + 斜体基座**时，锚点会成为内容的"最后一个原子"，
            //    引擎按它重算 skew/斜体修正 ⇒ 装饰可能重新对中 ~0.9px（实测 `\bar{y}`）。
            //    这**不是**"参与排版"（Math 盒尺寸严格相同 ✓），也看不见。
            expect((withLeaves[i].topLeft - noLeaves[i].topLeft).distance,
                lessThan(1.0),
                reason: '「$tex」rel=$rel：第 $i 个叶盒左上角位移过大'
                    '（${withLeaves[i]} vs ${noLeaves[i]}）');
            expect((withLeaves[i].bottomRight - noLeaves[i].bottomRight).distance,
                lessThan(1.0),
                reason: '「$tex」rel=$rel：第 $i 个叶盒右下角位移过大'
                    '（${withLeaves[i]} vs ${noLeaves[i]}）');
          }
          // 锚点确实在（否则上面那条是假通过）
          expect(_leaves(tester).any((Rect r) => r.width == 0 && r.height == 0),
              isTrue, reason: '「$tex」rel=$rel：找不到零尺寸锚点');
        }
      }
    });

    testWidgets('★ 锚点认得出来（`findCaretAnchor`），且**恰好一个**',
        (WidgetTester tester) async {
      await _pump(tester, renderMathTex(r'\hat{x}', caretRel: 6), caret: true);
      final RenderObject root =
          tester.renderObject<RenderObject>(find.byType(Math));
      expect(findCaretAnchor(root), isNotNull);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 二、竖条：在 / 不在，以及**高度随当地那一行自适应**
  // ─────────────────────────────────────────────────────────────
  group('竖条：光标在这段里才画', () {
    testWidgets('光标在里面 ⇒ 有一根竖条', (WidgetTester tester) async {
      await _pump(tester, renderMathTex(r'\hat{x}', caretRel: 6), caret: true);
      expect(_hasBar(tester), isTrue);
    });

    testWidgets('光标不在这段里 ⇒ 一根都不画（但空槽占位照旧）',
        (WidgetTester tester) async {
      await _pump(tester, renderMathTex(r'\hat{x}', caretRel: -1), caret: false);
      expect(_hasBar(tester), isFalse);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 二之二、★★ 高度自适应（用户第二轮实测：「分母的光标会顶穿分数线、
  //          根号里的会顶穿根号」—— 固定 20 px 高在 10–11 px 高的行里必然捅出去）
  // ─────────────────────────────────────────────────────────────
  group('★★ 竖条高度随当地那一行自适应（不许顶穿分数线 / 根号）', () {
    /// 取当前竖条
    Rect barOf(WidgetTester tester) {
      for (final CustomPaint p
          in tester.widgetList<CustomPaint>(find.byType(CustomPaint))) {
        if (p.child is Math) {
          return (p.foregroundPainter! as MathCaretPainter).rect;
        }
      }
      fail('找不到竖条');
    }

    /// 数学段里全部字形盒（¶）
    List<Rect> glyphsOf(WidgetTester tester) {
      final RenderObject root =
          tester.renderObject<RenderObject>(find.byType(Math));
      final List<Rect> out = <Rect>[];
      void walk(RenderObject o) {
        var hasChild = false;
        o.visitChildren((RenderObject c) {
          hasChild = true;
          walk(c);
        });
        if (!hasChild &&
            o is RenderBox &&
            o.hasSize &&
            o.size != Size.zero &&
            o.runtimeType.toString().contains('Paragraph')) {
          out.add(o.localToGlobal(Offset.zero, ancestor: root) & o.size);
        }
      }

      walk(root);
      return out;
    }

    testWidgets('★ 分式**分母**里的光标：整体待在分母那一格里，**没有越过分数线**',
        (WidgetTester tester) async {
      // `\frac{a}{b}` 的项表：0-4 命令 / 5 { / 6  / 7 } / 8 { / 9  ⇒ 分母内容起点 = 9
      await _pump(tester, renderMathTex(r'\frac{a}{b}', caretRel: 9), caret: true);
      final Rect bar = barOf(tester);
      final List<Rect> gl = glyphsOf(tester);
      final Rect num = gl.first, den = gl.last; // 先分子后分母（源码顺序）
      expect(bar.top, greaterThan(num.bottom),
          reason: '★ 竖条必须在**分子那一格的下方**（分数线就画在两格之间）'
              '：bar=$bar 分子=$num 分母=$den');
      expect(bar.top, greaterThanOrEqualTo(den.top - 2),
          reason: '竖条上端不许超出分母那一格：bar=$bar 分母=$den');
      expect(bar.bottom, lessThanOrEqualTo(den.bottom + 2));
    });

    testWidgets(r'★ 根号里的光标：待在内容格里，没有越过根号横线',
        (WidgetTester tester) async {
      await _pump(tester, renderMathTex(r'\sqrt{x}', caretRel: 6), caret: true);
      final Rect bar = barOf(tester);
      final Rect content = glyphsOf(tester).single;
      expect(bar.top, greaterThanOrEqualTo(content.top - 2),
          reason: '竖条上端不许超出被开方数那一格（横线在它上面）：bar=$bar');
      expect(bar.bottom, lessThanOrEqualTo(content.bottom + 2));
    });

    testWidgets('★ **上标/下标**（0.7 倍字号）⇒ 竖条自动变矮（比主行短）',
        (WidgetTester tester) async {
      await _pump(tester, renderMathTex(r'x^{2}', caretRel: 0), caret: true);
      final double main = barOf(tester).height;
      await _pump(tester, renderMathTex(r'x^{2}', caretRel: 3), caret: true);
      final double script = barOf(tester).height;
      expect(script, lessThan(main),
          reason: '脚本行的字号是主行的 0.7 倍 ⇒ 竖条也必须跟着矮（主行 $main，脚本 $script）');
    });

    testWidgets('★ 主行的竖条高度 ≈ 字形盒高度（不是固定 20 px）',
        (WidgetTester tester) async {
      await _pump(tester, renderMathTex(r'x+1', caretRel: 1), caret: true);
      final Rect bar = barOf(tester);
      final Rect glyph = glyphsOf(tester).first;
      expect(bar.height, lessThan(glyph.height),
          reason: '竖条在字形盒里（上下各留 8% 内缩）：bar=$bar 字形=$glyph');
      expect(bar.height, greaterThan(glyph.height * 0.7),
          reason: '也不许缩得太小：bar=$bar 字形=$glyph');
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 三、注入本身：锚点是零尺寸的，且**词法上 0 个原子**
  // ─────────────────────────────────────────────────────────────
  group('锚点：零尺寸 + 0 个可见原子（命中测试两边都不用补账）', () {
    test(r'`kCursorTex` 是 `\rule{0pt}{0pt}`（包在 `\textcolor` 里以保证脚本安全）', () {
      expect(kCursorTex.contains(r'\rule{0pt}{0pt}'), isTrue);
      expect(kCursorTex.contains(r'\cursor'), isFalse,
          reason: '引擎那根 14 px 的实心竖条**不再**由 tex 注入');
    });

    testWidgets('锚点渲染成 0×0 的盒子 ⇒ 不被 `scanLeafBoxes` 收进有效叶盒',
        (WidgetTester tester) async {
      await _pump(tester, renderMathTex(r'\hat{x}', caretRel: 6), caret: true);
      final RenderObject root =
          tester.renderObject<RenderObject>(find.byType(Math));
      final LeafBoxScan scan = scanLeafBoxes(root);
      expect(scan.eligible.any((LeafBox b) => b.rect.width == 0), isFalse);
      expect(scan.eligible.length, 1,
          reason: r'`\hat{x}` 只有一个可见原子（`x`）—— 锚点不该进来');
    });
  });
}
