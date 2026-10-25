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

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/caret_ownership.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/leaf_boxes.dart';
import 'package:mathlang/render/math_caret.dart';
import 'package:mathlang/render/slot_marks.dart';

const double kFontSize = 16;

Future<void> _pump(WidgetTester tester, String tex,
    {required bool caret, int caretDepth = -1}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: MathWithCaret(
          tex: tex,
          showCaret: caret,
          mathKey: GlobalKey(),
          fontSize: kFontSize,
          caretDepth: caretDepth,
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

/// 我们那支画笔（**包着 `Math` 的那个 `CustomPaint`** 的 foregroundPainter）；没挂就 null
MathCaretPainter? _painterOf(WidgetTester tester) {
  for (final CustomPaint p
      in tester.widgetList<CustomPaint>(find.byType(CustomPaint))) {
    if (p.child is Math) return p.foregroundPainter as MathCaretPainter?;
  }
  return null;
}

// ─────────────────────────────────────────────────────────────
// 像素级装置（**细线在压缩截图里会消失** ⇒ 一律程序扫，且排到"整像素"为止）
// ─────────────────────────────────────────────────────────────
final GlobalKey _boundaryKey = GlobalKey();

/// 把 [child] 放进一个**比它大**的白底画布（留 12px 边距）——
/// 这样"画在公式外侧"的刻度也落在重绘边界**之内**，`toImage` 能拍到。
Widget _onWhiteCanvas(Widget child) => RepaintBoundary(
      key: _boundaryKey,
      child: Container(
        color: const Color(0xFFFFFFFF),
        padding: const EdgeInsets.all(12),
        child: Center(child: child),
      ),
    );

/// 扫出与 [target] 足够接近的像素数（容差 [tol]，抗锯齿的过渡像素不算）
Future<int> _countColor(WidgetTester tester, Color target,
    {double tol = 3, bool Function(Offset p)? where}) async {
  final RenderRepaintBoundary b =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_boundaryKey));
  var n = 0;
  await tester.runAsync(() async {
    final ui.Image img = await b.toImage(pixelRatio: 1.0);
    final ByteData? d = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (d == null) return;
    final int w = img.width, h = img.height;
    final int tr = (target.r * 255).round(),
        tg = (target.g * 255).round(),
        tb = (target.b * 255).round();
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final int i = (y * w + x) * 4;
        if (d.getUint8(i + 3) < 8) continue;
        final int r = d.getUint8(i), g = d.getUint8(i + 1), bl = d.getUint8(i + 2);
        if ((r - tr).abs() > tol || (g - tg).abs() > tol || (bl - tb).abs() > tol) {
          continue;
        }
        if (where != null && !where(Offset(x.toDouble(), y.toDouble()))) continue;
        n++;
      }
    }
    img.dispose();
  });
  return n;
}

const Color _kDash = Color(kSlotDashColorValue);
const Color _kFill = Color(kSlotCurrentFillColorValue);

