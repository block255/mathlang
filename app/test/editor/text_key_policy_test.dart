// 「按空格文档区自己往下滚」的守卫（2026-10-17 用户实测）
//
// 根因：`EditView._onKey` 对可打印键返回 `ignored` ⇒ 键事件**冒泡给祖先 `Scrollable`**，
// 而 Flutter 默认快捷键里 **空格 = 向下翻页** ⇒ 文本区被翻走一块（标题栏不动，所以不是浏览器滚动）。

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/editor/edit_view.dart';

void main() {
  test('★ 空格属于"要产生文字的键" ⇒ `_onKey` 必须拦下它（否则会被 Scrollable 当翻页）', () {
    expect(isTextInputKey(LogicalKeyboardKey.space), isTrue);
  });

  test('★ 字母/数字/标点都算文字键', () {
    expect(isTextInputKey(LogicalKeyboardKey.keyA), isTrue);
    expect(isTextInputKey(LogicalKeyboardKey.digit0), isTrue);
    expect(isTextInputKey(LogicalKeyboardKey.comma), isTrue);
    expect(isTextInputKey(LogicalKeyboardKey.minus), isTrue);
  });

  test('★ 方向键/功能键/控制键**不算**文字键（它们各有专门分支或不该被吃）', () {
    expect(isTextInputKey(LogicalKeyboardKey.arrowUp), isFalse);
    expect(isTextInputKey(LogicalKeyboardKey.arrowLeft), isFalse);
    expect(isTextInputKey(LogicalKeyboardKey.enter), isFalse);
    expect(isTextInputKey(LogicalKeyboardKey.tab), isFalse);
    expect(isTextInputKey(LogicalKeyboardKey.f1), isFalse);
    expect(isTextInputKey(LogicalKeyboardKey.shiftLeft), isFalse);
    expect(isTextInputKey(LogicalKeyboardKey.controlLeft), isFalse);
  });
}
