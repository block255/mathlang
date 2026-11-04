// ★★★ 2026-10-24（批 17）：**行内 `$$`** —— 用户导入 `20261021作业编辑` 抓出的两组乱码
//
// 现场（真文件 `D:\学习文件\微积分\作业成品\20261021\20261021作业编辑.md`，2816 字符）：
//   · 第一组：整行 LaTeX 源码裸奔（`\to` / `k` / `\pi` 变文字 + 一排虚线小方框）
//   · 第二组：一处红字 `[公式不完整]`
//
// 根因链（探针 v19/v20 坐实）：**导入时的智能包裹把文档改坏了**
//   ① 文件第 15 行本来就有 4 处**行内 `$$`**（用户手打）
//   ② `scanMathSpans` 的行间判据**不看行首** ⇒ 把 `$$=$$` 当行间围栏 ⇒ 配对错位，
//      还吐出一个**跨行吞正文**的段（`tex="(-1)=-1\n\n左右极限…当x"`）
//   ③ 于是第 19 行真实的 `$\to$` **不在"已有结构、不许碰"的跳过表里** ⇒ 智能包裹当裸公式
//      再包一层 ⇒ `$$\to$$`（探针 runs：`[424,427)="\to"` …）
//   ④ 行内 `$$` ⇒ 投影按两个单 `$` 解 ⇒ 空段（虚线框）+ 后面掉文字层；
//      `Q={q|q` 那种花括号断裂 ⇒ KaTeX 报错 `[公式不完整]`
//
// 三条修法对应的断言：**A** 判据统一（行首 + 行内不许跨行）· **B** 包裹出口加闸
// （run 不许含 `$`、不与 `$` 相邻）· **C** 造出/存在行内 `$$` 时**可见**。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/math_spans.dart';
import 'package:mathlang/lang/smart_wrap.dart';

/// 三行真夹具（原文照抄，只删掉与本条无关的行）：
/// 第 1 行 = **触发点**（本来就有 4 处行内 `$$`）· 第 3 行 = 第一组的受害者 ·
/// 第 5 行 = 第二组（`[公式不完整]`）的受害者。
const String fixture =
    r'$\lim_{x\to0^{-}}\frac{x^{3}}{\left|{sinx}\right|^{3}}$$=$$\lim_{x\to0^{-}}\frac{x^{3}}{-x^{3}}$$=$$\lim_{x\to0^{-}}$(-1)=-1'
    '\n\n'
    r'当x$\to$k$\pi$(k$\ne$0时）,sinx$\to$0,$\frac{x^{3}}{\left|{sinx}\right|^{3}}\to\infty$'
    '\n\n'
    r'设Q={q|q$\le\frac{1}{\varepsilon}$},而q为正整数，可知Q为有限集';

String wrap(String s) => applySmartWrap(s, planSmartWrap(s));

