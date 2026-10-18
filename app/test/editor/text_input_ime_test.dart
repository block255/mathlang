// 守卫测试：中文输入（IME）**组合期不写缓冲区、提交只写一次**（2026-10-18 真机实测的 bug）。
//
// 修复前的现象（用户）：「把打字过程中的拼音也输入进去」「打出来的字被复制了多份」。
// 探针日志（146 行）证明根因：**每次提交后清空平台元素**（`setEditingState('')`）会把
// IME 的组合态当场打断 —— `composing` 从有效的 `(0,1)/(0,2)` 退化成 `(-1,-1)`，
// 于是拼音被当成普通文本插入，且引擎改送"累积整串"⇒ 整串被反复提交。
//
// 改后两条硬判据（本文件就是它们）：
//   ① 组合中（composing 有效且非折叠）⇒ 一个字符都不提交；
//   ② 同一份平台文本重复送达 ⇒ 只提交一次（基线跟随）。
// 另外还验：组合结束只提交**候选词**，不把之前的拼音一起带上。

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/editor/text_input_surface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> committed;
  late TextInputSurfaceController surface;
  late FocusNode focus;

  setUp(() {
    committed = <String>[];
    focus = FocusNode();
    surface = TextInputSurfaceController(focusNode: focus)
      ..onCommitText = (String t) => committed.add(t);
  });

  tearDown(() {
    surface.dispose();
    focus.dispose();
  });

  TextEditingValue composing(String text) => TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
        composing: TextRange(start: 0, end: text.length),
      );

  TextEditingValue committedValue(String text) => TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );

  test('组合期（拼音）一个字符都不提交', () {
    surface.updateEditingValue(composing('n'));
    surface.updateEditingValue(composing('ni'));
    surface.updateEditingValue(composing("ni'hao"));
    expect(committed, isEmpty, reason: '拼音是组合中间态，绝不能进缓冲区');
  });

  test('组合结束只提交候选词本身（不带拼音）', () {
    surface.updateEditingValue(composing('n'));
    surface.updateEditingValue(composing('ni'));
    surface.updateEditingValue(composing("ni'hao"));
    surface.updateEditingValue(composing('你好')); // 候选词出现，仍标组合中
    surface.updateEditingValue(committedValue('你好')); // 组合结束
    expect(committed, <String>['你好']);
  });

  test('同一份平台文本重复送达 ⇒ 只提交一次（修复"字被复制多份"）', () {
    surface.updateEditingValue(composing('nihao'));
    surface.updateEditingValue(committedValue('你好'));
    surface.updateEditingValue(committedValue('你好'));
    surface.updateEditingValue(committedValue('你好'));
    expect(committed, <String>['你好'], reason: '基线必须跟随，否则每次都当新内容再插一遍');
  });

  test('后续普通输入只提交新增后缀', () {
    surface.updateEditingValue(composing('nihao'));
    surface.updateEditingValue(committedValue('你好'));
    surface.updateEditingValue(committedValue('你好a'));
    surface.updateEditingValue(committedValue('你好ab'));
    expect(committed, <String>['你好', 'a', 'b']);
  });
}
