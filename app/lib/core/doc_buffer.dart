// 数语引擎 · L0 一维缓冲区（唯一事实来源）+ 光标 / 选区 + 编辑历史
//
// 规格：notes/design/块模型与md往返.md（§二 五条铁律、§四 输出侧写入约定、§六 失效范围）
// 纯 Dart，不依赖 Flutter。

import 'block.dart';
import 'text_normalize.dart';

/// 一次原子编辑：`[start, end)` 的原内容 [removed] 被替换为 [inserted]。
///
/// 逆操作 = 在 `[start, start + inserted.length)` 把 [inserted] 换回 [removed]。
class Edit {
  const Edit(this.start, this.end, this.removed, this.inserted,
      {this.eol = false,
      this.caretBefore = -1,
      this.caretAfter = -1,
      this.anchorBefore = -1,
      this.anchorAfter = -1});

  final int start;
  final int end;

  /// ★★★ 2026-11-01（反馈 5 · R11）：**编辑前 / 编辑后的光标与选区锚点**。
  ///
  /// 为什么必须记（而不是算）：撤销原先只有一条推断
  /// `caret = start + removed.length`（"被恢复区间的右缘"），
  /// 它只在"编辑前光标正好停在区间右缘"时成立 —— 而 5 处"整篇 replace"
  /// （面板插符号 / 自动展开 / 块类型 / 分页符）区间横跨全文 ⇒ 撤销后光标跳到**文末**
  /// （实测：用户报的"Ctrl+Z 后光标跑到下一行"）。
  /// ⇒ **撤销用记录、不靠推断**；`-1` = 老数据/未记录，退回旧推断。
  final int caretBefore;
  final int caretAfter;
  final int anchorBefore;
  final int anchorAfter;

  /// 编辑前的原内容（= 当时 buf.substring(start, end)）
  final String removed;

  /// 编辑后的新内容（★ **不含**补出来的行终止符 —— 那是 [eol] 的事）
  final String inserted;

  /// ★★★ 2026-10-27（只读基准 4）：这次编辑**补了文末的行终止符**。
  ///
  /// 为什么需要：光标是一个整数偏移，而"文末行末"和"下一行行首"只有在
  /// **文末行有行终止符**时才是两个不同的整数。没有它，那一行只能靠"把光标画在
  /// 上一行的行末、却宣称它在下一行"来假装 —— 一打字就露馅（字接在上一行末尾）。
  /// 所以：**非空文档永远以 `\n` 收尾**，补出来的那个 `\n` 记在这次编辑里（撤销才精确），
  /// 但**光标停在它前面**（= 用户打的那个字之后）。
  final bool eol;

  int get delta => inserted.length - removed.length;

  @override
  String toString() =>
      'Edit($start..$end, -${removed.length}, +${inserted.length}'
      '${eol ? ", eol" : ""})';
}

/// **进门的唯一归一**：换行归一（CRLF ⇒ LF）+ **非空文档以 `\n` 收尾**。
///
/// ★★★ 2026-10-27（只读基准 4 的地基）：光标是一个整数偏移，"文末行末"与"文末下一行行首"
/// 只有在**文末行有行终止符**时才是两个不同的整数。所以凡是从外面进来的正文
/// （打开文件 / 恢复暂存 / 导入）都走这一条 —— **连"上次保存的快照"也要走**，
/// 否则归一之后缓冲区与快照差一个 `\n`，外壳会以为文档一直是"脏"的（实测：自动保存死循环）。
String normalizeDocumentText(String text) {
  final String s = normalizeNewlines(text);
  return (s.isNotEmpty && !s.endsWith('\n')) ? '$s\n' : s;
}

/// L0：一条 md 字符串就是文档的**全部**真相；块 / 页都是它的派生视图。
class DocBuffer {
  DocBuffer([String initial = '']) : _buf = initial;

