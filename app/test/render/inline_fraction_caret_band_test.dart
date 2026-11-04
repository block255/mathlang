// N3c 真根因（2026-11-04 · 第四轮）：**行内分式后面那一格的竖条要落在主行带**。
//
// 现场（用户三张图 + 实测）：新建文档 → 打 `$\frac{a-x}{a+x}$` → `→` 出分式 → 点面板插 α
//   → 退格 ⇒ 竖条回到分式右缘，但**按分母画**。
//
// 根因（`math_caret._lineBoxCenterLocal`）：判"单行段"用的是**字号高度阈值**
//   `para.size.height > textCaretHeight × 1.6`。行内放一个分式时段盒变高
//   （18px 字号 ⇒ 段盒 37.0、阈值 36.0）⇒ 被当成"多行段" ⇒ 返回 null
//   ⇒ 上层退回 `rowBox.center`，而那个 rowBox 是**分母**那一行。
//   ★ 16px 字号下段盒 32.0 == 阈值 32.0、`>` 不成立 ⇒ 走对分支
//   —— 16px 正是测试默认字号，所以前几轮怎么都复现不出来。
//
// 修法：判据改成"**公式自己占了段高的 ≥70%**"（这一行就是它；多行段里公式只占一小截）。
//
// 改前必红：①（竖条中心落在分母字形带：126.35，而主行带中心 114.35）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/core/doc_settings.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/math_caret.dart';

import '../support/math_fonts.dart';

Future<DocBuffer> mount(WidgetTester t, String doc, int caret,
    {double fontSize = 18}) async {
  await t.pumpWidget(const SizedBox.shrink());
  final DocBuffer buf = DocBuffer(doc)..setCaret(caret);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 900,
        child: SingleChildScrollView(
          child: SizedBox(
            width: 793.7,
            child: EditView(
              buffer: buf,
              settings: DocSettings(bodyFontSize: fontSize),
            ),
          ),
        ),
      ),
    ),
  ));
  t.state<EditViewState>(find.byType(EditView)).focusInput();
  await t.pumpAndSettle();
  return buf;
}

/// 取竖条 + 分式那两条内层行的矩形（分子 / 分母）
({Rect bar, Rect num, Rect den})? probe(WidgetTester t) {
  final Element painterEl = find
      .byWidgetPredicate((Widget w) =>
          w is CustomPaint && w.foregroundPainter is MathCaretPainter)
      .evaluate()
      .first;
  final RenderBox root = painterEl.renderObject! as RenderBox;
  final MathCaretPainter p =
      (painterEl.widget as CustomPaint).foregroundPainter! as MathCaretPainter;
  if (!p.caretVisible) return null;
  final Rect bar = p.rect.shift(root.localToGlobal(Offset.zero));

  final List<Rect> rows = <Rect>[];
  void walk(RenderObject o) {
    if (o.runtimeType.toString().contains('RenderLine') && o is RenderBox) {
      final Rect r = o.localToGlobal(Offset.zero) & o.size;
      // 只要"比根行矮、且不是根行"的那些内层行
      if (r.height < root.size.height - 0.5) rows.add(r);
    }
    o.visitChildren(walk);
  }

  walk(root);
  if (rows.length < 2) return null;
  rows.sort((Rect a, Rect b) => a.top.compareTo(b.top));
  return (bar: bar, num: rows.first, den: rows.last);
}

void main() {
  setUpAll(() async {
    await loadMathFonts();
  });

  const String doc = r'$\frac{a-x}{a+x}$';

  testWidgets('① 18px 字号：行内分式 tex 末尾的竖条中心必须落在主行带',
      (WidgetTester t) async {
    await mount(t, doc, 16);
    final ({Rect bar, Rect num, Rect den})? m = probe(t);
    expect(m, isNotNull, reason: '分式的分子/分母行没找到');
    final double center = m!.bar.center.dy;
    // 主行带 = 分子行底 ~ 分母行顶
    expect(center, greaterThan(m.num.bottom - 2),
        reason: '竖条中心 $center 跑到分子上面去了');
    expect(center, lessThan(m.den.top + 2),
        reason: '改前：竖条中心 $center 落在**分母**那一带'
            '（分母行 ${m.den.top.toStringAsFixed(1)}..${m.den.bottom.toStringAsFixed(1)}）');
  });

  testWidgets('② 对照：字号 16（旧测试默认值）也不许倒退', (WidgetTester t) async {
    await mount(t, doc, 16, fontSize: 16);
    final ({Rect bar, Rect num, Rect den})? m = probe(t);
    expect(m, isNotNull);
    final double center = m!.bar.center.dy;
    expect(center, greaterThan(m.num.bottom - 2));
    expect(center, lessThan(m.den.top + 2));
  });
}
