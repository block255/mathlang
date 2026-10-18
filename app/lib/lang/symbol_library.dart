// 数语引擎 · **符号库**（S4-b）：`assets/symbols.json` 的模型、加载与搜索
//
// 为什么单独一个文件：符号表是**面板/快捷栏/快捷键设置**三处共用的唯一数据源
// （《符号面板与符号表.md》§二）。搜索排序规则也在这里，面板只负责画。
//
// 三条约定：
//   ① **空槽不写进符号表**：`\frac{}{}` 有几个空槽由引擎的**位点表**（`caret_sites`）推出来
//      —— 两处各写一份必然会漂（本仓反复踩过的坑）。
//   ② 搜索排序：`标签 > 别名 > 关键词 > 拼音首字母`，每档**开头优先于包含**，同分按 group 顺序（稳定）。
//   ③ **纯 Dart**（只 import `flutter/services.dart` 读资产），可单测。

import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

/// 一个可插入的东西：**符号**（插一个 tex）或**结构模板**（插一个带空槽的 tex）
enum SymbolKind { symbol, template }

/// 插成什么形态（★ 2026-10-18：`行间公式段` 与多行环境模板走 display，其余一律 inline）
///
/// ★ 口径（用户拍板）：**行内依然是主要地位** —— 用户的话是
/// "打行间加途径并不意味着走公式块思路，我们的行内依然是主要地位"。
/// 所以 `display` 只给**少数"天生就是一段"的东西**：`cases` / `aligned`（多行环境）
/// 与"行间公式段"本身。**绝大多数项仍然是 inline**（守卫会盯这个比例）。
enum SymbolInsertAs { inline, display }

class SymbolItem {
  const SymbolItem({
    required this.id,
    required this.kind,
    required this.tex,
    required this.label,
    required this.group,
    this.subgroup = '',
    this.aliases = const <String>[],
    this.pinyin = '',
    this.keywords = const <String>[],
    this.alsoIn = const <String>[],
    this.preview = '',
    this.insertAs = SymbolInsertAs.inline,
  });

  final String id;
  final SymbolKind kind;

  /// 插进缓冲区的 tex（**不含** `$…$`，建壳由 `symbol_insert.dart` 决定）
  final String tex;
  final String label;
  final String group;
  final String subgroup;
  final List<String> aliases;

  /// 拼音首字母（"德尔塔" → `det`），允许手填覆盖
  final String pinyin;
  final List<String> keywords;

  /// ★ 第二归属（2026-10-17 用户定：**可以一项多类，但要少**）
  ///
  /// 格式 `一级/子类`（如 `符号/运算`）；主归属仍是 [group] / [subgroup]。
  /// 只在"两种找法都自然"的少数项上用（白名单见《符号表-分类与关键词.md》）。
  final List<String> alsoIn;

  /// ★ 面板里画画用的**代表式**（空 ⇒ 用 [tex] 本身）
  ///
  /// 为什么需要：`\begin{cases}&\\&\end{cases}` 的格子是空的 ⇒ 面板里只看得见 `{` 和 `=`，
  /// 用户根本认不出这是"分段"。所以给一份**预览专用**的填充式
  /// （**插入的仍是空槽 tex**，两者不混）。
  final String preview;

  /// ★★ 插成**行内**还是**行间段**（默认行内 —— 行内是主要地位）
  ///
  /// `display` ⇒ 插入时包成
  /// ```
  /// $$
  /// <tex>
  /// $$
  /// ```
  /// （围栏独占一行，走 `insert_guard` 的规则 ③④）。
  /// `tex` 为空 ⇒ 插入一个**空的行间公式段**，光标落在围栏之间的空行上；
  /// 空段由 `render/empty_math_mark.dart` 画成淡虚线小框 ⇒ 看得见、点得到。
  final SymbolInsertAs insertAs;

  bool get isDisplay => insertAs == SymbolInsertAs.display;

  /// 预览该用哪份 tex
  String get previewTex => preview.isEmpty ? tex : preview;

  bool get isTemplate => kind == SymbolKind.template;

  /// 全部分类（主 + 第二归属），形如 `符号/逻辑集合`
  List<String> get categories => <String>[
        if (subgroup.isEmpty) group else '$group/$subgroup',
        ...alsoIn,
      ];

  @override
  String toString() => 'SymbolItem($id, $tex, $label)';
}

/// 匹配到的"档位"（数字越小越优先）
enum SymbolHitTier { labelPrefix, labelContains, aliasPrefix, aliasContains, keywordPrefix, keywordContains, pinyinPrefix, pinyinContains }

class SymbolHit {
  const SymbolHit(this.item, this.tier);
  final SymbolItem item;
  final SymbolHitTier tier;

  @override
  String toString() => '${item.label}(${tier.name})';
}

class SymbolLibrary {
  SymbolLibrary(List<SymbolItem> items)
      : items = List<SymbolItem>.unmodifiable(items),
        groups = List<String>.unmodifiable(<String>{
          for (final SymbolItem i in items) i.group,
        });

  final List<SymbolItem> items;

  /// 分类页签的顺序 = **JSON 里第一次出现的顺序**（不是字母序）
  final List<String> groups;

