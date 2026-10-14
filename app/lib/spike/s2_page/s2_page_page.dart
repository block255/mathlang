// ============================================================
//  数语引擎 · S2-4 A4 分页演示与验证页
//
//  验证清单：
//    ✅ 一页放不下的内容自动流到下一页（页码 x/y 正确）
//    ✅ 手动分页符 `<!-- pagebreak -->` 强制换页
//    ✅ 高于一页的块**不切断** + 页下黄色告警（原则 5：静默失败必须可见）
//    ✅ 页眉（姓名/学号）参与分页高度
//    ✅ 打字只重建变化的那个单元（两个 widget 池的大小不随文档长度线性增长）
// ============================================================
import 'package:flutter/material.dart';

import '../../core/block.dart';
import '../../core/doc_buffer.dart';
import '../../core/doc_settings.dart';
import '../../editor/doc_view.dart';

const String kSampleDoc = r'''# 第三章 · 导数与微分

## 3.1 导数的定义

设函数 $y=f(x)$ 在点 $x_0$ 的某个邻域内有定义，当自变量 $x$ 在 $x_0$ 处取得增量 $\Delta x$ 时，函数取得增量 $\Delta y = f(x_0+\Delta x)-f(x_0)$。

若极限 $\lim_{\Delta x \to 0}\frac{\Delta y}{\Delta x}$ 存在，则称 $f(x)$ 在 $x_0$ 处可导，并称此极限为 $f(x)$ 在 $x_0$ 处的导数，记作 $f'(x_0)$。

$$
f'(x_0) = \lim_{\Delta x \to 0}\frac{f(x_0+\Delta x)-f(x_0)}{\Delta x}
$$

## 3.2 求导法则

设 $u=u(x)$、$v=v(x)$ 都可导，则：

- 和差法则：$(u \pm v)' = u' \pm v'$
- 乘积法则：$(uv)' = u'v + uv'$
- 商法则：$\left(\frac{u}{v}\right)' = \frac{u'v-uv'}{v^2}$

## 3.3 例题

例 1 求 $f(x)=x^3-3x^2+2x$ 的导数。

解：

$$
\begin{aligned}
f'(x) &= 3x^2-6x+2 \\
      &= 3(x^2-2x)+2 \\
      &= 3(x-1)^2-1
\end{aligned}
$$

当 $f'(x)=0$ 时 $3(x-1)^2=1$，即 $x = 1 \pm \frac{\sqrt{3}}{3}$。这说明函数在 $x=1$ 附近取得极小值，与二次函数的图像完全吻合；把这两个点代回原式可以验证 $f(x)$ 的单调区间是 $\left(-\infty, 1-\frac{\sqrt{3}}{3}\right)$ 与 $\left(1+\frac{\sqrt{3}}{3}, +\infty\right)$，而与 $x$ 轴的交点共有三个。

<!-- pagebreak -->

例 2 求 $I=\int_{0}^{\infty} e^{-t^2}\,dt$ 的值。

解：令 $I=\int_{0}^{\infty} e^{-t^2}\,dt$，则

$$
I^2 = \int_{0}^{\infty}\int_{0}^{\infty} e^{-(x^2+y^2)}\,dx\,dy = \frac{\pi}{4}
$$

故 $I = \frac{\sqrt{\pi}}{2}$。

## 3.4 高于一页的块（用来触发告警）

$$
\begin{pmatrix}
1 \\ 2 \\ 3 \\ 4 \\ 5 \\ 6 \\ 7 \\ 8 \\ 9 \\ 10 \\
11 \\ 12 \\ 13 \\ 14 \\ 15 \\ 16 \\ 17 \\ 18 \\ 19 \\ 20 \\
21 \\ 22 \\ 23 \\ 24 \\ 25 \\ 26 \\ 27 \\ 28 \\ 29 \\ 30 \\
31 \\ 32 \\ 33 \\ 34 \\ 35 \\ 36 \\ 37 \\ 38 \\ 39 \\ 40 \\
41 \\ 42 \\ 43 \\ 44 \\ 45 \\ 46 \\ 47 \\ 48 \\ 49 \\ 50 \\
51 \\ 52 \\ 53 \\ 54 \\ 55 \\ 56 \\ 57 \\ 58 \\ 59 \\ 60 \\
61 \\ 62 \\ 63 \\ 64 \\ 65 \\ 66 \\ 67 \\ 68 \\ 69 \\ 70
\end{pmatrix}
$$

## 3.5 小结

本节给出了导数的定义、基本求导法则与两个例题。核心结论是：导数刻画的是函数在一点处的瞬时变化率，而所有求导法则都可以由定义直接推出。
''';

