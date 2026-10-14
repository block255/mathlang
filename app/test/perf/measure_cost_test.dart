// 数语引擎 · S2-3 块高测量与增量成本（widget 测试版）
//
// 为什么不在浏览器里测：Chrome 的**遮挡判定**会让页面进入 hidden → 不产帧、点击失效，
// 一整串自动化跑不完（实测多次中断）。widget 测试里帧是**同步**的：
// `setState(...)` 标脏之后 `tester.pump()` 就把这一帧做完，计时干净、可复现、还能当回归测试。
//
// 注意：这里的**绝对毫秒数**与浏览器（CanvasKit）不可直接比，但**相对关系**完全可比：
//   ① Offstage 离屏测量 vs 真实渲染：高度是否一致？成本差多少？
//   ② 单元级 widget 缓存：能不能把"整篇重建"降到 O(变化的单元)？
//
// 规格依据：notes/design/块模型与md往返.md §五、§六

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/inline_math_text.dart';

const double kContentWidth = 657.6; // A4 内容区宽（174mm）

const List<String> kUnitSources = <String>[
  r'设 $x^2+1$ 为多项式，又已知 $\frac{a}{b}=\sqrt{2}$ 为常数，求 $x$ 的取值范围。',
  r'由 $\sum_{i=1}^{n} i = \frac{n(n+1)}{2}$ 可得，代入 $\sqrt{x^2+y^2}$ 后结论不变。',
  '# 第三章 · 导数与微分',
  r'这一段是纯文字，用来做对照，看看不含公式的单元便宜多少；再补一句凑长度。',
  r'当 $x \to 0$ 时，$\lim_{x\to 0}\frac{\sin x}{x}=1$，这是重要极限。',
  r'- 第一步：求导  - 第二步：代入  - 第三步：化简',
  r'$$\int_{0}^{\infty} e^{-t^2}\,dt = \frac{\sqrt{\pi}}{2}$$',
  r'$\alpha+\beta=\gamma$ 且 $a_{i,j}+b^2 \ge 0$ 恒成立。',
];

class Lab extends StatefulWidget {
  const Lab({super.key});

  @override
  State<Lab> createState() => LabState();
}

class LabState extends State<Lab> {
  int n = 25;
  bool cacheOn = false;
  String suffix = '';
  int tokenA = 0;
  int tokenC = 0;

  final Map<String, GlobalKey> keys = <String, GlobalKey>{};

  /// ★ 缓存必须按 **位置**（tag/i）分桶，不能只按 i：
  /// flutter_math_fork 的 `Math` 会把 `Line(key: GlobalKey)` 这个 widget **记忆化**，
  /// 同一个 widget 实例被放到树的两个位置 → "Multiple widgets used the same GlobalKey"。
  /// 缓存的本意是"同一位置跨帧复用"，跨位置复用本来就不该做。
  final Map<String, Widget> widgetCache = <String, Widget>{};
  final Map<String, String> widgetCacheSrc = <String, String>{};

  void coldA() {
    keys.removeWhere((String k, _) => k.startsWith('A/'));
    tokenA++;
    setState(() {});
  }

  void coldC() {
    keys.removeWhere((String k, _) => k.startsWith('C/'));
    tokenC++;
    setState(() {});
  }

  void idle() => setState(() {});
  void toggleEdit() {
    suffix = suffix.isEmpty ? '（改过）' : '';
    setState(() {});
  }

  void setCache(bool v) => setState(() => cacheOn = v);
  void setN(int v) => setState(() => n = v);

  double heightOf(String tag, int token, int i) {
    final ro = keys['$tag/$i/$token']?.currentContext?.findRenderObject();
    return ro is RenderBox ? ro.size.height : double.nan;
  }

  String _srcOf(int i) {
    final s = kUnitSources[i % kUnitSources.length];
    return i == 12 ? '$s$suffix' : s;
  }

  /// ★ 单元级 widget 缓存：源文本没变就**复用同一个 widget 实例**，
  /// `Element.updateChild` 会直接返回 → 整棵子树不 build、不 layout。
  Widget _unit(String tag, int i) {
    final src = _srcOf(i);
    final ck = '$tag/$i';
    if (cacheOn && widgetCacheSrc[ck] == src) return widgetCache[ck]!;
    final w = _buildUnit(src);
    if (cacheOn) {
      widgetCache[ck] = w;
      widgetCacheSrc[ck] = src;
    }
    return w;
  }

