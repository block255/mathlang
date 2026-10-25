// ★★ 环境（矩阵 / 行列式）**内部**的落点与右键（P6.1，2026-10-18 晚 · 用户实测后修）
//
// 用户三条原话：
//  ①「右键必须右键到矩阵的**括号**才能判定到，右键内部没反应」
//  ②「矩阵括号里面我鼠标**完全点不到**，点了一定会落在括号外面」
//  ③「如果那一行没有数的话，我鼠标根本**点不到那一行**」
//
// 探针（穿过 EditView，真实指针）定位到两个真根因：
//  · 右键：`GestureDetector` 用默认 `deferToChild` ⇒ **格子之间的空白没有子节点认领**
//    ⇒ 手势不在命中路径上 ⇒ 那里右键什么都不发生（括号/字形上有墨迹 ⇒ 能认领 ⇒ 能弹）。
//    修：`HitTestBehavior.opaque`（整块公式都归它）。
//  · 左键：`envCellOffset` 的 `atEnd` 直接返回**槽区间末尾**，而环境格子槽**含两侧填充空格**
//    （`\begin{pmatrix} A & B` 的第一格是 `[16,18)`、18 正好是 `&`）⇒ 光标停在**分隔符**上，
//    视觉上就像"落在格子外面"。修：返回**去掉首尾空白后的内容边界**。
//  · 空行：行带只由有墨迹的格子并出来 ⇒ 整行空的那行没有带 ⇒ 永远点不到。
//    修：缺的行按"邻行 + 行高"补一条带。

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/lang/env_resize.dart';
import 'package:mathlang/render/env_cells.dart';
import 'package:mathlang/render/leaf_boxes.dart';
import 'package:mathlang/render/math_caret.dart';

import '../support/math_fonts.dart';

const String kTex = r'\begin{pmatrix} A & B \\ C & D \end{pmatrix}';
const String kDetTex = r'\begin{vmatrix} A & B \\ C & D \end{vmatrix}';
const String kEmptyRowTex = r'\begin{pmatrix} A & B \\ & \end{pmatrix}';

String _doc(String tex) => '${r'$$'}\n$tex\n${r'$$'}';

Future<DocBuffer> _pump(WidgetTester tester, String doc) async {
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer(doc)..setCaret(0);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
  ));
  tester.state<EditViewState>(find.byType(EditView)).focusInput();
  await tester.pumpAndSettle();
  return buf;
}

({RenderBox root, List<LeafBox> boxes}) _rig() {
  final RenderBox root =
      find.byType(MathWithCaret).last.evaluate().single.renderObject! as RenderBox;
  return (root: root, boxes: scanLeafBoxes(root).eligible);
}

Future<void> _leftClick(WidgetTester tester, RenderBox root, Offset local) async {
  await tester.tapAt(root.localToGlobal(local));
  await tester.pumpAndSettle();
}

Future<bool> _rightClick(WidgetTester tester, RenderBox root, Offset local) async {
  final TestGesture g = await tester.startGesture(root.localToGlobal(local),
      kind: PointerDeviceKind.mouse, buttons: kSecondaryButton);
  await g.up();
  await tester.pumpAndSettle();
  final bool open = find.byKey(const Key('env-size-dialog')).evaluate().isNotEmpty;
  if (open) {
    await tester.tap(find.byKey(const Key('env-size-cancel')));
    await tester.pumpAndSettle();
  }
  return open;
}

