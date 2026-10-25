// 删除的**命令名安全网**：不许把 `\text` 这类命令名劈开（`\ext` / `\txt` ⇒ `[公式不完整]`）。
//
// ★ 为什么必须有这一份（用户 2026-10-25 实测，`20261019作业` 第 (b) 题）：
//   在 `(\text{旁注：} …)` 里"点删除、把旁字删掉"⇒ 整块变 `[公式不完整]`。
//   探针 v59（真文档 + 真按键 + **真实引擎解析**）抓到的现场：
//     · Backspace @1872（= `\` `t` ｜`e` 之间）⇒ 删 `t` ⇒ `\ext{旁注：}` ⇒ 解析失败；
//     · Backspace @1873（= `\` `t` `e` ｜`x` 之间）⇒ 删 `e` ⇒ `\txt{旁注：}` ⇒ 解析失败。
//   这两个偏移**都不是合法位点**（`snap(1872)=1874`），可 `smartBackspace` 收到非位点偏移时
//   就按字节删 ⇒ 把命令名劈成两半（`\ext` 不是命令 ⇒ 引擎报错）。
//
// ★ 判据（不依赖"谁传了坏偏移"）：**删完之后不许出现原文没有的命令名**。
//   删内容、删整个结构（整块回收）都不会**造出**新命令名；只有"劈开命令名"才会。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/smart_delete.dart';

/// 用户那一行（第一个「旁注：」在这一行里）
const String _line =
    r'= \lim\limits_{x\to0} b^{x^{2}} (e^{x^2 \ln\frac{a}{b}} - 1) \quad (\text{旁注：} x\to0 \text{ 时 } x^2 \ln\frac{a}{b} \to 0)';

/// tex 里的命令名集合（`\text` / `\frac` …，不含 `\quad` 这类单字符转义）
Set<String> _commands(String tex) => <String>{
      for (final RegExpMatch m in RegExp(r'\\[a-zA-Z]+').allMatches(tex))
        m.group(0)!,
    };

String _apply(String tex, SmartEdit e) =>
    e.deletes ? tex.replaceRange(e.from!, e.to!, '') : tex;

void main() {
  group('现场：光标落在命令名中间', () {
    test(r'★ Backspace 在 `\text` 的命令名里 ⇒ 不许删出 `\ext` / `\txt`', () {
      final CaretSiteTable t = buildCaretSites(_line);
      final int back = _line.indexOf(r'\text{旁注');
      expect(back, greaterThan(0));
      // `\` 之后第 2、3 个字符 = 命令名中间（都不是合法位点）
      for (final int inside in <int>[back + 2, back + 3]) {
        expect(t.sites.any((CaretSite s) => s.offset == inside), isFalse,
            reason: '前提：$inside 不该是合法位点（snap 到 ${t.snap(inside).offset}）');
        final SmartEdit e = smartBackspace(t, inside);
        final String after = _apply(_line, e);
        final Set<String> created =
            _commands(after).difference(_commands(_line));
        expect(created, isEmpty,
            reason: 'Backspace@$inside 之后出现了新命令名 $created\n'
                '结果：「${after.substring(
                    (back - 10).clamp(0, after.length),
                    (back + 18).clamp(0, after.length))}」');
      }
    });

    test(r'★ Delete 在命令名里同理（两个方向都要挡）', () {
      final CaretSiteTable t = buildCaretSites(_line);
      final int back = _line.indexOf(r'\text{旁注');
      for (final int inside in <int>[back + 2, back + 3]) {
        final SmartEdit e = smartDelete(t, inside);
        final String after = _apply(_line, e);
        final Set<String> created =
            _commands(after).difference(_commands(_line));
        expect(created, isEmpty,
            reason: 'Delete@$inside 之后出现了新命令名 $created');
      }
    });
  });

  group('全域：连按三下也不许造出新命令名', () {
    const List<String> texs = <String>[
      _line,
      r'\text{旁注：当 } x\to+\infty',
      r'\text{ 时 } \frac{1}{f(x)} < \varepsilon',
      r'\lim\limits_{x\to0} \frac{\ln(\sin^2x+e^x)-x}{\ln(x^2+e^{2x})-2x}',
      r'\sqrt[3]{x^{2}}+\alpha',
      r'\left| x \right| + \lvert y \rvert',
      r'\begin{cases}a&b\\c&d\end{cases}',
      r'x^{\frac{1}{2}} + \limsup_{n\to\infty} a_n',
    ];

    test('每个偏移 × 两方向 × 连按三下', () {
      var checked = 0;
      for (final String tex in texs) {
        final CaretSiteTable t = buildCaretSites(tex);
        for (final bool forward in <bool>[false, true]) {
          for (var o = 0; o <= tex.length; o++) {
            String cur = tex;
            for (var press = 0; press < 3; press++) {
              final CaretSiteTable tt = press == 0 ? t : buildCaretSites(cur);
              if (tt.degraded) break;
              final int rel = o.clamp(0, cur.length);
              final SmartEdit e =
                  forward ? smartDelete(tt, rel) : smartBackspace(tt, rel);
              if (!e.deletes) {
                if (press == 0) checked++;
                break;
              }
              final String next = _apply(cur, e);
              final Set<String> created =
                  _commands(next).difference(_commands(tex));
              expect(created, isEmpty,
                  reason: '「$tex」off=$o forward=$forward 第 ${press + 1} 下'
                      '（删[${e.from},${e.to})）造出了新命令名 $created\n'
                      '结果：「$next」');
              cur = next;
              if (press == 0) checked++;
            }
          }
        }
      }
      expect(checked, greaterThanOrEqualTo(200),
          reason: '全域用例太少（只检查了 $checked 个位点）—— 守卫会变成空转');
    });
  });
}
