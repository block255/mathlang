// 编辑面测试（S3-2 · 输入层重做后）
//
// 输入层从「透明镜像框」换成「自实现 TextInputClient」（见 text_input_surface.dart 的头部注释）。
// 因此本文件的重点也随之改变 —— 现在要守住的是**三条新不变量**：
//   · ★ 推给平台的文本**永远是空的**（元素里装着 `$...$` 就是候选框错位的根源）
//   · ★ 组合中间态**一个字都不写进缓冲区**（设计稿 §11.7）
//   · ★ **文本与命令键是两条通道**：文本走平台文本值，命令键走键事件
// 外加提交规则 ① 的纯函数测试（Enter → 新块）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/render/inline_math_text.dart';

TextEditingValue _v(String text, [int? sel, TextRange? composing]) =>
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: sel ?? text.length),
      composing: composing ?? TextRange.empty,
    );

/// 挂上编辑面并**接上平台文本通道**（自动化的"点进去、把输入法连上"）。
///
/// ★ 必须真的接上：`TestTextInput.updateEditingValue` 只会送到**当前已连接的**客户端。
Future<EditViewState> _mount(
  WidgetTester tester,
  DocBuffer buf, {
  void Function(EditViewStats stats)? onStats,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      // A4 页（971 px）比测试视口（600 px）高 —— 不套滚动容器就会 RenderFlex overflow
      body: SingleChildScrollView(
        child: EditView(buffer: buf, onStats: onStats),
      ),
    ),
  ));
  final EditViewState st = tester.state<EditViewState>(find.byType(EditView));
  st.focusInput();
  await tester.pump();
  return st;
}

