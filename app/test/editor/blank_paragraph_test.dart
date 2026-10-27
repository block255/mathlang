// ★★ §11.46 真修 · 「真空段落」与文首空行（2026-10-18 晚，P5）
//
// 用户原话（2026-10-18）：「之前那一批遗留的关于**空行和 enter** …… 也别忘记了」。
// 规格（《位点与结构导航》§11.46）：
//   · **段距**：块之间**一个**空行（`A\n\nB`）⇒ 只是那一点 `gap`（不占整行）；
//   · **真空段落**：**两个以上**空行（`A\n\n\nB`）⇒ 第一个仍是段距，**其余每个占一整行**；
//   · 真空段落是**真单元**：点它能落光标（按第几行落）、能打字、退格能删、Enter 能再长出
//     一行（Enter 在空行上只补一个 `\n`）；
//   · **文首空行**（`\n甲`）以前是零高 —— 现在每个都占一整行（记账 #2）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/doc_view.dart';
import 'package:mathlang/editor/edit_view.dart';

final Finder _slots = find.byWidgetPredicate(
    (Widget w) => w.runtimeType.toString() == '_BlankSlot');

Future<DocBuffer> _pumpDocView(
  WidgetTester tester,
  String doc, {
  int caret = 0,
  void Function(int offset, Offset global, TapSource source)? onTapOffset,
}) async {
  final DocBuffer buf = DocBuffer(doc)..setCaret(caret);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: DocView(buffer: buf, onTapOffset: onTapOffset),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return buf;
}

Future<DocBuffer> _pumpEditView(WidgetTester tester, String doc,
    {int caret = 0}) async {
  final DocBuffer buf = DocBuffer(doc)..setCaret(caret);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: EditView(buffer: buf)),
    ),
  ));
  tester.state<EditViewState>(find.byType(EditView)).focusInput();
  await tester.pumpAndSettle();
  return buf;
}

/// 横线上有没有光标竖条（1.5 宽的那个 Container）
bool _hasCaretBar(WidgetTester tester) => tester
    .widgetList<Container>(find.byType(Container))
    .where((Container c) => c.constraints?.maxWidth == 1.5)
    .isNotEmpty;

/// 两行正文之间的**纵向距离**（用几何量，不依赖私有 widget 的高度）
double _vGap(WidgetTester tester, String a, String b) =>
    tester.getTopLeft(find.textContaining(b).first).dy -
    tester.getTopLeft(find.textContaining(a).first).dy;

