// 数语引擎 · **自动展开**（"打字即渲染"的那一层，纯 Dart，S4-c）
//
// 规格：《S4-语言层与输入层.md》§C2 ·《快捷键系统.md》§五（Autoformat 先例）。
//
// 处理三类"用户没写编码、但编辑器替他写了"的输入：
//   ① **`/` → 分式**：光标前那个**可见原子**当分子，光标进分母空槽（"任何位置"，不加护栏）；
//   ② **词触发**：`sqrt` `sum` `int` … ＋ **终止符**（空格 / `Tab` / `Enter`）⇒ 结构模板；
//      必须**整词匹配**（`summer` / `asint` 不触发），**空格被终止符吃掉**（不进缓冲区）；
//   ③ **缩写**：`>=` `<=` `!=` `+-` `->` ⇒ `\ge \le \ne \pm \to`。
//
// ★ 为什么是纯函数："能不能展开"与"展开成什么"要在**不碰缓冲区**的前提下测得了，
//   编辑层只负责把结果**一次**落盘（`_buf.replace(0, len, …)`）⇒ **一步撤销**。
//
// ★★ 与插入侧守门人的关系：本文件只算"删掉哪一段 + 展开成什么 tex"，
//   真正的落点/建壳/行边界由 `symbol_insert.applySymbolInsert`（内部走 `insert_guard`）决定。

import '../render/math_nav.dart';
import '../render/visible_atoms.dart';
import 'word_triggers.dart';

/// 能展开的三类
enum AutoExpandKind {
  /// `/` ⇒ 分式（分子 = 光标前的可见原子）
  fraction,

  /// 词触发（`sqrt` + 终止符）
  word,

  /// 缩写（`>=` ⇒ `\ge`）
  shorthand,

  /// `^` / `_` ⇒ 上下标（基座 = 光标前的可见原子；2026-10-18）
  script,
}

/// 一次自动展开：**先把源区间 `[from, caret)` 删掉，再在那里插入 [tex]**。
class AutoExpand {
  const AutoExpand({
    required this.from,
    required this.caret,
    required this.tex,
    required this.kind,
    required this.template,
    this.keptTerminator = '',
    this.matched = '',
  });

  /// 要删掉的源区间起点（含）
  final int from;

  /// 要删掉的源区间终点（不含）＝ 展开时的光标位置
  final int caret;

  /// 展开成的 tex（**不含 `$…$`**）
  final String tex;

  final AutoExpandKind kind;

  /// 有槽（光标落第一个空槽）还是原子（光标落内容之后）
  final bool template;

  /// ★ 被**保留**的终止符（空格/Tab 被吃掉 ⇒ `''`；`Enter` 保留 ⇒ `'\n'`）
  final String keptTerminator;

  /// 命中的原文（`sqrt` / `/` / `>=`），诊断与状态栏用
  final String matched;

  @override
  String toString() => 'AutoExpand(${kind.name}, $from..$caret, '
      '"$matched"→"$tex", template=$template)';
}

/// 缩写表（键 = 打出来的两个字符，值 = tex）
const Map<String, String> kShorthandTex = <String, String>{
  '>=': r'\ge',
  '<=': r'\le',
  '!=': r'\ne',
  '+-': r'\pm',
  '->': r'\to',
};

/// 能不能当"分子"的字符：字母 / 数字 / 汉字 / 常见标识符字符。
///
/// ★ 故意**不**包括空格、`$`、`\`、括号 —— 那些拿来当分子只会把文档弄坏。
bool _isNumeratorChar(String ch) {
  if (ch.isEmpty) return false;
  final int c = ch.codeUnitAt(0);
  if (c >= 0x30 && c <= 0x39) return true; // 0-9
  if (c >= 0x41 && c <= 0x5A) return true; // A-Z
  if (c >= 0x61 && c <= 0x7A) return true; // a-z
  if (c >= 0x4E00 && c <= 0x9FFF) return true; // 汉字
  if (c >= 0x0370 && c <= 0x03FF) return true; // 希腊字母
  return false;
}