void main() {
  group('提交规则 ①：NewBlockOnEnterFormatter（Enter → 新块 \\n\\n）', () {
    const NewBlockOnEnterFormatter f = NewBlockOnEnterFormatter();

    test('单独插入一个换行 → 变成两个，光标落在两行之间', () {
      final TextEditingValue out = f.formatEditUpdate(_v('ab'), _v('a\nb', 2));
      expect(out.text, 'a\n\nb');
      expect(out.selection.baseOffset, 3);
    });

    test('粘贴进来的一大段（含换行）→ 原样放行', () {
      final TextEditingValue out = f.formatEditUpdate(_v(''), _v('a\nb'));
      expect(out.text, 'a\nb');
    });

    test('普通字符不受影响', () {
      expect(f.formatEditUpdate(_v('a'), _v('ax')).text, 'ax');
    });

    test('删除一个换行不受影响（只处理插入）', () {
      expect(f.formatEditUpdate(_v('a\n\nb'), _v('a\nb')).text, 'a\nb');
    });

    test('组合中不干预', () {
      final TextEditingValue out = f.formatEditUpdate(
        _v('a'),
        _v('a\n', 2, const TextRange(start: 1, end: 2)),
      );
      expect(out.text, 'a\n');
    });
  });

  group('输入面：平台文本 → 缓冲区', () {
    testWidgets('打字 → 缓冲区更新、光标跟随、记一次编辑', (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer('abc');
      EditViewStats? last;
      await _mount(tester, buf, onStats: (EditViewStats s) => last = s);

      // ★ 插入位置**只由我们的光标决定** —— 平台元素是空的，它没有位置可给
      buf.setCaret(3);
      await tester.pump();

      tester.testTextInput.updateEditingValue(_v('X'));
      await tester.pump();

      expect(buf.buf, 'abcX');
      expect(buf.caret, 4, reason: '插入后光标在插入内容之后');
      expect(last?.edits, 1);
    });

    testWidgets('★ 推给平台的文本永远是空的（这才是候选框能对齐的原因）',
        (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer(r'设 $x^2+1$ 为常数');
      await _mount(tester, buf);
      buf.setCaret(buf.length);
      await tester.pump();

      // 接上时推过一次
      expect(tester.testTextInput.editingState?['text'], '',
          reason: '接上平台通道时元素里必须是空的');

      tester.testTextInput.updateEditingValue(_v('中'));
      await tester.pump();

      expect(buf.buf, r'设 $x^2+1$ 为常数中');
      expect(tester.testTextInput.editingState?['text'], '',
          reason: r'★ 提交之后元素必须被清空 —— 元素里留着 `$x^2+1$` 就会让插值符跑到别处，'
              '候选框也跟着跑（旧镜像框方案就是这么坏的）');
    });

    testWidgets('★ 组合中间态一个字都不写进缓冲区；提交后一次写入',
        (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer('');
      EditViewStats? last;
      await _mount(tester, buf, onStats: (EditViewStats s) => last = s);

      // 打拼音（组合中）
      tester.testTextInput.updateEditingValue(
        _v('zhong', 5, const TextRange(start: 0, end: 5)),
      );
      await tester.pump();
      expect(buf.buf, '', reason: '组合中间态不该写进缓冲区');
      expect(last?.edits, 0);
      expect(last?.composing, isTrue);
      expect(last?.composingText, 'zhong');

      // 选字提交（组合结束）
      tester.testTextInput.updateEditingValue(_v('中'));
      await tester.pump();
      expect(buf.buf, '中');
      expect(last?.edits, 1);
      expect(last?.composing, isFalse);
    });

    testWidgets('★ 组合取消 → 缓冲区一字未动、零编辑', (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer('abc');
      EditViewStats? last;
      await _mount(tester, buf, onStats: (EditViewStats s) => last = s);

      tester.testTextInput.updateEditingValue(
        _v('zhong', 5, const TextRange(start: 0, end: 5)),
      );
      await tester.pump();
      expect(last?.edits, 0);

      // 取消组合：文本回到上一步（空）
      tester.testTextInput.updateEditingValue(_v(''));
      await tester.pump();
      expect(buf.buf, 'abc');
      expect(last?.edits, 0, reason: '取消组合不该产生任何编辑');
    });

    testWidgets('多字符一次到达（粘贴 / 自动更正）→ 只算一次编辑',
        (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer('');
      EditViewStats? last;
      await _mount(tester, buf, onStats: (EditViewStats s) => last = s);

      tester.testTextInput.updateEditingValue(_v('中文abc'));
      await tester.pump();

      expect(buf.buf, '中文abc');
      expect(last?.edits, 1, reason: '一次语义编辑只能记一次（否则撤销栈会炸开）');
    });

    testWidgets('Enter 走文本通道 → 变成块间空行', (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer('abc');
      await _mount(tester, buf);
      buf.setCaret(3);
      await tester.pump();

      tester.testTextInput.updateEditingValue(_v('\n'));
      await tester.pump();

      expect(buf.buf, 'abc\n\n', reason: 'Enter = 新块（R3 输出侧约定：块间空一行）');
    });

    testWidgets('★ Enter 的平台真身是 performAction(newline) → 也要变成块间空行',
        (WidgetTester tester) async {
      // Web/Chrome 实测：Enter 不走文本通道，平台发的是 TextInputAction.newline。
      // 这条测试钉住"两条通道共用同一条提交规则链"。
      final DocBuffer buf = DocBuffer('abc');
      await _mount(tester, buf);
      buf.setCaret(3);
      await tester.pump();

      await tester.testTextInput.receiveAction(TextInputAction.newline);
      await tester.pump();

      expect(buf.buf, 'abc\n\n',
          reason: '若这里只 +1（`abc\\n`），说明 performAction 绕过了 formatter 链');
    });
  });

  group('输入面：命令键走键事件通道', () {
    testWidgets('★ 方向键移动光标，且不算一次编辑', (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer('abc');
      EditViewStats? last;
      await _mount(tester, buf, onStats: (EditViewStats s) => last = s);
      buf.setCaret(2);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(buf.caret, 1, reason: '方向键是键事件通道的事');
      expect(last?.edits, 0, reason: '纯移动不算编辑');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(buf.caret, 2);

      // 到边界不越界
      buf.setCaret(0);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(buf.caret, 0);
    });

    testWidgets('★ 退格 / Delete 走键事件', (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer('abc');
      EditViewStats? last;
      await _mount(tester, buf, onStats: (EditViewStats s) => last = s);
      buf.setCaret(2);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(buf.buf, 'ac', reason: '退格删光标前一个字符');
      expect(buf.caret, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(buf.buf, 'a', reason: 'Delete 删光标后一个字符');
      expect(last?.edits, 2,
          reason: '两条通道的编辑统一计数：缓冲区真被改了几次就是几次');

      // 落到边界上的删除**不算**编辑
      buf.setCaret(0);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(last?.edits, 2, reason: '边界上什么都没删掉，不该记编辑');
    });

    testWidgets('★ 组合中退格必须**让给输入法**（不能被缓冲区吃掉）',
        (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer('abc');
      await _mount(tester, buf);
      buf.setCaret(3);
      await tester.pump();

      // 进入组合态：元素里是 "zhong"，还没提交
      tester.testTextInput.updateEditingValue(
        _v('zhong', 5, const TextRange(start: 0, end: 5)),
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(buf.buf, 'abc',
          reason: '组合中退格 = 取消一个拼音字母，绝不能删掉已经写好的正文');
    });

    testWidgets('Shift+方向键 → 扩展选区（anchor 不动、光标动）',
        (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer('abcdef');
      await _mount(tester, buf);
      buf.setCaret(2);
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(buf.hasSelection, isTrue);
      expect(buf.anchor, 2);
      expect(buf.caret, 4);
    });

    testWidgets('Home / End → 行首行尾', (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer('第一行\n第二行');
      await _mount(tester, buf);
      buf.setCaret(5); // 「第二行」中间
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(buf.caret, 4, reason: '行首 = 换行符之后那一位');

      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      expect(buf.caret, 7);
    });

    testWidgets('Ctrl 组合键不拦截（留给撤销与后面的键）', (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer('abc');
      await _mount(tester, buf);
      buf.setCaret(3);
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(buf.buf, 'abc', reason: 'Ctrl+退格不该被当成普通退格');
    });

    testWidgets('★ Ctrl+Z 撤销 / Ctrl+Shift+Z 重做（结构删除要能一步撤回）',
        (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer(r'$a\pm b$');
      await _mount(tester, buf);
      // 把光标放到 `\pm` 之后（`\pm` 是 [2,6)）
      buf.setCaret(6);
      await tester.pump();

      // 一次退格 = 整个 `\pm` 一次删光
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(buf.buf, r'$a b$', reason: '原子级删除：`\\pm` 一次消失');

      // ★ 一次 Ctrl+Z 就把整个 `\pm` 撤回来（因为删除是**一次区间替换**）
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(buf.buf, r'$a\pm b$', reason: '删除 = 一步，撤销 = 一步');

      // 重做
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(buf.buf, r'$a b$');
    });
  });

  group('★ 组合中间态把后面的文字推开（用户实测提出）', () {
    testWidgets('拼音接进排版 → 段落宽度增大（后面的字被真的推开）',
        (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer('前面后面');
      await _mount(tester, buf);
      buf.setCaret(2); // 「前面|后面」
      await tester.pumpAndSettle();

      final double w0 = tester.getSize(find.byType(InlineMathText).first).width;

      tester.testTextInput.updateEditingValue(
        _v('zhong', 5, const TextRange(start: 0, end: 5)),
      );
      await tester.pumpAndSettle();

      final double w1 = tester.getSize(find.byType(InlineMathText).first).width;
      expect(w1, greaterThan(w0 + 20),
          reason: '★ 拼音必须占掉排版宽度（$w0 → $w1）；'
              '若两者相等，说明还停在"叠画"——那会盖住后面的字，正是用户报的问题');
    });

    testWidgets('组合结束后拼音从排版里消失（缓冲区一字未动）',
        (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer('前面后面');
      await _mount(tester, buf);
      buf.setCaret(2);
      await tester.pumpAndSettle();
      final double w0 = tester.getSize(find.byType(InlineMathText).first).width;

      tester.testTextInput.updateEditingValue(
        _v('zhong', 5, const TextRange(start: 0, end: 5)),
      );
      await tester.pumpAndSettle();
      expect(buf.buf, '前面后面', reason: '组合期间缓冲区不许变');

      tester.testTextInput.updateEditingValue(_v('', 0)); // 取消组合
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(InlineMathText).first).width,
          closeTo(w0, 0.5));
      expect(buf.buf, '前面后面');
    });

    testWidgets('★ 光标在行间公式块里 → 拼音**不塞进源码**，退回叠画',
        (WidgetTester tester) async {
      // 行间公式块的排版文本就是 LaTeX 源码，塞拼音进去会渲染失败
      final DocBuffer buf = DocBuffer('\$\$\nx = 1\n\$\$\n');
      await _mount(tester, buf);
      buf.setCaret(4); // 公式内部
      await tester.pumpAndSettle();

      tester.testTextInput.updateEditingValue(
        _v('zhong', 5, const TextRange(start: 0, end: 5)),
      );
      await tester.pumpAndSettle();

      expect(find.text('zhong'), findsOneWidget,
          reason: '公式块里应出现叠画层（而不是把拼音塞进 tex）');
    });
  });

  group('编辑面：点屏幕定位与输入面定位', () {
    testWidgets('★ 点段落里的字 → 光标落到对应偏移', (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer('abcdef');
      await _mount(tester, buf);
      await tester.pumpAndSettle();

      final Finder para = find.byType(InlineMathText);
      expect(para, findsOneWidget, reason: '这段文字渲染成一个段落');
      final Offset topLeft = tester.getTopLeft(para);
      final Size size = tester.getSize(para);

      await tester.tapAt(topLeft + Offset(1, size.height / 2));
      await tester.pump();
      expect(buf.caret, lessThanOrEqualTo(1), reason: '点在段落最左 → 光标在开头附近');

      await tester.tapAt(topLeft + Offset(size.width - 1, size.height / 2));
      await tester.pump();
      expect(buf.caret, greaterThan(3), reason: '点在段落最右 → 光标靠后');
    });

    testWidgets('★ 点屏幕定位后输入设备里的文本仍必须是空的',
        (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer('abcdef');
      await _mount(tester, buf);
      await tester.pumpAndSettle();

      final Finder para = find.byType(InlineMathText);
      await tester.tapAt(tester.getTopLeft(para) + const Offset(1, 8));
      await tester.pump();

      expect(tester.testTextInput.editingState?['text'], '',
          reason: '点哪儿都不该把正文灌进平台元素');
    });

    testWidgets('★ 输入面的定位矩形：左边界必须跟着光标的列走（候选框落在元素原点）',
        (WidgetTester tester) async {
      // 实测踩过：定位矩形用的是"整行"（左边界 = 段落左边界）→ 元素的插入符在行首
      // → IME 候选框出现在整行最左端，而不是光标处。这条测试钉死"左边界 = 光标 x"。
      final DocBuffer buf = DocBuffer('第一段很长很长的一段文字\n\n第二段\n\n第三段\n');
      final EditViewState st = await _mount(tester, buf);
      await tester.pumpAndSettle();

      buf.setCaret(1); // 第一行靠左
      await tester.pumpAndSettle();
      final Rect r1 = st.inputCaretRect;

      buf.setCaret(6); // 同一行往右挪（没换行）
      await tester.pumpAndSettle();
      final Rect r2 = st.inputCaretRect;
      expect(r2.left, greaterThan(r1.left),
          reason: '★ 同一行内光标右移，定位矩形的左边界必须右移；'
              '若 r1.left == r2.left == 段落左边界，说明又退回"整行盒子"了');
      expect(r2.top, closeTo(r1.top, 0.5), reason: '同一行，纵向不该动');

      buf.setCaret(buf.length - 1); // 第三段
      await tester.pumpAndSettle();
      final Rect r3 = st.inputCaretRect;
      expect(r3.top, greaterThan(r1.top),
          reason: '光标下移后输入面的定位矩形必须跟着下移（否则候选框留在原地）');
    });

    testWidgets('从缓冲区一侧改动（S3-3 导航 / 工具栏）→ 不回写平台元素',
        (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer('abc');
      await _mount(tester, buf);

      buf.setCaret(1);
      buf.insertText('X');
      await tester.pump();

      expect(buf.buf, 'aXbc');
      expect(buf.caret, 2);
      expect(tester.testTextInput.editingState?['text'], '',
          reason: '输入设备只接收"要提交的文本"，永远不接收文档内容');
    });

    testWidgets('★ 换一份文档 → 立刻上报新状态、编辑计数归零', (WidgetTester tester) async {
      // 实测踩过：换文档后外部状态栏一直显示旧数字（新缓冲区不会自己 notify）
      final DocBuffer first = DocBuffer('abc');
      EditViewStats? last;
      await _mount(tester, first, onStats: (EditViewStats s) => last = s);
      first.setCaret(3);
      await tester.pump();
      tester.testTextInput.updateEditingValue(_v('D'));
      await tester.pump();
      expect(last?.edits, 1);

      final DocBuffer second = DocBuffer('新文档内容');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EditView(
              buffer: second,
              onStats: (EditViewStats s) => last = s,
            ),
          ),
        ),
      ));
      await tester.pump();

      expect(last?.length, 5, reason: '换文档后必须立刻上报新长度');
      expect(last?.edits, 0, reason: '新文档 = 新的一次编辑会话');
    });
  });

  group('★ 注入不得破坏点击定位（2026-10-14 用户实测抓出的根因）', () {
    testWidgets('光标在公式里（空槽占位 + 光标条都已注入）时，点内部仍能移动光标',
        (WidgetTester tester) async {
      // 分母为空 → 注入"空槽占位"；光标在公式里 → 还会注入"光标条"。
      // 修复前：渲染叶盒数 = 原始原子数 + 2 → `hitTestMathTex` 判"数量不等" →
      //   **静默返回 null** → 公式内点击失效（箭头键还能用，所以症状很像"被锁住"）。
      final DocBuffer buf = DocBuffer(r'$\frac{a}{}$');
      await _mount(tester, buf);
      await tester.pumpAndSettle();

      expect(find.byType(Math), findsOneWidget, reason: '这段渲染成一个行内公式');
      final Offset tl = tester.getTopLeft(find.byType(Math));
      final Size sz = tester.getSize(find.byType(Math));

      buf.setCaret(9); // 光标落进**空的分母**（位点在 rel 8 → 绝对 9）
      await tester.pumpAndSettle();
      expect(buf.caret, 9);

      // ★ 必须点**两个不同位置**并断言落到**不同**偏移 ——
      //   只断言"动了"是不够的：公式内点击有两条路径同时跑
      //   （`_handleUnitHit` 的段落映射是**粗**的，会把公式内每一处都映到同一个偏移；
      //   精确落点靠 `Math` 的 GestureDetector → `hitTestMathTex`）。
      //   精确那一路一旦静默失败，光标仍会"动"到那个固定偏移 —— 假通过。
      await tester.tapAt(tl + Offset(2, sz.height / 2)); // 左端 = 分子那一带
      await tester.pump();
      final int left = buf.caret;

      await tester.tapAt(tl + Offset(sz.width - 2, sz.height / 2)); // 右端
      await tester.pump();
      final int right = buf.caret;

      expect(left, lessThan(right),
          reason: '★ 点公式左端与右端必须落到**不同**偏移；'
              '若两者相等，说明精确落点失效、只剩段落映射的粗落点（用户报的"被锁住"就是这个）');
      expect(left, inInclusiveRange(1, 11),
          reason: r'落点必须在公式源码 $\frac{a}{}$ 的 tex 区间里（1..11），不能跑到公式之外');
    });
  });

  group('编辑面：列表项点击（标记段落不能抢点）', () {
    testWidgets('★ 列表项：逐格点击，映射必须精确', (WidgetTester tester) async {
      // 内容「判别式」= 源区间 [2,5)；标记 `- ` 占 [0,2)
      final DocBuffer buf = DocBuffer('- 判别式\n- 第二项\n');
      await _mount(tester, buf);
      await tester.pumpAndSettle();

      final Finder content = find.byType(InlineMathText).first;
      final Rect rect = tester.getRect(content);

      final List<int> got = <int>[];
      for (final double dx in <double>[2, 14, 26, 38]) {
        await tester.tapAt(Offset(rect.left + dx, rect.center.dy));
        await tester.pump();
        got.add(buf.caret);
      }
      // 前三个字格精确；最后一格压在文字右边缘那 1px 上，文本命中的边界归属天然有 ±1 模糊
      expect(got.sublist(0, 3), <int>[2, 3, 4],
          reason: '点「判」「别」「式」应依次落到源偏移 2,3,4');
      expect(got.last, greaterThanOrEqualTo(4),
          reason: '点最右边应落在内容末尾附近（不能回退到标记里）');
    });

    testWidgets('★ 列表项：点内容区要落在内容里', (WidgetTester tester) async {
      // 第 1 项：行首 `- ` 占 2 个字符，内容是「判别式」= 源区间 [2,5)
      final DocBuffer buf = DocBuffer('- 判别式\n- 第二项\n');
      await _mount(tester, buf);
      await tester.pumpAndSettle();

      final Finder content = find.byType(InlineMathText).first;
      final Offset topLeft = tester.getTopLeft(content);
      final Size size = tester.getSize(content);

      await tester.tapAt(topLeft + Offset(size.width - 2, size.height / 2));
      await tester.pump();
      expect(buf.caret, 5,
          reason: '点内容区右端应落在内容末尾；落在 3 说明又是标记段落在抢点');
    });
  });

  // ─────────────────────────────────────────────────────────────
  // ★ 用户实测复现路径的回归
  //
  // 用户原话：「我点击根号里面的 c 后面，从这里删，一直点删除键，就会触发」
  // 触发的是 `Parser Error: Expected group after '^'` ——
  // 删掉 `b^2` 的 `2` 却把裸 `^` 留在原地 → `b^-4ac`。
  //
  // ★ 这条测试的两个关键点（缺一就测不到真东西）：
  //   ① 必须**连按**：单次删除不炸，是"删到最后一步"才留下坏式子
  //   ② 必须在**嵌套结构内部**（`\frac` 里的 `\sqrt` 里），不是在孤立的 `b^2-4ac` 上 ——
  //      修复前的 smart_delete 只处理了「光标的直接前后邻居」，
  //      在嵌套里那个邻居是 `}` 而不是 `^`
  // ─────────────────────────────────────────────────────────────
  group(r'★ 回归：行间公式里 \sqrt{b^2-4ac} 连按删除键（用户原始复现路径）', () {
    const String doc = r'''
$$
x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}
$$
''';

    /// `c` 之后的那个偏移（= `\sqrt` 被开方槽的末位点）
    int caretAfterC() => doc.indexOf('4ac') + 3;

    /// 连按 [key] [times] 次，每次都断言画面上没有 `❌` 报错块。
    Future<void> holdKey(
      WidgetTester tester,
      DocBuffer buf,
      LogicalKeyboardKey key,
      String label, {
      int from = -1,
      int times = 12,
    }) async {
      await _mount(tester, buf);
      await tester.pumpAndSettle();
      buf.setCaret(from < 0 ? caretAfterC() : from);
      await tester.pumpAndSettle();

      final List<String> trace = <String>['起始: ${buf.buf}'];
      for (int i = 1; i <= times; i++) {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
        trace.add('第 $i 次 $label: ${buf.buf}');
        expect(find.textContaining('❌'), findsNothing,
            reason: '删除过程中出现了渲染报错。轨迹：\n${trace.join('\n')}');
      }
    }

    // ★★ 这条是**用户原话的那条路**：「点击根号里面的 c 后面，从这里删，一直点删除键」——
    //    实测确认为 **Backspace**（删除键 = 退格），且**只有它**能抓住这个 bug。
    //    证据：把 `_removeAtom` 的 `^`/`_` 处理临时回退后，本文件里**只有这一条变红**，
    //    报出的正是用户看到的那句：`❌ Parser Error: Expected group after '^'`，
    //    轨迹为 `\sqrt{b^2}` → `\sqrt{b^}`（删掉 `2` 却把裸 `^` 留下）。
    testWidgets('Backspace 连按 12 次：每一步缓冲区都必须还能渲染',
        (WidgetTester tester) async {
      await holdKey(tester, DocBuffer(doc), LogicalKeyboardKey.backspace, 'Backspace');
    });

    // ⚠️ 诚实标注：**本条的起点碰不到 `^`**（`c` 后面是 `}`，往前删到 `b^2` 才碰到），
    //    所以它对上面那个 bug 是**假通过** —— 回退修复后它照样绿。
    //    留着是因为它守的是另一条不变量：**往后删也不许删出坏式子**。
    testWidgets('Delete 连按 12 次：每一步缓冲区都必须还能渲染',
        (WidgetTester tester) async {
      await holdKey(
          tester, DocBuffer(doc), LogicalKeyboardKey.delete, 'Delete');
    });

    // ★ 这条才是 Delete 方向的**真**守门人：把光标放在 `b^2` 里原子 `2` **之前**那个位点，
    //    往右删就直接撞上裸参数 —— 删掉 `2` 留下 `b^` 同样是那句 Parser Error。
    //    （上一条 Delete 是从 `c` 后面起步，往前删到 `b^2` 时才碰到脚本，
    //      而那时 `_atomRightOf` 看到的是运算符而不是 `^`，所以绕开了这个 bug。）
    testWidgets(r'Delete 在裸参数 `^2` 之前：必须把 `^2` 一起删掉',
        (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer(doc);
      await _mount(tester, buf);
      await tester.pumpAndSettle();

      buf.setCaret(doc.indexOf('b^2') + 2); // 位点表里「原子 `2` 之前」那个位点
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();

      expect(find.textContaining('❌'), findsNothing,
          reason: '删掉 `2` 却留下裸 `^` → Parser Error。实际缓冲区：${buf.buf}');
      expect(buf.buf.contains(r'b^-'), isFalse, reason: '实际缓冲区：${buf.buf}');
      expect(buf.buf.contains(r'\sqrt{b-4ac}'), isTrue,
          reason: r'`^2` 应当**整体**消失（`b` 后面直接接 `-`）。实际缓冲区：${buf.buf}');
    });
  });

  // ─────────────────────────────────────────────────────────────
  // ★ 用户实测的第二条路径（2026-10-15）：
  //   「点分式内 → 右箭头到数学区外行末 → 按 Enter → **分式被直接拆出编码**」
  //
  //   探针把根因钉死了：那个"行末"其实是**闭合 `$` 之前那一格**（还在公式里），
  //   插入 `\n\n` 会把 `$` 配成单数 → 整行退化成源码。
  //   现在**两层一起挡**：
  //     · `math_nav.nextCaretOffset` —— `→` 不再停在那看不见的一格（甲方案）
  //     · `insert_guard.planInsert` —— 就算强行停在那儿，插入落点也会被推到公式之后
  //
  //   ★ 判据是**客观**的：每一行的 `$` 必须成对（奇数 = 那一行会退化成源码）。
  // ─────────────────────────────────────────────────────────────
  group('★ 回归：公式里按 → 出到行末再 Enter，公式必须完好', () {
    const String doc = '文字。\$\\frac{a}{b}\$\n\n尾段\n';

    void expectDollarsPaired(String buf) {
      for (final String line in buf.split('\n')) {
        expect(r'$'.allMatches(line).length.isEven, isTrue,
            reason: '行「$line」的 \$ 不成对 → 这一行会退化成源码。整份缓冲区：\n$buf');
      }
    }

    testWidgets('★ 从分子里出发，落在**每一个可达位置**上按 Enter，公式都必须完好',
        (WidgetTester tester) async {
      // ★ 为什么是"逐个停点"而不是"连按 N 次"：
      //   初版写的是"连按 8 次 → 再 Enter"，结果 8 次已经**越过公式**了 ——
      //   把源码改动临时收起（`git stash push -- app/lib`）重跑，它**照样绿** = 假通过。
      //   真正会炸的只有"停在闭合 `$` 之前那一格"这一种，所以必须把每个停点都走一遍。
      for (var presses = 0; presses <= 8; presses++) {
        final DocBuffer buf = DocBuffer(doc);
        await _mount(tester, buf);
        buf.setCaret(doc.indexOf(r'\frac') + 5); // 分子里
        await tester.pump();

        for (var i = 0; i < presses; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pump();
        }
        final int stop = buf.caret;

        await tester.testTextInput.receiveAction(TextInputAction.newline);
        await tester.pump();

        expectDollarsPaired(buf.buf);
        expect(find.textContaining('❌'), findsNothing,
            reason: '按 $presses 次 → 停在 $stop，Enter 之后公式坏了：\n${buf.buf}');
      }
    });

    testWidgets('★ 反向也守：强行把光标放在公式内部各个位置再 Enter',
        (WidgetTester tester) async {
      final int contentEnd = doc.indexOf('b}') + 2; // = 闭合 `$` 那一格
      for (var back = 0; back <= 6; back++) {
        final DocBuffer buf = DocBuffer(doc);
        await _mount(tester, buf);
        buf.setCaret(contentEnd - back);
        await tester.pump();

        await tester.testTextInput.receiveAction(TextInputAction.newline);
        await tester.pump();

        expectDollarsPaired(buf.buf);
        expect(find.textContaining('❌'), findsNothing,
            reason: '在偏移 ${contentEnd - back} 按 Enter 之后渲染报错了：\n${buf.buf}');
      }
    });
  });

  // ─────────────────────────────────────────────────────────────
  // ★ §4.0 通则的端到端复验（2026-10-15 用户实测那条）：
  //   「光标在分式后面，删除只删掉了那个末尾分界符，里面的编码爆出来了」
  //   以及「点分式**整体**后面删，只删了分母里的 b，并不是像预期那样删除了整个 a/b」。
  //
  //   现行口径：**删除目标 = 与光标【同层】的、紧邻的那一个渲染对象** ——
  //     · 公式**外侧**（与公式末尾同一根像素）→ 删的是公式里紧邻的那个**结构**（整个分式）
  //     · 光标在公式**里面某一层**（如分母槽）→ 删的是**那一层**的对象（`b`）
  //     · `$` / `$$` **不属于任何层** ⇒ 一个都不许碰
  // ─────────────────────────────────────────────────────────────
  group('★ 回归：光标在公式后面退格 → 删掉公式里紧邻的那个对象（不再爆编码）', () {
    const String doc = '文字。\$\\frac{a}{b}\$\n\n尾段\n';

    testWidgets('退格 → 整个分式没了、留空壳；画面上不许出现 `\\frac` 源码',
        (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer(doc);
      await _mount(tester, buf);
      buf.setCaret(doc.indexOf('b}') + 3); // = 收尾 `$` 之后那一格（公式外）
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      expect(buf.buf.contains(r'\frac'), isFalse,
          reason: '★ 整个分式都该消失。实际缓冲区：\n${buf.buf}');
      expect(buf.buf.contains(r'$$'), isTrue,
          reason: '★ 定界符留着 = 空壳（§4.6），它会被画成一个占位字形（§6.1.1），不是幽灵');
      expect(find.textContaining(r'\frac'), findsNothing,
          reason: '★ 画面上不许出现 LaTeX 源码（原则 2：用户永远不需要看数学编码）');
      expect(find.textContaining('❌'), findsNothing);
    });

    testWidgets('★ 反过来：光标在公式**内**末尾退格 → **同一个结果**（同一根像素）',
        (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer(doc);
      await _mount(tester, buf);
      buf.setCaret(doc.indexOf('b}') + 2); // = 收尾 `$` 那一格（公式内末尾）
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      expect(buf.buf.contains(r'\frac'), isFalse,
          reason: '同一根像素必须同一种行为。实际缓冲区：\n${buf.buf}');
      expect(find.textContaining('❌'), findsNothing);
    });

    testWidgets('★ 而光标在**分母里** `b` 之后退格 → 只删 `b`（出现空位框），分式还在',
        (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer(doc);
      await _mount(tester, buf);
      buf.setCaret(doc.indexOf('b}') + 1); // = 分母内容末尾（b 之后）
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      expect(buf.buf.contains(r'\frac{a}{}'), isTrue,
          reason: '★ 层内删除只碰那一层。实际缓冲区：\n${buf.buf}');
      expect(find.textContaining('❌'), findsNothing);
    });

    testWidgets('★ 空公式必须看得见：光标在空壳外面时画面上也要有东西（不是幽灵）',
        (WidgetTester tester) async {
      const String shell = '文字。\$\$\n\n尾段\n';
      final DocBuffer buf = DocBuffer(shell);
      await _mount(tester, buf);
      buf.setCaret(5); // 空壳**之后**（= 粘贴/删空之后最常见的情形）
      await tester.pump();

      expect(find.textContaining('❌'), findsNothing);
      final Finder ms = find.byType(Math);
      expect(ms, findsWidgets,
          reason: '空公式也要渲染出来（占位字形）—— 否则既看不见也点不到');
      expect(tester.getSize(ms.first).width, greaterThan(5),
          reason: '★ 空公式若渲染成零尺寸，用户会看到"按了没反应"');
    });
  });
}