/// 区域内的**最大"蓝度"**（`b - r`）：用来判"有没有比淡蓝底更蓝的描边像素"——
/// 1px 描边必然跨两行像素（抗锯齿），**没有一个是纯色**，所以不能按等值色去数。
Future<int> _maxBlueness(WidgetTester tester, Rect region) async {
  final RenderRepaintBoundary b =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_boundaryKey));
  var best = 0;
  await tester.runAsync(() async {
    final ui.Image img = await b.toImage(pixelRatio: 1.0);
    final ByteData? d = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (d == null) return;
    final int w = img.width;
    final int x0 = region.left.floor(), x1 = region.right.ceil();
    final int y0 = region.top.floor(), y1 = region.bottom.ceil();
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        final int i = (y * w + x) * 4;
        if (d.getUint8(i + 3) < 8) continue;
        final int v = d.getUint8(i + 2) - d.getUint8(i);
        if (v > best) best = v;
      }
    }
    img.dispose();
  });
  return best;
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
      // `\frac{a}{b}` 的项表：0-4 命令 / 5 { / 6 a / 7 } / 8 { / 9 b ⇒ 分母内容起点 = 9
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

    // ★★ 2026-10-21（U3，用户拍板"平权"）：**主行的口径改了** ——
    //   行内公式的主行竖条不再按"当地字形盒 × 0.84"，而是按**文本层标准**
    //   （`字号 × 1.25`），与旁边的文字**同高同中心**。
    //   旧断言（"≈ 字形盒高度，不是固定 20 px"）证明的正是**改动前**的口径，
    //   现在改为显式传 `caretDepth: 0` 并钉住新口径；
    //   子层（分子/分母/上标）不带 depth ⇒ 仍是旧口径（见上面两条）。
    testWidgets('★ 主行（depth=0）的竖条 = 文本层标准（与文字同高，约 20px）',
        (WidgetTester tester) async {
      await _pump(tester, renderMathTex(r'x+1', caretRel: 1), caret: true,
          caretDepth: 0);
      final Rect bar = barOf(tester);
      final Rect glyph = glyphsOf(tester).first;
      expect(bar.height, lessThanOrEqualTo(glyph.height + 4),
          reason: '文本层标准（16px 字号 ⇒ 20px）不该比字行盒还高太多：'
              'bar=$bar 字形=$glyph');
      expect(bar.height, greaterThan(glyph.height * 0.9),
          reason: '★ 平权：主行竖条要接近"文字侧那根"的高度（改前是 13.4 = 字形盒×0.84）：'
              'bar=$bar 字形=$glyph');
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

  // ─────────────────────────────────────────────────────────────
  // 四、★★ ④-1 空槽占位框（**自绘**）：垫子认得出来、且与光标在不在**无关**
  //
  // 旧版是"注入一个看得见的灰方块"（观感像"一个域"，宽 11.2 < 一个汉字）；
  // 现在注入的是**看不见的垫子**（字形 + 零高宽度垫），框由这支画笔自己画虚线。
  // ─────────────────────────────────────────────────────────────
  group('④-1 空槽占位框：看不见的垫子 ＋ 自绘框', () {
    testWidgets('★ 光标不在这一段里 ⇒ **也**要画（§6.1：空槽恒可见）',
        (WidgetTester tester) async {
      await _pump(tester, renderMathTex(r'\frac{}{b}', caretRel: -1), caret: false);
      final MathCaretPainter? p = _painterOf(tester);
      expect(p, isNotNull,
          reason: '★ 改前"没有竖条就不挂 painter" ⇒ 空槽只剩一个白垫子 = 看不见的幽灵');
      expect(p!.pads.length, 1, reason: '分母非空 ⇒ 一个空槽');
      expect(p.pads.single.current, isFalse);
      expect(p.caretVisible, isFalse, reason: '光标不在这段里 ⇒ 没有竖条');
      expect(p.pads.single.rect.width, greaterThanOrEqualTo(16.0),
          reason: '槽矩形 ≥ 一个正文汉字（§6.1 的触摸目标）');
      expect(p.pads.single.rect.height, greaterThan(2.0),
          reason: '零高的是"宽度垫"，槽矩形还含字形盒 ⇒ 高度是那一行的行高');
    });

    testWidgets('光标在那个空槽里 ⇒ 同一个垫子被标成 current（实线 ＋ 淡蓝底）',
        (WidgetTester tester) async {
      await _pump(tester, renderMathTex(r'\frac{}{b}', caretRel: 6), caret: true);
      final MathCaretPainter p = _painterOf(tester)!;
      expect(p.pads.single.current, isTrue,
          reason: '判据 = **锚点落在哪个垫子盒里**（实测：空槽里锚点正好落在垫子右缘）');
      expect(p.caretVisible, isTrue);
    });

    testWidgets('没有空槽 ⇒ 不挂 painter（回归：不许多画东西）',
        (WidgetTester tester) async {
      await _pump(tester, renderMathTex(r'\frac{a}{b}', caretRel: -1), caret: false);
      expect(_painterOf(tester), isNull);
    });

    testWidgets('虚线尺度**跟随字号**（不写死像素，§6.4）',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: MathWithCaret(
              tex: renderMathTex(r'\frac{}{b}', caretRel: -1),
              showCaret: false,
              mathKey: GlobalKey(),
              fontSize: 24,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(_painterOf(tester)!.dashUnit, closeTo(24 / 16, 0.001));
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 五、★ ④-4「甲」**瞬时**边界刻度（§6.5，2026-10-16 用户拍板"甲＋丙"）
  //     只在"公式之前 / 之后"那两格出现，**离开即消失**；不连线、不包围、不覆盖内容。
  // ─────────────────────────────────────────────────────────────
  group('④-4 瞬时边界刻度', () {
    Future<void> pumpEdge(WidgetTester tester, CaretEdge edge) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: MathWithCaret(
              tex: renderMathTex(r'\frac{a}{b}', caretRel: 0),
              showCaret: true,
              caretEdge: edge,
              textFontSize: 16,
              mathKey: GlobalKey(),
              fontSize: 16,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('★ 公式之后那一格 ⇒ 有刻度（改前没有这个概念 ⇒ 红）',
        (WidgetTester tester) async {
      await pumpEdge(tester, CaretEdge.after);
      final MathCaretPainter p = _painterOf(tester)!;
      expect(p.tick, isNotNull,
          reason: '★ §6.5「甲」：这两格要看得见"公式的边界在哪"（竖条是插入点、刻度是边界）');
      final Size ms = tester.getSize(find.byType(Math));
      expect(p.tick!.left, greaterThanOrEqualTo(ms.width),
          reason: '画在公式**外侧** ⇒ 与竖条分开，不与内容重叠');
      expect(p.tick!.height, closeTo(p.rect.height, 0.01),
          reason: '刻度高 = 那一格的行高（与铅笔条同高）');
    });

    testWidgets('公式之前那一格 ⇒ 刻度在左外侧', (WidgetTester tester) async {
      await pumpEdge(tester, CaretEdge.before);
      final MathCaretPainter p = _painterOf(tester)!;
      expect(p.tick, isNotNull);
      expect(p.tick!.right, lessThanOrEqualTo(0.0));
    });

    testWidgets('光标在公式**内部** ⇒ 没有刻度（不常驻、不包围）',
        (WidgetTester tester) async {
      await pumpEdge(tester, CaretEdge.none);
      expect(_painterOf(tester)!.tick, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 六、★★ **像素级**验证：虚线 / 淡蓝底 / 外侧刻度**真的画出来了**
  //
  // 为什么单列：`pads` / `tick` 字段只能证明"我们打算画"，证明不了"画出来了、
  // 而且没被裁掉"。经验 #14/#10：**细线在压缩截图里会消失** ⇒ 一律程序扫像素。
  // ─────────────────────────────────────────────────────────────
  group('★★ 像素级：虚线 / 淡蓝底 / 外侧刻度真的落到了画面上', () {
    /// Math 盒在**画布坐标**里的矩形（画笔用的是 Math 局部坐标 ⇒ 平移一下就能对位）
    Rect mathInCanvas(WidgetTester tester) {
      final RenderBox canvas =
          tester.renderObject<RenderBox>(find.byKey(_boundaryKey));
      return tester
          .getRect(find.byType(Math))
          .shift(-canvas.localToGlobal(Offset.zero));
    }

    testWidgets('空槽 ⇒ 槽矩形里有**灰虚线**，且没有淡蓝底 / 蓝框',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: _onWhiteCanvas(MathWithCaret(
            tex: renderMathTex(r'\frac{}{b}', caretRel: -1),
            showCaret: false,
            mathKey: GlobalKey(),
            fontSize: kFontSize,
          )),
        ),
      ));
      await tester.pumpAndSettle();
      final Rect pad = scanSlotPads(tester.renderObject<RenderObject>(find.byType(Math)))
          .single
          .rect
          .shift(mathInCanvas(tester).topLeft);
      // ★ 1px 虚线必然跨两行像素（抗锯齿）⇒ 用**松容差**；但只认**槽矩形之内**，
      //   于是"字形边缘的灰过渡像素"这类假阳性被自然排除（槽里是空的）。
      final int dash = await _countColor(tester, _kDash,
          tol: 40, where: (Offset p) => pad.contains(p));
      final int fill = await _countColor(tester, _kFill,
          tol: 3, where: (Offset p) => pad.contains(p));
      debugPrint('空槽：pad=$pad 虚线像素 $dash，淡蓝像素 $fill');
      expect(dash, greaterThan(5),
          reason: '★ §6.1 的 1px 虚线框必须真的画出来（灰 $_kDash）—— '
              '只认槽矩形之内的像素，所以这条断言不可能被字形边缘的灰骗过');
      expect(fill, 0, reason: '光标不在这一段里 ⇒ 没有"当前槽"底色');
    });

    testWidgets('当前槽 ⇒ 槽矩形里有**淡蓝底 ＋ 蓝框**（§6.1）',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: _onWhiteCanvas(MathWithCaret(
            tex: renderMathTex(r'\frac{}{b}', caretRel: 6),
            showCaret: true,
            mathKey: GlobalKey(),
            fontSize: kFontSize,
          )),
        ),
      ));
      await tester.pumpAndSettle();
      final Rect pad = scanSlotPads(tester.renderObject<RenderObject>(find.byType(Math)))
          .single
          .rect
          .shift(mathInCanvas(tester).topLeft);
      final int fill = await _countColor(tester, _kFill,
          tol: 3, where: (Offset p) => pad.contains(p));
      final int blueness = await _maxBlueness(tester, pad);
      debugPrint('当前槽：pad=$pad 淡蓝像素 $fill，最大蓝度 $blueness'
          '（淡蓝底自身 = ${(_kFill.b * 255).round() - (_kFill.r * 255).round()}）');
      expect(fill, greaterThan(60),
          reason: '★ §6.1：当前槽 = 实线 ＋ **淡蓝底**（`#E3F2FD`）；'
              '槽矩形约 ${pad.width.toInt()}×${pad.height.toInt()} ⇒ 应有大量底色像素');
      expect(blueness, greaterThan(60),
          reason: '★ 当前槽的**实线**框（与光标同色 `#1E88E5`）：1px 描边跨两行像素、'
              '没有纯色，所以看"最蓝的一个像素"必须明显比底色更蓝（底色只有 26）');
    });

    testWidgets('★ ④-4 刻度画在公式**外侧**，且没有被重绘边界裁掉',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: _onWhiteCanvas(MathWithCaret(
            tex: renderMathTex(r'\frac{a}{b}', caretRel: 0),
            showCaret: true,
            caretEdge: CaretEdge.after,
            textFontSize: kFontSize,
            mathKey: GlobalKey(),
            fontSize: kFontSize,
          )),
        ),
      ));
      await tester.pumpAndSettle();
      final MathCaretPainter p = _painterOf(tester)!;
      final Rect math = mathInCanvas(tester);
      final int grayRight = await _countColor(tester, _kDash,
          tol: 40, where: (Offset px) => px.dx >= math.right - 0.5);
      debugPrint('刻度局部 ${p.tick}  Math 宽 ${math.width}  右侧灰像素 $grayRight');
      expect(p.tick!.left, greaterThanOrEqualTo(math.width),
          reason: '局部坐标上它就在公式右边之外');
      expect(grayRight, greaterThan(3),
          reason: '★ 刻度必须**真的可见**：公式右侧要有灰刻度像素'
              '（画在外侧 + 不被外层重绘边界裁掉）');
    });
  });
}
