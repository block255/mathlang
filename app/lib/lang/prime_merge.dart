// 数语引擎 · **撇（导数撇）的并入点**（纯 Dart）
//
// 为什么需要它（用户 2026-11-04 写作业实测）：
//   撇在源码里写的是 `^{\prime}`（2026-11-01 口径：撇是脚本，不是裸字符）。
//   于是"再打一个撇"= 在同一个基座上**再挂一个上标** ⇒ `f^{\prime}^{\prime}`
//   ⇒ TeX **Double superscript** ⇒ 屏上 `[公式不完整]`（`f` 能打一个撇、打不了两个）。
//
// 口径（用户 2026-11-04 拍板）：
//   ① **一律并进"往左最近的那个上标"**（不限于撇）：`x^{2}` + `'` ⇒ `x^{2\prime}`；
//   ② **光标永远停在组之后**（与现状一致）⇒ 之后打 `+` / `(` / `=` 仍落主行；
//   ③ 面板 / 快捷键的撇与打字同一条规则。
//
// 判据（只往左看，不看右边、不解析 tex）：
//   ① **裸撇串**：光标左边紧邻未转义的 `'` ⇒ 直接再接一个 `'`（`f'` + `'` ⇒ `f''`）。
//      ★ 2026-11-04 晚补（用户实测"行内还没修"）：老文档 / 从 AI 抄来的公式里撇是**裸字符**
//      （`$f'$`）。这时再打撇会得到 `f'^{\prime}` ⇒ 同样是 Double superscript。
//      裸撇串本来就是合法 TeX（`f''`），提交点的归一化会把它变成 `^{\prime\prime}`。
//   ② 光标正停在某个 `^{…}` 的 `}` 之前（= 该组内容末尾）⇒ 就地插 `\prime`；
//   ③ 否则从光标往左：紧邻 `}` ⇒ 找配对的 `{`；
//       - 前面是 `^` ⇒ 把 `\prime` 插到那个 `}` 之前；
//       - 前面是 `_` ⇒ **跳过这个下标组**继续往左（`f^{\prime}_{+}` 要并进撇组）；
//       - 其它 ⇒ null（不是脚本组，不并）。
typedef PrimeMerge = ({int at, String text});

PrimeMerge? primeMergeTarget(String tex, int caret) {
  if (caret < 0 || caret > tex.length) return null;
  // ① 裸撇串
  if (caret > 0 && tex[caret - 1] == "'" && !_escaped(tex, caret - 1)) {
    return (at: caret, text: "'");
  }
  // ② 光标在某个上标组的内容末尾（`^{\prime|}`）⇒ 就地
  if (caret < tex.length && tex[caret] == '}') {
    final int open = matchOpenBrace(tex, caret);
    if (open > 0 && tex[open - 1] == '^') {
      return (at: caret, text: r'\prime');
    }
  }
  // ③ 往左扫：跳过下标组，遇到第一个上标组就并
  var p = caret;
  while (p > 0) {
    if (tex[p - 1] != '}') return null;
    final int open = matchOpenBrace(tex, p - 1);
    if (open <= 0) return null;
    final String mark = tex[open - 1];
    if (mark == '^') return (at: p - 1, text: r'\prime');
    if (mark != '_') return null; // 普通花括号组（不是脚本）⇒ 不并
    p = open - 1; // 跳过下标组，继续往左找上标组
  }
  return null;
}

/// [close]（必须指向 `}`）配对的 `{` 下标；配不上 ⇒ −1。
///
/// 跳过 `\{` / `\}`（转义的字面量），嵌套按深度配对 —— 与 `caret_sites` 的词法口径一致。
int matchOpenBrace(String tex, int close) {
  if (close < 0 || close >= tex.length || tex[close] != '}') return -1;
  var depth = 0;
  for (var i = close; i >= 0; i--) {
    final String c = tex[i];
    if (_escaped(tex, i)) continue;
    if (c == '}') {
      depth++;
    } else if (c == '{') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

bool _escaped(String s, int i) {
  var k = i - 1;
  var n = 0;
  while (k >= 0 && s[k] == r'\') {
    n++;
    k--;
  }
  return n.isOdd;
}
