// ★★★ 2026-11-01（用户拍板 1–4）：**撇号归一到 `^{\prime}`**。
//
// 用户报的现象（`$f_{-}'f'_{+}$`）：
//   · 打字顺序不同 ⇒ 删除"粘连"完全相反：
//     `f'_{+}` 在 `f` 之后退格只删 `f`（剩 `'_{+}`）；`f_{-}'` 在整体之后退格只删 `f_{-}`（剩 `'`）。
//   · 而且有了撇之后，"f 与下标之间"那一格的语义也不一致。
// 根因：`'` 是 `^{\prime}` 的语法糖，但**在源码里只是普通字符** ⇒ `f'` 不是"一个对象"，
//   后面的 `_{-}` 贴在**撇**身上而不是 f 身上。
// 口径：提交点把裸撇归一成 `^{\prime}` ⇒ 撇变成普通 `^` 脚本，与 `x^{2}` 同一套模型。
//   **渲染逐像素等价**（探针：`f'` 与 `f^{\prime}` 都 14.39×13.89、叶盒 `"f""′"` 一致；
//   `f'_{-}` / `f^{\prime}_{-}` / `f_{-}'` / `f_{-}^{\prime}` 四种一律 18.91×20.31）。
//
// 本文件钉：① 归一结果 ② 两种打字顺序归一后**结构一致**（这是"顺序无关"的证据）
//          ③ `\text{}` 里的撇不动 ④ 幂等 ⑤ 渲染等价

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/normalize.dart';

import '../support/math_fonts.dart';

Future<Size> _size(WidgetTester tester, String tex) async {
  await tester.pumpWidget(MaterialApp(
    home: Center(
      child: Math.tex(tex,
          mathStyle: MathStyle.text,
          textStyle: const TextStyle(fontSize: 20)),
    ),
  ));
  await tester.pump();
  return tester.getSize(find.byType(Math));
}

void main() {
  setUpAll(() async => loadMathFonts());

  group('① 归一：裸撇 → ^{\'prime} 形态', () {
    test(r"f' ⇒ f^{\prime}", () {
      expect(normalizeTex(r"f'", 0).tex, r"f^{\prime}");
    });

    test(r"f'' ⇒ f^{\prime\prime}（连续两个撇）", () {
      expect(normalizeTex(r"f''", 0).tex, r"f^{\prime\prime}");
    });

    test(r"f'_{+} ⇒ f^{\prime}_{+}", () {
      expect(normalizeTex(r"f'_{+}", 0).tex, r"f^{\prime}_{+}");
    });

    test(r"f_{-}' ⇒ f^{\prime}_{-}（脚本顺序归一：撇永远排第一）", () {
      expect(normalizeTex(r"f_{-}'", 0).tex, r"f^{\prime}_{-}");
    });

    test(r"f_{+}' ⇒ f^{\prime}_{+}（同上：两种打字顺序产出**同一份源码**）", () {
      expect(normalizeTex(r"f_{+}'", 0).tex, r"f^{\prime}_{+}");
    });

    test(r"两种顺序归一后完全相等（顺序无关的直接证据）", () {
      expect(normalizeTex(r"f'_{+}", 0).tex, normalizeTex(r"f_{+}'", 0).tex);
    });
  });

  group('② 顺序无关：两种打字顺序归一后**结构一致**', () {
    test('位点数 / 层深序列 / 粘合标记都一致', () {
      const String a = r"f^{\prime}_{+}"; // 先撇后下标
      const String b = r"f_{+}^{\prime}"; // 先下标后撇
      final CaretSiteTable ta = buildCaretSites(a);
      final CaretSiteTable tb = buildCaretSites(b);
      expect(ta.sites.length, tb.sites.length,
          reason: '位点数必须一样（否则一处能停、另一处不能）');
      expect(
        ta.sites.map((CaretSite s) => '${s.path.length}/${s.glue}').toList(),
        tb.sites.map((CaretSite s) => '${s.path.length}/${s.glue}').toList(),
        reason: '每一格的层深与粘合标记必须一一对应',
      );
    });
  });

  group('③ 正文里的撇不动', () {
    test(r"\text{don't} 原样", () {
      const String tex = r"\text{don't}";
      expect(normalizeTex(tex, 0).tex, tex);
    });

    test(r"\mbox{don't} 原样", () {
      const String tex = r"\mbox{don't}";
      expect(normalizeTex(tex, 0).tex, tex);
    });
  });

  group('④ 幂等', () {
    test(r"f'_{+} 归一后再跑不变", () {
      final NormalizeResult once = normalizeTex(r"f'_{+}", 0);
      final NormalizeResult twice = normalizeTex(once.tex, once.caret);
      expect(twice.tex, once.tex);
      expect(twice.changed, isFalse);
    });
  });

  group('⑤ 渲染等价（归一是纯存储改写）', () {
    testWidgets(r"f' 与 f^{\prime} 尺寸完全一致", (WidgetTester tester) async {
      final Size a = await _size(tester, r"f'");
      final Size b = await _size(tester, r"f^{\prime}");
      expect((a.width - b.width).abs(), lessThan(0.01));
      expect((a.height - b.height).abs(), lessThan(0.01));
    });

    testWidgets(r"f'_{-} / f^{\prime}_{-} / f_{-}' / f_{-}^{\prime} 四种一致",
        (WidgetTester tester) async {
      final List<Size> sizes = <Size>[
        await _size(tester, r"f'_{-}"),
        await _size(tester, r"f^{\prime}_{-}"),
        await _size(tester, r"f_{-}'"),
        await _size(tester, r"f_{-}^{\prime}"),
      ];
      for (final Size s in sizes.skip(1)) {
        expect((s.width - sizes.first.width).abs(), lessThan(0.01));
        expect((s.height - sizes.first.height).abs(), lessThan(0.01));
      }
    });
  });
}
