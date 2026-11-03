// 数语引擎 · **多行环境的单元格模型**（纯 Dart，2026-11-03「表」批）
//
// 只服务**选择边界与剪贴板**：把一段 tex 里环境的"格"切成**源码区间**，
// 于是"选区覆盖了哪些格""该带什么壳"都能算出来，不必碰渲染。
//
// 口径（`notes/handover/20261102-选择边界与剪贴板.md` §3.2 / §3.6）：
//   · **表** = matrix 家族（`matrix` `pmatrix` `bmatrix` `Bmatrix` `vmatrix` `Vmatrix`
//     `smallmatrix`）⇒ 顶层 `&` 切列、`\\` 切行；复制**矩形**；
//     **局部**表用中性 `bmatrix` 壳（行列式必须方阵，局部块不是行列式），**整表**保留原类型；
//   · **行单位** = `cases`（一行一格，逗号）· `aligned`（一行两格，`&` 是对齐点）
//     ⇒ 只按**整行**扩，壳沿用原类型；
//   · `array` 暂不认（外部文档才有）：它的 `&` 会退到"整块环境"路径（`orphanOwnerBefore` ⑤）。
//
// ★ 切格只认**顶层**分隔符：`{}` 里、以及嵌套环境里的 `&` / `\\` 不算
//   （`\begin{cases}` 里嵌 `bmatrix` 很常见）。
// ★ `\&` 是转义的字面量（`math_escape` 打出来的），不是分隔符。

/// 环境怎么切格。
enum EnvKind {
  /// 矩形表：`&` 切列、`\\` 切行
  matrix,

  /// 行单位：`cases` / `aligned` 等，只按整行扩
  rows,
}

/// matrix 家族（`&` / `\\` 都是结构符号）。
const Set<String> kMatrixEnvs = <String>{
  'matrix',
  'pmatrix',
  'bmatrix',
  'Bmatrix',
  'vmatrix',
  'Vmatrix',
  'smallmatrix',
};

/// 行单位的环境（`\\` 才是单位边界）。
const Set<String> kRowEnvs = <String>{
  'cases',
  'aligned',
  'gathered',
};

/// 一行里的一个格：`[start, end)` 是**内容**区间（不含 `&` / `\\`，含两侧空白）。
typedef EnvCell = ({int start, int end});

/// 选区覆盖的格：**从首格沿流到末格**（含两端，**不是外接矩形**）。
///
/// `(r0, c0)` = 第一个被碰到的格；`(r1, c1)` = 最后一个。
/// 覆盖范围 = 行 `r0` 的 `c0..行尾` ＋ 中间整行 ＋ 行 `r1` 的 `0..c1`。
/// ★ 2026-11-03（用户更正）：拖选是**线性**的，屏幕上高亮的就是这条带 ——
///   3×3 里从 `b` 拖到 `e`，外接矩形会把没高亮的 `a`、`f` 也带走。
typedef CellSpan = ({int r0, int c0, int r1, int c1});

/// 一次"删格"的结果：把 `[from, to)` 换成 [replacement]（格内容清空、分隔符保留）。
class CellClear {
  const CellClear({
    required this.from,
    required this.to,
    required this.replacement,
    required this.payload,
  });

  final int from;
  final int to;
  final String replacement;

  /// 这些格作为剪贴板载荷的样子（带壳）。
  final String payload;
}

/// 一个多行环境（源码区间 + 格表），坐标都是**传入 tex 的局部坐标**。
class EnvTable {
  const EnvTable({
    required this.name,
    required this.kind,
    required this.beginStart,
    required this.bodyStart,
    required this.bodyEnd,
    required this.endEnd,
    required this.rows,
  });

  final String name;
  final EnvKind kind;

  /// `\begin{name}` 的 `\` 下标
  final int beginStart;

  /// `\begin{name}` 之后（= 环境体起点）
  final int bodyStart;

  /// `\end{name}` 的 `\` 下标（= 环境体终点）
  final int bodyEnd;

  /// `\end{name}` 之后
  final int endEnd;

  final List<List<EnvCell>> rows;

  bool get isMatrix => kind == EnvKind.matrix;

  int get rowCount => rows.length;