  String _buf;
  int _caret = 0;
  int _anchor = 0;
  int _epoch = 0;
  final List<Edit> _undoStack = <Edit>[];
  final List<Edit> _redoStack = <Edit>[];
  final List<void Function()> _listeners = <void Function()>[];

  // ---------- 读 ----------

  String get buf => _buf;
  int get length => _buf.length;

  /// ★★ 2026-10-20（T-A 实测抓到的 F2）：**"这一份文档是第几次载入"**。
  ///
  /// 为什么需要它：`newDocument()` / `openDocument()` 走的是 [loadDocument]（**同一个实例**
  /// 整篇换掉），而编辑层（`EditView`）的"次编辑"计数只在**换 buffer 实例**时才归零
  /// （`didUpdateWidget`）⇒ 新建之后状态栏显示「0 字符 · 2 次编辑」，数字自相矛盾。
  /// [loadDocument] 把它 +1，编辑层看到它变了就把计数清零。
  int get docEpoch => _epoch;
  int get caret => _caret;
  int get anchor => _anchor;
  bool get hasSelection => _caret != _anchor;
  int get selectionStart => _caret < _anchor ? _caret : _anchor;
  int get selectionEnd => _caret < _anchor ? _anchor : _caret;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// L1 视图（每次调用都重算；需要缓存时在编辑层做，见 §六）
  LineIndex get lines => LineIndex.of(_buf);

  /// L2 视图
  BlockIndex get blocks => BlockIndex.parse(_buf);

  // ---------- 监听 ----------

  void addListener(void Function() l) => _listeners.add(l);
  void removeListener(void Function() l) => _listeners.remove(l);

  void _notify() {
    for (final l in List<void Function()>.of(_listeners)) {
      l();
    }
  }

  // ---------- 光标 / 选区 ----------

  void setCaret(int offset, {bool extend = false}) {
    _caret = offset.clamp(0, _buf.length);
    // ★★★ 2026-11-04（P3b **撤案**，留痕）：这里**不能**断言"光标不在段落分隔符上"。
    //   试过一版 `assert(!isParagraphSeparator(_buf, _caret))`，全量测试当场红 15+ 条 ——
    //   而红的是 `caret_ownership_global_test` / `paragraph_separator_test` 这类**故意**
    //   把光标摆到分隔符上、用来验证"那一格一根竖条都不许画"的守卫。
    //   ⇒ "setCaret 出口唯一"这个前提不成立：**归属/渲染层必须能探针式地设置任意偏移**。
    //   硬断言在错误的层；光标合法性归**编辑入口**（点击 / 方向键 / Enter），不归缓冲区。
    if (!extend) _anchor = _caret;
    _notify();
  }

  void setSelection(int start, int end) {
    _anchor = start.clamp(0, _buf.length);
    _caret = end.clamp(0, _buf.length);
    _notify();
  }

  // ---------- 编辑 ----------

  /// 归一：**非空文档补行终止符**。
  ///
  /// ★ 这**不是一次编辑** —— 不进撤销栈、不动光标（"文档该以换行收尾"是格式约定，
  /// 不是用户写的一笔）。所有编辑进门时都会走一遍，所以调用方不必操心。
  void ensureDocumentEol() {
    if (_buf.isNotEmpty && !_buf.endsWith('\n')) _buf = '$_buf\n';
  }

  /// 把 `[start, end)` 换成 [inserted]；光标落到插入内容之后。
  ///
  /// ★★ [coalesce]（S4-e-①，2026-10-18）：**连续打字合并成一步撤销**。
  ///   `true` 时若这次编辑与栈顶那条"接得上"，就**并进那一条**（撤销栈长度不变）：
  ///     · 连续**打字**：新插入点 == 上一条的插入末尾 ⇒ 把字符接上去；
  ///     · 连续**退格**：新删除的右端 == 上一条的左端 ⇒ 把删掉的字符接到前面。
  ///   ★ 只由**编辑层**按"时间窗口 + 动作类型"决定要不要传 `true` —— `DocBuffer` 保持纯逻辑
  ///     （不读系统时钟、不认识"打字"是什么），这样"合并规则"可以单独测。
  void replace(int start, int end, String inserted, {bool coalesce = false}) {
    if (_replaceInternal(start, end, inserted, coalesce: coalesce)) _notify();
  }