class S2PagePage extends StatefulWidget {
  const S2PagePage({super.key});

  @override
  State<S2PagePage> createState() => _S2PagePageState();
}

class _S2PagePageState extends State<S2PagePage> {
  late final DocBuffer _buf = DocBuffer(kSampleDoc);
  DocSettings _s = DocSettings.defaults.copyWith(headerText: '张三 · 20230101');
  DocViewStats? _stats;

  @override
  Widget build(BuildContext context) {
    final DocViewStats? st = _stats;
    return Scaffold(
      appBar: AppBar(title: const Text('数语引擎 · S2-4 A4 分页')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                color: const Color(0xFFF7FAFC),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      st == null ? '（正在分页…）' : '$st',
                      style: const TextStyle(
                          fontSize: 12, fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '页眉：${_s.headerText.isEmpty ? "（关）" : _s.headerText}'
                      ' · 页面 ${_s.pageWidthMm.toStringAsFixed(0)}×'
                      '${_s.pageHeightMm.toStringAsFixed(0)}mm'
                      ' · 边距 上下${_s.marginTopMm.toStringAsFixed(0)}/'
                      '左右${_s.marginLeftMm.toStringAsFixed(0)}mm',
                      style:
                          const TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 4, children: <Widget>[
                FilledButton(
                  onPressed: _append,
                  child: const Text('追加一段（模拟打字）'),
                ),
                OutlinedButton(
                  onPressed: _insertPageBreak,
                  child: const Text('插入分页符'),
                ),
                OutlinedButton(
                  onPressed: _toggleHeader,
                  child: const Text('开/关页眉'),
                ),
                OutlinedButton(
                  onPressed: _shrinkFont,
                  child: const Text('正文字号 −1'),
                ),
                TextButton(onPressed: _reload, child: const Text('重载样本')),
              ]),
              const SizedBox(height: 12),
              DocView(
                buffer: _buf,
                settings: _s,
                onStats: (DocViewStats s) {
                  if (mounted) setState(() => _stats = s);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _append() {
    final int n = _buf.length;
    _buf.setCaret(n);
    _buf.insertText(
      '\n\n这是后加的一段（第 ${n + 1} 个字符处）：设 '
      r'$a_{i,j}+b^2 \ge 0$'
      ' 恒成立，于是 '
      r'$\frac{a}{b}=\sqrt{2}$'
      ' 可以取到最小值。',
    );
  }

  void _insertPageBreak() {
    _buf.setCaret(_buf.length);
    _buf.insertText(
      '\n\n$kPageBreakMarker\n\n这一页是新开的：'
      r'$\int_{0}^{1} x^2\,dx = \frac{1}{3}$'
      '。',
    );
  }

  void _toggleHeader() => setState(() {
        _s = _s.headerText.isEmpty
            ? _s.copyWith(headerText: '张三 · 20230101')
            : _s.copyWith(headerText: '');
      });

  void _shrinkFont() {
    final double next = _s.bodyFontSize - 1;
    if (next < 10) return;
    setState(() => _s = _s.copyWith(bodyFontSize: next));
  }

  void _reload() => _buf.replace(0, _buf.length, kSampleDoc);
}
