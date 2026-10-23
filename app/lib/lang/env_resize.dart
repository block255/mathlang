// 数语引擎 · **多行环境的尺寸重写**（PC-5 的地基，2026-10-18）
//
// 用途：右键矩阵/行列式 ⇒ 改行列数 / 换括号风格 ⇒ 就地重写这一段 tex。
//   · 矩阵（`bmatrix` / `pmatrix`）：行、列都可改；
//   · 行列式（`vmatrix`）：**强制方阵**（列数永远等于行数）；
//   · 既有内容按行列**保留**（左上角对齐），新格留空，被切掉的内容由调用方记进一次撤销。
//
// **纯 Dart**：不碰 Flutter、不碰渲染，便于单元测试。

/// 环境族：决定用什么定界符包。
enum EnvStyle {
  /// `\begin{bmatrix}…\end{bmatrix}`（中括号矩阵）
  bracket,

  /// `\begin{pmatrix}…\end{pmatrix}`（圆括号矩阵）
  paren,

  /// `\begin{vmatrix}…\end{vmatrix}`（竖线行列式）
  det,

  /// `\begin{cases}…\end{cases}`（分段函数）—— ★ 2026-10-23（批 2 · E1）：只有**段数**一个自由度
  cases,

  /// `\begin{aligned}…\end{aligned}`（对齐推导）—— 同上，只有**行数**
  aligned,
}

/// 这类环境**只有一个自由度**（行/段数），列数是固定的（`cases` / `aligned` 都是两列）
bool envRowsOnly(EnvStyle s) =>
    s == EnvStyle.cases || s == EnvStyle.aligned || s == EnvStyle.det;

/// 从 tex 里认出这是哪种环境；不是多行环境 ⇒ null。
EnvStyle? envStyleOf(String tex) {
  if (tex.contains(r'\begin{bmatrix}')) return EnvStyle.bracket;
  if (tex.contains(r'\begin{pmatrix}')) return EnvStyle.paren;
  if (tex.contains(r'\begin{vmatrix}')) return EnvStyle.det;
  if (tex.contains(r'\begin{cases}')) return EnvStyle.cases;
  if (tex.contains(r'\begin{aligned}')) return EnvStyle.aligned;
  return null;
}

const Map<EnvStyle, String> _kEnvNames = <EnvStyle, String>{
  EnvStyle.bracket: 'bmatrix',
  EnvStyle.paren: 'pmatrix',
  EnvStyle.det: 'vmatrix',
  EnvStyle.cases: 'cases',
  EnvStyle.aligned: 'aligned',
};

/// 把环境内容按 `\\`（行）与 `&`（列）切成格子。
///
/// 只切**顶层**分隔符：花括号内的 `&` / `\\` 不算（`\begin{cases}` 里嵌 `\\` 那种以后再说）。
List<List<String>> splitEnvCells(String body) {
  final List<List<String>> rows = <List<String>>[];
  final List<String> row = <String>[];
  final StringBuffer cell = StringBuffer();
  var depth = 0;
  var i = 0;
  while (i < body.length) {
    final String ch = body[i];
    if (ch == r'\') {
      if (i + 1 < body.length && body[i + 1] == r'\' && depth == 0) {
        row.add(cell.toString());
        rows.add(List<String>.of(row));
        row.clear();
        cell.clear();
        i += 2;
        continue;
      }
      cell.write(ch);
      if (i + 1 < body.length) {
        cell.write(body[i + 1]);
        i += 2;
      } else {
        i++;
      }
      continue;
    }
    if (ch == '{') depth++;
    if (ch == '}' && depth > 0) depth--;
    if (ch == '&' && depth == 0) {
      row.add(cell.toString());
      cell.clear();
      i++;
      continue;
    }
    cell.write(ch);
    i++;
  }
  row.add(cell.toString());
  rows.add(row);
  return rows;
}

/// 重写环境尺寸/风格。
///
/// - [rows] / [cols] 会被夹到 1..12；
/// - [EnvStyle.det] 强制方阵（`cols = rows`）；
/// - [EnvStyle.cases] / [EnvStyle.aligned] 只有行数可改（列数沿用调用方给的当前值）；
/// - 既有格子按**左上对齐**保留；不足的填空串；多余的丢掉（调用方负责撤销）。
String resizeEnvironment(
  String tex, {
  required int rows,
  required int cols,
  EnvStyle? style,
}) {
  final EnvStyle? found = envStyleOf(tex);
  final EnvStyle target = style ?? found ?? EnvStyle.bracket;
  final int r = rows.clamp(1, 12);
  int c = cols.clamp(1, 12);
  if (target == EnvStyle.det) c = r; // 行列式必须方阵

  // 取出原环境体
  final String name = _kEnvNames[found] ?? 'bmatrix';
  final int begin = tex.indexOf('\\begin{$name}');
  final int endTok = tex.indexOf('\\end{$name}');
  final String body = (begin >= 0 && endTok > begin)
      ? tex.substring(begin + '\\begin{$name}'.length, endTok)
      : '';

  final List<List<String>> old = splitEnvCells(body);
  // ★★ 2026-10-23（批 2）：**环境外面还有东西时不许吃掉它们**。
  //
  // 实测（`cases` 嵌在公式里特别常见：`f(x)=\begin{cases}…`）：老实现从头重写整段 tex，
  // ⇒ 右改尺寸会把 `f(x)=` 抹掉（矩阵同理：`A=\begin{bmatrix}…` 会丢掉 `A=`）。
  final String prefix = begin >= 0 ? tex.substring(0, begin) : '';
  final int endAt = endTok > begin ? endTok + '\\end{$name}'.length : -1;
  final String suffix = endAt >= 0 ? tex.substring(endAt) : '';
  final StringBuffer out = StringBuffer();
  out.write(r'\begin{');
  out.write(_kEnvNames[target]);
  out.write('}');
  for (var i = 0; i < r; i++) {
    if (i > 0) out.write(r'\\');
    for (var j = 0; j < c; j++) {
      if (j > 0) out.write('&');
      final String cell = (i < old.length && j < old[i].length) ? old[i][j] : '';
      out.write(cell);
    }
  }
  out.write(r'\end{');
  out.write(_kEnvNames[target]);
  out.write('}');
  return prefix + out.toString() + suffix;
}
