// 反馈 15（2026-10-30 · R3）守卫：**标准希腊字母一个都不许缺**。
//
// 用户实测：「`\xi` 这个对应的符号，面板里没有」——实测 `assets/symbols.json` 里
//   希腊只有 17 个，缺 22 个（`\xi` `\zeta` `\eta` `\iota` `\kappa` `\nu` `\upsilon`
//   `\chi` `\psi` `\epsilon` `\varpi` `\varrho` `\varsigma` `\phi` … 以及全部大写）。
// 这条直接读**真资产**（不走 `test/support/symbol_fixture.dart` 的小库）。
//
// 改前必红：①②（缺 22 个）。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 24 个小写 + 15 个大写（TeX 标准集合；`\epsilon`/`\varepsilon` 之类变体都算）
const List<String> kGreekTex = <String>[
  r'\alpha', r'\beta', r'\gamma', r'\delta', r'\epsilon', r'\varepsilon',
  r'\zeta', r'\eta', r'\theta', r'\vartheta', r'\iota', r'\kappa',
  r'\lambda', r'\mu', r'\nu', r'\xi', r'\pi', r'\varpi', r'\rho',
  r'\varrho', r'\sigma', r'\varsigma', r'\tau', r'\upsilon',
  r'\phi', r'\varphi', r'\chi', r'\psi', r'\omega',
  r'\Gamma', r'\Delta', r'\Theta', r'\Lambda', r'\Xi', r'\Pi',
  r'\Sigma', r'\Upsilon', r'\Phi', r'\Psi', r'\Omega',
];

void main() {
  final Map<String, dynamic> j =
      jsonDecode(File('assets/symbols.json').readAsStringSync())
          as Map<String, dynamic>;
  final List<dynamic> items = j['items'] as List<dynamic>;
  final List<Map<String, dynamic>> rows =
      items.map((dynamic e) => e as Map<String, dynamic>).toList();

  test('① 标准希腊字母一个不缺（40 个 TeX 命令）', () {
    final Set<String> have =
        rows.map((Map<String, dynamic> e) => e['tex'] as String).toSet();
    final List<String> missing =
        kGreekTex.where((String t) => !have.contains(t)).toList();
    expect(missing, isEmpty, reason: '面板里缺这些希腊字母：$missing');
  });

  test('② 每个希腊字母都有中文名 / 拼音 / 子类（能搜到）', () {
    for (final String tex in kGreekTex) {
      final Map<String, dynamic> e = rows.firstWhere(
        (Map<String, dynamic> r) => r['tex'] == tex,
        orElse: () => <String, dynamic>{},
      );
      if (e.isEmpty) continue; // ① 会报
      expect((e['label'] as String?)?.isNotEmpty, isTrue, reason: '$tex 缺 label');
      expect((e['pinyin'] as String?)?.isNotEmpty, isTrue, reason: '$tex 缺 pinyin');
      expect(e['subgroup'], '希腊', reason: '$tex 的子类不是「希腊」');
    }
  });

  test('③ id 不重复（新增条目最容易撞）', () {
    final List<String> ids =
        rows.map((Map<String, dynamic> e) => e['id'] as String).toList();
    final Set<String> uniq = ids.toSet();
    expect(uniq.length, ids.length);
  });
}
