// 数语引擎 · 光标归属的**全域不变量**测试（2026-10-15）
//
// ============================ 为什么是"不变量"而不是"逐例" ============================
// 2026-10-15，用户实测：「粘贴 `$\frac{}{}$` 直接消失了」（公式与光标一起消失）。
// 根因是光标归属有**一个偏移的洞**：
//   粘贴完光标恰好停在「**闭合 `$` 之后那一格**」（`absEnd + 1`），
//   而当时的判据 `c >= absStart && c <= absEnd` 不认它、段落又以公式结尾（后面没有文字段）
//   → **谁都不画**。于是没有空槽占位（空分数只有 3.4px 宽）+ 没有光标 = "消失"。
//
// ★ 事故当天全套 **267 条测试全绿** —— 因为它们是**逐例**的：
//   **没有一条在问"是不是每个偏移都有人认领"**。
//   本文件就是这个问题的正面回答：四条**全域**性质，任何一条红了都是同一类 bug 回来了。
//
// 判据只有一份：`caret_ownership.dart`（那之前有四份，其中一份是错的）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/caret_ownership.dart';
import 'package:mathlang/render/projection.dart';

/// 种子：既含**出事故的真实样本**，也含边界构造（空串 / 未闭合 / 段落以公式开头或结尾）
const List<String> kSeeds = <String>[
  // ★★ 真实事故样本：用户连粘三次之后，缓冲区尾部就是这样
  //    （实测缓冲区原文，见本次会话记录）
  r'设 $x^2+1$ 为多项式，$\frac{a}{b}=\sqrt{2}$ 为常数，求 $x$ 的值。$\frac{}{}$$\frac{}{}$$\frac{}{}$',
  r'文字。$\frac{}{}$', // ★ 事故的最小复现：段落以公式结尾
  r'$\frac{}{}$文字', // 段落以公式开头
  r'文字。$\frac{}{}$文字2', // 公式夹在中间
  r'$\frac{}{}$$\frac{}{}$', // 只有相邻公式（中间会拼出 `$$`）
  r'设 $x^2+1$ 为多项式，$\frac{a}{b}=\sqrt{2}$ 为常数，求 $x$ 的值。',
  r'a $b$ c $d$ e',
  r'没有公式',
  r'未闭合 $\frac{', // 半成品：`$` 未闭合
  r'$\sqrt[3]{x^{2n}}$ 与 $x_1$',
  r'$',
  r'$a$',
];

