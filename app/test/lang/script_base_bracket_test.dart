// 反馈 17（2026-10-30 · 口径 §3.4 / §4.1）守卫：**基座规则的正文侧**。
//
// 用户实测（图 17）：正文 `合E={(-1)` 后面按 Shift+6 ⇒ 打进去一个**字面 `^`**
//   （判据只看"前一个字符是不是字母数字"，`)` 不算 ⇒ 放弃）。
// 口径：**括号是一对"看得见的边界" ⇒ 整对当基座**；紧跟一段 `$…$` 的收尾 `$` ⇒ **并回原段**。
//
// ★ 2026-11-01 补（用户拍板"甲"）：**括号里恰好是一整段 `$…$`** 时也要能当基座 ——
//   现场（讨论稿 §一「多段同行」）：`$\lim_{x\to\infty}$($\frac{…}{2020}$)` 后面按 Shift+6，
//   原来吃到护栏①「括号里不许有 `$`」⇒ 返回 null ⇒ 打进一个字面 `^`。
//   现在把那段 tex **内联**进来，整对括号并成一段：`$(\frac{…}{2020})^{}$`。
//   ★ 只认"**恰好一整段**"：混着正文（`($x$ + 1)`）或两段公式仍放过 ——
//     并进去会把正文字体变成数学、还会吃掉空格，那是**改内容**。
//
// 改前必红：①②（改前返回 null / 只搬单个字符）· ⑤ ⑤b ⑧（改前返回 null）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/auto_expand.dart';
import 'package:mathlang/lang/word_triggers.dart';

AutoExpand? _plan(String doc, String typed, [int? at]) => planAutoExpand(
      doc: doc,
      caret: at ?? doc.length,
      typed: typed,
      triggers: TriggerSettings.defaults(),
    );

void main() {
  test('① 正文 `(-1)` + `^` ⇒ **整对括号**当基座（改前是字面 `^`）', () {
    final AutoExpand ex = _plan('合E={(-1)', '^')!;
    expect(ex.from, 4, reason: '搬运起点 = 开括号（`(`）那一格');
    expect(ex.tex, r'(-1)^{}');
  });

  test('② 正文 `[a+b]` + `_` ⇒ 整对方括号', () {
    final AutoExpand ex = _plan('x[a+b]', '_')!;
    expect(ex.from, 1);
    expect(ex.tex, r'[a+b]_{}');
  });

  test('③ 嵌套括号取**最外层配对**', () {
    final AutoExpand ex = _plan('f((a)b)', '^')!;
    expect(ex.from, 1);
    expect(ex.tex, r'((a)b)^{}');
  });

  test(r'④ 紧跟一段 `$…$` 的收尾 `$` ⇒ **并回原段**', () {
    final AutoExpand ex = _plan(r'前 $\alpha$', '^')!;
    expect(ex.from, 9, reason: r'替换区间定在收尾 ``$`` 那一格（长度 0）');
    expect(ex.caret, 9);
    expect(ex.tex, r'^{}', reason: '只插 tex，不另建公式');
  });

  test(r'⑤ 括号里**恰好一整段** `$…$` ⇒ 内联合并（改前返回 null）', () {
    final String doc = r'前 ($\alpha$)';
    final AutoExpand ex = _plan(doc, '^')!;
    expect(ex.from, 2, reason: '搬运起点 = 开括号那一格');
    expect(ex.caret, doc.length, reason: r'替换区间 = 整对括号（含中间那两个 ``$``）');
    expect(ex.tex, r'$(\alpha)^{}$', reason: '内容内联，围栏只剩一对');
  });

  test(r'⑤b 同上，`_` ⇒ 下标槽（同一个判据）', () {
    expect(_plan(r'前 ($\alpha$)', '_')!.tex, r'$(\alpha)_{}$');
  });

  test(r'⑤c 括号里**混着正文** ⇒ 仍放过（并进去会把正文字体变成数学）', () {
    expect(_plan(r'前 ($\alpha$ + 1)', '^'), isNull);
  });

  test(r'⑤d 括号里是**两段**公式 ⇒ 仍放过', () {
    expect(_plan(r'前 ($\alpha$$b$)', '^'), isNull);
  });

  test(r'⑤e 括号里是**空段** `($$)` ⇒ 仍放过（合并出来是空基座）', () {
    expect(_plan(r'前 ($$)', '^'), isNull);
  });

  test('⑥ 跨行的括号不算一个视觉对象', () {
    expect(_plan('(\n)', '^'), isNull, reason: '闭括号在下一行 ⇒ 不配对');
  });

  test('⑦ 不匹配的闭括号 ⇒ 仍然不展开', () {
    expect(_plan('甲)', '^'), isNull);
  });

  test(r'⑧ 用户现场（讨论稿 §一「多段同行」）：`$…$($\frac{…}$)` + `^`', () {
    final String doc = r'$\lim_{x\to\infty}$($\frac{a_{1}+a_{2020}}{2020}$)';
    final AutoExpand ex = _plan(doc, '^')!;
    expect(ex.from, doc.indexOf('('));
    expect(ex.caret, doc.length);
    expect(ex.tex, r'$(\frac{a_{1}+a_{2020}}{2020})^{}$');
    expect(ex.template, isTrue, reason: '光标要落进 `^{}` 里');
  });

  // ===== 2026-11-02（R-甲5 / R-甲6 / 空格归一）=====

  test(r'⑨ 方括号保真：`[$\alpha$]` + `^` ⇒ `$[\alpha]^{}$`（改前变圆括号）', () {
    final AutoExpand ex = _plan(r'前 [$\alpha$]', '^')!;
    expect(ex.tex, r'$[\alpha]^{}$');
  });

  test(r'⑩ 花括号保真（转义）：`{$\alpha$}` + `^` ⇒ `$\{\alpha\}^{}$`', () {
    final AutoExpand ex = _plan(r'前 {$\alpha$}', '^')!;
    expect(ex.tex, r'$\{\alpha\}^{}$',
        reason: r'数学里 { } 是分组、不画字形；必须转义成 \{ \} 才看得见');
  });

  test(r'⑪ 全角括号：`（$\alpha$）` + `^`', () {
    final AutoExpand ex = _plan(r'前 （$\alpha$）', '^')!;
    expect(ex.tex, r'$（\alpha）^{}$');
  });

  test(r'⑫ 升格空白 ⇒ `\ `：`(x + a)`', () {
    final AutoExpand ex = _plan(r'前 (x + a)', '^')!;
    expect(ex.tex, r'(x\ +\ a)^{}');
  });

  test(r'⑬ 连续空白折叠成一个 `\ `：`(a  b)`', () {
    final AutoExpand ex = _plan(r'前 (a  b)', '^')!;
    expect(ex.tex, r'(a\ b)^{}');
  });

  test(r'⑭ 全角括号 + 空白：`（x + a）`', () {
    final AutoExpand ex = _plan('前 （x + a）', '^')!;
    expect(ex.tex, r'（x\ +\ a）^{}');
  });

  test(r'⑮ 撇 + 方括号仍是保真的：`[$\alpha$]` + 撇', () {
    const String doc = r'前 [$\alpha$]';
    final AutoExpand ex = planPrimeInsert(doc: doc, caret: doc.length)!;
    expect(ex.tex, r'$[\alpha]^{\prime}$');
  });
}
