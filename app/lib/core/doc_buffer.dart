// 数语引擎 · L0 一维缓冲区（唯一事实来源）+ 光标 / 选区 + 编辑历史
//
// 规格：notes/design/块模型与md往返.md（§二 五条铁律、§四 输出侧写入约定、§六 失效范围）
// 纯 Dart，不依赖 Flutter。

import 'block.dart';

/// 一次原子编辑：`[start, end)` 的原内容 [removed] 被替换为 [inserted]。
///
/// 逆操作 = 在 `[start, start + inserted.length)` 把 [inserted] 换回 [removed]。
class Edit {
  const Edit(this.start, this.end, this.removed, this.inserted);

  final int start;
  final int end;

  /// 编辑前的原内容（= 当时 buf.substring(start, end)）
  final String removed;

  /// 编辑后的新内容
  final String inserted;

  int get delta => inserted.length - removed.length;

  @override
  String toString() =>
      'Edit($start..$end, -${removed.length}, +${inserted.length})';
}

/// L0：一条 md 字符串就是文档的**全部**真相；块 / 页都是它的派生视图。
class DocBuffer {
  DocBuffer([String initial = '']) : _buf = initial;

  String _buf;
  int _caret = 0;
  int _anchor = 0;
  final List<Edit> _undoStack = <Edit>[];
  final List<Edit> _redoStack = <Edit>[];
  final List<void Function()> _listeners = <void Function()>[];

  // ---------- 读 ----------

  String get buf => _buf;
  int get length => _buf.length;
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
    if (!extend) _anchor = _caret;
    _notify();
  }

  void setSelection(int start, int end) {
    _anchor = start.clamp(0, _buf.length);
    _caret = end.clamp(0, _buf.length);
    _notify();
  }

  // ---------- 编辑 ----------

  /// 把 `[start, end)` 换成 [inserted]；光标落到插入内容之后。
  void replace(int start, int end, String inserted) {
    if (_replaceInternal(start, end, inserted)) _notify();
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
    } else if (_caret > 0) {
      replace(_caret - 1, _caret, '');
    }
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

  bool _replaceInternal(int start, int end, String inserted) {
    final s = start.clamp(0, _buf.length);
    final e = end.clamp(s, _buf.length);
    final removed = _buf.substring(s, e);
    if (removed.isEmpty && inserted.isEmpty) return false;
    final edit = Edit(s, e, removed, inserted);
    _applyForward(edit);
    _undoStack.add(edit);
    _redoStack.clear();
    return true;
  }

  void _applyForward(Edit e) {
    _buf = _buf.replaceRange(e.start, e.end, e.inserted);
    _setCaretRaw(e.start + e.inserted.length);
  }

  void _applyBackward(Edit e) {
    _buf = _buf.replaceRange(e.start, e.start + e.inserted.length, e.removed);
    _setCaretRaw(e.start + e.removed.length);
  }

  void _setCaretRaw(int offset) {
    _caret = offset.clamp(0, _buf.length);
    _anchor = _caret;
  }
}
