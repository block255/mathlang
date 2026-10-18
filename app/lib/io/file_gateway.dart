// 数语引擎 · **文件入口的抽象**（S4-d-①）
//
// 为什么抽象：① 测试要能注入**假文件系统**（不能真弹系统对话框）；
//   ② 平台要分叉（Windows/Android 用 `dart:io`，Web 只能用浏览器下载/选择器）。
//
// 语义（用户 2026-10-17 定的"普通文件编辑器"口径）：
//   · [openText] 打开磁盘文件；取消 ⇒ `null`；
//   · [saveText] 有 [path] 就**直接写回**（Ctrl+S 不该每次弹框）；
//     没有 [path] 就弹"另存为"让用户自己选位置；
//   · 取消 ⇒ [SaveOutcome.cancelled]，界面**什么都不该做**（不能把 dirty 清掉）。

import '../core/document_file.dart';

/// 打开的文件（含解码后的文本与"解码是否有损"的如实标记）
class OpenedFile {
  const OpenedFile({
    required this.path,
    required this.name,
    required this.text,
    this.lossy = false,
    this.encoding = 'utf-8',
  });

  final String path;
  final String name;
  final String text;

  /// 解码时有字节对不上 UTF-8（界面要提示"可能是别的编码"）
  final bool lossy;
  final String encoding;

  @override
  String toString() => 'OpenedFile($name, ${text.length} 字符, $encoding'
      '${lossy ? ', 容错' : ''})';
}

/// 可注入的文件后端
abstract class FileGateway {
  /// 打开一个文本文件；用户取消 ⇒ `null`
  Future<OpenedFile?> openText({
    List<String> extensions = const <String>['md', 'txt', 'markdown'],
  });

  /// 写文本。[path] 非空 ⇒ 直接写回；否则弹"另存为"
  Future<SaveOutcome> saveText({
    required String text,
    String? path,
    String suggestedName = '未命名文档.md',
    String extension = 'md',
  });

  /// ★★ S4-d③：写**二进制**（PDF）。语义与 [saveText] 相同。
  Future<SaveOutcome> saveBytes({
    required List<int> bytes,
    String? path,
    String suggestedName = '未命名文档.pdf',
    String extension = 'pdf',
  });

  /// ★★ S4-d③：**一批文件写进同一个目录**（图片集 = 每页一张 PNG）。
  ///
  /// [files] 的每一项 = 文件名 + 内容；[directory] 为空 ⇒ 弹"选文件夹"让用户挑。
  /// 用户取消 ⇒ `null`（界面什么都不该做）。
  Future<ExportBatch?> saveBatch({
    required List<ExportFile> files,
    String? directory,
    String dialogTitle = '选择保存位置',
  });
}

/// 一批导出里的一项
class ExportFile {
  const ExportFile({required this.name, required this.bytes});

  final String name;
  final List<int> bytes;

  @override
  String toString() => 'ExportFile($name, ${bytes.length} B)';
}

/// 一次批量导出的结果（目录 + 真正写下去的路径）
class ExportBatch {
  const ExportBatch({required this.directory, required this.paths});

  final String directory;
  final List<String> paths;

  int get count => paths.length;

  @override
  String toString() => 'ExportBatch($directory, ${paths.length} 个文件)';
}
