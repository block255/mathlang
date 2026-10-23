// ★★ 2026-10-23（批 2 · A）：**整行 `---` 才是分隔线**（用户 2026-10-23 确认口径）。
//
// 规则（代码里本来就有，`_dividerRe`）：整行 3 个以上的 `-` / `*` / `_`，行首最多 3 个空格；
// 其余位置（句子中间、只有两个减号、四个空格缩进、代码块/公式块内部）都**不是**分隔线。
//
// 这份守卫是新加的：老代码没有专门测过"分隔线"这条（AI 答案里却到处都是 `---`）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/block.dart';

int _dividers(String src) =>
    BlockIndex.parse(src).blocks.where((Block b) => b.type == BlockType.divider).length;

void main() {
  group('认：整行 3 个以上', () {
    test('`---` / `***` / `___`', () {
      for (final String line in <String>['---', '***', '___', '----', '-----']) {
        expect(_dividers('a\n\n$line\n\nb'), 1, reason: line);
      }
    });

    test('行首 3 个空格以内仍算', () {
      expect(_dividers('a\n\n   ---\n\nb'), 1);
    });

    test('行尾有空格 / `\\r`（CRLF 残留）也认', () {
      expect(_dividers('a\n\n---   \n\nb'), 1);
      expect(_dividers('a\n\n---\r\n\r\nb'), 1);
    });

    test('文首 / 文末单独一行也认', () {
      expect(_dividers('---'), 1);
      expect(_dividers('---\n'), 1);
      expect(_dividers('\n---\n'), 1);
    });
  });

  group('不认：其它位置 / 其它形态', () {
    test('只有两个减号', () {
      expect(_dividers('a\n\n--\n\nb'), 0);
    });

    test('夹在句子里', () {
      expect(_dividers('a --- b'), 0);
    });

    test('四个空格缩进（那是代码块的味道）', () {
      expect(_dividers('a\n\n    ---\n\nb'), 0);
    });

    test('公式块内部', () {
      expect(_dividers('a\n\n\$\$\n---\n\$\$\n\nb'), 0);
    });

    test('代码围栏内部', () {
      expect(_dividers('a\n\n```\n---\n```\n\nb'), 0);
    });
  });
}
