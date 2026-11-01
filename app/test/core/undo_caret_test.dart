// 反馈 5（2026-10-30 · R11）守卫：**撤销要把光标与选区一起还回去**。
//
// 病灶：5 处"整篇 replace"（面板插符号 / 自动展开 / 块类型 / 分页符）让 `Edit`
//   记成 `start=0 / removed=整篇旧文档`；撤销走 `_setCaretRaw(start + removed.length)`
//   = **文末**（用户报的"Ctrl+Z 后光标跑到下一行"）。
// 口径：**撤销用记录、不靠推断** —— `Edit` 带 `caretBefore/After` 与 `anchorBefore/After`。
//
// 改前必红：① 撤销后光标 = 文末（不是编辑前那一格）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';

void main() {
  test('① 整篇 replace（模拟插符号）撤销后光标回到编辑前的位置', () {
    final DocBuffer buf = DocBuffer('甲\n乙丙\n丁\n');
    buf.setCaret(4); // 「丙」之后
    final int before = buf.caret;
    final String beforeText = buf.buf;

    // 模拟 _applyAutoExpand / _insertTexViaSymbolPath：整篇替换
    final String next = buf.buf.replaceRange(4, 4, r'\frac{}{}');
    buf.replace(0, buf.buf.length, next);
    expect(buf.buf, isNot(beforeText), reason: '前提：这次编辑真的改了缓冲区');

    expect(buf.undo(), isTrue);
    expect(buf.buf, beforeText, reason: '撤销要还原缓冲区');
    expect(buf.caret, before, reason: '撤销要还原光标（改前会跳到文末）');
  });

  test('② 最小差分：整篇 replace 也能算出局部区间（撤销组不被并坏）', () {
    final DocBuffer buf = DocBuffer('甲\n乙丙\n丁\n');
    buf.setCaret(4);
    final String next = buf.buf.replaceRange(4, 4, r'\sqrt{}');
    buf.replace(0, buf.buf.length, next);
    // 撤销之后光标必须还在 4（= 插入点），而不是 6（插入物末尾）或文末
    buf.undo();
    expect(buf.caret, 4);
    // 重做回到"编辑后"
    expect(buf.redo(), isTrue);
    expect(buf.buf, next);
    expect(buf.caret, 4 + 7, reason: '重做后光标 = 插入物末尾');
  });

  test('③ 选区也一起还原', () {
    final DocBuffer buf = DocBuffer('abcdef\n');
    buf.setSelection(1, 4); // 选中 bcd
    final String before = buf.buf;
    buf.insertText('Z'); // 有选区 ⇒ 替换掉选区
    expect(buf.buf, 'aZef\n');

    expect(buf.undo(), isTrue);
    expect(buf.buf, before);
    expect(buf.selectionStart, 1, reason: '撤销后选区起点要还原');
    expect(buf.selectionEnd, 4, reason: '撤销后选区终点要还原');
  });
}
