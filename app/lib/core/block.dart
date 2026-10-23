// 数语引擎 · 块模型（L1 行 / L2 块 / FlowUnit 分页单元）
//
// 规格：notes/design/块模型与md往返.md（R0–R8 定稿）
// 本文件是**纯 Dart**，不依赖 Flutter —— 规则可以直接被单测钉死。

/// 块类型。L0（md 源）里的「行首标记」才是唯一真相，本枚举只是它的**推断结果**。
enum BlockType {
  paragraph,
  heading1,
  heading2,
  heading3,
  bulletList,
  orderedList,
  quote,
  code,
  math,
  divider,
  pageBreak,
}

extension BlockTypeX on BlockType {
  bool get isList =>
      this == BlockType.bulletList || this == BlockType.orderedList;

  int get headingLevel => switch (this) {
        BlockType.heading1 => 1,
        BlockType.heading2 => 2,
        BlockType.heading3 => 3,
        _ => 0,
      };
}

/// 手动分页符在 L0 里的写法（各 md 工具渲染时不可见 —— R7）。
const String kPageBreakMarker = '<!-- pagebreak -->';

/// 围栏 / 标记常量。
const String kFence = '```';
const String kMathFence = r'$$';

final RegExp _headingRe = RegExp(r'^ {0,3}(#{1,6}) +');
final RegExp _listRe = RegExp(r'^( *)([-*+]|\d{1,9}[.)])( +)');
final RegExp _quoteRe = RegExp(r'^ {0,3}> ?');
final RegExp _dividerRe = RegExp(r'^ {0,3}(?:-{3,}|\*{3,}|_{3,}) *$');
final RegExp _digitRe = RegExp(r'^\d');

int _indentOf(String s) {
  var i = 0;
  while (i < s.length && s[i] == ' ') {
    i++;
  }
  return i;
}

/// 一个列表行首标记的解析结果。
class ListMarker {
  const ListMarker({
    required this.indent,
    required this.ordered,
    required this.contentStart,
    required this.raw,
  });

  /// 前导空格数（v1 用它区分嵌套，但渲染只做一层）
  final int indent;

  /// 是有序列表标记（`1.` / `1)`）还是无序（`-` / `*` / `+`）
  final bool ordered;

  /// 内容在行内的起始下标（= 缩进 + 标记 + 后随空白）
  final int contentStart;

  /// 标记本身（不含缩进与后随空白），如 `-` 或 `12.`
  final String raw;
}

/// L1：行索引。按 `\n` 切；**行尾空格原样保留**（R8 的硬换行标记就在行尾）。
class LineIndex {
  LineIndex._(this.buf, this.starts, this.ends);

  factory LineIndex.of(String buf) {
    final starts = <int>[];
    final ends = <int>[];
    var i = 0;
    while (true) {
      starts.add(i);
      final nl = buf.indexOf('\n', i);
      if (nl < 0) {
        ends.add(buf.length);
        break;
      }
      ends.add(nl);
      i = nl + 1;
    }
    return LineIndex._(buf, starts, ends);
  }

  final String buf;

  /// 每行起始偏移（含）
  final List<int> starts;

  /// 每行结束偏移（不含 `\n`）
  final List<int> ends;

  int get count => starts.length;

  String text(int i) => buf.substring(starts[i], ends[i]);

  /// 空行 = 去掉空白后长度为 0（R1 的边界判定）
  bool isBlank(int i) => text(i).trim().isEmpty;

  /// 行尾是否有硬换行标记（两个空格或反斜杠）—— R8
  bool hasHardBreak(int i) {
    final t = text(i);
    return t.endsWith('  ') || t.endsWith(r'\');
  }

  /// 偏移 → 行号（二分查找）
  int lineOf(int offset) {
    final o = offset.clamp(0, buf.length);
    var lo = 0;
    var hi = count - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (starts[mid] <= o) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }
}

/// L2：块 = 一个**行区间** + 推断出的类型。
class Block {
  const Block(this.type, this.lineFrom, this.lineTo);

  final BlockType type;

  /// 含
  final int lineFrom;

  /// 不含
  final int lineTo;

  int get lineCount => lineTo - lineFrom;
  bool get isList => type.isList;

  @override
  String toString() => 'Block($type, $lineFrom..$lineTo)';
}

/// 分页原子：块是「语义」，FlowUnit 才是「不可再分」（见设计文档 §五）。
class FlowUnit {
  const FlowUnit(this.blockIndex, this.lineFrom, this.lineTo);

  final int blockIndex;
  final int lineFrom;
  final int lineTo;

  int get lineCount => lineTo - lineFrom;

  @override
  String toString() => 'FlowUnit(blk=$blockIndex, $lineFrom..$lineTo)';
}

/// L2 的完整视图：行 + 块 + 分页单元。**三者都是 L0 的纯函数派生。**
class BlockIndex {
  BlockIndex._(this.lines, this.blocks, this.flowUnits);