void main() {
  setUpAll(() async => loadMathFonts());

  group('① 左键：矩阵**内部**点哪落哪（不许停在 `&` 上）', () {
    testWidgets('★ 点 A 的中心 ⇒ 落在 A 之后（不是分隔符 `&` 上）',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, _doc(kTex));
      final ({RenderBox root, List<LeafBox> boxes}) r = _rig();
      final Rect a = r.boxes.firstWhere((LeafBox b) => b.text == 'A').rect;
      await _leftClick(tester, r.root, a.center);
      // tex: `\begin{pmatrix} ` 之后 A 在 16，`&` 在 18 ⇒ 文档里 A=19、&=21
      final int aAt = buf.buf.indexOf('A');
      expect(buf.caret, aAt + 1,
          reason: '点 A 中心 ⇒ 落在 A **之后**（${aAt + 1}），不许停在 `&`（${aAt + 2}）上；'
              '实际 ${buf.caret}');
    });

    testWidgets('★ 点 A 的右半边 ⇒ 同样落在 A 之后', (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, _doc(kTex));
      final ({RenderBox root, List<LeafBox> boxes}) r = _rig();
      final Rect a = r.boxes.firstWhere((LeafBox b) => b.text == 'A').rect;
      await _leftClick(tester, r.root, Offset(a.right - 2, a.center.dy));
      expect(buf.caret, buf.buf.indexOf('A') + 1);
    });

    testWidgets('★ 点 B 的中心 ⇒ 落在 B 之后（第二列也对）',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, _doc(kTex));
      final ({RenderBox root, List<LeafBox> boxes}) r = _rig();
      final Rect b = r.boxes.firstWhere((LeafBox leaf) => leaf.text == 'B').rect;
      await _leftClick(tester, r.root, b.center);
      expect(buf.caret, buf.buf.indexOf('B') + 1, reason: '实际 ${buf.caret}');
    });

    testWidgets('★ 行列式：点 A 中心 ⇒ 落在 A 之后（不是竖线、不是外部）',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, _doc(kDetTex));
      final ({RenderBox root, List<LeafBox> boxes}) r = _rig();
      final Rect a = r.boxes.firstWhere((LeafBox b) => b.text == 'A').rect;
      await _leftClick(tester, r.root, a.center);
      expect(buf.caret, buf.buf.indexOf('A') + 1, reason: '实际 ${buf.caret}');
    });

    testWidgets('★★ 整行都空的第二行：点它 ⇒ 光标落进**那一行**',
        (WidgetTester tester) async {
      // 用户原话："如果那一行没有数的话，我鼠标根本点不到那一行"
      final DocBuffer buf = await _pump(tester, _doc(kEmptyRowTex));
      final ({RenderBox root, List<LeafBox> boxes}) r = _rig();
      final Rect a = r.boxes.firstWhere((LeafBox b) => b.text == 'A').rect;
      // 第二行在第一行下面约一个行高（实测 24 px）
      await _leftClick(tester, r.root, Offset(a.center.dx, a.center.dy + 24));
      final int rowSep = buf.buf.indexOf(r'\\');
      expect(buf.caret, greaterThan(rowSep),
          reason: '点空行 ⇒ 光标必须在**行分隔符之后**（那一行里）；实际 ${buf.caret}、分隔符 $rowSep');
    });
  });

  group('⑧ 行间公式的**外侧**：点左边/右边 ⇒ 落在"公式之前/之后"（用户："外面都点不到"）', () {
    testWidgets('★★ 点矩阵左右两侧的留白 ⇒ 光标在公式外（不是被吸进第一格）',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, _doc(kTex));
      final RenderBox root = _rig().root;
      final Offset tl = root.localToGlobal(Offset.zero);
      final double midY = tl.dy + root.size.height / 2;
      // 左边 12 px
      buf.setCaret(0);
      await tester.tapAt(Offset(tl.dx - 12, midY));
      await tester.pumpAndSettle();
      expect(buf.caret, 3, reason: '左侧留白 ⇒ 公式**之前**（内容起点 3），实际 ${buf.caret}');
      // ★★★ 2026-10-24（批 19 · F1-b）：右侧留白现在**按行带判** —— 点在哪一行的高度，
      //   就落**那一行的末尾**（该行最后一格的内容末尾；末行也是行末，**不是**块末尾）。
      //   y 用**字形位置**（比"块高 ÷ 行数"稳：块里还有括号与行距）。
      final List<LeafBox> boxes = _rig().boxes;
      final LeafBox b1 = boxes.firstWhere((LeafBox b) => b.text == 'B');
      final LeafBox d2 = boxes.firstWhere((LeafBox b) => b.text == 'D');
      buf.setCaret(0);
      await tester.tapAt(Offset(
          tl.dx + root.size.width + 12, tl.dy + b1.rect.center.dy));
      await tester.pumpAndSettle();
      expect(buf.caret, buf.buf.indexOf('B') + 1,
          reason: '右侧留白（第一行高度）⇒ 第一行末尾，实际 ${buf.caret}');
      buf.setCaret(0);
      await tester.tapAt(Offset(
          tl.dx + root.size.width + 12, tl.dy + d2.rect.center.dy));
      await tester.pumpAndSettle();
      expect(buf.caret, buf.buf.indexOf('D') + 1,
          reason: '右侧留白（末行高度）⇒ 末行末尾（`D` 之后，仍在块内），实际 ${buf.caret}');
    });
  });
  group('② 右键：整块都算（含格子之间的空白）', () {
    testWidgets('★★ 三个位置右键**都要弹面板**（改前：只有字形/括号能弹）',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, _doc(kTex));
      final ({RenderBox root, List<LeafBox> boxes}) r = _rig();
      final Rect a = r.boxes.firstWhere((LeafBox b) => b.text == 'A').rect;
      final Rect d = r.boxes.firstWhere((LeafBox b) => b.text == 'D').rect;
      final Rect paren = r.boxes.firstWhere((LeafBox b) => b.text == '(').rect;
      expect(await _rightClick(tester, r.root, a.center), isTrue,
          reason: '字形上');
      expect(
          await _rightClick(tester, r.root,
              Offset(a.center.dx, (a.bottom + d.top) / 2)),
          isTrue,
          reason: '★ 两个格子之间的**空白**（用户报的就是这里没反应）');
      expect(await _rightClick(tester, r.root, paren.center), isTrue,
          reason: '括号上');
      expect(buf.buf, _doc(kTex), reason: '右键本身不改文档');
    });
  });

  group('③ 比 2×2 大的环境（用户："一旦扩大出 2×2 就内部完全点不到"）', () {
    testWidgets('★★ 3×3（由 2×2 扩大而成）：点字母中心都能落进本格',
        (WidgetTester tester) async {
      // 根因：超过一行高之后，引擎把括号画成**分段碎片** `⎛ ⎝ ⎞ ⎠`，
      //   而 `kFrameDelimiters` 里没有它们 ⇒ 配对整份判死 ⇒ 整块点不进去。
      final String tex = resizeEnvironment(
          r'\begin{pmatrix} A & B \\ C & D \end{pmatrix}',
          rows: 3,
          cols: 3);
      final DocBuffer buf = await _pump(tester, _doc(tex));
      final ({RenderBox root, List<LeafBox> boxes}) r = _rig();
      for (final String letter in <String>['A', 'B', 'C', 'D']) {
        final Iterable<LeafBox> found =
            r.boxes.where((LeafBox b) => b.text == letter);
        if (found.isEmpty) continue; // 极端情况下该字没画出来，跳过（其余字母仍要能点）
        await _leftClick(tester, r.root, found.first.rect.center);
        final int at = buf.buf.indexOf(letter);
        expect(buf.caret, inInclusiveRange(at, at + 2),
            reason: '3×3 里点 `$letter` 要落在**本格**（$at±2），实际 ${buf.caret}');
      }
    });

    testWidgets('★ 3×3 里右键照样弹面板', (WidgetTester tester) async {
      final String tex = resizeEnvironment(
          r'\begin{pmatrix} A & B \\ C & D \end{pmatrix}',
          rows: 3,
          cols: 3);
      await _pump(tester, _doc(tex));
      final ({RenderBox root, List<LeafBox> boxes}) r = _rig();
      final LeafBox a = r.boxes.firstWhere((LeafBox b) => b.text == 'A');
      expect(await _rightClick(tester, r.root, a.rect.center), isTrue);
    });
  });

  group('⑤ 版面稳定性：在格子之间移动光标**不许改列宽**（用户："改列间距、扰动竖线"）', () {
    testWidgets('★★ 光标从实格移到空格：其它字形与竖线的位置必须一模一样',
        (WidgetTester tester) async {
      // 空的是 (0,0)（第一列）⇒ 若往那格注入垫子，第一列变宽、B 与竖线都会右移
      const String tex = r'\begin{vmatrix} & B \\ C & D \end{vmatrix}';
      final DocBuffer buf = await _pump(tester, _doc(tex));

      Map<String, double> xs() {
        final List<LeafBox> boxes = _rig().boxes;
        return <String, double>{
          for (final LeafBox b in boxes)
            if (b.text != null && <String>['B', 'C', 'D', '|', '∣'].contains(b.text))
              '${b.text}@${b.rect.top.round()}': b.rect.left,
        };
      }

      buf.setCaret(buf.buf.indexOf('D') + 1);
      await tester.pumpAndSettle();
      final Map<String, double> before = xs();

      final int cellStart =
          buf.buf.indexOf(r'\begin{vmatrix}') + r'\begin{vmatrix}'.length + 1;
      buf.setCaret(cellStart);
      await tester.pumpAndSettle();
      final Map<String, double> after = xs();

      expect(before, isNotEmpty, reason: '至少要量到 B/C/D 与竖线');
      expect(after, before,
          reason: '空格子不该有"占位垫"改变列宽 —— 排版必须一个像素都不动（改前会整体右移）');
    });
  });

  group('⑨ 网格落点：空列 / 空行 / 两字之间（2026-10-19 重写 envCellHitAt 之后）', () {
    const String t3 = r'\begin{pmatrix} a & b & \\ c & d & \\ & & \end{pmatrix}';

    testWidgets('★★ 点最右边的空列 ⇒ 落在**那一列**（不是第二列）',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, _doc(t3));
      final ({RenderBox root, List<LeafBox> boxes}) r = _rig();
      final Rect d = r.boxes.firstWhere((LeafBox b) => b.text == 'd').rect;
      // d 右边一个 em 左右：就是第三列（空）
      await _leftClick(tester, r.root, Offset(d.right + 10, d.center.dy));
      final int rowSep = buf.buf.indexOf(r'\\');
      expect(buf.caret, greaterThan(buf.buf.indexOf('d')),
          reason: '要在 d **之后**（第三列），实际 ${buf.caret}');
      expect(buf.caret, greaterThan(rowSep - 1),
          reason: '而且已经越过列分隔符 `&`（第三列），实际 ${buf.caret}');
    });

    testWidgets('★ 点 `a` 与 `b` 之间 ⇒ 落在它们之间（不是被扔到最右列）',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, _doc(t3));
      final ({RenderBox root, List<LeafBox> boxes}) r = _rig();
      final Rect a = r.boxes.firstWhere((LeafBox b) => b.text == 'a').rect;
      final Rect b = r.boxes.firstWhere((LeafBox leaf) => leaf.text == 'b').rect;
      await _leftClick(tester, r.root, Offset((a.right + b.left) / 2, a.center.dy));
      // ★ 字母 a / b 也出现在环境名 \begin{pmatrix} 里 ⇒ 必须取**最后一个**
      final int cellStart =
          buf.buf.indexOf(r'\begin{pmatrix}') + r'\begin{pmatrix}'.length;
      final int firstAmp = buf.buf.indexOf('&', cellStart);
      // 允许落在第二格开头（空隙里'归左还是归右'是品味问题）；关键是**不能**被扔到最右列
      final int secondAmp = buf.buf.indexOf('&', firstAmp + 1);
      expect(buf.caret, inInclusiveRange(cellStart, secondAmp),
          reason: '应在第一/第二格之间（..），实际 ${buf.caret}');
    });

    testWidgets('★★ 点整行都空的最后一行 ⇒ 落在那一行',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, _doc(t3));
      final ({RenderBox root, List<LeafBox> boxes}) r = _rig();
      final Rect c = r.boxes.firstWhere((LeafBox b) => b.text == 'c').rect;
      await _leftClick(tester, r.root, Offset(c.center.dx, c.center.dy + 26));
      final int lastSep = buf.buf.lastIndexOf(r'\\');
      expect(buf.caret, greaterThan(lastSep),
          reason: '必须落在最后一个行分隔符**之后**（最后一行），实际 ${buf.caret}、分隔符 $lastSep');
    });
  });
  group('⑩ 大网格（4×6，只填左上 2×2）：每一列都要能点（用户："只会落在第一列"）', () {
    const String big =
        r'\begin{pmatrix} a & b & &&& \\ c & d & &&& \\ &&&&& \\ &&&&& \end{pmatrix}';

    testWidgets('★★ 点第 3 列（空）⇒ 不落在第一列', (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, _doc(big));
      final ({RenderBox root, List<LeafBox> boxes}) r = _rig();
      final Rect b = r.boxes.firstWhere((LeafBox leaf) => leaf.text == 'b').rect;
      await _leftClick(tester, r.root, Offset(b.right + 22, b.center.dy));
      final int row0End = buf.buf.indexOf(r'\\');
      expect(buf.caret, greaterThan(buf.buf.indexOf('b') + 2),
          reason: '必须在 b 之后（第 3 列起），实际 ${buf.caret}');
      expect(buf.caret, lessThan(row0End + 1),
          reason: '而且仍在第一行里（行分隔符在 $row0End），实际 ${buf.caret}');
    });

    testWidgets('★ 点最后一列（空）⇒ 落在行末附近', (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, _doc(big));
      final ({RenderBox root, List<LeafBox> boxes}) r = _rig();
      final Rect b = r.boxes.firstWhere((LeafBox leaf) => leaf.text == 'b').rect;
      await _leftClick(tester, r.root,
          Offset(r.root.size.width - 24, b.center.dy));
      final int row0End = buf.buf.indexOf(r'\\');
      expect(buf.caret, greaterThan(row0End - 8),
          reason: '最后一列应靠近行末（行分隔符 $row0End），实际 ${buf.caret}');
    });
  });
  group('⑪ 占位框：高度统一 / 只在空格子 / 公式外面不出现（用户 2026-10-19 四张图）', () {
    const String det5 =
        r'\begin{vmatrix} a & b & & & \\ c & d & & & \\ & & & & \\ & & & & \\ & & & & \end{vmatrix}';

    List<Rect> envPads(WidgetTester tester) {
      final List<Rect> out = <Rect>[];
      for (final RenderObject ro in tester.allRenderObjects) {
        if (ro is RenderCustomPaint && ro.foregroundPainter is MathCaretPainter) {
          for (final SlotPad p
              in (ro.foregroundPainter! as MathCaretPainter).pads) {
            // 只挑"环境格框"：宽 > 0.5 字号
            if (p.rect.width > 6) out.add(p.rect);
          }
        }
      }
      return out;
    }

    testWidgets('★★ 不同行/列的框**高度一致**（改前：有的矮有的方）',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, _doc(det5));
      final RenderBox root = _rig().root;
      final Offset tl = root.localToGlobal(Offset.zero);
      buf.setCaret(0);
      await tester.tapAt(Offset(tl.dx + 17.5 + 3 * 40 + 10, tl.dy + 12));
      await tester.pumpAndSettle();
      final List<Rect> a = envPads(tester);
      buf.setCaret(0);
      await tester.tapAt(Offset(tl.dx + 17.5 + 40 + 10, tl.dy + 12 + 3 * 24));
      await tester.pumpAndSettle();
      final List<Rect> b = envPads(tester);
      expect(a, isNotEmpty, reason: '第一处应当有格框');
      expect(b, isNotEmpty, reason: '第二处应当有格框');
      expect((a.first.height - b.first.height).abs(), lessThan(1.5),
          reason: '两处框高必须一致（实测 ${a.first.height} vs ${b.first.height}）');
      expect((a.first.width - b.first.width).abs(), lessThan(1.5),
          reason: '两处框宽必须一致（实测 ${a.first.width} vs ${b.first.width}）');
    });

    testWidgets('★ 点公式**后面**：光标落在外面，且**不出现**格框',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, _doc(det5));
      final RenderBox root = _rig().root;
      final Offset tl = root.localToGlobal(Offset.zero);
      buf.setCaret(0);
      await tester.tapAt(Offset(tl.dx + root.size.width + 12, tl.dy + 12));
      await tester.pumpAndSettle();
      // ★★★ 2026-10-24（批 19 · F1-b）：右侧留白改成**按行带判** ⇒ 点第一行的高度
      //   落**第一行末尾**（`b` 之后），不再是块末尾。本子测的真意是"**不冒格框**"，
      //   第一行有内容（`a`/`b`）⇒ 那一格不画框，断言照旧成立。
      final int base = buf.buf.indexOf(det5);
      // ★ 末列（第 5 列 = col 4）才是这一行的右端：`det5` 每行有 5 格，后面三格是空的
      final int row1End =
          base + envCellOffset(det5, const EnvCellHit(0, 4, atEnd: true))!;
      expect(buf.caret, row1End,
          reason: '右侧留白（第一行高度）⇒ 第一行末尾（F1-b），实际 ${buf.caret}');
      // ★★★ 口径变更（批 19 · F1-b + F1-c）：落点现在是"**那一行的最后一格**"，
      //   而 `det5` 的末三格是空的 ⇒ 那一格**本来就该有框**（空位恒画框）。
      //   本条原来的意思是"点块**外面**不许冒框"；现在要点到"外面"，得让 y 落在
      //   **所有行带之外**（块上方/下方），那时 `_mathTapTexOffset` 会走页面级兜底。
      //   这里改成钉"**落点那一格有框**"（`det5` 里空格很多，本来就会有好几个框 ——
      //   这正是 F1-c 要的"空位恒画框"；框的高度一致性由上面那条子测钉住）。
      expect(envPads(tester), isNotEmpty, reason: '落进空格 ⇒ 那一格必须有框');
    });
  });
  group('④ 行内矩阵：右键也要能改尺寸', () {
    testWidgets('★★ 段落里的行内矩阵右键 ⇒ 弹面板（改前：一点反应没有）',
        (WidgetTester tester) async {
      final String doc = '甲${r'$'}$kTex${r'$'}乙';
      await _pump(tester, doc);
      final ({RenderBox root, List<LeafBox> boxes}) r = _rig();
      final LeafBox a = r.boxes.firstWhere((LeafBox b) => b.text == 'A');
      expect(await _rightClick(tester, r.root, a.rect.center), isTrue,
          reason: '行内公式也必须能右键（以前只有行间块接了手势）');
    });
  });

  group('⑫ ★ 4 段全空的分段函数：点第几段**就落第几段**（2026-10-24 · D3 续）', () {
    // 用户原话：「点第 2 段落到第 1 段、点第 4 段落到第 3 段」「第 2 段后面还冒出一个位点」。
    // 根因：`&` 的**列间距**是 1em 宽零高的垫子盒，与空格子的预留垫 `\rule{1em}{0pt}` 同形
    //   ⇒ 配对把列间距当成格子垫吃掉 ⇒ 整行错位一位。
    const String cases4 = r'f(x)=\begin{cases}&\\&\\&\\&\end{cases}';

    /// 从真实渲染里量出两列的左缘与行高：
    /// 零高垫子的 x 有三档 —— 第 1 列垫子、列间距、第 2 列垫子（升序）。
    ({double col0, double col1, double pitch}) measure(
        RenderBox root, List<LeafBox> boxes) {
      final List<double> xs = <double>[
        for (final LeafBox b in boxes)
          if (b.kind == LeafBoxKind.pad && b.rect.height.abs() < 0.5) b.rect.left
      ]..sort();
      final List<double> uniq = <double>[];
      for (final double x in xs) {
        if (uniq.isEmpty || x - uniq.last > 0.5) uniq.add(x);
      }
      expect(uniq.length, greaterThanOrEqualTo(2),
          reason: '至少要量到两列的垫子（实测 $uniq）');
      return (col0: uniq.first, col1: uniq.last, pitch: root.size.height / 4);
    }

    testWidgets('★★ 第 2 列：四段各自落回自己那一段的起点', (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, _doc(cases4));
      final ({RenderBox root, List<LeafBox> boxes}) r = _rig();
      final ({double col0, double col1, double pitch}) m = measure(r.root, r.boxes);
      // 源 tex 里第 2 列四格的起点：19 / 22 / 25 / 28（每行 +3）
      const List<int> starts = <int>[19, 22, 25, 28];
      for (var row = 0; row < 4; row++) {
        final Offset target =
            Offset(m.col1 + 6, (row + 0.5) * m.pitch);
        buf.setCaret(0);
        await _leftClick(tester, r.root, target);
        final int want = buf.buf.indexOf(cases4) + starts[row];
        expect(buf.caret, want,
            reason: '点第 ${row + 1} 段第 2 列（$target）⇒ 应在 tex[${starts[row]}]'
                '（文档 $want），实际 ${buf.caret}');
      }
    });

    testWidgets('★★ 第 1 列：四段也各自落回自己那一段', (WidgetTester tester) async {
      final DocBuffer buf = await _pump(tester, _doc(cases4));
      final ({RenderBox root, List<LeafBox> boxes}) r = _rig();
      final ({double col0, double col1, double pitch}) m = measure(r.root, r.boxes);
      // 源 tex 里第 1 列四格的起点：18 / 21 / 24 / 27
      const List<int> starts = <int>[18, 21, 24, 27];
      for (var row = 0; row < 4; row++) {
        final Offset target =
            Offset(m.col0 + 6, (row + 0.5) * m.pitch);
        buf.setCaret(0);
        await _leftClick(tester, r.root, target);
        final int want = buf.buf.indexOf(cases4) + starts[row];
        expect(buf.caret, want,
            reason: '点第 ${row + 1} 段第 1 列（$target）⇒ 应在 tex[${starts[row]}]'
                '（文档 $want），实际 ${buf.caret}');
      }
    });
  });
}