// 数语引擎 · **撤销分组**的守卫（S4-e-①，2026-10-18）
//
// 用户口径：「连续打字合并成一步」——但**一次语义操作**（模板、粘贴、自动展开、整段删）
// 本来就该独占一步。所以判据是：
//   ① 连续打字（500ms 内、落点接得上）⇒ **一步**撤销；
//   ② 停顿超过窗口 ⇒ 断组，分两步；
//   ③ 两次之间夹了别的动作 ⇒ 断组；
//   ④ 连续退格同理；
//   ⑤ 打字 ↔ 退格**不互相合并**（不同类）。
//
// ★ 2026-10-28：正文现在一律以 `\n` 收尾（`DocBuffer` 的不变量），所以断言里的缓冲区
//   都多一个 `\n`；但那个 `\n` 由 `Edit.eol` 表达、**不算用户输入的内容**，
//   所以"连续退格/连续打字"的合组判据一个都没变（`ab\n` 退两下仍然是一步）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';

void main() {
  group('① 连续打字 ⇒ 一步撤销', () {
    test('打 5 个字（coalesce）⇒ 撤销栈 1 条，撤销回到空', () {
      final DocBuffer b = DocBuffer('');
      for (final String ch in <String>['a', 'b', 'c', 'd', 'e']) {
        b.replace(b.caret, b.caret, ch, coalesce: true);
      }
      expect(b.buf, 'abcde\n');
      expect(b.undo(), isTrue);
      expect(b.buf, '', reason: '一步就该回到最初');
      expect(b.canUndo, isFalse);
    });

    test('不传 coalesce（默认）⇒ 每个字符各一步', () {
      final DocBuffer b = DocBuffer('');
      for (final String ch in <String>['a', 'b', 'c']) {
        b.replace(b.caret, b.caret, ch);
      }
      expect(b.undo(), isTrue);
      expect(b.buf, 'ab\n', reason: '一次撤销只回一个字');
    });

    test('★ 落点接不上 ⇒ 不合并（在别处打字要独立成步）', () {
      final DocBuffer b = DocBuffer('');
      b.replace(0, 0, 'a', coalesce: true);
      b.replace(0, 0, 'b', coalesce: true); // 插在 a **之前**，落点不接 ⇒ 不合并
      expect(b.buf, 'ba\n');
      b.undo();
      expect(b.buf, 'a\n', reason: '只撤掉 b');
    });
  });

  group('② 连续退格 ⇒ 一步撤销', () {
    test('退 3 个字符（coalesce）⇒ 一步回来', () {
      final DocBuffer b = DocBuffer('abcd')..setCaret(4);
      for (var i = 0; i < 3; i++) {
        b.replace(b.caret - 1, b.caret, '', coalesce: true);
      }
      expect(b.buf, 'a\n');
      expect(b.undo(), isTrue);
      expect(b.buf, 'abcd\n', reason: '一步就全回来（回到归一之后的原文）');
      expect(b.canUndo, isFalse);
    });
  });

  group('③ 打字 ↔ 退格不合并（不同类）', () {
    test('打两个再退一个 ⇒ 两步', () {
      final DocBuffer b = DocBuffer('');
      b.replace(0, 0, 'a', coalesce: true);
      b.replace(1, 1, 'b', coalesce: true);
      b.replace(1, 2, '', coalesce: true);
      expect(b.buf, 'a\n');
      expect(b.undo(), isTrue);
      expect(b.buf, 'ab\n', reason: '第一步只撤掉那次退格');
      expect(b.undo(), isTrue);
      expect(b.buf, '', reason: '第二步撤掉两个字的输入');
    });
  });

  group('④ 重做栈：合并之后仍然正确', () {
    test('合并的一段可以撤销再重做回原样', () {
      final DocBuffer b = DocBuffer('甲');
      b.replace(1, 1, '乙', coalesce: true);
      b.replace(2, 2, '丙', coalesce: true);
      expect(b.buf, '甲乙丙\n');
      b.undo();
      expect(b.buf, '甲\n');
      b.redo();
      expect(b.buf, '甲乙丙\n', reason: '合并成一条之后，重做也要一次回来');
    });
  });

  group('⑤ 合并不会破坏"一次语义编辑 = 一步"', () {
    test('整段替换（不传 coalesce）依旧独占一步', () {
      final DocBuffer b = DocBuffer(r'前$\sqrt{}$后');
      final int at = b.buf.indexOf(r'$\sqrt{}$');
      // 模拟"删掉整个结构"（区间替换，不合并）
      b.replace(at, at + r'$\sqrt{}$'.length, '');
      expect(b.buf, '前后\n');
      b.undo();
      // ★ 撤销回到的是**归一之后**的原文（非空文档带一个尾换行；看不见，也不该由撤销来抹掉）
      expect(b.buf, '前\$\\sqrt{}\$后\n');
    });
  });
}
