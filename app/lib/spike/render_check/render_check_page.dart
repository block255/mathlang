// ============================================================
//  数语引擎 · S1 渲染验证页（既有取证，2026-10-13）
//  原 main.dart 的内容搬到这里，作为 S1 风险 1 与"错误容错"的取证页面保留。
//  结论见 notes/design/技术选型与风险.md 第二节 / notes/dev_log/2026-10-13立项与S1验证.md
// ============================================================
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

class Case {
  final String title;
  final String tex;
  final bool display;
  const Case(this.title, this.tex, {this.display = true});
}

const List<Case> _cases = <Case>[
  Case('分式（横线+上下）', r'\frac{a+b}{c-d}'),
  Case('嵌套分式', r'\frac{1}{1+\frac{1}{x}}'),
  Case('行内分式（应小一号）', r'\frac{a}{b}', display: false),
  Case('根号', r'\sqrt{x^2+y^2}'),
  Case('n 次根', r'\sqrt[3]{\frac{a}{b}}'),
  Case('上下标', r'x^{n+1}_{i,j} = a_{i,j} + b^{2}'),
  Case('希腊字母', r'\alpha\beta\gamma\Gamma\Delta\Theta\lambda\pi\sigma\omega\Omega'),
  Case('求和（带上限）', r'\sum_{i=1}^{n} i = \frac{n(n+1)}{2}'),
  Case('积分', r'\int_{-\infty}^{\infty} e^{-x^2}\,\mathrm{d}x = \sqrt{\pi}'),
  Case('极限', r'\lim_{x \to 0}\frac{\sin x}{x} = 1'),
  Case('矩阵 pmatrix', r'\begin{pmatrix} a & b \\ c & d \end{pmatrix}'),
  Case('行列式 vmatrix', r'\begin{vmatrix} a & b \\ c & d \end{vmatrix} = ad-bc'),
  Case('分段函数 cases', r'|x| = \begin{cases} x, & x \geq 0 \\ -x, & x < 0 \end{cases}'),
  Case('多行对齐 aligned', r'\begin{aligned} (a+b)^2 &= a^2 + 2ab + b^2 \\ &= a^2 + ab + ab + b^2 \end{aligned}'),
  Case('array 三列对齐', r'\begin{array}{lcr} x & = & 1 \\ y & = & 2 \end{array}'),
  Case('中文 text', r'\text{当 } x > 0 \text{ 时，} f(x) = x^2'),
  Case('箭头与关系', r'a \leq b \implies a^2 \leq b^2, \quad f: X \to Y'),
  Case('集合与逻辑', r'\forall \varepsilon > 0,\ \exists \delta > 0:\ |x-a|<\delta \Rightarrow |f(x)-f(a)|<\varepsilon'),
  Case('重音与花体', r'\mathbb{R},\ \mathcal{L},\ \mathfrak{g},\ \vec{F} = m\vec{a},\ \overline{AB}'),
  Case('自适应括号', r'\left( \frac{a}{b} \right)^{n}, \quad \left\{ \frac{x}{y} \right\}'),
  Case('超长公式（预期溢出）',
      r'(a+b+c+d+e+f+g+h)^2 = a^2+b^2+c^2+d^2+e^2+f^2+g^2+h^2+2ab+2ac+2ad+2ae+2af+2ag+2ah+2bc+2bd+2be+2bf+2bg+2bh+2cd+2ce+2cf+2cg+2ch'),
];

const List<Case> _broken = <Case>[
  Case('未闭合（半成品）', r'\frac{1}{'),
  Case('拼错的命令', r'\alpa + \beta'),
];

class RenderCheckPage extends StatelessWidget {
  const RenderCheckPage({super.key});

  @override
  Widget build(BuildContext context) {
    final String platform = kIsWeb ? 'Web(CanvasKit)' : defaultTargetPlatform.name;
    return Scaffold(
      appBar: AppBar(
        title: const Text('数语引擎 · 渲染验证（S1 spike）'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(26),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'Flutter $platform · 本页仅验证渲染能力，不是产品界面',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          // 模拟 A4 正文宽度（约 174mm 内容宽 ≈ 658 逻辑像素 @96dpi）
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              _sectionTitle('一、正常公式（${_cases.length} 条）'),
              ..._cases.map((c) => _CaseRow(c: c)),
              const SizedBox(height: 24),
              _sectionTitle('二、错误容错（必须不崩，显示红色提示）'),
              ..._broken.map((c) => _CaseRow(c: c, broken: true)),
              const SizedBox(height: 24),
              _sectionTitle('三、可选中公式（SelectableMath，实验性）'),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)),
                child: SelectableMath.tex(r'\frac{a}{b} + \sqrt{x}',
                    textStyle: const TextStyle(fontSize: 22)),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      );
}

class _CaseRow extends StatelessWidget {
  const _CaseRow({required this.c, this.broken = false});

  final Case c;
  final bool broken;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('${c.title}${c.display ? "" : "（行内）"}',
              style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600)),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              border: Border.all(color: broken ? Colors.red.shade200 : Colors.grey.shade300),
              borderRadius: BorderRadius.circular(6),
              color: broken ? const Color(0xFFFFF5F5) : Colors.white,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Math.tex(
                c.tex,
                mathStyle: c.display ? MathStyle.display : MathStyle.text,
                textStyle: const TextStyle(fontSize: 20),
                onErrorFallback: (err) => Text(
                  '❌ 渲染失败：${err.messageWithType}',
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
