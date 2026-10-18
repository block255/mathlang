// 数语引擎 · **词触发（快捷输入）**（纯 Dart，S4-b②）
//
// 规格：《S4-语言层与输入层.md》§C ·《界面与布局》§6「智能输入」·《快捷键系统》§六-2（缩写展开**默认关**）。
//
// 一句话：在公式里打 `sqrt` + 终止符 ⇒ 直接变成 `\sqrt{□}`，光标进第一个空槽。
// 用户 2026-10-17 确认的边界：词表**可以加行、可以删行**（因为是用户自己编的），
// 与快捷键表不同（那张表只能给**已有动作**加副绑定）。
//
// ★ 状态：**还没接入**（S4-c 才接进输入链）。这一批只做"能看、能改、能存偏好"，
//   界面必须标明"未接入"，绝不假装已经能展开。

/// 一条词触发
class WordTrigger {
  const WordTrigger({
    required this.word,
    required this.tex,
    this.terminators = 'Tab · 空格 · Enter',
    this.enabled = true,
  });

  /// 触发的单词（`sqrt`）
  final String word;

  /// 展开成的 tex（`\sqrt{}`，不含 `$…$`）
  final String tex;

  /// 终止符（人类可读；S4-c 接线时再解析成集合）
  final String terminators;
  final bool enabled;

  WordTrigger copyWith({
    String? word,
    String? tex,
    String? terminators,
    bool? enabled,
  }) =>
      WordTrigger(
        word: word ?? this.word,
        tex: tex ?? this.tex,
        terminators: terminators ?? this.terminators,
        enabled: enabled ?? this.enabled,
      );

  @override
  String toString() => 'WordTrigger($word → $tex)';
}

/// 默认词表（8 条；都是"打出来比找面板快"的东西）
const List<WordTrigger> kDefaultWordTriggers = <WordTrigger>[
  WordTrigger(word: 'sqrt', tex: r'\sqrt{}'),
  WordTrigger(word: 'frac', tex: r'\frac{}{}'),
  WordTrigger(word: 'sum', tex: r'\sum_{}^{}'),
  WordTrigger(word: 'prod', tex: r'\prod_{}^{}'),
  WordTrigger(word: 'int', tex: r'\int_{}^{}'),
  WordTrigger(word: 'lim', tex: r'\lim_{}'),
  WordTrigger(word: 'vec', tex: r'\vec{}'),
  WordTrigger(word: 'abs', tex: r'\left|{}\right|'),
];

/// 用户的词表（内存态；持久化随 S4-e）
class TriggerSettings {
  const TriggerSettings({required this.triggers});

  final List<WordTrigger> triggers;

  factory TriggerSettings.defaults() =>
      TriggerSettings(triggers: List<WordTrigger>.of(kDefaultWordTriggers));

  TriggerSettings withItem(int index, WordTrigger t) {
    if (index < 0 || index >= triggers.length) return this;
    final List<WordTrigger> next = List<WordTrigger>.of(triggers)..[index] = t;
    return TriggerSettings(triggers: next);
  }

  /// 加一行（空白行，用户自己填）
  TriggerSettings add() => TriggerSettings(
        triggers: <WordTrigger>[
          ...triggers,
          const WordTrigger(word: '', tex: ''),
        ],
      );

  TriggerSettings removeAt(int index) {
    if (index < 0 || index >= triggers.length) return this;
    final List<WordTrigger> next = List<WordTrigger>.of(triggers)
      ..removeAt(index);
    return TriggerSettings(triggers: next);
  }

  /// 词重复 / 空词 ⇒ 不算数（UI 上标红；S4-c 接线时以这里为准）
  bool isValid(int index) {
    if (index < 0 || index >= triggers.length) return false;
    final WordTrigger t = triggers[index];
    if (t.word.trim().isEmpty || t.tex.trim().isEmpty) return false;
    var n = 0;
    for (final WordTrigger o in triggers) {
      if (o.word.trim() == t.word.trim()) n++;
    }
    return n == 1;
  }

  bool get allValid {
    for (var i = 0; i < triggers.length; i++) {
      if (!isValid(i)) return false;
    }
    return true;
  }
}
