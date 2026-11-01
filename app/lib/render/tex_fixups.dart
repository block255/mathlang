// 数语引擎 · **tex 显示修正**（2026-10-20，用户实测"行间的上下极限不符合书写习惯"）
//
// 现象：`\limsup_{n\to\infty}` 在**行间**渲染成"lim sup + 右下角小下标"，
//   而 `\lim_{n\to\infty}` 是"lim + 正下方堆叠" —— 同一份作业里两种样子，不像教材。
// 探针实测（flutter_math_fork 0.7.4）：
//   `\limsup_{x}`               高度 18.8（侧标，错）
//   `\limsup\limits_{x}`        高度 31.8（**堆叠**，对）
//   `\operatorname*{lim sup}`   高度 18.8（这个移植版不认 `*`）
// ⇒ 只能插 `\limits`。但**插入会改长度**，而光标注入/选区/原子映射全都用 tex 偏移
//   ⇒ 本文件同时给出**偏移映射**（map），调用方把偏移换算过去再注入。
//
// 纯 Dart，可单测。

/// 需要"把上下限摆到正下方"的算符（KaTeX 里本该带 `\limits` 的那些）
const List<String> _kLimitOps = <String>[r'\limsup', r'\liminf'];

/// 一次修正的结果：[tex] 是给渲染器看的串，[mapOffset] 把**原串偏移**换成**新串偏移**。
class FixedTex {
  const FixedTex(this.tex, this._inserts, {this._insertLen = 7});

  /// 修正后的 tex（可以直接喂给 `Math.tex`）
  final String tex;

  /// 每个插入点：原串里的位置（命令名之后）
  final List<int> _inserts;

  /// 每个插入点的**插入长度**。
  ///
  /// ★★ 2026-10-24（批 4 · C1）：原先是写死的 `kLimitInsert.length`（`\limits` = 7），
  ///   而 `\frac` → `\dfrac` 只插 **1** 个字符 ⇒ 硬编码会让 frac 之后的偏移多算 6 格
  ///   （守卫当场抓到：`mapOffset(3)` 返回 10 而不是 4）。⇒ 改成每个实例自带长度。
  final int _insertLen;

  /// 原串偏移 → 新串偏移（落在插入点之前的偏移不受影响）
  int mapOffset(int offset) {
    var shifted = offset;
    for (final int at in _inserts) {
      if (at <= offset) shifted += _insertLen;
    }
    return shifted;
  }
}

/// 插入的串（`\limits`）
const String kLimitInsert = r'\limits';
/// 给 `\limsup` / `\liminf` 补 `\limits`（已经是 `\limits` 的跳过）。
FixedTex withOperandLimits(String tex) {
  final List<int> inserts = <int>[];
  final StringBuffer out = StringBuffer();
  var i = 0;
  while (i < tex.length) {
    var matched = false;
    if (tex[i] == r'\') {
      for (final String op in _kLimitOps) {
        if (!tex.startsWith(op, i)) continue;
        final int after = i + op.length;
        // 命令名后面必须是"非字母"（避免把 `\limsupfoo` 当命令）
        final bool nameEnds = after >= tex.length ||
            !RegExp(r'[A-Za-z]').hasMatch(tex[after]);
        if (!nameEnds) continue;
        // 已经有 `\limits` 或 `\nolimits` ⇒ 尊重用户的写法
        final String tail = tex.substring(after);
        if (tail.startsWith(r'\limits') || tail.startsWith(r'\nolimits')) {
          matched = true;
          out.write(op);
          i = after;
          break;
        }
        out.write(op);
        out.write(kLimitInsert);
        inserts.add(after);
        i = after;
        matched = true;
        break;
      }
    }
    if (matched) continue;
    out.write(tex[i]);
    i++;
  }
  if (inserts.isEmpty) return FixedTex(tex, const <int>[]);
  return FixedTex(out.toString(), inserts);
}

// ---------------------------------------------------------------------------
// ★★ 2026-10-24（批 4 · C1）：**行内分式加大** —— `\frac` → `\dfrac`
// ---------------------------------------------------------------------------

