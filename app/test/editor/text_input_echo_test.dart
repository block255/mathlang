// 2026-11-10 · 反馈 ②：平台"开始组合"的回声**不许**被当成新输入
//
// 引擎侧序列（源码，不是猜测）：
//   · `engine/.../windows/text_input_plugin.cc:126-139` `ComposeBeginHook()` ——
//     组合一开始就 `BeginComposing()` **然后发一次状态更新**；
//   · `.../common/text_input_model.cc` `TextInputModel::BeginComposing()` ——
//     `composing_range_ = TextRange(selection_.start())` ⇒ **组合区塌陷成一点**。
//   ⇒ 起组合的那一下会来一次「文本一字未变 + composing 塌陷」的更新，**里面没有新输入**。
//
// 现场（用户反馈 2）：先打一个中文左括号 `（`，接着打拼音 ⇒ 屏幕上是 `（（我`；
//   分式那一半：新文档按 `/`（自动展开成分式）后起拼音 ⇒ 叠套。
//
// 根因：`text_input_surface.updateEditingValue` 里那条 2026-10-18 的兜底
//   「平台重发同一份、长度 ≤ 1 ⇒ 当成又打了一个字」把**回声**吃成了新输入。
//
// 本文件钉三条：① 括号 · ② 分式（自动展开）· ③ 不回归：累积式连打同一个字仍要插两次。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/editor/edit_view.dart';
import 'package:mathlang/editor/text_input_surface.dart';

TextEditingValue _v(String text, [int? sel, TextRange? composing]) =>
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: sel ?? text.length),
      composing: composing ?? TextRange.empty,
    );

/// 起组合的回声：文本一模一样、composing 塌成一点（= 引擎 `BeginComposing()` 之后那次更新）
TextEditingValue _echo(String text) =>
    _v(text, text.length, TextRange(start: text.length, end: text.length));

void main() {
  group('① 输入面（纯逻辑）：回声不许产生提交', () {
    late FocusNode focus;
    late TextInputSurfaceController input;
    late List<String> committed;

    setUp(() {
      focus = FocusNode();
      input = TextInputSurfaceController(focusNode: focus);
      committed = <String>[];
      input.onCommitText = committed.add;
    });
    tearDown(() {
      input.dispose();
      focus.dispose();
    });

    test('★ 打 `（` → 起组合回声 → 拼音 → 提交 `我` ⇒ 只提交「（」「我」', () {
      input.updateEditingValue(_v('（', 1, const TextRange(start: 0, end: 1)));
      input.updateEditingValue(_v('（', 1)); // 提交「（」，基线 = `（`
      expect(committed, <String>['（']);

      // ★ 回声（文本没变、composing 塌陷）—— 改前这里会再插一个「（」
      input.updateEditingValue(_echo('（'));
      expect(committed, <String>['（'], reason: '回声里没有新输入，一个字都不许插');

      input.updateEditingValue(_v('（wo', 3, const TextRange(start: 1, end: 3)));
      input.updateEditingValue(_v('（我', 2)); // 选字结束
      expect(committed, <String>['（', '我']);
    });

    test('★ 不回归：累积式连打同一个字（a → aa）仍要插两次', () {
      input.updateEditingValue(_v('a', 1));
      input.updateEditingValue(_v('aa', 2));
      expect(committed, <String>['a', 'a']);
    });
  });

  group('② 真编辑器：分式不会叠套', () {
    testWidgets('`/` 自动展开后起组合回声 ⇒ 仍只有一个分式', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1100, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final DocBuffer buf = DocBuffer('');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: EditView(buffer: buf))),
      ));
      tester.state<EditViewState>(find.byType(EditView)).focusInput();
      await tester.pumpAndSettle();

      tester.testTextInput.updateEditingValue(_v('/'));
      await tester.pumpAndSettle();
      expect(buf.buf, r'$\frac{}{}$' '\n', reason: '`/` 应自动展开成一个分式');

      // ★ 起组合回声：改前这里会再插一个 `/` ⇒ 光标在分子里 ⇒ **又展开一个分式**
      tester.testTextInput.updateEditingValue(_echo('/'));
      await tester.pumpAndSettle();
      expect(buf.buf, r'$\frac{}{}$' '\n',
          reason: '回声不许再展开一个分式（改前是叠套：\\frac{\\frac{}{}}{}）');
    });
  });
}