  factory BlockIndex.parse(String buf) {
    final lines = LineIndex.of(buf);
    final blocks = <Block>[];
    final n = lines.count;
    var i = 0;
    while (i < n) {
      if (lines.isBlank(i)) {
        i++; // R1：多个连续空行 = 一个边界，不产生空块
        continue;
      }
      final t = lines.text(i);

      // R6 代码块
      if (BlockMarkers.isFence(t)) {
        final start = i;
        i++;
        while (i < n && !BlockMarkers.isFence(lines.text(i))) {
          i++;
        }
        if (i < n) i++; // 未闭合 → 吞到文末
        blocks.add(Block(BlockType.code, start, i));
        continue;
      }

      // R5 公式块
      if (BlockMarkers.isMathFence(t)) {
        final start = i;
        i++;
        if (!BlockMarkers.isClosedMathFence(t)) {
          while (i < n && !BlockMarkers.isMathFence(lines.text(i))) {
            i++;
          }
          if (i < n) i++; // 未闭合 → 吞到文末
        }
        blocks.add(Block(BlockType.math, start, i));
        continue;
      }

      // R2 标题
      final level = BlockMarkers.headingLevel(t);
      if (level > 0) {
        blocks.add(Block(BlockMarkers.headingType(level), i, i + 1));
        i++;
        continue;
      }

      // R7 分隔线 / 分页符
      if (BlockMarkers.isDivider(t)) {
        blocks.add(Block(BlockType.divider, i, i + 1));
        i++;
        continue;
      }
      if (BlockMarkers.isPageBreak(t)) {
        blocks.add(Block(BlockType.pageBreak, i, i + 1));
        i++;
        continue;
      }

      // 引用（连续 `>` 行 = 一块）
      if (BlockMarkers.quoteMatch(t) != null) {
        final start = i;
        while (i < n && BlockMarkers.quoteMatch(lines.text(i)) != null) {
          i++;
        }
        blocks.add(Block(BlockType.quote, start, i));
        continue;
      }

      // R4 列表
      final firstMarker = BlockMarkers.listMarker(t);
      if (firstMarker != null) {
        final start = i;
        final ordered = firstMarker.ordered;
        while (i < n) {
          if (lines.isBlank(i)) break; // R1
          final lt = lines.text(i);
          final m = BlockMarkers.listMarker(lt);
          if (m != null) {
            if (i > start && m.ordered != ordered) break; // 有/无序不合并
            i++;
            continue;
          }
          if (BlockMarkers.isListContinuation(lt)) {
            i++;
            continue;
          }
          break;
        }
        blocks.add(Block(
          ordered ? BlockType.orderedList : BlockType.bulletList,
          start,
          i,
        ));
        continue;
      }

      // R3 段落（软换行：块内单个 \n 渲染成空格）
      final start = i;
      i++;
      while (i < n &&
          !lines.isBlank(i) &&
          !BlockMarkers.interruptsParagraph(lines.text(i))) {
        i++;
      }
      blocks.add(Block(BlockType.paragraph, start, i));
    }
    return BlockIndex._(lines, blocks, _buildFlowUnits(lines, blocks));
  }

  final LineIndex lines;
  final List<Block> blocks;
  final List<FlowUnit> flowUnits;

  /// 按 §五 的粒度把块拆成分页单元。
  static List<FlowUnit> _buildFlowUnits(LineIndex lines, List<Block> blocks) {
    final out = <FlowUnit>[];
    for (var bi = 0; bi < blocks.length; bi++) {
      final b = blocks[bi];
      if (b.type == BlockType.paragraph || b.type == BlockType.quote) {
        // 段落 / 引用：每个源行 = 1 个分页单元
        for (var l = b.lineFrom; l < b.lineTo; l++) {
          out.add(FlowUnit(bi, l, l + 1));
        }
      } else if (b.isList) {
        // 列表：每个列表项（含它的续行）= 1 个分页单元
        var l = b.lineFrom;
        while (l < b.lineTo) {
          final from = l;
          l++;
          while (l < b.lineTo &&
              BlockMarkers.listMarker(lines.text(l)) == null) {
            l++;
          }
          out.add(FlowUnit(bi, from, l));
        }
      } else {
        // 标题 / 公式块 / 代码块 / 分隔线 / 分页符：整块 = 1 个，不切
        out.add(FlowUnit(bi, b.lineFrom, b.lineTo));
      }
    }
    return out;
  }
}

/// 行首标记的识别与生成 —— R2–R7 的"唯一真相在 L0"就落在这些函数上。
class BlockMarkers {
  const BlockMarkers._();

  static bool isFence(String s) => s.trimLeft().startsWith(kFence);