  /// 最宽那一行有几格（参差行：只有导入/粘贴才会有）。
  int get maxCols =>
      rows.fold<int>(0, (int m, List<EnvCell> r) => r.length > m ? r.length : m);

  /// 整段环境的源码（`\begin{name}…\end{name}`）
  String textOf(String tex) =>
      tex.substring(beginStart.clamp(0, tex.length), endEnd.clamp(0, tex.length));

  @override
  String toString() => 'EnvTable($name, ${rows.length}×$maxCols) '
      '[$beginStart,$endEnd)';
}

/// `tex` 里**所有**多行环境（含嵌套；坐标在 [tex] 里）。
List<EnvTable> envTablesIn(String tex) {
  final List<_Open> stack = <_Open>[];
  final List<EnvTable> out = <EnvTable>[];
  for (final _Tok t in _tokens(tex)) {
    if (t.isBegin) {
      stack.add(_Open(t.at, t.end, t.name));
      continue;
    }
    if (stack.isEmpty || stack.last.name != t.name) continue;
    final _Open o = stack.removeLast();
    final EnvKind? kind = _kindOf(o.name);
    if (kind == null) continue;
    out.add(EnvTable(
      name: o.name,
      kind: kind,
      beginStart: o.at,
      bodyStart: o.end,
      bodyEnd: t.at,
      endEnd: t.end,
      rows: _splitBody(tex, o.end, t.at),
    ));
  }
  return out;
}

/// `offset` 落在**哪个（最内层）**多行环境里；不在 ⇒ null。
///
/// ★ 用 body 半开区间 `[bodyStart, bodyEnd]`：方块末尾那一格也算法在内。
EnvTable? envTableAt(String tex, int offset) {
  EnvTable? best;
  for (final EnvTable t in envTablesIn(tex)) {
    if (offset < t.bodyStart || offset > t.bodyEnd) continue;
    if (best == null || t.beginStart > best.beginStart) best = t;
  }
  return best;
}

/// `[s, e)` **整段**落在哪个（最内层）多行环境的**体内**；不在 ⇒ null。
///
/// 只处理"选区完全在环境内部"——跨环境边界的选区走通用补全（环境成对）。
EnvTable? envTableForRange(String tex, int s, int e) {
  if (e <= s) return null;
  EnvTable? best;
  for (final EnvTable t in envTablesIn(tex)) {
    if (s < t.bodyStart || e > t.bodyEnd) continue;
    if (best == null || t.beginStart > best.beginStart) best = t;
  }
  return best;
}

/// 覆盖 `[s, e)` 的格：**从首格沿流到末格**（不是外接矩形）。
///
/// ★★ 2026-11-03（用户更正）：**拖选是线性的**——屏幕上高亮的就是这条带。
///   3×3 里从 `b` 拖到 `e`，碰到的格是 `b c` + `d e`；外接矩形会把没高亮的
///   `a`、`f` 也带走（违反「粘贴结果 = 高亮那段」）。
/// ⇒ `(r0,c0)` 取**第一个**碰到的格、`(r1,c1)` 取**最后一个**，覆盖范围 = 那条带。
///
/// 零长格（`a & ` 里 `&` 后面那个空格）用**闭区间**判触碰，否则"选到行尾"会漏掉空格。
CellSpan? cellsSpanning(EnvTable t, int s, int e) {
  ({int r, int c})? first;
  ({int r, int c})? last;
  for (var r = 0; r < t.rows.length; r++) {
    for (var c = 0; c < t.rows[r].length; c++) {
      final EnvCell cell = t.rows[r][c];
      if (cell.end < s || cell.start > e) continue;
      first ??= (r: r, c: c);
      last = (r: r, c: c);
    }
  }
  if (first == null) {
    // 选区只压在分隔符上（`&` 本身）⇒ 归**最近的那一格**
    final ({int r, int c})? near = _nearestCell(t, s);
    if (near == null) return null;
    return (r0: near.r, c0: near.c, r1: near.r, c1: near.c);
  }
  return (r0: first.r, c0: first.c, r1: last!.r, c1: last.c);
}

