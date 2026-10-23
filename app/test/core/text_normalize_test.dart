// ★★ 2026-10-23（批 2 · A）：**换行归一** —— 外部文件是 CRLF，整行语法会被 `\r` 静默打坏。
//
// 现场（用户那份 DeepSeek 抄写稿）：`CR=140 / LF=140`，`---` 分隔线 3 个**一个都没认出来**，
// 页面上原样印成 `---`。而 `isPageBreak` 因为用了 `trim()` 反而没事 —— 这就是"同一类判据两份写法"。
//
// 判据：进门（`loadDocument` / 粘贴）之后**缓冲区里不许有 `\r`**。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/block.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/core/text_normalize.dart';

void main() {
  group('normalizeNewlines', () {
    test('CRLF ⇒ LF', () {
      expect(normalizeNewlines('a\r\nb\r\n'), 'a\nb\n');
    });

    test('落单的 CR 也当成换行', () {
      expect(normalizeNewlines('a\rb'), 'a\nb');
    });

    test('本来就是 LF ⇒ 原样返回**同一个实例**（不做无谓拷贝）', () {
      const String s = 'a\nb';
      expect(identical(normalizeNewlines(s), s), isTrue);
    });
  });

  group('进门处归一', () {
    test('`DocBuffer.loadDocument` 之后缓冲区里没有 `\\r`', () {
      final DocBuffer buf = DocBuffer('')..loadDocument('甲\r\n乙\r\n\r\n丙');
      expect(buf.buf.contains('\r'), isFalse);
      expect(buf.buf, '甲\n乙\n\n丙');
    });

    test('★ 旧账：CRLF 文档现在也能认出 `---` 分隔线', () {
      // 归一之后
      final DocBuffer buf = DocBuffer('')
        ..loadDocument('上面\r\n\r\n---\r\n\r\n下面');
      final BlockIndex idx = BlockIndex.parse(buf.buf);
      expect(idx.blocks.where((Block b) => b.type == BlockType.divider).length, 1,
          reason: buf.buf.replaceAll('\n', r'\n'));
    });

    test('★ 第二道兜底：**没归一**的 CRLF 行，`isDivider` 也要认', () {
      expect(BlockMarkers.isDivider('---\r'), isTrue);
      expect(BlockMarkers.isDivider('---   \r'), isTrue);
    });
  });
}
