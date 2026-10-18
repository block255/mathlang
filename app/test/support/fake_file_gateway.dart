// 测试用：**假文件后端**（不弹系统对话框、不碰磁盘）
//
// 用来守"按钮 → 后端 → 缓冲区/标题/dirty"这条链；真实的文件对话框由人工验收。

import 'package:mathlang/core/document_file.dart';
import 'package:mathlang/io/file_gateway.dart';

class FakeFileGateway implements FileGateway {
  FakeFileGateway({
    this.toOpen,
    this.savePath,
    this.cancelSave = false,
    this.throwOnOpen,
    this.throwOnSave,
  });

  /// 让 open / save **抛异常**（用来守"错误必须可见"）
  final Object? throwOnOpen;
  final Object? throwOnSave;

  /// `openText()` 要返回的内容（null = 用户取消）
  OpenedFile? toOpen;

  /// `saveText()` 返回的路径（null 且不取消 = 用 suggestedName 造一个）
  String? savePath;

  /// 用户点了"取消"
  bool cancelSave;

  /// 每次 saveText 的记录：(path, text)
  final List<({String? path, String text})> saves =
      <({String? path, String text})>[];

  /// ★ S4-d③：saveBytes / saveBatch 的记录（导出 PDF 与图片集走这两条）
  final List<({String? path, int length, String suggestedName})> savesBytes =
      <({String? path, int length, String suggestedName})>[];

  /// 真正写下去的二进制内容（按调用顺序；守"PDF 头是不是 %PDF"要用）
  final List<List<int>> savedPayloads = <List<int>>[];

  final List<ExportBatch> batches = <ExportBatch>[];

  /// saveBatch 的"用户取消"
  bool cancelBatch = false;

  /// saveBatch 落盘的目录（默认造一个）
  String batchDirectory = r'C:\out';

  int opens = 0;

  @override
  Future<OpenedFile?> openText({
    List<String> extensions = const <String>['md', 'txt', 'markdown'],
  }) async {
    opens++;
    if (throwOnOpen != null) throw throwOnOpen!;
    return toOpen;
  }

  @override
  Future<SaveOutcome> saveText({
    required String text,
    String? path,
    String suggestedName = '未命名文档.md',
    String extension = 'md',
  }) async {
    saves.add((path: path, text: text));
    if (throwOnSave != null) throw throwOnSave!;
    if (cancelSave) return const SaveOutcome.cancelled();
    final String out = path ?? savePath ?? r'C:\docs\' + suggestedName;
    return SaveOutcome(path: out);
  }

  @override
  Future<SaveOutcome> saveBytes({
    required List<int> bytes,
    String? path,
    String suggestedName = '未命名文档.pdf',
    String extension = 'pdf',
  }) async {
    savesBytes
        .add((path: path, length: bytes.length, suggestedName: suggestedName));
    if (throwOnSave != null) throw throwOnSave!;
    if (cancelSave) return const SaveOutcome.cancelled();
    // ★ 用户取消 ⇒ **什么都没写下去**（所以 payload 只在真写时记）
    savedPayloads.add(bytes);
    final String out = path ?? savePath ?? r'C:\docs\' + suggestedName;
    return SaveOutcome(path: out);
  }

  @override
  Future<ExportBatch?> saveBatch({
    required List<ExportFile> files,
    String? directory,
    String dialogTitle = '选择保存位置',
  }) async {
    if (cancelBatch) return null;
    final String dir = directory ?? batchDirectory;
    final ExportBatch b = ExportBatch(
      directory: dir,
      paths: <String>[for (final ExportFile f in files) '$dir\\${f.name}'],
    );
    batches.add(b);
    return b;
  }
}