  void insertText(String text) {
    if (hasSelection) {
      replace(selectionStart, selectionEnd, text);
    } else {
      replace(_caret, _caret, text);
    }
  }

  void deleteBackward() {
    if (hasSelection) {
      replace(selectionStart, selectionEnd, '');
      return;
    }
    if (_caret <= 0) return;
    // ★★★ 2026-10-27（只读基准 3 最后一句）：
    //   「如果是在文末的下一行这个空行，点退格仅回到文末那一行末尾，
    //     因为我们要确保文末下一行这个空行永远能承接光标」。
    //   判据：光标在文末、末尾是 `\n`，而**末尾连续换行符不超过 2 个** ——
    //   那说明光标站的就是"文末下一行这个空行"（行表里只有它一行，见 `doc_view._rowsAfter`）。
    //   ⇒ 退格**不删那个换行符**（删了行就没了），只把光标退回文末那一行的行末 ——
    //     一个字都不改，也不进撤销栈。
    //   ★ `甲⏎⏎⏎`（3 个换行）不命中：那说明中间已经多出**用户造出来的空行**，该删（基准 3 第二句）。
    if (_caret == _buf.length && _buf.endsWith('\n')) {
      var m = 0;
      while (m < _buf.length && _buf[_buf.length - 1 - m] == '\n') {
        m++;
      }
      // `m < _buf.length` ⇒ 文末**真有内容行**（整篇都是空行的文档照常删）
      // ★ 2026-10-28：判据从"m <= 2"收紧成 **m == 1** —— 文末的行表改成"每个空行都是一行"
      //   之后，只有 `甲⏎` 那一格是"文末下一行"（删了就没位置承接光标）；
      //   `甲⏎⏎` 的 EOF 已经是**第二行**，退格该把这一行收掉（与 Enter 1:1）。
      if (m < _buf.length && m == 1) {
        _setCaretRaw(_buf.length - m); // = 文末那一行的行末
        _notify();
        return;
      }
    }
    final bool wasNewline = _buf[_caret - 1] == '\n';
    replace(_caret - 1, _caret, '');
    // ★★★ 2026-10-28（只读基准 2 / 3）：删掉的是**换行符**时，光标要落到
    //   **上一行的边界**上，而不是留在被删掉的那一格：
    //     · 上一行有字 ⇒ 它的**行末**（"按退格回到 A-B，并且光标回到 A 行末"）；
    //     · 上一行是空行 ⇒ 那个空行的行首（行首==行末，同一格）。
    //   判据：删完之后光标**前面紧跟着的还是换行符** ⇒ 说明光标还在换行串里，退一格。
    //   ★ 文末那一串空行**不退**：那里每个空行都是一行（行表不 skip）⇒ 退格就是把这一行
    //     收掉、光标落到**上一行**（= 上一格），再退一格就跳了两行（Enter/退格不再 1:1）。
    if (wasNewline &&
        _caret > 0 &&
        !_onlyNewlinesFrom(_caret) &&
        _buf[_caret - 1] == '\n') {
      _setCaretRaw(_caret - 1);
    }
  }

  /// 从 [p] 起到末尾是不是**全是换行符**（= 光标在"文末那一串空行"里）
  bool _onlyNewlinesFrom(int p) {
    for (var i = p; i < _buf.length; i++) {
      if (_buf[i] != '\n') return false;
    }
    return true;
  }

  void deleteForward() {
    if (hasSelection) {
      replace(selectionStart, selectionEnd, '');
    } else if (_caret < _buf.length) {
      replace(_caret, _caret + 1, '');
    }
  }

  /// `Enter` = 新块。R3 输出侧约定：**块间空一行**（否则 md 会把两段合并成一段，往返就坏了）。
  void newBlock() => insertText('\n\n');

