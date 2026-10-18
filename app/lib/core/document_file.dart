// 数语引擎 · **当前文档的身份**（S4-d-①，纯 Dart，可单测）
//
// 一个普通文件编辑器的语义（用户 2026-10-17 定的口径）：
//   · **能打开电脑里的文件**；**没保存的只活在内存里**；
//   · 「最近打开 / 多文档列表」这层清单**不做**（那是另一个东西，归 S4-e 以后）；
//   · 标题 = 文件名去扩展名；标题改了 = 下次保存要问"存哪儿"（= 另存为语义）。
//
// ★ **排版设置不写进文档**：(页边距/字号) 跟 App 走（《界面与布局》§6 的口径 + 2026-10-17 拍板 A）。
//   md 必须保持"别的编辑器也能打开"的干净文本。

/// 文档的**身份**：显示名 + 磁盘路径
///
/// ★ 「有没有未保存改动」**不放在这里** —— 外壳用**正文快照**判（`buf.buf != savedText`）：
///   打开另一个文件后编辑计数器不会归零，"次数比对"会一直显示脏；而"改完又改回去"本来就该算干净。
class DocumentFile {
  const DocumentFile({
    this.title = kUntitled,
    this.path,
  });

  static const String kUntitled = '未命名文档';

  /// 显示名（不含扩展名）；`null` 路径时它是用户随手改的名字
  final String title;

  /// 磁盘上的绝对路径（Windows/Android）；`null` = 还没落到文件
  final String? path;

  bool get hasFile => path != null && path!.isNotEmpty;

  /// 扩展名（小写，不含点）；没有则空串
  String get extension => extensionOf(path ?? '');

  DocumentFile copyWith({
    String? title,
    String? path,
    bool clearPath = false,
  }) =>
      DocumentFile(
        title: title ?? this.title,
        path: clearPath ? null : (path ?? this.path),
      );

  /// 从路径推标题：`作业辅导1.md` ⇒ `作业辅导1`；没有扩展名就整串
  static String titleFromPath(String path) {
    final String name = fileNameOf(path);
    final int dot = name.lastIndexOf('.');
    final String stem = dot > 0 ? name.substring(0, dot) : name;
    return stem.trim().isEmpty ? kUntitled : stem.trim();
  }

  /// 路径里的文件名（兼容 `/` 与 `\`）
  static String fileNameOf(String path) {
    final int a = path.lastIndexOf('/');
    final int b = path.lastIndexOf(r'\');
    final int cut = a > b ? a : b;
    return cut >= 0 ? path.substring(cut + 1) : path;
  }

  /// 扩展名（小写，不含点）
  static String extensionOf(String path) {
    final String name = fileNameOf(path);
    final int dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
  }

  /// 保存/另存为时该用的文件名：`标题.md`（标题里已经带 `.md` 就不重复加）
  String suggestedFileName({String ext = 'md'}) {
    final String t = title.trim().isEmpty ? kUntitled : title.trim();
    return t.toLowerCase().endsWith('.$ext') ? t : '$t.$ext';
  }

  @override
  String toString() => 'DocumentFile($title, path=$path)';

  @override
  bool operator ==(Object other) =>
      other is DocumentFile && other.title == title && other.path == path;

  @override
  int get hashCode => Object.hash(title, path);
}

/// 一次"保存到哪里"的结果（文件对话框可能被取消）
class SaveOutcome {
  const SaveOutcome({this.path, this.cancelled = false});

  const SaveOutcome.cancelled() : this(cancelled: true);

  final String? path;
  final bool cancelled;

  bool get ok => !cancelled && path != null;
}
