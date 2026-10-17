// 测试用的小符号库（不走资产加载，避免测试依赖 pubspec 的 assets 打包）
//
// 字段与 `assets/symbols.json` 完全同构 —— 这样守的是**同一套解析/搜索代码**。

import 'package:mathlang/lang/symbol_library.dart';

const String kTestSymbolsJson = '''
{
  "version": 1,
  "items": [
    {"id":"frac","kind":"template","tex":"\\\\frac{}{}","label":"分式","alias":["fraction","frac"],"pinyin":"fs","keywords":["除法"],"group":"结构"},
    {"id":"sum","kind":"template","tex":"\\\\sum_{}^{}","label":"求和","alias":["sum"],"pinyin":"qh","keywords":["累加"],"group":"结构"},
    {"id":"alpha","kind":"symbol","tex":"\\\\alpha","label":"阿尔法","alias":["alpha"],"pinyin":"aef","keywords":["希腊"],"group":"希腊"},
    {"id":"plus","kind":"symbol","tex":"+","label":"加号","alias":["plus"],"pinyin":"jh","keywords":[],"group":"运算"}
  ]
}
''';

SymbolLibrary testSymbolLibrary() => SymbolLibrary.fromJson(kTestSymbolsJson);
