// 符号库（S4-b）的守卫：**数据 → 搜索排序**，以及"分类顺序 = JSON 顺序"。
//
// 规格：《符号面板与符号表.md》§三（搜索四路：中文名 / 别名 / 拼音 / LaTeX）＋《界面与布局.md》§4。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/symbol_library.dart';

const String _fixture = '''
{
  "version": 1,
  "items": [
    {"id":"frac","kind":"template","tex":"\\\\frac{}{}","label":"分式","alias":["fraction","frac"],"pinyin":"fs","keywords":["除法"],"group":"结构"},
    {"id":"int","kind":"template","tex":"\\\\int_{}^{}","label":"积分","alias":["integral","int"],"pinyin":"jf","keywords":["微积分"],"group":"结构"},
    {"id":"sum","kind":"template","tex":"\\\\sum_{}^{}","label":"求和","alias":["sum"],"pinyin":"qh","keywords":["累加"],"group":"结构"},
    {"id":"delta","kind":"symbol","tex":"\\\\delta","label":"德尔塔","alias":["delta"],"pinyin":"det","keywords":["希腊","判别式"],"group":"希腊"},
    {"id":"alpha","kind":"symbol","tex":"\\\\alpha","label":"阿尔法","alias":["alpha"],"pinyin":"aef","keywords":["希腊"],"group":"希腊"}
  ]
}
''';

void main() {
  final SymbolLibrary lib = SymbolLibrary.fromJson(_fixture);

  group('解析', () {
    test('字段、种类、分组顺序（= JSON 里第一次出现的顺序）', () {
      expect(lib.items.length, 5);
      expect(lib.groups, <String>['结构', '希腊']);
      expect(lib.items.first.isTemplate, isTrue);
      expect(lib.byId('frac')!.tex, r'\frac{}{}');
      expect(lib.byId('frac')!.aliases, contains('fraction'));
      expect(lib.inGroup('希腊').length, 2);
    });
  });

  group('搜索排序：标签 > 别名 > 关键词 > 拼音', () {
    test('中文标签命中（"积分" ⇒ 积分）', () {
      final List<SymbolHit> hits = lib.search('积分');
      expect(hits.first.item.id, 'int');
      expect(hits.first.tier, SymbolHitTier.labelPrefix,
          reason: '标签等于查询 ⇒ "开头"档（比"包含"更优先）');
      expect(lib.search('积').first.tier, SymbolHitTier.labelPrefix);
    });

    test('别名命中（"integral" ⇒ 积分）', () {
      expect(lib.search('integral').first.item.id, 'int');
    });

    test('关键词命中（"希腊" ⇒ 德尔塔/阿尔法，且保持库内顺序）', () {
      final List<SymbolHit> hits = lib.search('希腊');
      expect(<String>[for (final SymbolHit h in hits) h.item.id],
          <String>['delta', 'alpha']);
    });

    test('拼音首字母命中（"det" ⇒ 德尔塔）', () {
      expect(lib.search('det').first.item.id, 'delta');
    });

    test('★ 全拼也命中（"jifen" ⇒ 积分；"jf" 是"jifen"的子序列）', () {
      final List<SymbolHit> hits = lib.search('jifen');
      expect(hits.map((SymbolHit h) => h.item.id), contains('int'));
    });

    test('LaTeX 别名也命中（"frac" ⇒ 分式）', () {
      expect(lib.search('frac').first.item.id, 'frac');
    });

    test('空查询 ⇒ 空结果（面板此时显示分类/全部）', () {
      expect(lib.search('   '), isEmpty);
    });
  });
}
