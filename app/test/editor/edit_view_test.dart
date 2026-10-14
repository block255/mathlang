// 编辑面测试（S3-2）
//
// 重点验两条由 S3-1b 实测逼出来的规则（设计稿 §11.7）：
//   · 组合中间态**一个字都不写进缓冲区**
//   · 组合取消 → 缓冲区一字未动、零编辑
// 外加提交规则 ① 的纯函数测试（Enter → 新块）

import 'package:flutter/material.dart';
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

  group('EditView：镜像 ⇄ 缓冲区', () {
    testWidgets('打字 → 缓冲区更新、光标跟随、记一次编辑', (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer('abc');
      EditViewStats? last;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          // A4 页（971 px）比测试视口（600 px）高 —— 不套滚动容器就会 RenderFlex overflow
          body: SingleChildScrollView(
            child: EditView(buffer: buf, onStats: (EditViewStats s) => last = s),
          ),
        ),
      ));
      await tester.showKeyboard(find.byType(TextField));
      await tester.pump();

      tester.testTextInput.updateEditingValue(_v('abXc', 3));
      await tester.pump();

      expect(buf.buf, 'abXc');
      expect(buf.caret, 3);
      expect(last?.edits, 1);
    });

    testWidgets('★ 组合中间态一个字都不写进缓冲区；提交后一次写入',
        (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer('');
      EditViewStats? last;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          // A4 页（971 px）比测试视口（600 px）高 —— 不套滚动容器就会 RenderFlex overflow
          body: SingleChildScrollView(
            child: EditView(buffer: buf, onStats: (EditViewStats s) => last = s),
          ),
        ),
      ));
      await tester.showKeyboard(find.byType(TextField));
      await tester.pump();

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
      tester.testTextInput.updateEditingValue(_v('中', 1));
      await tester.pump();
      expect(buf.buf, '中');
      expect(last?.edits, 1);
      expect(last?.composing, isFalse);
    });

    testWidgets('★ 组合取消 → 缓冲区一字未动、零编辑', (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer('abc');
      EditViewStats? last;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          // A4 页（971 px）比测试视口（600 px）高 —— 不套滚动容器就会 RenderFlex overflow
          body: SingleChildScrollView(
            child: EditView(buffer: buf, onStats: (EditViewStats s) => last = s),
          ),
        ),
      ));
      await tester.showKeyboard(find.byType(TextField));
      await tester.pump();

      tester.testTextInput.updateEditingValue(
        _v('abczhong', 8, const TextRange(start: 3, end: 8)),
      );
      await tester.pump();
      expect(last?.edits, 0);

      // 取消组合：文本回到原样
      tester.testTextInput.updateEditingValue(_v('abc', 3));
      await tester.pump();
      expect(buf.buf, 'abc');
      expect(last?.edits, 0, reason: '取消组合不该产生任何编辑');
    });

    testWidgets('★ 方向键：只改选区不改文本 → 光标必须跟着走，且不算编辑',
        (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer('abc');
      EditViewStats? last;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EditView(buffer: buf, onStats: (EditViewStats s) => last = s),
          ),
        ),
      ));
      await tester.showKeyboard(find.byType(TextField));
      await tester.pump();

      // 文本一字未改，只把选区挪到 1（= 按了一下 ← 或 →）
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'abc',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      await tester.pump();
      expect(buf.buf, 'abc');
      expect(buf.caret, 1, reason: '方向键只改选区，光标也要跟着走');
      expect(last?.edits, 0, reason: '纯移动不算编辑');

      // 再往右一格
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'abc',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      await tester.pump();
      expect(buf.caret, 2);
      expect(last?.edits, 0);
    });

    testWidgets('Shift+方向键的范围选区 → anchor / caret 都同步',
        (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer('abc');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: EditView(buffer: buf)),
        ),
      ));
      await tester.showKeyboard(find.byType(TextField));
      await tester.pump();

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'abc',
          selection: TextSelection(baseOffset: 1, extentOffset: 3),
        ),
      );
      await tester.pump();
      expect(buf.hasSelection, isTrue);
      expect(buf.anchor, 1);
      expect(buf.caret, 3);
    });

    testWidgets('★ 点屏幕定位：点段落里的字 → 光标落到对应偏移',
        (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer('abcdef');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: EditView(buffer: buf)),
        ),
      ));
      await tester.pumpAndSettle();

      final Finder para = find.byType(InlineMathText);
      expect(para, findsOneWidget, reason: '这段文字渲染成一个段落');
      final Offset topLeft = tester.getTopLeft(para);
      final Size size = tester.getSize(para);

      // 点最左边
      await tester.tapAt(topLeft + Offset(1, size.height / 2));
      await tester.pump();
      expect(buf.caret, lessThanOrEqualTo(1), reason: '点在段落最左 → 光标在开头附近');

      // 点最右边
      await tester.tapAt(topLeft + Offset(size.width - 1, size.height / 2));
      await tester.pump();
      expect(buf.caret, greaterThan(3), reason: '点在段落最右 → 光标靠后');
    });

    testWidgets('点屏幕定位后，镜像框的光标也跟着挪（否则下一个字会插到别处）',
        (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer('abcdef');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: EditView(buffer: buf)),
        ),
      ));
      await tester.pumpAndSettle();

      final Finder para = find.byType(InlineMathText);
      final Offset topLeft = tester.getTopLeft(para);
      final Size size = tester.getSize(para);
      await tester.tapAt(topLeft + Offset(1, size.height / 2));
      await tester.pump();

      final TextField f = tester.widget<TextField>(find.byType(TextField));
      expect(f.controller!.selection.baseOffset, buf.caret,
          reason: '镜像框的选区必须与缓冲区光标一致');
    });

    testWidgets('★ 列表项：逐格点击，映射必须精确（标记宽度不能被算进去）',
        (WidgetTester tester) async {
      // 内容「判别式」= 源区间 [2,5)；标记 `- ` 占 [0,2)
      final DocBuffer buf = DocBuffer('- 判别式\n- 第二项\n');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: EditView(buffer: buf)),
        ),
      ));
      await tester.pumpAndSettle();

      final Finder content = find.byType(InlineMathText).first;
      final Rect rect = tester.getRect(content);

      // 每个汉字约 12–13px；在段落**文字起点**附近逐格点
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

    testWidgets('★ 列表项：点内容区要落在内容里（标记段落不能把点抢走）',
        (WidgetTester tester) async {
      // 第 1 项：行首 `- ` 占 2 个字符，内容是「判别式」= 源区间 [2,5)
      final DocBuffer buf = DocBuffer('- 判别式\n- 第二项\n');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: EditView(buffer: buf)),
        ),
      ));
      await tester.pumpAndSettle();

      final Finder content = find.byType(InlineMathText).first;
      final Offset topLeft = tester.getTopLeft(content);
      final Size size = tester.getSize(content);

      // 点内容区最右边 → 应落在「判别式」的末尾（源偏移 5），
      // 而不是被只有 1 个码元的标记段落夹到偏移 3。
      await tester.tapAt(topLeft + Offset(size.width - 2, size.height / 2));
      await tester.pump();
      expect(buf.caret, 5,
          reason: '点内容区右端应落在内容末尾；落在 3 说明又是标记段落在抢点');
    });

    testWidgets('★ 镜像框跟着光标走（Web 上中文候选框就是靠它定位的）',
        (WidgetTester tester) async {
      // 三段文字，光标从第 1 段移到第 3 段时，镜像框的纵向位置应该跟着下去
      final DocBuffer buf = DocBuffer('第一段\n\n第二段\n\n第三段\n');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: EditView(buffer: buf)),
        ),
      ));
      await tester.pumpAndSettle();

      final Rect r1 = tester.getRect(find.byType(TextField));
      expect(r1.height, greaterThan(0),
          reason: '镜像框要有实际高度（否则候选框无处可放）；实际矩形 $r1');
      expect(r1.width, greaterThan(50),
          reason: '宽度要与段落一致，内部排版才接近文档；实际矩形 $r1');

      buf.setCaret(buf.length - 1); // 移到第三段（贴着文末的 \n 会落在空行上）
      await tester.pumpAndSettle();

      final Rect r2 = tester.getRect(find.byType(TextField));
      expect(r2.top, greaterThan(r1.top),
          reason: '光标下移后镜像框必须跟着下移（否则候选框会留在原地）');
    });

    testWidgets('键盘改动缓冲区后，镜像跟着同步（否则平台光标会漂）',
        (WidgetTester tester) async {
      final DocBuffer buf = DocBuffer('abc');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: EditView(buffer: buf)),
        ),
      ));
      await tester.showKeyboard(find.byType(TextField));
      await tester.pump();

      // 直接从缓冲区这一侧改（模拟 S3-3 的结构导航 / 工具栏改块类型）
      buf.setCaret(1);
      buf.insertText('X');
      await tester.pump();

      final TextField f = tester.widget<TextField>(find.byType(TextField));
      expect(f.controller!.text, 'aXbc');
      expect(f.controller!.selection.baseOffset, 2);
    });
  });
}