/// 行内 `\frac` 换成的命令（KaTeX 里 = 分子分母走 display 尺寸，即**全尺寸**）
const String kBigFrac = r'\dfrac';

/// `\frac` 与 `\dfrac` 的长度差 = 1（多出那个 `d`），插在 `\` 之后
const String kDfracInsert = 'd';

/// 把**顶层** `\frac` 换成 `\dfrac`（只给行内用；行间块本来就是 display 尺寸，不用换）。
///
/// 为什么要它：行内 `\frac` 的分子分母是 **0.71 档**（实测 15 px vs 正文 21 px），
/// 用户口径是"分式看起来过小，即使调大字号也没用"（C1）。这套引擎里没有"介于
/// 0.7 与 1.0 之间"的旋钮（0.7/0.5 是包里写死的常量），所以只能给它换档。
///
/// ★★★ 2026-11-01（反馈 18）：**只换顶层** —— 指数 / 上下限 / 另一个分式里的 `\frac`
///   一律不动。根因：`\dfrac` 会把这个分式的分子分母**直接顶到 1.0 档**，而它本来
///   应当由引擎按层降档（指数里是 0.5 档）。实测（字号 20，字形盒高）：
///   `e^{\frac{\theta}{2}}` ⇒ θ **10.0**；`e^{\dfrac{\theta}{2}}` ⇒ θ **21.0**（大两档）。
///   判据：花括号深度 = 0，且**不是** `^` / `_` 的裸参数（`e^\frac{a}{b}`）。
///
/// ★ 只改**渲染**用的 tex，L0 源码一个字符都不动；
/// ★ 插入点是 `\` 之后那一个 `d` ⇒ [FixedTex.mapOffset] 会把光标偏移同步过去。
FixedTex withBigFractions(String tex) {
  if (!tex.contains(r'\frac')) {
    return FixedTex(tex, const <int>[], insertLen: kDfracInsert.length);
  }
  final List<int> inserts = <int>[];
  final StringBuffer out = StringBuffer();
  var depth = 0;
  // 跳过空白后的前一个"有意义的字符"⇒ 用来认 `^` / `_` 的裸参数
  var prev = '';
  var i = 0;
  while (i < tex.length) {
    final String ch = tex[i];
    if (ch == r'\') {
      if (tex.startsWith(r'\frac', i)) {
        final int after = i + r'\frac'.length;
        // 命令名后面必须是"非字母"（`\fracA` 不是 `\frac`；`\dfrac` 根本不会命中这里）
        final bool nameEnds = after >= tex.length ||
            !RegExp(r'[A-Za-z]').hasMatch(tex[after]);
        final bool topLevel = depth == 0 && prev != '^' && prev != '_';
        if (nameEnds && topLevel) {
          out.write(r'\');
          out.write(kDfracInsert); // ← 插入点在这里（原串的 i+1 之前）
          out.write('frac');
          inserts.add(i + 1);
          prev = 'c';
          i = after;
          continue;
        }
      }
      // 其它控制序列整体复制（`\{` / `\}` / `\\` / `\ ` 都不改变深度）
      final int end = _commandEnd(tex, i);
      out.write(tex.substring(i, end));
      final String last = tex[end - 1];
      if (last != ' ') prev = last;
      i = end;
      continue;
    }
    if (ch == '{') {
      depth++;
    } else if (ch == '}' && depth > 0) {
      depth--;
    }
    if (ch != ' ') prev = ch;
    out.write(ch);
    i++;
  }
  if (inserts.isEmpty) {
    return FixedTex(tex, const <int>[], insertLen: kDfracInsert.length);
  }
  return FixedTex(out.toString(), inserts, insertLen: kDfracInsert.length);
}

/// 一个控制序列的结束位置（`\` + 字母串，或 `\` + 单个非字母）。
int _commandEnd(String tex, int start) {
  var j = start + 1;
  if (j >= tex.length) return j;
  if (RegExp(r'[A-Za-z]').hasMatch(tex[j])) {
    while (j < tex.length && RegExp(r'[A-Za-z]').hasMatch(tex[j])) {
      j++;
    }
    return j;
  }
  return j + 1;
}