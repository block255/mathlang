// 多行公式的引擎事实（2026-10-15 探针实测后固化成守门人）
//
// ============================ 为什么要有这个文件 ============================
// 起因：S3-5 记下一条缺口「多行公式（`aligned`/`cases`）写不出来」，
// 提出了一个看起来很自然的方案：**数学段内按 Enter = 插入数学换行 `\\`**。
// 2026-10-15 探针实测把这个方案**否掉了**，理由必须固化下来，否则以后一定有人再想一遍：
//
//   tex                 行内(MathStyle.text)      行间(display)
//   a+b                 48.2 × 10.9   OK          OK            ← 对照
//   a\\b                ★ 渲染失败                ★ 渲染失败
//   a+b\\               ★ 渲染失败                ★ 渲染失败     ← 末尾悬空（刚按 Enter 的状态）
//   \begin{cases}…\\…   93.5 × 34.5   OK  ★       OK  ★
//   \begin{aligned}…   50.3 × 42.0   OK  ★       OK  ★
//
// ★ 结论一：**`\\` 在公式顶层是非法的** —— 它只允许出现在 `array`/`aligned`/`cases`
//   这类**环境内部**。所以"Enter 插 `\\`"一旦做成通用规则，公式会**当场炸成 `❌`**
//   （与"悬空 `^`"同一性质：都是"为了一个动作引入了非法语法"）。
//   正确的说法是：**在数组/对齐环境内部**按 Enter 才 = 加一行；而"进入环境"靠
//   S4 符号面板的模板（`aligned`/`cases` 骨架自带槽）。
//
// ★★ 结论二（更重要）：`cases` / `aligned` **行内就能正常渲染**（实测见上表）
//   ⇒ **「多行」不强制「行间」** ⇒ 行内/行间的选择**只由排版意图决定**
//     （要不要独占一行居中），与**内容长短、行数完全无关**。
//     ⇒ 因此**不做**"按长短自动升格/降格"（那会静默重排用户的版面）。
//
// ★ 结论三：顶层 `\\` 会让**整个公式**渲染失败 ⇒ 从外部**粘贴**含它的 LaTeX 会出红字。
//   这属于「问题清单」该管的事（原则 5：问题可见，但不阻断操作）——归到 S6 导入导出。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _math(String tex, MathStyle style) => Math.tex(
      tex,
      mathStyle: style,
      onErrorFallback: (e) => Text('❌ ${e.messageWithType}'),
    );

/// 渲染一次，返回"是否走了 onErrorFallback（= 渲染失败）"。
Future<bool> _fails(WidgetTester t, String tex, MathStyle style) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(body: Center(child: _math(tex, style))),
  ));
  await t.pump();
  return find.textContaining('❌').evaluate().isNotEmpty;
}

/// 环境类多行结构（合法）—— 行内行间都要能渲染
const List<String> kEnvs = <String>[
  r'\begin{cases} a & x>0 \\ b & x\le 0 \end{cases}',
  r'\begin{aligned} x &= 1 \\ y &= 2 \end{aligned}',
  r'\begin{aligned} x &= 1 \\ \end{aligned}', // 末行空的中间态
  r'\begin{pmatrix} 1 & 2 \\ 3 & 4 \end{pmatrix}',
];

/// 顶层 `\\`（非法）—— 包括"刚按完 Enter"的悬空状态
const List<String> kTopLevelBreaks = <String>[
  r'a\\b',
  r'a+b\\',
  r'a\\',
  r'\\',
];

void main() {
  group('★ 环境类多行：行内与行间都渲染得出来（"多行"不强制"行间"）', () {
    for (final String tex in kEnvs) {
      testWidgets('行内：$tex', (WidgetTester t) async {
        expect(await _fails(t, tex, MathStyle.text), isFalse,
            reason: '环境类结构在行内必须渲染得出来 —— 这是"形态与行数解耦"的实测依据');
      });
      testWidgets('行间：$tex', (WidgetTester t) async {
        expect(await _fails(t, tex, MathStyle.display), isFalse);
      });
    }
  });

  group('★★ 顶层 `\\\\` 非法 —— 所以 Enter 不能用它当换行', () {
    // 这四条是"以后再想一遍那个方案"的刹车片。
    // 若哪天它们变成通过，说明引擎行为变了：那时**先读本文件头部三条结论**，
    // 再同步改 `insert_guard` 与位点表，不要只改这里。
    for (final String tex in kTopLevelBreaks) {
      testWidgets('顶层 `\\\\`（$tex）→ 渲染失败（有意钉住）',
          (WidgetTester t) async {
        expect(await _fails(t, tex, MathStyle.text), isTrue,
            reason: '★ 若这里变成"渲染 OK"，说明引擎行为变了 —— '
                '先读本文件头部三条结论，再同步改 insert_guard 与位点表');
      });
    }
  });
}