  /// `Shift+Enter` = 块内硬换行。R8：行尾写**两个空格**（★ 任何环节都不许 trim）。
  void softBreak() => insertText('  \n');

  // ---------- 撤销 / 重做 ----------

  bool undo() {
    if (_undoStack.isEmpty) return false;
    final e = _undoStack.removeLast();
    _applyBackward(e);
    _redoStack.add(e);
    _notify();
    return true;
  }

  bool redo() {
    if (_redoStack.isEmpty) return false;
    final e = _redoStack.removeLast();
    _applyForward(e);
    _undoStack.add(e);
    _notify();
    return true;
  }

  // ---------- 块级操作（改的仍然是 L0 里的行首标记）----------

  /// 切换某一行所属的块类型：**只改行首标记**（R2–R4 的"唯一真相在 L0"）。
  void setLineBlockType(int line, BlockType type, {int order = 1}) {
    final marker = BlockMarkers.markerFor(type, order: order);
    if (marker == null) {
      throw ArgumentError(
        'setLineBlockType 只支持 段落/标题/列表/引用；'
        '$type 是整块语义（数学块 / 代码块 / 分隔线 / 分页符），见设计文档 §七',
      );
    }
    final idx = LineIndex.of(_buf);
    if (line < 0 || line >= idx.count) return;
    final lineStart = idx.starts[line];
    final t = idx.text(line);
    final oldLen = BlockMarkers.markerLength(t);
    final caretInLine = (_caret - lineStart).clamp(0, t.length);
    final contentOffset = (caretInLine - oldLen).clamp(0, t.length - oldLen);
    if (_replaceInternal(lineStart, lineStart + oldLen, marker)) {
      _setCaretRaw(lineStart + marker.length + contentOffset);
      _notify();
    }
  }

  /// 重排一个**有序列表块**的序号（normalize —— 只在提交点跑，见 §六）。
  void renumberOrderedList(BlockIndex idx, int blockIndex) {
    if (blockIndex < 0 || blockIndex >= idx.blocks.length) return;
    final b = idx.blocks[blockIndex];
    if (b.type != BlockType.orderedList) return;
    final start = idx.lines.starts[b.lineFrom];
    final end = idx.lines.ends[b.lineTo - 1];
    final sb = StringBuffer();
    var n = 1;
    for (var l = b.lineFrom; l < b.lineTo; l++) {
      if (l > b.lineFrom) sb.write('\n');
      final t = idx.lines.text(l);
      final m = BlockMarkers.listMarker(t);
      if (m != null && m.ordered) {
        final prefix = '${''.padRight(m.indent)}$n. ';
        sb.write(t.replaceRange(0, m.contentStart, prefix));
        n++;
      } else {
        sb.write(t);
      }
    }
    final savedCaret = _caret;
    final savedAnchor = _anchor;
    if (_replaceInternal(start, end, sb.toString())) {
      // normalize 不该把光标甩走（序号长度变化很小，clamp 足够）
      _caret = savedCaret.clamp(0, _buf.length);
      _anchor = savedAnchor.clamp(0, _buf.length);
      _notify();
    }
  }

  // ---------- 内部 ----------

  /// ★ S4-d：「打开文件 / 新建」用 —— **整篇换掉，并且把撤销栈清空**。
  ///
  /// 为什么不能用 `replace(0, len, …)`：那是一次普通编辑，撤销栈里会留着旧文档，
  /// 用户按 `Ctrl+Z` 会把"旧文件的内容"撤回来（打开另一个文件后还能撤回去 = 见鬼）。
  void loadDocument(String text) {
    // ★★ 2026-10-23（批 2）：进门先把换行归一成 LF。
    //
    // 外部文件（AI 答案 / 记事本）普遍是 CRLF，而 `$$` 围栏 / `---` 分隔线 / `# ` 标题 /
    // 列表标记 / 分页符 都按**整行**判定 —— 行尾那个 `\r` 会让判据**静默失效**
    // （实测用户那份抄写稿 CRLF，3 个 `---` 一个都没认成分隔线）。
    // 在缓冲区里存 LF 也顺手消掉"看不见的 `\r` 占偏移、污染字符数/光标"这条老账。
    _buf = normalizeDocumentText(text);
    _caret = 0;
    _anchor = 0;
    _undoStack.clear();
    _redoStack.clear();
    _epoch++; // 换了一份文档 ⇒ 编辑层的"次编辑"要归零（见 [docEpoch]）
    _notify();
  }