/// 这条带是不是**把整张表都盖住了**（⇒ 按整表处理：保留原类型 / 连壳删）。
bool coversAllCells(EnvTable t, CellSpan span) {
  if (span.r0 != 0 || span.c0 != 0) return false;
  if (span.r1 != t.rows.length - 1) return false;
  // 首行从 0 起、末行盖上它的最后一格 ⇒ 中间各行整行都在范围内
  return span.c1 >= t.rows.last.length - 1;
}

/// 这条带里**实际存在**的格（行优先；参差行缺的格不算）。
List<EnvCell> cellsIn(EnvTable t, CellSpan span) {
  final List<EnvCell> out = <EnvCell>[];
  for (var r = span.r0; r <= span.r1 && r < t.rows.length; r++) {
    final List<EnvCell> row = t.rows[r];
    final int a = r == span.r0 ? span.c0 : 0;
    final int b = r == span.r1 ? span.c1 : row.length - 1;
    for (var c = a; c <= b && c < row.length; c++) {
      out.add(row[c]);
    }
  }
  return out;
}

/// 这条带作为**剪贴板载荷**的 tex（带壳，不含 `$`）。
///
/// · 整表 ⇒ 原样（保留原类型，`vmatrix` 还是 `vmatrix`）；
/// · 局部表 ⇒ 中性 `bmatrix`（行列式不能带源类型：局部块不是方阵）；
///   每行只带**这一带**的格 ⇒ 可能**参差**（`b&c` 与 `d`），粘贴时再补空；
/// · 行单位（`cases` / `aligned`）⇒ **整行**，壳沿用原类型。
String cellsPayload(EnvTable t, String tex, CellSpan span) {
  if (coversAllCells(t, span)) return t.textOf(tex);

  if (t.kind == EnvKind.rows) {
    final List<String> lines = <String>[];
    for (var r = span.r0; r <= span.r1 && r < t.rows.length; r++) {
      final List<EnvCell> row = t.rows[r];
      if (row.isEmpty) {
        lines.add('');
        continue;
      }
      lines.add(tex.substring(row.first.start, row.last.end).trim());
    }
    return '\\begin{${t.name}}${lines.join(r'\\')}\\end{${t.name}}';
  }

  final StringBuffer sb = StringBuffer();
  sb.write(r'\begin{bmatrix}');
  for (var r = span.r0; r <= span.r1 && r < t.rows.length; r++) {
    if (r > span.r0) sb.write(r'\\');
    final List<EnvCell> row = t.rows[r];
    final int a = r == span.r0 ? span.c0 : 0;
    final int b = r == span.r1 ? span.c1 : row.length - 1;
    var firstCol = true;
    for (var c = a; c <= b && c < row.length; c++) {
      if (!firstCol) sb.write('&');
      firstCol = false;
      sb.write(tex.substring(row[c].start, row[c].end).trim());
    }
  }
  sb.write(r'\end{bmatrix}');
  return sb.toString();
}

/// 删格：**清空**这条带里每一格的内容，`&` / `\\` 与壳都保留。
///
/// 返回一次替换（`[from, to)` → [CellClear.replacement]）——压成一次 `replace`，
/// 所以是**一步撤销**。带之外的内容原样保留（包括右侧没被选中的格）。
CellClear? cellClearPlan(EnvTable t, String tex, CellSpan span) {
  final List<EnvCell> cells = cellsIn(t, span);
  if (cells.isEmpty) return null;
  final int from = cells.first.start;
  final int to = cells.last.end;
  final StringBuffer sb = StringBuffer();
  var p = from;
  for (final EnvCell cell in cells) {
    if (cell.start > p) sb.write(tex.substring(p, cell.start)); // 分隔符（`&` / `\\`）
    if (cell.end > p) p = cell.end; // 内容整段抹掉
  }
  if (p < to) sb.write(tex.substring(p, to));
  return CellClear(
    from: from,
    to: to,
    replacement: sb.toString(),
    payload: cellsPayload(t, tex, span),
  );
}

// ---------------------------------------------------------------------------
// 解析
// ---------------------------------------------------------------------------

class _Open {
  const _Open(this.at, this.end, this.name);

  final int at;
  final int end;
  final String name;
}

