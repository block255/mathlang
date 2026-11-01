// 反馈 17（2026-10-30 · 口径 §3.4 / §4.1）守卫：**基座规则的正文侧**。
//
// 用户实测（图 17）：正文 `合E={(-1)` 后面按 Shift+6 ⇒ 打进去一个**字面 `^`**
//   （判据只看"前一个字符是不是字母数字"，`)` 不算 ⇒ 放弃）。
// 口径：**括号是一对"看得见的边界" ⇒ 整对当基座**；紧跟一段 `$…$` 的收尾 `$` ⇒ **并回原段**。
//
// 改前必红：①②（改前返回 null / 只搬单个字符）。

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

  test(r'⑤ 括号里含 `$` ⇒ **不搬**（跨公式的括号留给"相邻公式合并"）', () {
    expect(_plan(r'前 ($\alpha$)', '^'), isNull);
  });

  test('⑥ 跨行的括号不算一个视觉对象', () {
    expect(_plan('(\n)', '^'), isNull, reason: '闭括号在下一行 ⇒ 不配对');
  });

  test('⑦ 不匹配的闭括号 ⇒ 仍然不展开', () {
    expect(_plan('甲)', '^'), isNull);
  });
}