  bool _replaceInternal(int start, int end, String inserted,
      {bool coalesce = false}) {
    // ★ 进门先把"缺行终止符的遗留缓冲区"补上（老文件 / 测试里手搭的缓冲区）。
    //   必须在**取 removed 之前**做 —— 这样这次编辑是按归一后的文本记账的，
    //   "这次编辑碰到末尾了 ⇒ 顺手补终止符"那条判断（`eol`）也才成立。
    ensureDocumentEol();
    final s = start.clamp(0, _buf.length);
    final e = end.clamp(s, _buf.length);
    final removed = _buf.substring(s, e);
    if (removed.isEmpty && inserted.isEmpty) return false;
    // ★★★ 2026-10-27：**非空文档永远以 `\n` 收尾**（只读基准 4 的地基）。
    //   判据只看"改完之后是什么样"：只要结果少了行终止符、而且这次编辑碰到了末尾，就补一个。
    //   补出来的那个 `\n` 由 `Edit.eol` 表达（撤销才精确），光标停在它前面。
    final String after = _buf.replaceRange(s, e, inserted);
    final bool eol = after.isNotEmpty && !after.endsWith('\n') && e == _buf.length;
    // ★★★ 2026-11-01（R11）：**最小差分** —— 把 `[s, e)` 缩到"真正变化的那一段"。
    //   为什么：5 处调用点是 `replace(0, 长度, 新全文)`（面板插符号 / 自动展开 /
    //   块类型 / 分页符），区间横跨整篇 ⇒ ① 撤销的光标推断落到文末；
    //   ② 紧接着打字会被 `_tryMerge` 的"连续打字"规则并进那条巨区间 ⇒ 一次 Ctrl+Z 撤太多。
    //   缩到差分之后，这两件事都结构性消失（等价性：公共前后缀相同 ⇒ 两种写法结果一致）。
    final (int rs, int re, String rRemoved, String rInserted) =
        _minimalDiff(s, e, removed, inserted);
    final int newLen = _buf.length - (e - s) + inserted.length + (eol ? 1 : 0);
    final int caretAfter = (rs + rInserted.length).clamp(0, newLen);
    final edit = Edit(rs, re, rRemoved, rInserted, eol: eol,
        caretBefore: _caret.clamp(0, _buf.length),
        caretAfter: caretAfter,
        anchorBefore: _anchor.clamp(0, _buf.length),
        anchorAfter: caretAfter);
    _applyForward(edit);
    // ★ 撤销分组：能并就并进栈顶那一条（栈长度不变 ⇒ Ctrl+Z 一步回一大段）
    final Edit? merged =
        coalesce && _undoStack.isNotEmpty ? _tryMerge(_undoStack.last, edit) : null;
    if (merged != null) {
      _undoStack[_undoStack.length - 1] = merged;
    } else {
      _undoStack.add(edit);
    }
    _redoStack.clear();
    return true;
  }

