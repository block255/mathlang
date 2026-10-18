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
import 'file_gateway.dart';
import 'text_codec.dart';

FileGateway createFileGateway() => NativeFileGateway();

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
    );
    if (r == null || r.files.isEmpty) return null; // 取消
    final PlatformFile f = r.files.single;
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
      bytes: bytes,
    );
    if (out == null || out.isEmpty) return const SaveOutcome.cancelled();
    return SaveOutcome(path: out);
  }
}