void main() {
  group(r'A · 判据统一（$$ 只有行首才是行间围栏；行内段不许跨行）', () {
    test(r'行内 $$ 不是行间段', () {
      final List<MathSpan> spans = scanMathSpans(r'当x$$\to$$k');
      expect(spans.where((MathSpan s) => s.display), isEmpty);
    });

    test(r'★ 行内段不许跨行（改前：一个段能吞掉两行正文）', () {
      final String cross = '${r'行一 $a'}\n${r'行二 b$'}';
      for (final MathSpan s in scanMathSpans(cross)) {
        expect(s.display || !s.tex.contains('\n'), isTrue,
            reason: '行内段跨了行：${s.tex}');
      }
    });

    test(r'行首 $$ 仍是行间块（多行与同行闭合两种）', () {
      final List<MathSpan> multi =
          scanMathSpans('${r'$$'}${'\n'}x=1${'\n'}${r'$$'}');
      expect(multi.length, 1);
      expect(multi.first.display, isTrue);
      final List<MathSpan> single = scanMathSpans(r'$$x=1$$');
      expect(single.length, 1);
      expect(single.first.display, isTrue);
    });

    test(r'相邻两个行内段各算一段（$a$$b$ 是 a 与 b，不是行间）', () {
      final List<MathSpan> spans = scanMathSpans(r'$a$$b$');
      expect(spans.map((MathSpan s) => s.tex).toList(), <String>['a', 'b']);
    });

    test(r'C 的判据函数：行内 $$ 落在哪几行', () {
      expect(inlineDoubleDollarLines(r'当x$$\to$$k'), <int>[1]);
      expect(inlineDoubleDollarLines('${r'$$'}${'\n'}x${'\n'}${r'$$'}'), isEmpty,
          reason: r'行首 $$ 是合法围栏');
    });

    // ★★★ 2026-11-04（P2 剩余部分）：判据从"这个 `$$` 在不在行首"改成
    //   "**span 模型 + 块模型解释得了它吗**"。语料两类：
    //     · **真实文档里的形状**（盘里 53 份 md 扫出来的，见台账 §一·零六）；
    //     · 探针构造的边界形状（`$$(x)` 一族）。
    //   改前必红：合法 5 条里 3 条会被报（单行块 / 缩进 4 格两种），
    //             非法 2 条会被漏（`$$(x)` / `$$ x`）。
    test(r'C2 · 表驱动：什么算"能被模型解释的 $$"', () {
      // 合法的 `$$`：围栏（含缩进 ≥4 格的）、相邻两段的接缝
      final Map<String, String> legal = <String, String>{
        r'R5 单行块 $$x=1$$': r'$$x=1$$',
        '多行块': '${r'$$'}\nx=1\n${r'$$'}\n',
        r'相邻两段 $a$$b$': r'$a$$b$',
        '缩进 4 格的单行块': r'    $$x=1$$',
        '缩进 4 格的多行块': '    ${r'$$'}\nx=1\n    ${r'$$'}\n',
        r'真事故夹具第 1 行（三个行内公式首尾相邻）':
            r'$\lim_{x\to0^{-}}\frac{x^{3}}{\left|{sinx}\right|^{3}}$$=$$\lim_{x\to0^{-}}\frac{x^{3}}{-x^{3}}$$=$$\lim_{x\to0^{-}}$(-1)=-1',
      };
      legal.forEach((String name, String doc) {
        expect(inlineDoubleDollarLines(doc), isEmpty, reason: '合法却报了：$name');
      });

      // 非法的 `$$`：行首空壳、行内夹心、围栏内容里的、闭合挂在内容行尾的
      final Map<String, (String, List<int>)> illegal =
          <String, (String, List<int>)>{
        r'行首空壳 + 内容 $$(x)': (r'$$(x)', <int>[1]),
        r'行首空壳 + 空格 $$ x': (r'$$ x', <int>[1]),
        r'行首空壳 + 两个行内公式': (r'$$ $\hat{x}$ $\bar{y}$', <int>[1]),
        r'行内夹心 甲$$x$$乙': (r'甲$$x$$乙', <int>[1]),
        r'围栏**内容**里出现 $$': ('${r'$$'}\na${r'$$'}b\n${r'$$'}\n', <int>[2]),
        r'多行块的闭合挂在内容行尾（真实文档 电容与RC滤波:125-127）': (
          r'$$'
              r'\text{纹波} \approx \frac{T}{\tau} = \frac{T}{RC}'
              '\n'
              r'C \geq \frac{I_{load} \cdot T}{V_{ripple}}$$'
              '\n',
          <int>[1, 2]
        ),
      };
      illegal.forEach((String name, (String, List<int>) c) {
        expect(inlineDoubleDollarLines(c.$1), c.$2, reason: '非法却没按行报：$name');
      });
    });
  });

  group('B · 智能包裹出口加闸', () {
    test(r'★ 夹具包裹之后**不许新增行内 $$**', () {
      final String out = wrap(fixture);
      expect(inlineDoubleDollarLines(out), inlineDoubleDollarLines(fixture),
          reason: r'改前：第 1 行的行内 $$ 会把第 3 行改坏（\to 等 4 处）');
    });

    test(r'★ 原文里每一处 $…$ 都必须**原样保留**', () {
      final String out = wrap(fixture);
      for (final MathSpan s in scanMathSpans(fixture)) {
        final String raw = fixture.substring(s.start, s.end);
        expect(out.contains(raw), isTrue, reason: '被改坏的那一段：$raw');
      }
    });

    test(r'★ 幂等：wrap(wrap(x)) == wrap(x)', () {
      final String once = wrap(fixture);
      expect(wrap(once), once);
    });

    test(r'★ run 不许含 $、也不许与 $ 相邻（宁可少包一处）', () {
      const String s = r'设Q={q|q$\le x$,可知';
      final SmartWrapPlan plan = planSmartWrap(s);
      for (final WrapRun r in plan.runs) {
        final String seg = s.substring(r.start, r.end);
        expect(seg.contains(r'$'), isFalse, reason: 'run 里带美元：$seg');
        expect(r.start > 0 && s[r.start - 1] == r'$', isFalse,
            reason: 'run 左贴美元：$seg');
        expect(r.end < s.length && s[r.end] == r'$', isFalse,
            reason: 'run 右贴美元：$seg');
      }
    });
  });
}
