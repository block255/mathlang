// 测试用的小符号库（不走资产加载，避免测试依赖 pubspec 的 assets 打包）
//
// ★ 2026-10-17 改成 **v2 口径**（《符号表-分类与关键词.md》）：
//   一级只有 `结构` / `符号`；**子类只有「符号」有**（希腊 / 关系 / 运算 / 逻辑集合 / 箭头 / 特殊 / 线性代数）；
//   `kind`（模板 / 符号）与分类**解耦**；`alsoIn` = 允许一项多类（求和同时属"运算"与"逻辑集合"）。
//
// 字段与 `assets/symbols.json` 完全同构 —— 这样守的是**同一套解析/搜索/筛选代码**。

import 'package:mathlang/lang/symbol_library.dart';

const String kTestSymbolsJson = '''
{
  "version": 2,
  "items": [
    {"id":"frac","kind":"template","tex":"\\\\frac{}{}","label":"分式","alias":["fraction","frac"],"pinyin":"fs","keywords":["除法"],"group":"结构"},
    {"id":"sqrt","kind":"template","tex":"\\\\sqrt{}","label":"根号","alias":["sqrt","root"],"pinyin":"gh","keywords":[],"group":"结构"},
    {"id":"alpha","kind":"symbol","tex":"\\\\alpha","label":"阿尔法","alias":["alpha"],"pinyin":"aef","keywords":["希腊"],"group":"符号","subgroup":"希腊"},
    {"id":"delta","kind":"symbol","tex":"\\\\delta","label":"德尔塔","alias":["delta"],"pinyin":"det","keywords":["判别式","线性代数"],"group":"符号","subgroup":"希腊"},
    {"id":"plus","kind":"symbol","tex":"+","label":"加号","alias":["plus"],"pinyin":"jh","keywords":[],"group":"符号","subgroup":"运算"},
    {"id":"sum","kind":"template","tex":"\\\\sum_{}^{}","label":"求和","alias":["sum"],"pinyin":"qh","keywords":["累加","批量"],"group":"符号","subgroup":"运算","alsoIn":["符号/逻辑集合"]},
    {"id":"leq","kind":"symbol","tex":"\\\\leq","label":"小于等于","alias":["leq"],"pinyin":"xydy","keywords":[],"group":"符号","subgroup":"关系"}
  ]
}
''';

SymbolLibrary testSymbolLibrary() => SymbolLibrary.fromJson(kTestSymbolsJson);
