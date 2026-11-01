// 2026-11-01（反馈 10 / 22 ＋ F15）：**光标不许落在行间块的围栏字符上**，且每一步都要前进。
//
// ## 为什么单开一条
// 行内公式早就有这条口径（`math_nav` 头注释："跨 `$` 边界进公式，**且光标不落在 `$` 上**"），
// 行间块一直没有。后果不是"位置难看"，是**数据级损坏**：在 `$$` 的两个 `$` 之间打字，
// 那一行就不再以 `$$` 开头（`w$$` / `$w$`）⇒ 后面**所有**块的围栏配对全体错位
// ⇒ 一串 `[公式不完整]` ＋ 裸源码（用户 2026-11-01 两张图）。
//
// ## 要钉的四件事
//   ① `→` 从上一行末尾一步进到**内容起点**（`contentStart`），不经过 `$$` 任何一个 `$`；
//   ② 行间块的 tex 末尾按 `→` 必须**前进**（原来算回同一格 = "按了没反应"，台账 F15）；
//   ③ `←` 从公式第一个位置出去，落到**上一行末尾**，不落在 `$` 上；
//   ④ **全域**：把文档从头 `→` 到尾，每一步都前进、且一次都不落在围栏字符上。
//
// ★ 另外两件同一批的相邻事（不在本文件）：
//   · 点"块前那段空白"落内容起点 —— `doc_view` 的 `landFirst`，由 `block_landing_test` 钉；
//   · 零高度公式盒不许算出 NaN —— `math_caret_test` 的像素组已有 NaN 兜底，
//     结构上的修法在 `doc_view` 的 `ConstrainedBox(minWidth/minHeight: 1)`。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/block.dart';
import 'package:mathlang/render/math_nav.dart';

/// 文档里所有 `$$` 的 `$` 字符偏移（这些格子**永远**不许成为落点）。
Set<int> _fenceChars(String src) {
  final Set<int> out = <int>{};
  final BlockIndex idx = BlockIndex.parse(src);
  for (final Block b in idx.blocks) {
    if (b.type != BlockType.math) continue;
    for (var l = b.lineFrom; l < b.lineTo; l++) {
      final String raw = idx.lines.text(l);
      if (raw.trim() != r'$$') continue;
      final int lead = raw.length - raw.trimLeft().length;
      final int s = idx.lines.starts[l] + lead;
      out.add(s);
      out.add(s + 1);
    }
  }
  return out;
}

/// 行间块的内容起点（= 块的第一个"可打字位置"）。
int _contentStart(String src, int blockLineStart) =>
    displayTexStartAt(src, blockLineStart)!;

const Map<String, String> kDocs = <String, String>{
  '① 块前紧贴文字': '甲\n\$\$\nx=1\n\$\$\n乙\n',
  '② 块前空一行': '甲\n\n\$\$\nx=1\n\$\$\n\n乙\n',
  '③ 两块紧贴': '甲\n\n\$\$\nx\n\$\$\n\$\$\ny\n\$\$\n\n乙\n',
  '④ 两块之间空一行': '甲\n\n\$\$\nx\n\$\$\n\n\$\$\ny\n\$\$\n\n乙\n',
  '⑤ 三块紧贴（文首）': '\$\$\na\n\$\$\n\$\$\nb\n\$\$\n\$\$\nc\n\$\$\n',
  '⑥ 块在文末': '甲\n\n\$\$\nx\n\$\$\n',
  '⑦ 单行闭合块': '甲\n\$\$x=1\$\$\n乙\n',
};

void main() {
  group('围栏不是落点', () {
    test('★★★ 全域：从头 `→` 到尾，每一步都前进且一次都不落在围栏字符上', () {
      for (final MapEntry<String, String> d in kDocs.entries) {
        final Set<int> fences = _fenceChars(d.value);
        final List<int> hits = <int>[];
        var c = 0;
        var steps = 0;
        while (c < d.value.length) {
          final int n = nextCaretOffset(d.value, c);
          expect(n, greaterThan(c),
              reason: '${d.key}：`→` 在 $c 处不前进（算回同一格 = 按了没反应）');
          c = n;
          steps++;
          if (fences.contains(c)) hits.add(c);
          if (steps > 400) break;
        }
        expect(steps, greaterThan(0));
        expect(hits, isEmpty,
            reason: '${d.key}：这些落点停在 `\$\$` 的 `\$` 上 —— $hits。'
                '在那一格打字会把围栏劈开（`w\$\$`），后面全体配对错位');
      }
    });

    test('★★ 进块：位点 = 内容起点（不是 `\$\$`）', () {
      // 甲⏎⏎$$⏎x=1⏎$$⏎⏎乙 —— 文字行尾 → 进块
      const String doc = '甲\n\n\$\$\nx=1\n\$\$\n\n乙\n';
      final int textEnd = doc.indexOf('\n'); // 「甲」后面那一格
      final int blockStart = doc.indexOf(r'$$');
      final int content = _contentStart(doc, blockStart);
      expect(nextCaretOffset(doc, textEnd), content,
          reason: '★ 一步进到公式内容起点；若等于 $blockStart = 停在围栏上');
    });

    test('★★ 出块：tex 末尾按 `→` 必须前进（F15）', () {
      const String doc = '甲\n\n\$\$\nx=1\n\$\$\n\n乙\n';
      final int blockStart = doc.indexOf(r'$$');
      final MathRegion r = mathRegionAt(doc, blockStart + 1)!;
      final int texEnd = r.contentStart + r.tex.length; // 公式最后一个位置
      final int n = nextCaretOffset(doc, texEnd);
      expect(n, greaterThan(texEnd),
          reason: '★ 原来在行间块的 tex 末尾 `→` 算回同一格 ⇒ 用户看到"按了没反应"');
      expect(_fenceChars(doc).contains(n), isFalse);
    });

    test('★★ `←` 从公式第一个位置出去 ⇒ 上一行末尾（不落在 `\$\$`）', () {
      const String doc = '甲\n\n\$\$\nx=1\n\$\$\n\n乙\n';
      final int blockStart = doc.indexOf(r'$$');
      final int content = _contentStart(doc, blockStart);
      final int p = prevCaretOffset(doc, content);
      expect(p, lessThan(blockStart),
          reason: '★ 原来 `←` 直接返回 `openStart`（= 围栏第一个 `\$`），在那里打字同样劈围栏');
      expect(_fenceChars(doc).contains(p), isFalse);
    });
  });
}