class _Tok {
  const _Tok(this.at, this.end, this.isBegin, this.name);

  final int at;
  final int end;
  final bool isBegin;
  final String name;
}

EnvKind? _kindOf(String name) {
  if (kMatrixEnvs.contains(name)) return EnvKind.matrix;
  if (kRowEnvs.contains(name)) return EnvKind.rows;
  return null;
}

List<_Tok> _tokens(String s) {
  final RegExp rx = RegExp(r'\\(begin|end)\s*\{([^{}]*)\}');
  final List<_Tok> out = <_Tok>[];
  for (final Match m in rx.allMatches(s)) {
    out.add(_Tok(m.start, m.end, m.group(1) == 'begin', m.group(2)!.trim()));
  }
  return out;
}

/// 把环境体按**顶层** `\\`（行）与 `&`（列）切成格。
List<List<EnvCell>> _splitBody(String tex, int from, int to) {
  final List<List<EnvCell>> rows = <List<EnvCell>>[];
  List<EnvCell> row = <EnvCell>[];
  var cellStart = from;
  var braceDepth = 0;
  var envDepth = 0;
  var i = from;
  while (i < to) {
    final String c = tex[i];
    if (c == r'\') {
      if (i + 1 < to && tex[i + 1] == r'\') {
        if (braceDepth == 0 && envDepth == 0) {
          row.add((start: cellStart, end: i));
          rows.add(row);
          row = <EnvCell>[];
          i += 2;
          cellStart = i;
          continue;
        }
        i += 2;
        continue;
      }
      final String word = _wordAt(tex, i);
      if (word == 'begin' || word == 'end') {
        if (word == 'begin') {
          envDepth++;
        } else if (envDepth > 0) {
          envDepth--;
        }
        i = _afterName(tex, i);
        continue;
      }
      i = _skipControl(tex, i); // `\&` 等转义：整段跳过，不是分隔符
      continue;
    }
    if (c == '{') {
      braceDepth++;
    } else if (c == '}' && braceDepth > 0) {
      braceDepth--;
    } else if (c == '&' && braceDepth == 0 && envDepth == 0) {
      row.add((start: cellStart, end: i));
      i++;
      cellStart = i;
      continue;
    }
    i++;
  }
  row.add((start: cellStart, end: to));
  rows.add(row);
  return rows;
}

({int r, int c})? _nearestCell(EnvTable t, int offset) {
  ({int r, int c})? best;
  var bestDist = -1;
  for (var r = 0; r < t.rows.length; r++) {
    for (var c = 0; c < t.rows[r].length; c++) {
      final EnvCell cell = t.rows[r][c];
      final int d = offset < cell.start
          ? cell.start - offset
          : (offset > cell.end ? offset - cell.end : 0);
      if (bestDist < 0 || d < bestDist) {
        bestDist = d;
        best = (r: r, c: c);
      }
    }
  }
  return best;
}

String _wordAt(String s, int i) {
  if (i >= s.length || s[i] != r'\') return '';
  var j = i + 1;
  final int start = j;
  while (j < s.length && _isLetter(s[j])) {
    j++;
  }
  return s.substring(start, j);
}

int _skipControl(String s, int i) {
  if (i >= s.length || s[i] != r'\') return i + 1;
  var j = i + 1;
  if (j >= s.length) return j;
  if (!_isLetter(s[j])) return j + 1;
  while (j < s.length && _isLetter(s[j])) {
    j++;
  }
  return j;
}

/// `\begin{X}` / `\end{X}` 之后的位置（不是这个形状 ⇒ 跳过控制词）。
int _afterName(String s, int i) {
  var j = _skipControl(s, i);
  while (j < s.length && (s[j] == ' ' || s[j] == '\t' || s[j] == '\n')) {
    j++;
  }
  if (j >= s.length || s[j] != '{') return _skipControl(s, i);
  var depth = 0;
  for (var k = j; k < s.length; k++) {
    if (s[k] == '{') depth++;
    if (s[k] == '}') {
      depth--;
      if (depth == 0) return k + 1;
    }
  }
  return s.length;
}

bool _isLetter(String c) {
  final int u = c.codeUnitAt(0);
  return (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A);
}