void main() {
  group('① 真空段落要占一整行（改前：段距恒为一点，多按 Enter 不长高）', () {
    testWidgets('★ 一个空行 = 段距；两个空行 = 段距 ＋ **一整行**', (WidgetTester tester) async {
      await _pumpDocView(tester, '甲\n\n乙');
      final double one = _vGap(tester, '甲', '乙');
      await _pumpDocView(tester, '甲\n\n\n乙');
      final double two = _vGap(tester, '甲', '乙');
      // 多出来的应当≈一行高（正文 16 ⇒ textCaretHeight ≈ 20）
      expect(two - one, greaterThan(30.0),
          reason: '`甲\\n\\n\\n乙` 中间那行空行必须真占高（实测差 ${two - one}）');
      expect(two - one, lessThan(46.0), reason: '只该多**一行**，不是两行');
    });

    testWidgets('★ 三个空行 ⇒ 两行高（每多一个空行就多一行）', (WidgetTester tester) async {
      await _pumpDocView(tester, '甲\n\n\n乙');
      final double two = _vGap(tester, '甲', '乙');
      await _pumpDocView(tester, '甲\n\n\n\n乙');
      final double three = _vGap(tester, '甲', '乙');
      expect(three - two, greaterThan(12.0));
    });

    testWidgets('★ 空行上要有**光标竖条**（改前：真空段落根本没人画）',
        (WidgetTester tester) async {
      // `甲\n\n\n乙`：空行是 [2,3) 这一行，光标落在 2 = 那一行行首
      await _pumpDocView(tester, '甲\n\n\n乙', caret: 2);
      expect(_hasCaretBar(tester), isTrue, reason: '光标在真空段落里必须看得见');
    });
  });

  group('② 点哪一行就落哪一行（一个槽覆盖多行）', () {
    testWidgets('★ 点槽的下半部分 ⇒ 落到**第二行**空行（不是永远落第一行）',
        (WidgetTester tester) async {
      int? got;
      // `甲\n\n\n\n乙`：三个空行 = **两行**（第一个空行只是段距那一截），
      // 行首偏移 = 3（第一行）与 4（第二行）。
      await _pumpDocView(tester, '甲\n\n\n\n乙',
          caret: 0, onTapOffset: (int o, Offset _, TapSource _) => got = o);
      final Rect slot = tester.getRect(_slots.first);
      // ★ 2026-10-28 改口径：空行的行表 = `空行串[1..]`
      //   （第一个空行是"段距那一截"，紧贴上一段行盒底，不是整行）
      //   ⇒ 第一行在 `段距 + 行内内缩 ≈ 14.8`，第二行在 +38.4 ≈ 53.2。
      await tester.tapAt(Offset(slot.left + 40, slot.top + 60));
      await tester.pumpAndSettle();
      expect(got, 4, reason: '点在第二个空行上 ⇒ 光标落在第二个空行的行首（实际 $got）');
    });

    testWidgets('★ 点上半部分 ⇒ 第一行（偏移 2）', (WidgetTester tester) async {
      int? got;
      await _pumpDocView(tester, '甲\n\n\n\n乙',
          caret: 0, onTapOffset: (int o, Offset _, TapSource _) => got = o);
      final Rect slot = tester.getRect(_slots.first);
      await tester.tapAt(Offset(slot.left + 40, slot.top + 4));
      await tester.pumpAndSettle();
      expect(got, 2);
    });
  });

  group('③ 文首空行（记账 #2：以前是零高、点不到）', () {
    testWidgets('★ `\\n甲`：文首那一行要占高、并有一个可点的槽',
        (WidgetTester tester) async {
      await _pumpDocView(tester, '\n甲');
      // 改前：文首没有 gap ⇒ 只有文末槽 1 个；现在应当有 **2 个**（文首 + 文末）
      expect(_slots, findsNWidgets(2),
          reason: '文首空行也必须是一个槽（否则点不到、光标没人画）');
      expect(tester.getSize(_slots.first).height, greaterThan(12.0));
    });

    testWidgets('★ `\\n\\n甲`：两个空行 ⇒ 两行高', (WidgetTester tester) async {
      await _pumpDocView(tester, '\n甲');
      final double one = tester.getTopLeft(find.textContaining('甲').first).dy;
      await _pumpDocView(tester, '\n\n甲');
      final double two = tester.getTopLeft(find.textContaining('甲').first).dy;
      expect(two - one, greaterThan(30.0),
          reason: '文首多一个空行就多一整行（实测 ${two - one}）');
    });
  });

  group('⑤ 用户实测的两条（2026-10-18 晚第二批）', () {
    testWidgets('★★ Enter 之后竖条要落在**新段落会落脚**的位置（差一个段距）',
        (WidgetTester tester) async {
      // 用户原话：「enter 之后光标在这儿，但打出文本时字符比它低一截」
      // 根因：`甲` 按 Enter ⇒ `甲\n\n`，新段落要落在 `甲` 底下**再让开一个段距**，
      //       而竖条原来画在空隙最顶上（dy = 0）。
      await _pumpDocView(tester, '甲\n\n', caret: 3);
      final Rect slot = tester.getRect(_slots.first);
      final Rect bar = tester.getRect(find
          .byWidgetPredicate((Widget w) =>
              w is Container && w.constraints?.maxWidth == 1.5)
          .first);
      final double dy = bar.top - slot.top;
      expect(dy, greaterThan(6.0),
          reason: '竖条要往下让开一个段距（实测 dy=${dy.toStringAsFixed(1)}）');
      // ★ 2026-10-27：文末空行按 `trailingBlankHeight = n × 行高` 结算（与文首对称），
      //   所以 `甲⏎⏎` 里那行空行是**真的一行** ⇒ 新段落落在它**下面**（段距 + 一行），
      //   不再是"只让开一个段距"（旧口径下 `甲⏎⏎` 的高度是 0）。
      expect(dy, lessThan(18.0 + 30.0), reason: '让开一个段距 + 一行，不是两行');
    });

    testWidgets('★★ 段落边界**一次退格整个删掉**（Enter 插了两个 `\\n`）',
        (WidgetTester tester) async {
      // 用户原话：「点一次删除没还原，点两次才还原」
      final DocBuffer buf = await _pumpEditView(tester, '一\n\n行', caret: 3);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();
      expect(buf.buf, '一行\n', reason: '一次退格 = 撤销那一次 Enter（不是删一个字符）');
      expect(buf.caret, 1);
    });

    testWidgets('★ `Delete` 镜像：段落边界也一次删光', (WidgetTester tester) async {
      final DocBuffer buf = await _pumpEditView(tester, '一\n\n行', caret: 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(buf.buf, '一行\n');
      expect(buf.caret, 1);
    });
  });

  group('④ Enter 的口径：**一次按键 = 一行**（2026-10-27 口径变更）', () {
    // ★★★ 2026-10-27 口径变更（用户拍板）：撤销批 42 的"文末 / 页尾 Enter 封顶"。
    //   基准 = `notes/design/行与段-空行基准.md` §三 E1/E2 + §六 实测：
    //     · 旧版（1.1.1）与开发版（1.1.2）都实测过 —— 文末第二下起屏幕完全不动（封顶），
    //       而"一次按键动一行"才是用户要的；封顶的依据（页尾空行不占行盒）经查不成立
    //       （真正缺的是文末那行的行盒与光标跟随，已在本轮补上）。
    //   ⇒ 下面三条期望随之改写：文末每按一次**都**多一整行。
    testWidgets('★ 普通行按 Enter ⇒ 立刻出现**一整行**（`甲⏎⏎`）',
        (WidgetTester tester) async {
      // ★ 2026-10-27 最终口径：文末空行按 `trailingBlankHeight = n × 行高` 结算（与**文首对称**）
      //   ⇒ 一个空行就是一行、就是一个换行符 ⇒ 一次 Enter 补**一个** `\n`。
      //   （中间那两版：补两个 / 补三个，都是"第一个空行不占整行"造成的补偿。）
      final DocBuffer buf = await _pumpEditView(tester, '甲', caret: 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(buf.buf, '甲\n\n', reason: '一次 Enter = 一个换行 = 看得见的一行');
      expect(buf.caret, 3);
    });

    testWidgets('★★ 空行上按 Enter ⇒ 再长一行（不再封顶）',
        (WidgetTester tester) async {
      // `甲\n\n`：光标在 3 = 文末空行位置；再按一次必须**真的再加一行**。
      final DocBuffer buf = await _pumpEditView(tester, '甲\n\n', caret: 3);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(buf.buf, '甲\n\n\n', reason: '空行上 Enter 再长一行（批 42 封顶已撤）');
      expect(buf.caret, 4);
    });

    testWidgets('★ 连按两次 Enter（从正文出发）⇒ `甲⏎⏎⏎`（两行空行）',
        (WidgetTester tester) async {
      final DocBuffer buf = await _pumpEditView(tester, '甲', caret: 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(buf.buf, '甲\n\n\n', reason: '两次 Enter = 两个换行 = 两行（一次一行）');
    });
  });
}
