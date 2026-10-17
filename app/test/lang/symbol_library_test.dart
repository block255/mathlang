// 符号库（S4-b）的守卫：**数据 → 搜索排序**，以及"分类顺序 = JSON 顺序"。
//
// 规格：《符号面板与符号表.md》§三（搜索四路：中文名 / 别名 / 拼音 / LaTeX）＋《界面与布局.md》§4。

import 'dart:io';

import 'package:flutter_math_fork/tex.dart' show TexParser, TexParserSettings;
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/symbol_library.dart';
import 'package:mathlang/render/slot_marks.dart';

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
  realLibraryTests();

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

// ---------------------------------------------------------------------------
// ★★ 真实符号库（assets/symbols.json）的分类口径守卫
//
// 这些断言是 2026-10-17 一整轮讨论的**落账**（《界面与布局》§4.3 +《符号表-分类与关键词.md》）：
// 一级只有 结构/符号；子类只有"符号"有 7 个；kind 与分类解耦；keywords 只进搜索；
// alsoIn 只在白名单上；**每条 tex 都必须能被 KaTeX 解析**（防手滑写错命令）。
// ---------------------------------------------------------------------------
void realLibraryTests() {
  late final SymbolLibrary lib;
  setUpAll(() {
    // 直接读文件（测试工作目录 = app/），不走资产管道，避免依赖 pubspec 的打包行为
    final String src = File('assets/symbols.json').readAsStringSync();
    lib = SymbolLibrary.fromJson(src);
  });

  group('真实符号库：分类口径', () {
    test('一级分类只有 结构 / 符号', () {
      expect(lib.groups.toSet(), <String>{'结构', '符号'});
    });

    test('只有「符号」有子类，且正好是 7 个', () {
      expect(lib.subgroupsOf('结构'), isEmpty, reason: '结构 = 排版积木，不该有子类');
      expect(lib.subgroupsOf('符号').toSet(), <String>{
        '希腊', '关系', '运算', '逻辑集合', '箭头', '特殊', '线性代数',
      });
    });

    test('id 唯一、tex 非空', () {
      final Set<String> ids = <String>{};
      for (final SymbolItem i in lib.items) {
        expect(ids.add(i.id), isTrue, reason: '重复 id: ${i.id}');
        expect(i.tex.trim(), isNotEmpty, reason: i.id);
      }
    });

    test('★ kind 与分类解耦：符号类里也有模板（求和/积分/批量集合）', () {
      final List<SymbolItem> ops = lib.inCategory(group: '符号', subgroup: '运算');
      expect(ops.any((SymbolItem i) => i.id == 'sum' && i.isTemplate), isTrue);
      expect(ops.any((SymbolItem i) => i.id == 'int' && i.isTemplate), isTrue);
      final List<SymbolItem> sets =
          lib.inCategory(group: '符号', subgroup: '逻辑集合');
      expect(sets.any((SymbolItem i) => i.id == 'bigcup' && i.isTemplate), isTrue);
    });

    test('★ alsoIn 白名单：只有 6 个 n 元集合算子 + 所以/因为', () {
      final Set<String> withAlso = <String>{
        for (final SymbolItem i in lib.items)
          if (i.alsoIn.isNotEmpty) i.id,
      };
      expect(withAlso, <String>{
        'bigcup', 'bigcap', 'biguplus', 'bigsqcup', 'bigvee', 'bigwedge',
        'therefore', 'because',
      });
    });

    test('★ 一项多类：批量集合算子既能从「逻辑集合」找到，也能从「运算」找到', () {
      final Set<String> byOps = <String>{
        for (final SymbolItem i in lib.inCategory(group: '符号', subgroup: '运算'))
          i.id,
      };
      expect(byOps.containsAll(<String>['bigcup', 'bigcap']), isTrue);
      final Set<String> bySets = <String>{
        for (final SymbolItem i
            in lib.inCategory(group: '符号', subgroup: '逻辑集合'))
          i.id,
      };
      expect(bySets.containsAll(<String>['bigcup', 'bigcap']), isTrue);
    });

    test('★ 关键词不撒滥：搜「线性代数」只出线性代数那几项', () {
      final List<String> ids = <String>[
        for (final SymbolHit h in lib.search('线性代数')) h.item.id,
      ];
      expect(ids.toSet(), <String>{
        'mat2', 'det2', 'det', 'tr', 'transpose', 'otimes', 'odot',
      }, reason: '实际命中：$ids');
    });

    test('★ 搜「批量」出 6 个 n 元集合算子', () {
      final Set<String> ids = <String>{
        for (final SymbolHit h in lib.search('批量')) h.item.id,
      };
      expect(ids, <String>{
        'bigcup', 'bigcap', 'biguplus', 'bigsqcup', 'bigvee', 'bigwedge',
      });
    });

    test('★ 每条 tex 都能被 KaTeX 解析（空槽用注入后的形态解析）', () {
      for (final SymbolItem i in lib.items) {
        final String tex = renderMathTex(i.tex, caretRel: -1);
        expect(
          () => TexParser(tex, const TexParserSettings()).parse(),
          returnsNormally,
          reason: '「${i.id}」解析失败：$tex',
        );
      }
    });
  });
}