bool _isAsciiLetter(String ch) {
  if (ch.isEmpty) return false;
  final int c = ch.codeUnitAt(0);
  return (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
}

/// ★ 自动展开的**唯一入口**。
///
/// [typed] = 这一次本来要写进缓冲区的文本（单字符 / `'\n'` / `'\n\n'`）。
/// 返回 `null` = 按原样插入（不展开）。
///
/// 三个开关都由调用方给（用户在设置页里可关；关掉就是"这个键恢复成普通字符"）：
/// [slashFraction] · [wordTriggers]（词表本身能否用）· [shorthand]。
AutoExpand? planAutoExpand({
  required String doc,
  required int caret,
  required String typed,
  required TriggerSettings triggers,
  bool slashFraction = true,
  bool wordTriggers = true,
  bool shorthand = true,
}) {
  if (typed.isEmpty) return null;
  final int c = caret.clamp(0, doc.length);
  if (c != caret) return null; // 越界的光标不做决定（让编辑层自己去夹）

  // ---------- ① `/` → 分式 ----------
  if (slashFraction && typed == '/') {
    return _planFraction(doc, c);
  }

  // ---------- ①b `^` / `_` → 上下标（2026-10-18 用户实测：原来只是插了个字符）----------
  //   ★ 与 `/` 同一条思路：**基座 = 光标前那个可见原子**；在正文里则把基座包进 `$…$`。
  if (typed == '^' || typed == '_') {
    return _planScript(doc, c, typed);
  }

  // ---------- ② 词触发（需要终止符）----------
  if (wordTriggers) {
    final bool isSpace = typed == ' ';
    final bool isTab = typed == '\t';
    final bool isEnter = typed.startsWith('\n');
    if (isSpace || isTab || isEnter) {
      final AutoExpand? w = _planWord(doc, c, triggers);
      if (w != null) {
        return AutoExpand(
          from: w.from,
          caret: w.caret,
          tex: w.tex,
          kind: AutoExpandKind.word,
          template: w.template,
          matched: w.matched,
          // ★ 空格 / Tab **被终止符吃掉**（`\sqrt{}` 后面不跟空白）；`Enter` 保留（它是块级动作）
          keptTerminator: isEnter ? '\n' : '',
        );
      }
    }
  }

  // ---------- ③ 缩写 ----------
  if (shorthand && typed.length == 1) {
    final AutoExpand? s = _planShorthand(doc, c, typed);
    if (s != null) return s;
  }
  return null;
}

// ---------------------------------------------------------------------------
// `/` → 分式
// ---------------------------------------------------------------------------

/// 分子 = **光标前那个可见原子**（公式里）/ **光标前那一个字符**（正文里）。
///
/// ★ 公式里用 `lexVisibleAtoms` 的源区间（它跳过 `{` `}` `^` `_` `&` 这些**语法字符**），
///   所以"抽走分子"永远不会留下半个花括号 —— 这条是文档不被弄坏的关键。
/// `^` / `_` ⇒ 上下标（基座 = 光标前那个可见原子 / 一个字符）。
///
/// ★ 与 [_planFraction] 同一条判据：公式里用 `lexVisibleAtoms` 的源区间，
///   所以抽走基座不会留下半个花括号；正文里则把基座包进 `$…$`（同权：数学由内容产生）。
/// ★ 空槽由 `firstSlotOffset` 定位 ⇒ 光标自动落进 `^{}` / `_{}` 里。
AutoExpand? _planScript(String doc, int caret, String mark) {
  if (caret <= 0) return null;
  final MathRegion? r = mathRegionAt(doc, caret);
  if (r != null) {
    final int contentStart = r.contentStart;
    final int rel = (caret - contentStart).clamp(0, r.tex.length);
    VisibleAtom? last;
    for (final VisibleAtom a in lexVisibleAtoms(r.tex)) {
      if (a.kind == 'tail' || a.kind == 'slotpad' || a.kind == 'pad') continue;
      if (a.end > rel) break;
      last = a;
    }
    if (last == null || last.length == 0) return null;
    final String base = r.tex.substring(last.start, last.end);
    return AutoExpand(
      from: contentStart + last.start,
      caret: caret,
      tex: '$base$mark{}',
      kind: AutoExpandKind.script,
      template: true,
      matched: mark,
    );
  }
    // 正文里：光标前那一个字符当基座（`$…$` 由编辑层按模板统一包，别在这里自己加）
    final String prev = doc[caret - 1];
    if (!_isNumeratorChar(prev)) return null;
    return AutoExpand(
      from: caret - 1,
      caret: caret,
      tex: '$prev$mark{}',
      kind: AutoExpandKind.script,
      template: true,
      matched: mark,
    );
}

AutoExpand? _planFraction(String doc, int caret) {
  // ★★ 2026-10-18（用户改口径）：`/` = **独立插入一条分数线**，**不吃**前面的字符。
  //   旧行为把光标前那个原子抽走当分子（`a/b` ⇒ `\frac{a}{}`），用户复验后明确否掉：
  //   打 `/` 只该表示"这里开始一个分式"，前面写的东西原样留着；
  //   空格之后裸打一个 `/` 同样要成分式 ⇒ **不看前面有没有原子**。
  //   `$…$` 由编辑层按模板统一包（正文里会包成 `$\frac{}{}$`）。
  return AutoExpand(
    from: caret,
    caret: caret,
    tex: '\\frac{}{}',
    kind: AutoExpandKind.fraction,
    template: true,
    matched: '/',
  );
}

// ---------------------------------------------------------------------------
// 词触发
// ---------------------------------------------------------------------------

/// 向前扫一整串字母；**整串**必须与词表里的某个词相同（大小写不敏感）。
///
/// 三条护栏：
///  ① 前面紧跟 `\` ⇒ 用户是**故意**在写 LaTeX（`\sqrt`）⇒ 不展开；
///  ② 前面紧贴数字/汉字 ⇒ 说明它不是"独立的一个词"（`2sqrt`）⇒ 不展开；
///  ③ 词表里被停用 (`enabled == false`) 或非法的行 ⇒ 不展开。
AutoExpand? _planWord(String doc, int caret, TriggerSettings triggers) {
  if (caret <= 0) return null;
  var start = caret;
  while (start > 0 && _isAsciiLetter(doc[start - 1])) {
    start--;
  }
  if (start == caret) return null;
  final String word = doc.substring(start, caret);
  if (start > 0) {
    final String before = doc[start - 1];
    // ① 用户在**故意写 LaTeX**（`\sqrt`）⇒ 不展开
    if (before == r'\') return null;
    // ② 前面紧贴数字（`2sqrt`）⇒ 它不是一个独立的词
    if (before.codeUnitAt(0) >= 0x30 && before.codeUnitAt(0) <= 0x39) {
      return null;
    }
  }
  for (var i = 0; i < triggers.triggers.length; i++) {
    final WordTrigger t = triggers.triggers[i];
    if (!t.enabled) continue;
    if (!triggers.isValid(i)) continue; // 空词 / 词重复 ⇒ 不算数（与设置页同一判据）
    if (t.word.trim().toLowerCase() != word.toLowerCase()) continue;
    final String tex = t.tex.trim();
    return AutoExpand(
      from: start,
      caret: caret,
      tex: tex,
      kind: AutoExpandKind.word,
      template: tex.contains('{}') || tex.contains('[]'),
      matched: word,
    );
  }
  return null;
}

// ---------------------------------------------------------------------------
// 缩写
// ---------------------------------------------------------------------------

/// `>=` `<=` `!=` `+-` `->`：把**两格**一起换成一个符号。
AutoExpand? _planShorthand(String doc, int caret, String typed) {
  if (caret <= 0) return null;
  final String pair = '${doc[caret - 1]}$typed';
  final String? tex = kShorthandTex[pair];
  if (tex == null) return null;
  // `\a+=`：紧贴在控制词后面就不动（别把用户写的命令名拆了）
  if (caret >= 2 && doc[caret - 2] == r'\') return null;
  return AutoExpand(
    from: caret - 1,
    caret: caret,
    tex: tex,
    kind: AutoExpandKind.shorthand,
    template: false,
    matched: pair,
  );
}
