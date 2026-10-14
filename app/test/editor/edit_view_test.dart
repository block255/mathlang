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

      // 点公式左端（分子 a 那一带）→ 光标必须真的动
      await tester.tapAt(tl + Offset(2, sz.height / 2));
      await tester.pump();
      expect(buf.caret, isNot(9),
          reason: '★ 公式内部点击必须能移动光标；'
              '若这里仍是 9，说明命中测试又因为"注入让叶盒数≠原子数"而静默失效了');
      expect(buf.caret, lessThan(9), reason: '点在左端 → 光标应往左走');
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
}
