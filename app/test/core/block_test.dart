import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/block.dart';

/// L0 里 `$$` 的写法（Dart 字符串里 `$` 要转义，所以用 raw）
const String d2 = r'$$';

List<BlockType> typesOf(String src) =>
    BlockIndex.parse(src).blocks.map((b) => b.type).toList();

void main() {
  group('R0 归一化（仅导入时）', () {
    test('剥 UTF-8 BOM，CRLF / CR 归一为 LF', () {
      expect(BlockMarkers.normalizeImported('\uFEFFa\r\nb\rc'), 'a\nb\nc');
    });

    test('★ 不 trim 行尾空格（R8 的硬换行标记就是两个尾随空格）', () {
      expect(BlockMarkers.normalizeImported('a  \n'), 'a  \n');
    });
  });

  group('R1 空行是边界，且只在块外', () {
    test('空行切出两个段落', () {
      final idx = BlockIndex.parse('第一段\n\n第二段');
      expect(idx.blocks.length, 2);
      expect(idx.blocks.every((b) => b.type == BlockType.paragraph), isTrue);
    });

    test('多个连续空行 = 一个边界，不产生空块', () {
      expect(BlockIndex.parse('a\n\n\n\nb').blocks.length, 2);
    });

    test('★ 公式块内部的空行是内容，不切块', () {
      final src = '$d2\na = b\n\nc = d\n$d2';
      final idx = BlockIndex.parse(src);
      expect(idx.blocks.length, 1);
      expect(idx.blocks.single.type, BlockType.math);
      expect(idx.blocks.single.lineCount, 5);
    });
  });

  group('R2 标题', () {
    test('标题打断段落', () {
      expect(typesOf('正文一行\n# 标题\n又一段'),
          [BlockType.paragraph, BlockType.heading1, BlockType.paragraph]);
    });

    test('`#` 后面没空格不算标题', () {
      expect(typesOf('#不是标题'), [BlockType.paragraph]);
    });

    test('4–6 级按 3 级处理', () {
      expect(typesOf('#### 四级'), [BlockType.heading3]);
      expect(typesOf('###### 六级'), [BlockType.heading3]);
    });

    test('三级标题各自成块', () {
      expect(typesOf('# 一\n## 二\n### 三'),
          [BlockType.heading1, BlockType.heading2, BlockType.heading3]);
    });
  });

  group('R3 段落', () {
    test('连续行合并成一个段落块（块内 \\n 是软换行）', () {
      final idx = BlockIndex.parse('第一行\n第二行\n第三行');
      expect(idx.blocks.length, 1);
      expect(idx.blocks.single.lineCount, 3);
    });
  });

  group('R4 列表', () {
    test('无序列表整组一块，续行归入其项', () {
      final idx = BlockIndex.parse('- a\n  cont\n- b');
      expect(idx.blocks.length, 1);
      expect(idx.blocks.single.type, BlockType.bulletList);
      expect(idx.blocks.single.lineTo, 3);
    });

    test('★ 每个列表项 = 1 个 FlowUnit（含续行）', () {
      final idx = BlockIndex.parse('- a\n  cont\n- b');
      expect(idx.flowUnits.length, 2);
      expect(idx.flowUnits[0].lineFrom, 0);
      expect(idx.flowUnits[0].lineTo, 2);
      expect(idx.flowUnits[1].lineFrom, 2);
      expect(idx.flowUnits[1].lineTo, 3);
    });

    test('空行结束列表', () {
      expect(typesOf('- a\n\n- b'),
          [BlockType.bulletList, BlockType.bulletList]);
    });

    test('有 / 无序不合并', () {
      expect(typesOf('- a\n1. b'),
          [BlockType.bulletList, BlockType.orderedList]);
    });

    test('有序列表识别为 orderedList', () {
      expect(typesOf('1. a\n2. b\n3. c'), [BlockType.orderedList]);
    });

    test('列表项之间不空行（紧凑列表）', () {
      final idx = BlockIndex.parse('- a\n- b\n- c');
      expect(idx.blocks.length, 1);
      expect(idx.flowUnits.length, 3);
    });
  });

  group('R5 公式块', () {
    // 注意：测试名里带 `$$` 时必须用 raw 字符串，否则 `$` 会被当成插值
    test(r'多行公式围栏 $$…$$ 一块', () {
      final idx = BlockIndex.parse('$d2\na = b\nc = d\n$d2');
      expect(idx.blocks.single.type, BlockType.math);
      expect(idx.blocks.single.lineCount, 4);
    });

    test(r'同行闭合 $$x=1$$ 也算一块', () {
      expect(typesOf('$d2 x = 1 $d2'), [BlockType.math]);
    });

    test('未闭合 → 吞到文末', () {
      final idx = BlockIndex.parse('$d2\na = b\nc = d');
      expect(idx.blocks.length, 1);
      expect(idx.blocks.single.type, BlockType.math);
      expect(idx.blocks.single.lineCount, 3);
    });

    test('★ 公式块整块 = 1 个 FlowUnit（不切）', () {
      final idx = BlockIndex.parse('$d2\n\\begin{aligned}\na &= b\n\\end{aligned}\n$d2');
      expect(idx.flowUnits.length, 1);
      expect(idx.flowUnits.single.lineTo - idx.flowUnits.single.lineFrom, 5);
    });
  });

  group('R6 代码块', () {
    test('围栏一块，内部空行不算边界', () {
      final idx = BlockIndex.parse('```\ncode\n\nmore\n```');
      expect(idx.blocks.single.type, BlockType.code);
      expect(idx.blocks.single.lineCount, 5);
    });
  });

  group('R7 分页符 / 分隔线', () {
    test('分页符打断段落', () {
      expect(typesOf('正文\n<!-- pagebreak -->\n正文 2'),
          [BlockType.paragraph, BlockType.pageBreak, BlockType.paragraph]);
    });

    test('分隔线打断段落', () {
      expect(typesOf('正文\n---\n正文 2'),
          [BlockType.paragraph, BlockType.divider, BlockType.paragraph]);
    });
  });

  group('R8 硬换行', () {
    test('行尾两个空格 = 硬换行，仍属同一块', () {
      final idx = BlockIndex.parse('第一行  \n第二行');
      expect(idx.blocks.length, 1);
      expect(idx.lines.hasHardBreak(0), isTrue);
      expect(idx.lines.hasHardBreak(1), isFalse);
    });

    test('★ 两个尾随空格被原样保留', () {
      expect(BlockIndex.parse('第一行  \n第二行').lines.text(0), '第一行  ');
    });

    test('行尾反斜杠也算硬换行', () {
      expect(BlockIndex.parse('a\\\nb').lines.hasHardBreak(0), isTrue);
    });
  });

  group('引用', () {
    test('连续引用行 = 一块；每个源行 = 1 个 FlowUnit', () {
      final idx = BlockIndex.parse('> a\n> b');
      expect(idx.blocks.single.type, BlockType.quote);
      expect(idx.flowUnits.length, 2);
    });
  });

  group('L1 行索引', () {
    test('尾随换行会产生一个空行（光标可以落在那里）', () {
      final li = LineIndex.of('a\nb\n');
      expect(li.count, 3);
      expect(li.text(2), '');
    });

    test('lineOf（换行符本身属它前面那行）', () {
      final li = LineIndex.of('ab\ncd');
      expect(li.lineOf(0), 0);
      expect(li.lineOf(2), 0);
      expect(li.lineOf(3), 1);
      expect(li.lineOf(5), 1);
    });
  });

  group('行首标记识别 / 生成', () {
    test('markerLength', () {
      expect(BlockMarkers.markerLength('## x'), 3);
      expect(BlockMarkers.markerLength('- x'), 2);
      expect(BlockMarkers.markerLength('12. x'), 4);
      expect(BlockMarkers.markerLength('> x'), 2);
      expect(BlockMarkers.markerLength('普通文字'), 0);
    });

    test('markerFor', () {
      expect(BlockMarkers.markerFor(BlockType.heading1), '# ');
      expect(BlockMarkers.markerFor(BlockType.paragraph), '');
      expect(BlockMarkers.markerFor(BlockType.orderedList, order: 3), '3. ');
      expect(BlockMarkers.markerFor(BlockType.math), isNull);
      expect(BlockMarkers.markerFor(BlockType.pageBreak), isNull);
    });
  });
}