  /// 行首 `$$` 算不算**行间公式的围栏**？（R5）
  ///
  /// ★★ **2026-10-15 晚收紧**（用户实测抓出 `Parser Error`，精确复现见 `block_test.dart`）：
  /// 原判据只要求"行首是 `$$`"⇒ **空壳公式落在行首**时整行会被判成**行间公式块**。
  /// 而空壳是**设计要留的**（§4.6：公式里删到空 ⇒ 留 `$$`），并且那一行后面往往还跟着
  /// 别的行内公式（实测：`$$ $\hat{x}$ $\bar{y}$`）⇒ 整行当 tex 送进渲染器
  /// ⇒ 行里剩下的 `$` 落进数学模式 ⇒ `Parser Error: Can't use function '$' in math mode`。
  ///
  /// 收紧后的判据 —— 只有这两种才算围栏：
  ///   · **整行就是 `$$`**（开/闭围栏）
  ///   · **同行闭合的 `$$…$$`**（[isClosedMathFence]）
  /// `$$ … $`（空壳 + 后续内容）**不算** ⇒ 退回普通段落，那里的 `$$` 按**空的行内公式**渲染
  /// （§6.1.1 本来就要求把空公式画出来）✓
  static bool isMathFence(String s) {
    final String l = s.trimLeft();
    if (!l.startsWith(kMathFence)) return false;
    if (l.trimRight() == kMathFence) return true;
    return isClosedMathFence(l);
  }

  /// 同一行闭合的 `$$...$$`（R5）
  static bool isClosedMathFence(String s) {
    final t = s.trimRight();
    return t.length > 4 &&
        t.trimLeft().startsWith(kMathFence) &&
        t.endsWith(kMathFence);
  }

  /// 标题级别；0 = 不是标题。4–6 级按 3 级渲染（R2）
  static int headingLevel(String s) {
    final m = _headingRe.firstMatch(s);
    if (m == null) return 0;
    final lv = m.group(1)!.length;
    return lv > 3 ? 3 : lv;
  }

  static BlockType headingType(int level) => switch (level) {
        1 => BlockType.heading1,
        2 => BlockType.heading2,
        _ => BlockType.heading3,
      };

  /// 分隔线：整行 3 个以上的 `-` / `*` / `_`（行首最多 3 空格）。
  ///
  /// ★ 2026-10-23（批 2）：用 [String.trimRight] —— 老实现直接拿原行匹配，
  ///   碰上 **CRLF** 文件（行尾多一个 `\r`）就**静默失效**（实测用户那份抄写稿 3 个 `---` 全漏）。
  ///   进门已经会归一成 LF（`text_normalize.normalizeNewlines`），这里是**第二道兜底**。
  static bool isDivider(String s) => _dividerRe.hasMatch(s.trimRight());

  static bool isPageBreak(String s) => s.trim() == kPageBreakMarker;

  static Match? quoteMatch(String s) => _quoteRe.firstMatch(s);

  static ListMarker? listMarker(String s) {
    final m = _listRe.firstMatch(s);
    if (m == null) return null;
    final raw = m.group(2)!;
    return ListMarker(
      indent: m.group(1)!.length,
      ordered: _digitRe.hasMatch(raw),
      contentStart: m.end,
      raw: raw,
    );
  }

  /// 列表项的续行：缩进 ≥2 空格，且本身不是新的列表标记（R4）
  static bool isListContinuation(String s) {
    if (s.trim().isEmpty) return false;
    if (listMarker(s) != null) return false;
    return _indentOf(s) >= 2;
  }

  /// 会打断段落的行首写法（R2 / R7，以及各"块起始"写法）
  static bool interruptsParagraph(String s) =>
      isFence(s) ||
      isMathFence(s) ||
      headingLevel(s) > 0 ||
      isDivider(s) ||
      isPageBreak(s) ||
      quoteMatch(s) != null ||
      listMarker(s) != null;

  /// 行首标记长度（0 = 无标记）—— 切换块类型时用来剥掉旧标记
  static int markerLength(String s) {
    final h = _headingRe.firstMatch(s);
    if (h != null) return h.end;
    final l = listMarker(s);
    if (l != null) return l.contentStart;
    final q = quoteMatch(s);
    if (q != null) return q.end;
    return 0;
  }

  /// 块类型 → 行首标记。返回 `null` 表示"不能用'改行首标记'的方式切到该类型"
  /// （数学块 / 代码块 / 分隔线 / 分页符是**整块**语义，见 §七）。
  static String? markerFor(BlockType type, {int order = 1}) => switch (type) {
        BlockType.paragraph => '',
        BlockType.heading1 => '# ',
        BlockType.heading2 => '## ',
        BlockType.heading3 => '### ',
        BlockType.bulletList => '- ',
        BlockType.orderedList => '$order. ',
        BlockType.quote => '> ',
        _ => null,
      };

  /// R0：**仅导入时**使用的归一化。此外一个字符都不改。
  static String normalizeImported(String raw) {
    var s = raw;
    if (s.startsWith('\uFEFF')) s = s.substring(1);
    return s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }
}
