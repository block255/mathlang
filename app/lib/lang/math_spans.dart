// 数语引擎 · **数学段扫描**（纯 Dart，S4-b②）
//
// 为什么需要：诊断清单要说"**编辑器替你补了哪几处 `$…$`**"，而不只是"补了几处"。
// 这个扫描器只做一件事：把源码里所有**成对的定界符**找出来（行内 `$…$` / 行间 `$$…$$`），
// 用于把"刚刚写进去的那一段"切成可以点、可以高亮的区间。
//
// 三条约定：
//   ① **不解析 tex**：只认定界符，成对才产出；落单的 `$` 一律跳过（那种情况有别的守卫盯着）；
//   ② `\$`（转义）不算定界符；行间 `$$` 优先于行内 `$`（同一位置先试两个）；
//   ③ 扫描是**线性**的，长文档也没问题（不含任何递归/回溯）。

/// 一段数学区间的**绝对偏移**（`[start, end)` 含定界符本体）
class MathSpan {
  const MathSpan({
    required this.start,
    required this.end,
    required this.tex,
    required this.display,
  });

  /// 开头定界符的起点
  final int start;

  /// 收尾定界符之后的位置
  final int end;

  /// 定界符**之间**的源码
  final String tex;

  /// 行间（`$$…$$`）还是行内（`$…$`）
  final bool display;

  int get length => end - start;

  /// 清单里显示用的一行摘要（太长就截断，正文里换行会被压扁）
  String summary({int max = 28}) {
    final String t = tex.replaceAll('\n', ' ').trim();
    return t.length <= max ? t : '${t.substring(0, max)}…';
  }

  @override
  String toString() =>
      'MathSpan[$start..$end)${display ? ' 行间' : ' 行内'} "$tex"';

  @override
  bool operator ==(Object other) =>
      other is MathSpan &&
      other.start == start &&
      other.end == end &&
      other.display == display &&
      other.tex == tex;

  @override
  int get hashCode => Object.hash(start, end, display, tex);
}

/// 扫描整份源码里的数学段（按出现顺序）
List<MathSpan> scanMathSpans(String source) {
  final List<MathSpan> out = <MathSpan>[];
  var i = 0;
  while (i < source.length) {
    if (source[i] != r'$' || _escaped(source, i)) {
      i++;
      continue;
    }
    final bool display = i + 1 < source.length && source[i + 1] == r'$';
    final int open = display ? 2 : 1;
    final int closeAt = _findClose(source, i + open, display);
    if (closeAt < 0) {
      // 落单的定界符：跳过这一个字符（不要整段放弃 —— 后面可能还有成对的）
      i += open;
      continue;
    }
    out.add(MathSpan(
      start: i,
      end: closeAt + open,
      tex: source.substring(i + open, closeAt),
      display: display,
    ));
    i = closeAt + open;
  }
  return out;
}

/// `i` 下标处的字符是不是被反斜杠转义（`\$`）
bool _escaped(String s, int i) {
  var k = i - 1;
  var n = 0;
  while (k >= 0 && s[k] == r'\') {
    n++;
    k--;
  }
  return n.isOdd;
}

/// 从 [from] 起找收尾定界符（跳过转义的与公式内部的代码块）
int _findClose(String s, int from, bool display) {
  var i = from;
  while (i < s.length) {
    if (s[i] != r'$' || _escaped(s, i)) {
      i++;
      continue;
    }
    if (display) {
      if (i + 1 < s.length && s[i + 1] == r'$') return i;
      i++;
      continue;
    }
    // 行内时遇到 `$$` 视作"这一对没配上"（交给下一个循环去当行间处理）
    if (i + 1 < s.length && s[i + 1] == r'$') return -1;
    return i;
  }
  return -1;
}
