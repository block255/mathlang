// 2026-11-01（反馈 19）：**拖选分子，不许把分母一起涂上**。
//
// ## 现场
// 用户：`(2) lim_{x→∞} (x^2+1)/(2x^2+x-1)` 里，只想选分子 `x^2+1`，
// 拖选动作是对的，但**分母**和**`x→∞` 那个下标**跟着一起被涂上了。
//
// ## 根因（`selectionBands` 的两条兜底规则）
// 底色是按**配对组**（= 渲染对象）铺的，判据是"组的源区间与选区相交"。这没错 ——
// 探针实测组区间是干净的：分子 `[23,24) [26,27) [28,29) [29,30)`、分母 `[32,33) …`。
// 错的是后面那条"紧邻已选中盒也跟着铺"的兜底：
//   ① **"只传播一轮"其实会连锁** —— `picked[i]` 在同一次循环里被改，i+1 立刻看见它。
//      而引擎的**渲染顺序 ≠ 源码顺序**（分式就是这样：分子盒和分母盒在扫描顺序上相邻），
//      于是选中分子会顺着索引把整条分母一路染色（实测：11 条底色、跨 4 个视觉行）；
//   ② **有主的盒也参与传播** —— 它的源区间明明在选区之外，却被邻居"带"进来。
//
// ## 修法
//   ① 只给**没有组**的盒兜底（那才是这条规则的初衷：配对算法漏掉的盒）；
//   ② 用**快照**判邻居 ⇒ 真的只传播一轮。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/hit_map.dart';
import 'package:mathlang/render/slot_marks.dart';

const String kTex = r'\lim_{x\to\infty}\frac{x^{2}+1}{2x^{2}+x-1}';
const String kNum = 'x^{2}+1';
const String kDen = '2x^{2}+x-1';

Future<({List<Rect> bands, RenderObject root})> _bands(
  WidgetTester tester,
  String which,
) async {
  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: Math.tex(
          renderMathTex(kTex, caretRel: -1, showCursor: false),
          key: key,
          mathStyle: MathStyle.display,
          textStyle: const TextStyle(fontSize: 20),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  final RenderObject root = key.currentContext!.findRenderObject()!;
  final int from = kTex.indexOf(which == 'num' ? kNum : kDen);
  final List<Rect> bands = selectionBands(
    root: root,
    tex: kTex,
    from: from,
    to: from + (which == 'num' ? kNum : kDen).length,
    displayStyle: true,
  );
  return (bands: bands, root: root);
}

void main() {
  testWidgets('★★ 只选分子 ⇒ 分母一格都不许被涂', (WidgetTester tester) async {
    final ({List<Rect> bands, RenderObject root}) r =
        await _bands(tester, 'num');
    // 分子在分数线上方（实测 centerY ≈ 9.8 / 5.5），分母在下方（≈ 37.4）
    const double kBarY = 20.0;
    final List<Rect> below =
        r.bands.where((Rect b) => b.center.dy > kBarY).toList();
    expect(below, isEmpty,
        reason: '★ 改前：选中分子会连带涂上分母与 `x→∞` 下标'
            '（11 条底色、跨 4 个视觉行；根因是"邻居兜底"会连锁 + 有主的盒也参与）'
            '\n落在分数线下面的底色：$below');
    expect(r.bands.length, 4,
        reason: '分子 = `x` `^{2}` `+` `1` 四个字形盒（合并后 4 条）');
  });

  testWidgets('★★ 只选分母 ⇒ 分子一格都不许被涂', (WidgetTester tester) async {
    final ({List<Rect> bands, RenderObject root}) r =
        await _bands(tester, 'den');
    const double kBarY = 20.0;
    final List<Rect> above =
        r.bands.where((Rect b) => b.center.dy < kBarY).toList();
    expect(above, isEmpty, reason: '对称方向：分母也不许把分子带进来\n$above');
  });
}