  /// 两条 Edit 能不能并成一条（并规则见 [replace] 的注释）
  ///
  /// ★ 2026-10-28：`inserted` 里**不含**补出来的行终止符（那是 [Edit.eol]），
  /// 所以这里的比较全按"用户真写进去的内容"算 —— 连续退格/打字**不会**因为那个 `\n` 断组。
  static Edit? _tryMerge(Edit top, Edit next) {
    // ① 连续打字：上一条插进去的东西末尾正好是这次插入的位置
    if (top.inserted.isNotEmpty &&
        next.inserted.isNotEmpty &&
        top.removed.isEmpty &&
        next.removed.isEmpty &&
        next.start == top.start + top.inserted.length &&
        next.end == next.start) {
      return Edit(top.start, top.end, top.removed,
          '${top.inserted}${next.inserted}',
          eol: top.eol || next.eol,
          caretBefore: top.caretBefore,
          caretAfter: next.caretAfter,
          anchorBefore: top.anchorBefore,
          anchorAfter: next.anchorAfter);
    }
    // ② 连续退格：这次删的范围正好紧贴在上一条的左端
    if (top.removed.isNotEmpty &&
        next.removed.isNotEmpty &&
        top.inserted.isEmpty &&
        next.inserted.isEmpty &&
        next.end == top.start) {
      return Edit(next.start, top.end, '${next.removed}${top.removed}', '',
          eol: top.eol || next.eol,
          caretBefore: top.caretBefore,
          caretAfter: next.caretAfter,
          anchorBefore: top.anchorBefore,
          anchorAfter: next.anchorAfter);
    }
    return null;
  }

  /// 把一次替换缩到**真正变化的那一段**（公共前缀 / 公共后缀都不算变化）。
  ///
  /// ★ 2026-11-01（R11）：`replace(0, 全文长度, 新全文)` 的 5 个调用点靠它变成"局部编辑"。
  /// 等价性：`[s,e)` 换成 [inserted] 与 `[s+p, e-q)` 换成 [inserted] 去掉公共前后缀 —— 结果同串。
  static (int, int, String, String) _minimalDiff(
      int s, int e, String removed, String inserted) {
    final int maxP =
        removed.length < inserted.length ? removed.length : inserted.length;
    var p = 0;
    while (p < maxP && removed.codeUnitAt(p) == inserted.codeUnitAt(p)) {
      p++;
    }
    var q = 0;
    while (q < maxP - p &&
        removed.codeUnitAt(removed.length - 1 - q) ==
            inserted.codeUnitAt(inserted.length - 1 - q)) {
      q++;
    }
    return (
      s + p,
      e - q,
      removed.substring(p, removed.length - q),
      inserted.substring(p, inserted.length - q),
    );
  }

  void _applyForward(Edit e) {
    _buf = _buf.replaceRange(e.start, e.end, e.inserted);
    // ★ 补出来的行终止符挂在**文末**；光标停在它前面（否则每打一个字就跳到下一行）
    if (e.eol) _buf = '$_buf\n';
    // ★★ 2026-11-01（R11）：**重做**恢复"编辑后的光标/选区"（记录优先，推断兜底）
    if (e.caretAfter >= 0) {
      _caret = e.caretAfter.clamp(0, _buf.length);
      _anchor =
          (e.anchorAfter >= 0 ? e.anchorAfter : e.caretAfter).clamp(0, _buf.length);
    } else {
      _setCaretRaw(e.start + e.inserted.length);
    }
  }

  void _applyBackward(Edit e) {
    // ★ 补出来的 `\n` 一定在末尾（用它之后的编辑都已撤销），先摘掉它再还原这一段
    if (e.eol && _buf.endsWith('\n')) {
      _buf = _buf.substring(0, _buf.length - 1);
    }
    _buf = _buf.replaceRange(e.start, e.start + e.inserted.length, e.removed);
    // ★★ 2026-11-01（R11）：**撤销**恢复"编辑前的光标/选区" —— 不靠"区间右缘"推断
    if (e.caretBefore >= 0) {
      _caret = e.caretBefore.clamp(0, _buf.length);
      _anchor = (e.anchorBefore >= 0 ? e.anchorBefore : e.caretBefore)
          .clamp(0, _buf.length);
    } else {
      _setCaretRaw(e.start + e.removed.length);
    }
  }

  void _setCaretRaw(int offset) {
    _caret = offset.clamp(0, _buf.length);
    _anchor = _caret;
  }
}
