// 数语引擎 · **Web 的文件后端**（S4-d-①，只在开发/预览用；正式端是 Windows/Android）
//
// ★ 这里**不许**出现 `dart:io`（web 编译会直接失败）：
//   打开 = `<input type=file>`（file_picker 的 web 实现），保存 = 触发浏览器下载。

import 'package:file_picker/file_picker.dart';

import '../core/document_file.dart';
import 'file_gateway.dart';
import 'text_codec.dart';

FileGateway createFileGateway() => WebFileGateway();

class WebFileGateway implements FileGateway {
  const WebFileGateway();

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
    if (r == null || r.files.isEmpty) return null;
    final PlatformFile f = r.files.single;
    final List<int> bytes = f.bytes ?? const <int>[];
    final DecodedText d = decodeTextBytes(bytes);
    return OpenedFile(
      // web 上没有可写回的路径 ⇒ 用文件名占位（每次保存都会再下载一次）
      path: f.name,
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
    // web 的 saveFile 是"下载"，没有"写回某个路径"的概念 ⇒ 每次都下载
    final String? out = await FilePicker.platform.saveFile(
      dialogTitle: '下载文档',
      fileName: suggestedName,
      type: FileType.custom,
      allowedExtensions: <String>[extension],
      bytes: encodeTextForExport(text),
    );
    if (out == null) return const SaveOutcome.cancelled();
    return SaveOutcome(path: out);
  }
}
