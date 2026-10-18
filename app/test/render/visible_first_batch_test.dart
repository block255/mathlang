// ④ 看得见（第一批，2026-10-15）：**可选槽占位** + **公式范围可见**
//
// §4.8 必填槽 / 可选槽（用户 2026-10-15 提出并拍板）：
//   · **必填槽**（分式分子分母 / 被开方数 / 普通上下标）⇒ 占位**恒可见**（§6.1）
//   · **可选槽**（`\sqrt[n]{…}` 的次数 · **算子的上下限 / 底数**，如 `\sum_{}^{}`、`\int_a^b`、`\log_{}`）
//     ⇒ 位点照样提供，但**空着不算问题**、占位**只在光标进入该结构时才画**（"不打扰"）
//
// §6.5 公式范围可见：光标落在某段数学里 ⇒ 给**整段**一个淡色范围（**自绘**，不改 tex）。
//   它解决"光标在公式里 / 公式外画在同一根像素上"（§3.3「甲」的由来与 W1）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/inline_math_text.dart';
import 'package:mathlang/render/slot_marks.dart';

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

/// 画面上有没有"公式范围"那层淡色（§6.5）
bool _hasRangeTint(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(find.byType(DecoratedBox))
    .any((DecoratedBox d) =>
        d.decoration is BoxDecoration &&
        (d.decoration as BoxDecoration).color == kMathRangeColor);

/// 空槽占位的个数
int _marks(String renderTex) =>
    RegExp(RegExp.escape(kEmptySlotTex)).allMatches(renderTex).length +
    RegExp(RegExp.escape(kCurrentSlotTex)).allMatches(renderTex).length;

void main() {
  // ─────────────────────────────────────────────────────────────
  // 一、§4.8 可选槽：只在光标进入该结构时才画
  // ─────────────────────────────────────────────────────────────
  group('§4.8 可选槽占位：只在光标进入该结构时才画', () {
    test(r'`\sum_{}^{}` 光标**不在**这段里 ⇒ 一个占位都不画（不打扰）', () {
      expect(_marks(renderMathTex(r'\sum_{}^{}', caretRel: -1)), 0);
    });

    test(r'`\sum_{}^{}` 光标**在**这个求和对象里 ⇒ 上下限两个占位都画', () {
      // rel 0 = `\sum` 之前（在作用域 [0, limitsEnd) 之内）
      expect(_marks(renderMathTex(r'\sum_{}^{}', caretRel: 0)), 2);
      // rel 9 = 上限槽里（当前槽 + 另一个可选槽）
      expect(_marks(renderMathTex(r'\sum_{}^{}', caretRel: 9)), 2);
    });

    test(r'`\log_{}x` 的底数槽同理（光标在 `\log x` 里就画）', () {
      expect(_marks(renderMathTex(r'\log_{}x', caretRel: -1)), 0);
      expect(_marks(renderMathTex(r'\log_{}x', caretRel: 0)), 1);
    });

    test(r'`\int_a^b` 这类上下限：光标不在里面就不画（不定积分不必填）', () {
      expect(_marks(renderMathTex(r'\int_{}^{}f', caretRel: -1)), 0);
      expect(_marks(renderMathTex(r'\int_{}^{}f', caretRel: 0)), 2);
    });

    test(r'`\sqrt[]{}`：可选次数槽跟着结构走，**被开方数**（必填）恒可见', () {
      // 光标不在 → 只画被开方数那一个（必填）
      expect(_marks(renderMathTex(r'\sqrt[]{}', caretRel: -1)), 1);
      // 光标在结构里（被开方槽里）→ 两个都画
      expect(_marks(renderMathTex(r'\sqrt[]{}', caretRel: 7)), 2);
    });

    test(r'★ 必填槽**恒可见**（分式、被开方数）—— 不管光标在不在这一段里', () {
      expect(_marks(renderMathTex(r'\frac{}{}', caretRel: -1)), 2);
      expect(_marks(renderMathTex(r'\sqrt{}', caretRel: -1)), 1);
      // ★★★ 2026-10-18 晚**改口径**：脚本槽从"挂件"里分出来 ——
      //   它是"可选槽"那一类：**光标在这段里就画**（不常驻）。
      //   起因：面板插入的 `\mathrm{C}_{}^{}` 在屏幕上只是一个 C（用户报"没给子位点"）。
      expect(_marks(renderMathTex(r'x^{}', caretRel: -1)), 0,
          reason: '光标不在这一段里 ⇒ 不画（不常驻）');
      expect(_marks(renderMathTex(r'x^{}', caretRel: 3)), 1,
          reason: '光标在空脚本里 ⇒ 画出落点（否则又一个"看不见的槽"）');
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 二、★ 过闸守卫：**不许把"渲染提示"画成"一个对象"**（2026-10-15 用户指出后立的）
  //
  //   §6.5 旧版给"光标所在的那一整段公式"刷了一层淡色底，用户一眼看出来：
  //   `$\frac{a}{b}=\sqrt{2}$` 是**三个对象**（分式 / `=` / 根号），
  //   一整块底色等于在说"这是**一整个**东西" ⇒ 那是**公式块**的观感
  //   （也正是过闸表 §7.2 里"公式有专用底色 = 症状"那一条）。
  //   ⇒ 这条守卫把它钉死：**数学段上不许出现"整段底色"这类整体视觉**；
  //     真要给"里 / 外"提示，也必须是**自绘**且**不覆盖整段**的手段（§六-6）。
  // ─────────────────────────────────────────────────────────────
  group('★ 过闸：数学段上不许有"整段底色"这类整体视觉', () {
    testWidgets('行内公式：光标在里面时也不许刷整段底色', (WidgetTester tester) async {
      const String doc = r'设 $x^2+1$ 为常数';
      final DocBuffer buf = DocBuffer(doc);
      await _mountEdit(tester, buf);
      await tester.pumpAndSettle();

      buf.setCaret(doc.indexOf(r'x^2'));
      await tester.pumpAndSettle();
      expect(_hasRangeTint(tester), isFalse,
          reason: '整段底色 = 把"渲染提示"画成"一个对象"（公式块观感，用户 2026-10-15 指出）');
    });

    testWidgets('行间公式：同样不许', (WidgetTester tester) async {
      const String doc = '正文\n\n\$\$\nx^2+1\n\$\$\n\n尾段\n';
      final DocBuffer buf = DocBuffer(doc);
      await _mountEdit(tester, buf);
      await tester.pumpAndSettle();

      buf.setCaret(doc.indexOf('x^2'));
      await tester.pumpAndSettle();
      expect(_hasRangeTint(tester), isFalse);
    });

    testWidgets('★ 数学的渲染与缓冲区**一字不差**（视觉不许反过来动数据）',
        (WidgetTester tester) async {
      const String doc = r'设 $x^2+1$ 为常数';
      final DocBuffer buf = DocBuffer(doc);
      await _mountEdit(tester, buf);
      await tester.pumpAndSettle();
      final String before = buf.buf;
      buf.setCaret(doc.indexOf(r'x^2'));
      await tester.pumpAndSettle();
      expect(buf.buf, before, reason: '任何视觉都不许动缓冲区');
      expect(find.byType(Math), findsOneWidget);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 四、★ §4.8 **第三类：挂件槽不画占位框**（2026-10-15 晚用户拍板）
  //
  //   挂件 = 脚本（`^`/`_`）＋ 定宽 accent（`\hat` 一族）。
  //   用户模型：**挂件是挂在/套在基座上的，不是结构** —— 文本里的一个字旁边没有格子；
  //   空挂件已经有可见落点（基座字符 / 那顶帽子），光标进去时竖条自己会画出来
  //   ⇒ 不必再造一个方框（"占位框"这个念头本身就有公式块味道）。
  //   ★★ **2026-10-18 晚收窄**：脚本槽（`^`/`_`）改成"**光标在这一段里就画**"，
  //      理由见 `slot_marks.dart` 里那段注释（C/A 模板空脚本 ⇒ 屏幕上一个 C）。
  //      **定宽 accent 的参数槽仍然不画**（帽子就是落点）。
  // ─────────────────────────────────────────────────────────────
  group(r'§4.8 第三类：挂件槽不画占位框（脚本 + 定宽 accent）', () {
    test(r'空脚本：光标不在这一段 ⇒ 不画；光标在里面 ⇒ **画**（2026-10-18 收窄）', () {
      for (final String tex in <String>[r'x^{}', r'x_{}']) {
        expect(_marks(renderMathTex(tex, caretRel: -1)), 0, reason: tex);
        expect(_marks(renderMathTex(tex, caretRel: 3)), 1,
            reason: '$tex：光标在空脚本里 ⇒ 必须看得见落点');
      }
    });

    test(r'★★ C/A 模板（组合数 / 排列数）：两个空脚本**都画**（用户报"没给子位点"）', () {
      const String c = r'\mathrm{C}_{}^{}';
      // 光标在下标槽（`firstSlotOffset` 就是 12）
      final String inside = renderMathTex(c, caretRel: 12);
      expect(_marks(inside), 2,
          reason: '下标 ＋ 上标两个空槽都要画出来（否则只是"一个裸 C"）');
      expect(inside.contains(kCurrentSlotTex), isTrue,
          reason: '光标所在的那一个用"当前槽"样式（淡蓝底 + 蓝框）');
      // 光标不在这一段 ⇒ 不常驻
      expect(_marks(renderMathTex(c, caretRel: -1)), 0);
    });

    test(r'空 accent：`\hat{}` / `\bar{}` / `\vec{}` ⇒ 不画（帽子就是落点）', () {
      for (final String tex in <String>[r'\hat{}', r'\bar{}', r'\vec{}']) {
        expect(_marks(renderMathTex(tex, caretRel: -1)), 0, reason: tex);
        expect(_marks(renderMathTex(tex, caretRel: 5)), 0, reason: tex);
      }
    });

    test(r'★ **结构类**槽照旧恒可见：`\frac{}{}` / `\sqrt{}` / `\frac{a}{}`', () {
      expect(_marks(renderMathTex(r'\frac{}{}', caretRel: -1)), 2,
          reason: '分式分子分母是**结构的内容**（空着时整个结构是零尺寸）');
      expect(_marks(renderMathTex(r'\sqrt{}', caretRel: -1)), 1);
      expect(_marks(renderMathTex(r'\frac{a}{}', caretRel: -1)), 1);
    });

    test(r'★ 可选槽照旧"进入才画"：`\sum_{}^{}` / `\sqrt[]{}`', () {
      expect(_marks(renderMathTex(r'\sum_{}^{}', caretRel: -1)), 0);
      expect(_marks(renderMathTex(r'\sum_{}^{}', caretRel: 0)), 2);
    });

    test(r'★ **拉伸型** accent 的参数照旧画：`\overline{}`', () {
      expect(_marks(renderMathTex(r'\overline{}', caretRel: -1)), 1,
          reason: '空着只剩一条线 ⇒ 需要可见落点（它与定宽 accent 不同族）');
    });

    test(r'★ 非空挂件本来就不画（有内容 ⇒ 没有空槽）', () {
      expect(_marks(renderMathTex(r'x^{2}', caretRel: -1)), 0);
      expect(_marks(renderMathTex(r'\hat{x}', caretRel: -1)), 0);
    });
  });
}
