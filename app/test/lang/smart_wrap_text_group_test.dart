// ★★ 2026-10-23（批 1 · G1/G2）：公测反馈「DeepSeek 抄写稿导入」的两条真缺陷。
//
// G1：[公式不完整] —— 智能包裹按"数学字符"切段，而**中文不算数学字符**
//     ⇒ `\quad (\text{旁注：当 } …)` 被从「旁注」处切断 ⇒ `\text{` 与 `}` 分到两个包裹里
//     ⇒ 两段都语法不完整 ⇒ 页面上 `[公式不完整]`。
//     实测：整份抄写稿 69 段包裹里 **20 段悬空**。
// G2：行间推导的**最后一个结果行**（`= 1` / `= -1`）被"悬空运算符"判据整行漏掉
//     ⇒ 落成正文文字（用户看到的"被识别为行内"）。
//
// 改前必红：本文件里的 G1 用例在改前 runs 会被切成 3 段（且括号不平衡）、
// G2 用例改前 `planSmartWrap('= 1').isEmpty` 为真。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/smart_wrap.dart';

/// 一段包裹的括号净深度（`{}` 配平；跳过 `\{` / `\}`）
int _brace(String s) {
  var d = 0;
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && s[i - 1] == r'\') continue;
    if (s[i] == '{') d++;
    if (s[i] == '}') d--;
  }
  return d;
}

/// 每个 `run` 拿到的原文片段
List<String> _segs(String line, SmartWrapPlan p) => <String>[
      for (final WrapRun r in p.runs) line.substring(r.start, r.end),
    ];

void main() {
  group('G1 `\\text{…}` 里的中文不许被切断', () {
    const String withNote =
        r'= \lim_{x\to+\infty} (x+1)\ln(1-\frac{1}{x+1}) \quad (\text{旁注：当 } x\to+\infty \text{ 时 } -\frac{1}{x+1}\to0)';

    test('带中文旁注的整行 ⇒ 只包一处，且括号平衡', () {
      final SmartWrapPlan p = planSmartWrap(withNote);
      expect(p.runs.length, 1,
          reason: '改前会被切成 3 段（`\\text{` 与 `}` 分家）：${_segs(withNote, p)}');
      final String seg = _segs(withNote, p).single;
      expect(seg, withNote.trim(), reason: '整行就是这个式子，别切碎');
      expect(_brace(seg), 0);
      expect(seg.contains(r'\text{'), isTrue);
    });

    test('全域：抄写稿里 8 条带 `\\text{中文}` 的行，每个包裹都必须括号平衡', () {
      const List<String> lines = <String>[
        r'= \lim_{x\to+\infty} (x+1)\ln(1-\frac{1}{x+1}) \quad (\text{旁注：当 } x\to+\infty \text{ 时 } -\frac{1}{x+1}\to0)',
        r'= \lim_{x\to0} \frac{3^x[e^{x\ln(1+\frac{2}{3}\sin x)}-1]}{x^2} \quad (\text{旁注：由于 } x\to0, \frac{2}{3}\sin x\to0, x\ln(1+\frac{2}{3}\sin x)\to0)',
        r'= \lim_{x\to0} \frac{2\tan x}{\sqrt{1+\tan x}+\sqrt{1-\tan x}} \quad (\text{旁注：当 } x\to0 \text{ 时 } \tan x\to0)',
        r'= \lim_{x\to0} x \quad (\text{旁注：且 } \tan x \sim x)',
        r'= \lim_{x\to0} b^{x^2} \cdot x^2\ln\frac{a}{b} \quad (\text{旁注：} e^{x^2\ln\frac{a}{b}}-1 \sim x^2\ln\frac{a}{b})',
        r'0 < |x-x_0| < \delta \text{ 时 } |\frac{1}{f(x)}| < \varepsilon',
        r'\text{中文} x^2 + 1',
        r'x^2 + \text{中文}',
      ];
      for (final String line in lines) {
        final SmartWrapPlan p = planSmartWrap(line);
        expect(p.runs, isNotEmpty, reason: '这一行必须至少包一处：$line');
        for (final String seg in _segs(line, p)) {
          expect(_brace(seg), 0, reason: '包裹片段括号必须平衡：「$seg」');
          // `\text{` 出现几次，就要有几个对应的 `}` —— 用"总深度为 0"已经保证，
          // 这里再钉一条更直白的：不许以 `\text{` 结尾
          expect(seg.trimRight().endsWith(r'\text{'), isFalse,
              reason: '不许把 `\\text{` 单独留在段尾：「$seg」');
        }
      }
    });

    test('行内夹在文字里的 `\\text{中文}`：只包数学那段，中文段原样不动', () {
      const String line = r'当 \text{当且仅当} x>0 时成立';
      final SmartWrapPlan p = planSmartWrap(line);
      final String out = applySmartWrap(line, p);
      expect(out.contains(r'\text{当且仅当}'), isTrue, reason: '不许把 `\\text{…}` 拆开：$out');
      // 中文本身仍不进数学段（中文不是数学字符）
      for (final String seg in _segs(line, p)) {
        expect(_brace(seg), 0, reason: seg);
      }
    });
  });

  group('G2 整行以运算符开头 = 续行（不许被"悬空"判据漏掉）', () {
    test('`= 1` / `= -1` / `= 0` ⇒ 包成行间块', () {
      for (final String line in <String>['= 1', '= -1', '= 0', '= \\pi']) {
        final SmartWrapPlan p = planSmartWrap(line);
        expect(p.runs.length, 1, reason: '改前一处都不包：$line');
        final String out = applySmartWrap(line, p);
        expect(out.contains(r'$$'), isTrue, reason: '整行式子 ⇒ 行间块：$out');
        expect(out.contains(line.trim()), isTrue, reason: '原文一字不差：$out');
      }
    });

    test('反例①：尾部悬空（`b >`）仍然不包（F13 那条不许退化）', () {
      for (final String s in <String>['b >', 'a 大于 b >', '先 < 后', '甲 + 乙']) {
        expect(planSmartWrap(s).isEmpty, isTrue, reason: s);
      }
    });

    test('反例②：开头是运算符但**不是整行**（句子中间）⇒ 仍然不包', () {
      for (final String s in <String>['甲则 = 1', '所以 > 0 不成立']) {
        final SmartWrapPlan p = planSmartWrap(s);
        for (final String seg in _segs(s, p)) {
          expect(seg.trimLeft().startsWith('='), isFalse, reason: '不该包悬空段：$seg');
          expect(seg.trimLeft().startsWith('>'), isFalse, reason: '不该包悬空段：$seg');
        }
      }
    });

    test('反例③：引用行 `> 素材：…` 与列表标记照旧不包', () {
      expect(planSmartWrap('> 素材：homework').isEmpty, isTrue);
      expect(planSmartWrap('- 列表项').isEmpty, isTrue);
    });
  });
}
