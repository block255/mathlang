// 槽序与邻接测试（S3-3）
//
// 规格：notes/design/位点与结构导航.md §三（槽序 = 深度优先·源顺序；键位映射）
//       + §十-①（Tab 落点：空槽 → 槽末尾 → 退出公式）+ §十-⑤（↑↓ 用语法特例表）

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/site_adjacency.dart';

/// 把槽序画成标签，便于肉眼核对（`\frac` 分子 → 分子里的根号 → 分母）
List<String> _labels(CaretSiteTable t) => <String>[
      for (final SlotSpan s in slotOrder(t))
        s.path.map((SlotStep p) => '${p.command}(${p.argIndex})').join('>'),
    ];

void main() {
  group('槽序 = 深度优先 · 源顺序（§3.1）', () {
    test(r'\frac{\sqrt{x}}{y}：分子 → 分子里的根号 → 分母', () {
      final CaretSiteTable t = buildCaretSites(r'\frac{\sqrt{x}}{y}');
      expect(_labels(t), <String>['frac(0)', 'frac(0)>sqrt(0)', 'frac(1)']);
    });

    test('父槽与子槽起点相同时，父槽在前（前序，不是后序）', () {
      // 解析器是"子槽先入表"（后序），slotOrder 必须把它纠正成前序
      final CaretSiteTable t = buildCaretSites(r'\frac{\sqrt{x}}{y}');
      final List<SlotSpan> order = slotOrder(t);
      expect(order.first.path.length, 1, reason: '最外层槽必须排在最前');
    });
  });

  group('Tab 走槽（§十-①：空槽 → 槽内容末尾 → 退出公式）', () {
    test(r'\frac{}{}：分子 → 分母 → null（该退出公式了）', () {
      final CaretSiteTable t = buildCaretSites(r'\frac{}{}');
      expect(tabForward(t, 0), 6, reason: '先跳到空着的分子');
      expect(tabForward(t, 6), 8, reason: '再跳到空着的分母');
      expect(tabForward(t, 8), isNull, reason: '没有空槽了 → 走出公式');
    });

    test(r'\frac{a}{b}：没有空槽 → 落到最后一个槽内容末尾 → 再 Tab 退出', () {
      final CaretSiteTable t = buildCaretSites(r'\frac{a}{b}');
      expect(tabForward(t, 0), 10);
      expect(tabForward(t, 10), isNull);
    });

    test(r'\frac{a}{}：有内容时只认"空槽"', () {
      final CaretSiteTable t = buildCaretSites(r'\frac{a}{}');
      expect(tabForward(t, 0), 9, reason: '分子非空 → 直接去空着的分母（分母区间是 [9,9)）');
    });

    test('Shift+Tab 镜像：先空槽（从右往左）、再当前槽首、然后退出', () {
      final CaretSiteTable t = buildCaretSites(r'\frac{}{}');
      expect(tabBackward(t, 9), 8);
      expect(tabBackward(t, 8), 6);
      expect(tabBackward(t, 6), isNull);
    });

    test('降级表里不猜结构：Tab 返回 null（交给调用方）', () {
      // ★ 只有**多余的 `}`** 才降级；未闭合的 `{` 是打字中间态，不降级（源码里写死的规则）
      final CaretSiteTable t = buildCaretSites(r'a}b');
      expect(t.degraded, isTrue);
      expect(tabForward(t, 0), isNull);
    });
  });

  group('↑↓ 竖直邻接（§十-⑤：v1 用语法特例表）', () {
    test(r'\frac{a}{b}：分母 ↑ 到分子、分子 ↓ 到分母', () {
      final CaretSiteTable t = buildCaretSites(r'\frac{a}{b}');
      expect(verticalNeighbor(t, 9, up: true), 6);
      expect(verticalNeighbor(t, 6, up: false), 9);
    });

    test(r'x^2：指数是"右上"，**不算**竖直邻居 → 不移动', () {
      final CaretSiteTable t = buildCaretSites(r'x^2');
      expect(verticalNeighbor(t, 2, up: true), isNull);
      expect(verticalNeighbor(t, 3, up: false), isNull);
    });

    test(r'\sum_{i}^{n}：上下限互为竖直邻居（大算符上才成立）', () {
      final CaretSiteTable t = buildCaretSites(r'\sum_{i}^{n}');
      expect(verticalNeighbor(t, 6, up: true), 10, reason: '下限 ↑ 到上限');
      expect(verticalNeighbor(t, 10, up: false), 6, reason: '上限 ↓ 到下限');
    });

    test(r'\sqrt[3]{x}：次数在上、被开方数在下', () {
      final CaretSiteTable t = buildCaretSites(r'\sqrt[3]{x}');
      expect(verticalNeighbor(t, 9, up: true), 6, reason: '被开方数 ↑ 到次数');
      expect(verticalNeighbor(t, 6, up: false), 9);
    });

    test('主行上没有竖直邻居（不越出公式，避免误跳）', () {
      final CaretSiteTable t = buildCaretSites(r'\frac{a}{b}');
      expect(verticalNeighbor(t, 0, up: true), isNull);
      expect(verticalNeighbor(t, 11, up: false), isNull);
    });
  });
}