void main() {
  group('★ 全域不变量（每一条都对应一类真会漏出去的 bug）', () {
    for (final String src in kSeeds) {
      group('「$src」', () {
        test('P1 完备：每个偏移都有人认领（不许有洞）', () {
          final List<int> orphans = <int>[];
          for (var c = 0; c <= src.length; c++) {
            if (caretPlacement(src, c) == null) orphans.add(c);
          }
          expect(orphans, isEmpty,
              reason: '这些偏移没有任何分段认领：$orphans\n'
                  '→ 光标会被画到不存在的地方（用户看到"光标消失"）。\n'
                  r'★ 粘贴 `$\frac{}{}$` 之后光标就落在其中一个上。');
        });

        test('P2 归属单调：分段下标随偏移非递减（不许跳回前一段）', () {
          var last = -1;
          for (var c = 0; c <= src.length; c++) {
            final CaretPlacement pl = caretPlacement(src, c)!;
            expect(pl.segIndex, greaterThanOrEqualTo(last),
                reason: '偏移 $c 归属到分段 ${pl.segIndex}，比上一个（$last）还靠前 —— '
                    '说明区间重叠且"先到先得"被破坏（会画出两个光标或高亮叠色）');
            last = pl.segIndex;
          }
        });

        test('P3 段内偏移合法（否则注入 / 切片会越界）', () {
          final List<ProjectionSegment> segs = projectInline(src);
          for (var c = 0; c <= src.length; c++) {
            final CaretPlacement pl = caretPlacement(src, c)!;
            final ProjectionSegment s = segs[pl.segIndex];
            expect(pl.isMath, s.isMath);
            expect(pl.segStart, s.start);
            final int max = s.isMath ? s.tex.length : s.text.length;
            expect(pl.localRel, inInclusiveRange(0, max),
                reason: '偏移 $c 在分段 ${pl.segIndex} 里的相对偏移是 ${pl.localRel}，'
                    '超出 0..$max');
          }
        });

        test('P4 往返：文字段归属经 paragraphIndexMap 反查必须回到原偏移', () {
          // ★ 这条把"画在哪"（本模块）与"点哪落哪"（projection 的映射表）钉在一起：
          //   两份判据必须对同一个偏移说同一句话。
          final List<int> map = paragraphIndexMap(src);
          for (var c = 0; c <= src.length; c++) {
            final CaretPlacement pl = caretPlacement(src, c)!;
            if (pl.isMath) continue; // 数学段整体占段落一格，没有"格"可以反查到它的内部
            expect(pl.paragraphPos, lessThan(map.length));
            expect(map[pl.paragraphPos], c,
                reason: '偏移 $c → 段落第 ${pl.paragraphPos} 格，'
                    '但 paragraphIndexMap 说那一格对应源偏移 ${map[pl.paragraphPos]}');
          }
        });
      });
    }
  });

  group('★ 事故本身：粘贴后光标停的那一格必须归数学段', () {
    test(r'「文字。$\frac{}{}$」闭合 $ 之后那一格 → 归数学段，且夹进 tex 末尾', () {
      const String src = r'文字。$\frac{}{}$';
      // 文(0) 字(1) 。(2) $(3) 内容 4..12 $(13) → 「闭合 $ 之后」= 14
      final CaretPlacement after = caretPlacement(src, 14)!;
      expect(after.isMath, isTrue,
          reason: '★ 这一格原先**谁都不认领** → 光标与空槽占位一起消失');
      expect(after.localRel, 9,
          reason: r'tex `\frac{}{}` 长 9 → 夹进末尾，交给 injectCursor(tex, 9)');

      final CaretPlacement onDollar = caretPlacement(src, 13)!;
      expect(onDollar.isMath, isTrue);
      expect(onDollar.localRel, 9,
          reason: r'闭合 `$` 自己那一格同样画在公式**右边缘**（画的位置可以多对一；'
              '插入点仍然是两个不同的整数）');
    });

    test(r'开 `$` 那一格：前面有文字段就归它，段落以公式开头时归数学段', () {
      const String mid = r'文字。$\frac{}{}$';
      final CaretPlacement atDollar = caretPlacement(mid, 3)!;
      expect(atDollar.isMath, isFalse, reason: '前面有文字段 → 由它认领（画在文字末尾）');
      expect(atDollar.localRel, 3);

      const String head = r'$\frac{}{}$文字';
      final CaretPlacement lead = caretPlacement(head, 0)!;
      expect(lead.isMath, isTrue,
          reason: '段落以公式开头时前面没有文字段 → 必须由公式认领（否则又是那个洞）');
      expect(lead.localRel, 0);
    });

    test(r'相邻公式的接缝也要有人认领（`$$\frac{}{}$$` 这种拼出 `$$` 的地方）', () {
      const String src = r'$\frac{}{}$$\frac{}{}$';
      for (var c = 0; c <= src.length; c++) {
        expect(caretPlacement(src, c), isNotNull, reason: '偏移 $c 没人认领');
      }
    });

    test('空串是唯一允许返回 null 的情形（空行还不是一等公民）', () {
      expect(caretPlacement('', 0), isNull,
          reason: '空行没有渲染物可归属 —— 那是 W3/W4 那个问题，本模块不假装能解决它');
    });

    test('越界偏移会被夹回范围内（不抛异常）', () {
      const String src = r'a$b$c';
      expect(caretPlacement(src, -5), isNotNull);
      expect(caretPlacement(src, 999), isNotNull);
    });
  });
}
