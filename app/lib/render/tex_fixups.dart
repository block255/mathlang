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
  const FixedTex(this.tex, this._inserts);

  /// 修正后的 tex（可以直接喂给 `Math.tex`）
  final String tex;

  /// 每个插入点：原串里的位置（命令名之后）
  final List<int> _inserts;

  /// 原串偏移 → 新串偏移（落在插入点之前的偏移不受影响）
  int mapOffset(int offset) {
    var shifted = offset;
    for (final int at in _inserts) {
      if (at <= offset) shifted += kLimitInsert.length;
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