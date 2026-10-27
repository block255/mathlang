import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/block.dart';
import 'package:mathlang/core/doc_buffer.dart';

// ★ 2026-10-28：**非空文档一律以 `\n` 收尾**（`DocBuffer` 的不变量，只读基准 4 的地基）。
//   凡是在"文末"发生的插入/删除，编辑都会顺手补上那个行终止符（撤销/重做能精确还原它），
//   所以下面这些断言里的正文都比以前多一个 `\n` —— 这是**规格**，不是宽容。
void main() {
  group('基础编辑', () {
    test('插入文本并移动光标', () {
      final b = DocBuffer('ab');
      b.setCaret(1);
      b.insertText('X');
      expect(b.buf, 'aXb\n');
      expect(b.caret, 2);
    });

    test('光标越界被夹住', () {
      final b = DocBuffer('ab');
      b.setCaret(99);
      expect(b.caret, 2);
    });

    test('deleteBackward / deleteForward', () {
      final b = DocBuffer('abc');
      b.setCaret(2);
      b.deleteBackward();
      expect(b.buf, 'ac\n');
      expect(b.caret, 1);
      b.deleteForward();
      expect(b.buf, 'a\n');
    });

    test('有选区时替换选区', () {
      final b = DocBuffer('abcdef');
      b.setSelection(1, 4);
      expect(b.hasSelection, isTrue);
      b.insertText('X');
      expect(b.buf, 'aXef\n');
      expect(b.caret, 2);
      expect(b.hasSelection, isFalse);
    });
  });

  group('撤销 / 重做', () {
    test('逐步撤销回原文，逐步重做回终态', () {
      final b = DocBuffer('ab');
      b.setCaret(2);
      b.insertText('c');
      b.insertText('d');
      expect(b.buf, 'abcd\n');

      expect(b.undo(), isTrue);
      expect(b.buf, 'abc\n');
      expect(b.undo(), isTrue);
      // 撤销回到的是**归一之后**的原文（非空文档带一个尾换行）
      expect(b.buf, 'ab\n');
      expect(b.undo(), isFalse);
      expect(b.canUndo, isFalse);

      expect(b.redo(), isTrue);
      expect(b.buf, 'abc\n');
      expect(b.canUndo, isTrue);
    });

    test('新的编辑会清空重做栈', () {
      final b = DocBuffer('ab');
      b.setCaret(2);
      b.insertText('c');
      b.undo();
      expect(b.canRedo, isTrue);
      b.insertText('Z');
      expect(b.canRedo, isFalse);
    });

    test('删除也能撤销', () {
      final b = DocBuffer('abc');
      b.setCaret(3);
      b.deleteBackward();
      expect(b.buf, 'ab\n');
      b.undo();
      expect(b.buf, 'abc\n'); // 归一之后的原文
    });
  });

  group('输出侧写入约定（R3 / R8）', () {
    test('Enter = 新块：写入空行分隔', () {
      final b = DocBuffer('第一段');
      b.setCaret(3);
      b.newBlock();
      b.insertText('第二段');
      expect(b.buf, '第一段\n\n第二段\n');
      expect(b.blocks.blocks.map((x) => x.type).toList(),
          [BlockType.paragraph, BlockType.paragraph]);
    });

    test('★ Shift+Enter = 硬换行：行尾两个空格，仍属同一块', () {
      final b = DocBuffer('第一行');
      b.setCaret(3);
      b.softBreak();
      b.insertText('第二行');
      expect(b.buf, '第一行  \n第二行\n');
      expect(b.blocks.blocks.length, 1);
      expect(b.lines.hasHardBreak(0), isTrue);
    });
  });

  group('块类型切换（只改 L0 里的行首标记）', () {
    test('段落 → 标题 1', () {
      final b = DocBuffer('正文');
      b.setCaret(0);
      b.setLineBlockType(0, BlockType.heading1);
      expect(b.buf, '# 正文\n');
      expect(b.caret, 2);
    });

    test('标题 2 → 标题 1（剥掉旧标记）', () {
      final b = DocBuffer('## 标题');
      b.setLineBlockType(0, BlockType.heading1);
      expect(b.buf, '# 标题\n');
    });

    test('标题 → 段落（去掉标记）', () {
      final b = DocBuffer('### 标题');
      b.setLineBlockType(0, BlockType.paragraph);
      expect(b.buf, '标题\n');
    });

    test('段落 → 无序列表 / 有序列表', () {
      final b = DocBuffer('第一项\n第二项');
      b.setLineBlockType(0, BlockType.bulletList);
      expect(b.buf, '- 第一项\n第二项\n');
      b.setLineBlockType(1, BlockType.orderedList, order: 2);
      expect(b.buf, '- 第一项\n2. 第二项\n');
    });

    test('只动被点的那一行', () {
      final b = DocBuffer('第一行\n第二行');
      b.setLineBlockType(1, BlockType.heading2);
      expect(b.buf, '第一行\n## 第二行\n');
      expect(b.blocks.blocks.map((x) => x.type).toList(),
          [BlockType.paragraph, BlockType.heading2]);
    });

    test('整块语义的类型不能用这种方式切', () {
      final b = DocBuffer('x');
      expect(
        () => b.setLineBlockType(0, BlockType.math),
        throwsArgumentError,
      );
      expect(
        () => b.setLineBlockType(0, BlockType.pageBreak),
        throwsArgumentError,
      );
    });
  });

  group('normalize：有序列表重排（只在提交点跑）', () {
    test('序号重排为 1,2,3', () {
      final b = DocBuffer('1. 甲\n1. 乙\n1. 丙');
      b.renumberOrderedList(b.blocks, 0);
      expect(b.buf, '1. 甲\n2. 乙\n3. 丙\n');
    });

    test('重排不该把光标甩到文档末尾', () {
      final b = DocBuffer('1. 甲\n1. 乙');
      b.setCaret(0);
      b.renumberOrderedList(b.blocks, 0);
      expect(b.caret, lessThan(5));
    });

    test('非有序列表块不动', () {
      final b = DocBuffer('- 甲\n- 乙');
      b.renumberOrderedList(b.blocks, 0);
      expect(b.buf, '- 甲\n- 乙');
    });
  });
}
