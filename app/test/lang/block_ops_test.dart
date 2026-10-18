// 数语引擎 · **块类型快捷键**的守卫（S4-c）
//
// 判据都是"L0 里的行首标记"（《块模型与md往返》R2–R7），所以断言直接看字符串，
// 外加两条**全域不变量**：
//   ① 任何操作都**不许拆坏 `$` 的成对**（文档还得能解析）；
//   ② 操作后块模型必须认出目标类型（不是"看起来像"）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/block.dart';
import 'package:mathlang/lang/block_ops.dart';

/// 把结果落到文档上，返回 (新文档, 新光标)
({String doc, int caret}) run(String doc, int caret, BlockOp op) {
  final BlockOpResult? r = planBlockOp(doc, caret, op);
  if (r == null) return (doc: doc, caret: caret);
  return (doc: applyBlockOpTo(doc, r), caret: r.caret);
}

/// 光标所在行的块类型（走真实块模型）
BlockType typeAt(String doc, int caret) {
  final BlockIndex idx = BlockIndex.parse(doc);
  final int line = idx.lines.lineOf(caret);
  for (final Block b in idx.blocks) {
    if (line >= b.lineFrom && line < b.lineTo) return b.type;
  }
  return BlockType.paragraph;
}

void main() {
  group('标题：Ctrl+1/2/3（再按一次回正文）', () {
    test('正文行 ⇒ 标题 1，光标随标记右移', () {
      final r = run('例 1', 2, BlockOp.h1);
      expect(r.doc, '# 例 1');
      expect(r.caret, 4);
      expect(typeAt(r.doc, r.caret), BlockType.heading1);
    });

    test('再按一次 ⇒ 回正文（用户定的"再按回正文"）', () {
      final r1 = run('例 1', 0, BlockOp.h1);
      final r2 = run(r1.doc, r1.caret, BlockOp.h1);
      expect(r2.doc, '例 1');
      expect(typeAt(r2.doc, r2.caret), BlockType.paragraph);
    });

    test('标题 1 ⇒ 标题 2（替换而不是叠加）', () {
      final r = run('# 例', 3, BlockOp.h2);
      expect(r.doc, '## 例');
      expect(r.caret, 4);
    });

    test('直接给标题 3', () {
      final r = run('推导', 0, BlockOp.h3);
      expect(r.doc, '### 推导');
    });
  });

  group('列表 / 引用', () {
    test('有序列表：加与去', () {
      final a = run('牛奶', 0, BlockOp.ol);
      expect(a.doc, '1. 牛奶');
      final b = run(a.doc, a.caret, BlockOp.ol);
      expect(b.doc, '牛奶');
    });

    test('无序列表：加与去', () {
      final a = run('牛奶', 1, BlockOp.ul);
      expect(a.doc, '- 牛奶');
      expect(typeAt(a.doc, a.caret), BlockType.bulletList);
      final b = run(a.doc, a.caret, BlockOp.ul);
      expect(b.doc, '牛奶');
    });

    test('从列表换成引用（旧标记被替换，不是叠加）', () {
      final r = run('- 某句', 4, BlockOp.quote);
      expect(r.doc, '> 某句');
      expect(typeAt(r.doc, r.caret), BlockType.quote);
    });

    test('从列表换成标题', () {
      final r = run('- 某句', 4, BlockOp.h1);
      expect(r.doc, '# 某句');
    });
  });

  group('整块语义的行不许改行首标记', () {
    test('`\$\$` 围栏行上按标题 ⇒ 什么都不做', () {
      expect(planBlockOp('\$\$', 1, BlockOp.h1), isNull);
    });
    test('代码围栏行上按标题 ⇒ 什么都不做', () {
      expect(planBlockOp('```dart', 2, BlockOp.h2), isNull);
    });

    test('分页符行上按列表 ⇒ 什么都不做', () {
      expect(planBlockOp('<!-- pagebreak -->', 3, BlockOp.ul), isNull);
    });
  });

  group('代码块', () {
    test('加围栏 ⇒ 块模型认成 code，内容原样', () {
      final r = run('print(1)', 3, BlockOp.codeblock);
      expect(r.doc, '```\nprint(1)\n```');
      expect(typeAt(r.doc, r.caret), BlockType.code);
      expect(r.doc.contains('print(1)'), isTrue);
    });

    test('句中加围栏 ⇒ 前后两行各自成段（不粘在一起）', () {
      final r = run('前一段\nprint(1)\n后一段', 6, BlockOp.codeblock);
      expect(r.doc, '前一段\n```\nprint(1)\n```\n后一段');
      expect(typeAt(r.doc, r.caret), BlockType.code);
    });

    test('再按一次 ⇒ 拆掉围栏，只剩内容', () {
      final a = run('print(1)', 3, BlockOp.codeblock);
      final b = run(a.doc, a.caret, BlockOp.codeblock);
      expect(b.doc, 'print(1)');
      expect(typeAt(b.doc, b.caret), BlockType.paragraph);
    });
  });

  group('分页符', () {
    test('插入后自成一行，块模型认成 pageBreak', () {
      final r = run('前一段\n\n后一段', 1, BlockOp.pagebreak);
      expect(r.doc.contains('<!-- pagebreak -->'), isTrue);
      // 分页符必须独占一行
      final List<String> lines = r.doc.split('\n');
      expect(lines.contains('<!-- pagebreak -->'), isTrue);
      expect(typeAt(r.doc, r.doc.indexOf('<!-- pagebreak -->') + 2),
          BlockType.pageBreak);
    });

    test('幂等：紧邻已有分页符时不再插', () {
      final r1 = run('前一段\n\n后一段', 1, BlockOp.pagebreak);
      final int at = r1.doc.indexOf('<!-- pagebreak -->');
      final r2 = run(r1.doc, at, BlockOp.pagebreak);
      expect(r2.doc, r1.doc);
    });

    test('★ 光标在行内公式内部 ⇒ 分页符被推到公式之后（`\$` 仍成对）', () {
      final r = run(r'文字 $\frac{a}{b}$ 尾巴', 6, BlockOp.pagebreak);
      // 公式字符一个不少
      expect(r.doc.contains(r'$\frac{a}{b}$'), isTrue);
      expect(_mathFencesBalanced(r.doc), isTrue);
    });
  });

  group('★ 全域不变量：任何偏移 × 任何操作都不许拆坏 `\$`', () {
    const List<String> corpus = <String>[
      '普通一段话。',
      r'公式 $\frac{a}{b}$ 在中间。',
      '\$\$\nx=1\n\$\$',
      r'$\sum_{i=1}^{n}a_i$',
      '# 标题\n\n正文 \$x\$',
      r'- 列表项 $a^2$',
      '```\ncode\n```',
      '前\n\n<!-- pagebreak -->\n\n后',
      '',
    ];
    test('每个偏移都跑一遍八种操作', () {
      for (final String doc in corpus) {
        for (var at = 0; at <= doc.length; at++) {
          for (final BlockOp op in BlockOp.values) {
            final BlockOpResult? r = planBlockOp(doc, at, op);
            if (r == null) continue;
            final String out = applyBlockOpTo(doc, r);
            expect(_mathFencesBalanced(out), isTrue,
                reason: '${op.name} @ $at on "${doc.replaceAll('\n', r'\n')}" '
                    '⇒ "${out.replaceAll('\n', r'\n')}"');
            // 光标必须落在合法范围里（越界会在真机上直接抛）
            expect(r.caret, inInclusiveRange(0, out.length));
          }
        }
      }
    });
  });
}

/// 每一行的 `$` 成对，而且 `$$` 不被劈成单数
bool _mathFencesBalanced(String doc) {
  for (final String line in doc.split('\n')) {
    var n = 0;
    for (var i = 0; i < line.length; i++) {
      if (line[i] == '\\') {
        i++; // 跳过转义
        continue;
      }
      if (line[i] == r'$') n++;
    }
    if (n.isOdd) return false;
  }
  return true;
}