  Widget _buildUnit(String src) {
    if (src.startsWith('# ')) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(src.substring(2),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      );
    }
    if (src.startsWith(r'$$')) {
      return Center(
        child: Math.tex(
          src.substring(2, src.length - 2),
          mathStyle: MathStyle.display,
          textStyle: const TextStyle(fontSize: 16),
        ),
      );
    }
    return InlineMathText(
      source: src,
      mathFontSize: 16,
      textStyle: const TextStyle(fontSize: 16, height: 1.7),
    );
  }

  Widget _column(String tag, int token) => SizedBox(
        width: kContentWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (var i = 0; i < n; i++)
              KeyedSubtree(
                key: keys.putIfAbsent('$tag/$i/$token', () => GlobalKey()),
                child: _unit(tag, i),
              ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(
          children: <Widget>[
            Offstage(offstage: true, child: _column('A', tokenA)),
            SizedBox(
              height: 500,
              child: SingleChildScrollView(child: _column('C', tokenC)),
            ),
          ],
        ),
      );
}

void main() {
  testWidgets('S2-3 · 块高测量与增量成本', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1500, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final GlobalKey<LabState> labKey = GlobalKey<LabState>();
    await tester.pumpWidget(MaterialApp(home: Lab(key: labKey)));
    final LabState lab = labKey.currentState!;
    await tester.pump(); // 首帧稳定

    // 预热：第一次布局含字体 / 度量预热（S1 的 release 基准也踩过这个坑）→ 丢弃
    lab.coldA();
    await tester.pump();
    lab.coldC();
    await tester.pump();
    lab.coldA();
    await tester.pump();

    final rows = <String>[];

    Future<double> measure(String label, VoidCallback invalidate) async {
      invalidate(); // 标脏（此时还没有帧）
      final sw = Stopwatch()..start();
      await tester.pump(); // ← 这一帧做工作，被计时
      sw.stop();
      final ms = sw.elapsedMicroseconds / 1000.0;
      rows.add('$label → ${ms.toStringAsFixed(1)} ms');
      return ms;
    }

    // ---------- 第一轮：不开单元缓存 ----------
    final coldAOff = await measure('A 离屏 N=25 · 缓存关', lab.coldA);
    final coldCOff = await measure('C 真实渲染 N=25 · 缓存关', lab.coldC);
    final idleOff = await measure('对照：什么都不改 · 缓存关', lab.idle);
    final incOff = await measure('增量：只改 1 个单元 · 缓存关', lab.toggleEdit);

    // ---------- 正确性：A 与 C 的高度必须一致 ----------
    final int nCheck = lab.n;
    var maxDiff = 0.0;
    var resolved = 0;
    for (var i = 0; i < nCheck; i++) {
      final double a = lab.heightOf('A', lab.tokenA, i);
      final double c = lab.heightOf('C', lab.tokenC, i);
      if (a.isNaN || c.isNaN) continue;
      resolved++;
      final d = (a - c).abs();
      if (d > maxDiff) maxDiff = d;
    }
    rows.add('高度一致性：$resolved/$nCheck 个单元，A 与 C 最大差 '
        '${maxDiff.toStringAsFixed(3)} px');

    // ---------- 第二轮：开单元缓存 ----------
    lab.setCache(true);
    await tester.pump();
    final coldAOn = await measure('A 离屏 N=25 · 缓存开', lab.coldA);
    final coldCOn = await measure('C 真实渲染 N=25 · 缓存开', lab.coldC);
    final idleOn = await measure('对照：什么都不改 · 缓存开', lab.idle);
    final incOn = await measure('增量：只改 1 个单元 · 缓存开', lab.toggleEdit);

    // ---------- N=100（缓存开）----------
    lab.setN(100);
    await tester.pump();
    final coldA100 = await measure('A 离屏 N=100 · 缓存开', lab.coldA);
    final idle100 = await measure('对照：什么都不改 N=100 · 缓存开', lab.idle);

    // ignore: avoid_print
    print('\n===== S2-3 测量结果（widget test · debug VM · 一整帧）=====');
    for (final r in rows) {
      // ignore: avoid_print
      print(r);
    }
    // ignore: avoid_print
    print('=========================================================\n');

    // ---------- 断言 ----------
    expect(resolved, nCheck, reason: 'A / C 两组的高度都要取到');
    expect(maxDiff, lessThan(0.001),
        reason: '★ Offstage 离屏测量得到的高度必须与真实渲染**完全一致**');

    expect(idleOn * 4, lessThan(idleOff),
        reason: '★ 单元缓存应把"整篇重建"的空帧成本降到 1/4 以下'
            '（关=$idleOff ms，开=$idleOn ms）');
    expect(incOn * 4, lessThan(incOff),
        reason: '★ 缓存下改 1 个单元不应重建整篇（关=$incOff ms，开=$incOn ms）');
    expect(idle100 * 4, lessThan(coldA100),
        reason: 'N=100 时空帧也应远低于冷布局');

    // 冷布局成本量级参考（不断言绝对值，只记录）
    // ignore: avoid_print
    print('参考：冷 A(关)=$coldAOff 冷 C(关)=$coldCOff 冷 A(开)=$coldAOn '
        '冷 C(开)=$coldCOn 冷 A(100)=$coldA100');
  });
}