  static SymbolLibrary fromJson(String source) {
    final Map<String, dynamic> root =
        jsonDecode(source) as Map<String, dynamic>;
    final List<dynamic> raw = (root['items'] as List<dynamic>?) ?? <dynamic>[];
    final List<SymbolItem> out = <SymbolItem>[];
    for (final dynamic r in raw) {
      final Map<String, dynamic> m = r as Map<String, dynamic>;
      out.add(SymbolItem(
        id: m['id'] as String,
        kind: (m['kind'] as String?) == 'template'
            ? SymbolKind.template
            : SymbolKind.symbol,
        tex: m['tex'] as String,
        label: m['label'] as String,
        group: (m['group'] as String?) ?? '其它',
        subgroup: (m['subgroup'] as String?) ?? '',
        aliases: <String>[
          for (final dynamic a in (m['alias'] as List<dynamic>?) ?? <dynamic>[])
            a as String,
        ],
        pinyin: (m['pinyin'] as String?) ?? '',
        keywords: <String>[
          for (final dynamic k
              in (m['keywords'] as List<dynamic>?) ?? <dynamic>[])
            k as String,
        ],
        alsoIn: <String>[
          for (final dynamic a in (m['alsoIn'] as List<dynamic>?) ?? <dynamic>[])
            a as String,
        ],
        preview: (m['preview'] as String?) ?? '',
        insertAs: (m['insertAs'] as String?) == 'display'
            ? SymbolInsertAs.display
            : SymbolInsertAs.inline,
      ));
    }
    return SymbolLibrary(out);
  }

  static Future<SymbolLibrary> load({AssetBundle? bundle}) async {
    final String src =
        await (bundle ?? rootBundle).loadString('assets/symbols.json');
    return fromJson(src);
  }

  /// 一个一级分类下的项（**含 alsoIn 第二归属**）
  List<SymbolItem> inGroup(String group) => <SymbolItem>[
        for (final SymbolItem i in items)
          if (i.categories.any((String c) => c == group || c.startsWith('$group/')))
            i,
      ];

  /// 按「一级 [+ 子类]」筛选；两个参数都可为 `null`（= 全部）。
  /// ★ 命中**任一**归属即算（主归属或 alsoIn）。
  List<SymbolItem> inCategory({String? group, String? subgroup}) {
    final String? want = group == null
        ? null
        : (subgroup == null ? group : '$group/$subgroup');
    if (want == null) return items;
    return <SymbolItem>[
      for (final SymbolItem i in items)
        if (i.categories.any((String c) =>
            subgroup == null
                ? (c == group || c.startsWith('$group/'))
                : (c == want || i.alsoIn.contains(want))))
          i,
    ];
  }

  /// 某分类下出现过的子类（**去重保序**）；没有子类返回空表
  ///
  /// ★ 2026-10-17 修：原实现忘了去重 ⇒ 下拉里会出现 `希腊 · 希腊 · 运算 · 运算 · 关系`。
  List<String> subgroupsOf(String group) {
    final List<String> out = <String>[];
    for (final SymbolItem i in items) {
      if (i.group != group || i.subgroup.isEmpty) continue;
      if (!out.contains(i.subgroup)) out.add(i.subgroup);
    }
    return out;
  }

  SymbolItem? byId(String id) {
    for (final SymbolItem i in items) {
      if (i.id == id) return i;
    }
    return null;
  }

  /// 搜索：`标签 > 别名 > 关键词 > 拼音`，每档"开头"优先于"包含"；同档保持库内顺序（稳定）
  List<SymbolHit> search(String query, {int limit = 60}) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return const <SymbolHit>[];
    final List<SymbolHit> hits = <SymbolHit>[];
    for (final SymbolItem i in items) {
      final SymbolHitTier? t = _tierOf(i, q);
      if (t != null) hits.add(SymbolHit(i, t));
    }
    // 稳定排序：只按 tier 排（Dart 的 List.sort 不保证稳定 ⇒ 用带下标的比较）
    final List<int> idx = List<int>.generate(hits.length, (int i) => i);
    idx.sort((int a, int b) {
      final int d = hits[a].tier.index.compareTo(hits[b].tier.index);
      return d != 0 ? d : a.compareTo(b);
    });
    return <SymbolHit>[for (final int i in idx.take(limit)) hits[i]];
  }

  static SymbolHitTier? _tierOf(SymbolItem i, String q) {
    if (i.label.toLowerCase().startsWith(q)) return SymbolHitTier.labelPrefix;
    if (i.label.toLowerCase().contains(q)) return SymbolHitTier.labelContains;
    for (final String a in i.aliases) {
      if (a.toLowerCase().startsWith(q)) return SymbolHitTier.aliasPrefix;
    }
    for (final String a in i.aliases) {
      if (a.toLowerCase().contains(q)) return SymbolHitTier.aliasContains;
    }
    for (final String k in i.keywords) {
      if (k.toLowerCase().startsWith(q)) return SymbolHitTier.keywordPrefix;
    }
    for (final String k in i.keywords) {
      if (k.toLowerCase().contains(q)) return SymbolHitTier.keywordContains;
    }
    if (i.pinyin.toLowerCase().startsWith(q)) return SymbolHitTier.pinyinPrefix;
    // ★ 全拼也能命中首字母：`jifen` ⇒ `jf`（首字母串是查询的**子序列**）
    if (_isSubsequence(i.pinyin.toLowerCase(), q)) {
      return SymbolHitTier.pinyinContains;
    }
    if (i.pinyin.toLowerCase().contains(q)) return SymbolHitTier.pinyinContains;
    return null;
  }

  /// [short] 是不是 [long] 的**子序列**（"jf" ⊂ "jifen"、"aef" ⊂ "aerfaf"）
  static bool _isSubsequence(String short, String long) {
    if (short.isEmpty || short.length > long.length) return false;
    var k = 0;
    for (var i = 0; i < long.length && k < short.length; i++) {
      if (long[i] == short[k]) k++;
    }
    return k == short.length;
  }
}
