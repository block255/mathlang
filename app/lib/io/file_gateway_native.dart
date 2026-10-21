// 数语引擎 · **桌面 / 移动端的文件后端**（S4-d-①，用 `dart:io` + `file_picker`）
//
// 两条路：
//   · 有 `path` ⇒ 直接 `File(path).writeAsString`（Ctrl+S 不弹框）；
//   · 没 `path` ⇒ `FilePicker.saveFile` 让用户自己挑位置（"可以让用户自己选"，2026-10-17 拍板）。
// 打开走 `FilePicker.pickFiles(withData: true)`：桌面/安卓都能拿到字节，**不依赖 web**。
//
// ★ 编码一律交给 `text_codec`（UTF-8 严格 → 容错；写出 UTF-8 无 BOM + LF）。

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../core/document_file.dart';
import 'dir_memory.dart';
import 'file_gateway.dart';
import 'text_codec.dart';

FileGateway createFileGateway() => NativeFileGateway();

/// 对话框的初始目录（`null` = 交回系统默认）。
///
/// ★ F19（2026-10-21，用户实测）：以前**一个都不传** ⇒ Windows 用进程当前目录
/// （= exe 所在目录）当地点，用户每次都要从头找。现在统一走 [DirMemory]。
String? _initialDir() {
  final String d = DirMemory.initialDirectory();
  return d.isEmpty ? null : d;
}

class NativeFileGateway implements FileGateway {
  const NativeFileGateway();

  @override
  Future<OpenedFile?> openText({
    List<String> extensions = const <String>['md', 'txt', 'markdown'],
  }) async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
      withData: true,
      dialogTitle: '打开文档',
      initialDirectory: _initialDir(), // ★ F19
    );
    if (r == null || r.files.isEmpty) return null; // 取消
    final PlatformFile f = r.files.single;
    if (f.path != null) DirMemory.rememberFile(f.path!); // ★ F19：记住这次用的目录
    List<int>? bytes = f.bytes;
    // 极端情况：桌面某些实现不给 bytes ⇒ 退回按路径读
    if (bytes == null && f.path != null) {
      bytes = await File(f.path!).readAsBytes();
    }
    if (bytes == null) return null;
    final DecodedText d = decodeTextBytes(bytes);
    return OpenedFile(
      path: f.path ?? f.name,
      name: f.name,
      text: d.text,
      lossy: d.lossy,
      encoding: d.encoding,
    );
  }

  @override
  Future<SaveOutcome> saveText({
    required String text,
    String? path,
    String suggestedName = '未命名文档.md',
    String extension = 'md',
  }) async {
    final Uint8List bytes = encodeTextForExport(text);
    if (path != null && path.isNotEmpty) {
      // ★ 已有文件 ⇒ 直接写回（不动用户选好的位置）
      await File(path).writeAsBytes(bytes, flush: true);
      return SaveOutcome(path: path);
    }
    final String? out = await FilePicker.platform.saveFile(
      dialogTitle: '保存文档',
      fileName: suggestedName,
      type: FileType.custom,
      allowedExtensions: <String>[extension],
      initialDirectory: _initialDir(), // ★ F19
      bytes: bytes,
    );
    if (out == null || out.isEmpty) return const SaveOutcome.cancelled();
    DirMemory.rememberFile(out); // ★ F19
    return SaveOutcome(path: out);
  }

  @override
  Future<SaveOutcome> saveBytes({
    required List<int> bytes,
    String? path,
    String suggestedName = '未命名文档.pdf',
    String extension = 'pdf',
  }) async {
    final Uint8List data = Uint8List.fromList(bytes);
    if (path != null && path.isNotEmpty) {
      await File(path).writeAsBytes(data, flush: true);
      return SaveOutcome(path: path);
    }
    final String? out = await FilePicker.platform.saveFile(
      dialogTitle: '导出 PDF',
      fileName: suggestedName,
      type: FileType.custom,
      allowedExtensions: <String>[extension],
      initialDirectory: _initialDir(), // ★ F19
      bytes: data,
    );
    if (out == null || out.isEmpty) return const SaveOutcome.cancelled();
    DirMemory.rememberFile(out); // ★ F19
    return SaveOutcome(path: out);
  }

  @override
  Future<ExportBatch?> saveBatch({
    required List<ExportFile> files,
    String? directory,
    String dialogTitle = '选择保存位置',
  }) async {
    var dir = directory;
    if (dir == null || dir.isEmpty) {
      dir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: dialogTitle,
        initialDirectory: _initialDir(), // ★ F19
      );
    }
    if (dir == null || dir.isEmpty) return null; // 取消
    DirMemory.rememberDirectory(dir); // ★ F19
    final List<String> written = <String>[];
    for (final ExportFile f in files) {
      final String p = '$dir${Platform.pathSeparator}${f.name}';
      await File(p).writeAsBytes(Uint8List.fromList(f.bytes), flush: true);
      written.add(p);
    }
    return ExportBatch(directory: dir, paths: written);
  }
}
