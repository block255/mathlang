// 数语引擎 · **文本字节 ↔ 字符串**（S4-d-①，纯 Dart）
//
// 为什么单独一个文件：导入的 `.md` / `.txt` 可能是**别人给的**，
// 编码不一定是我们写出去的 UTF-8。这里只做三件事：
//   ① 认 BOM（UTF-8 / UTF-16 LE / BE）；
//   ② 没有 BOM 先按 UTF-8 **严格**解；失败再**容错**解（并如实报 `lossy`）；
//   ③ 写出去永远是 **UTF-8 无 BOM + LF**（跨平台一致，diff 干净）。
//
// ★ "容错读了"必须能被界面说出来（原则 5：可疑要可见）——所以返回 [DecodedText.lossy]，
//   不在这里悄悄吞掉错误。

import 'dart:convert';
import 'dart:typed_data';

class DecodedText {
  const DecodedText(this.text, {this.lossy = false, this.encoding = 'utf-8'});

  final String text;

  /// 有字节解不出来（按容错模式替换成 U+FFFD）⇒ 界面要提示
  final bool lossy;
  final String encoding;

  @override
  String toString() => 'DecodedText(${text.length} 字符, $encoding, lossy=$lossy)';
}

/// 导出时统一的行尾（Windows 上的记事本也能正常看）
const String kExportLineEnding = '\n';

DecodedText decodeTextBytes(List<int> bytes) {
  final Uint8List b =
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  if (b.isEmpty) return const DecodedText('');

  // ① BOM
  if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
    return DecodedText(const Utf8Decoder().convert(b.sublist(3)),
        encoding: 'utf-8(bom)');
  }
  if (b.length >= 2 && b[0] == 0xFF && b[1] == 0xFE) {
    return DecodedText(_decodeUtf16(b.sublist(2), littleEndian: true),
        encoding: 'utf-16le');
  }
  if (b.length >= 2 && b[0] == 0xFE && b[1] == 0xFF) {
    return DecodedText(_decodeUtf16(b.sublist(2), littleEndian: false),
        encoding: 'utf-16be');
  }

  // ② UTF-8 严格
  try {
    return DecodedText(const Utf8Decoder().convert(b));
  } on FormatException {
    // ③ 容错（GBK 之类会落在这里；我们不解码它，只保证"不崩、不丢结构"）
    return DecodedText(
      const Utf8Decoder(allowMalformed: true).convert(b),
      lossy: true,
      encoding: 'utf-8(容错)',
    );
  }
}

/// 写出去：UTF-8 无 BOM；行尾统一成 [kExportLineEnding]
Uint8List encodeTextForExport(String text) {
  final String normalized = text
      .replaceAll('\r\n', kExportLineEnding)
      .replaceAll('\r', kExportLineEnding);
  return const Utf8Encoder().convert(normalized);
}

/// UTF-16（带 BOM 的老文件）手动解：dart:convert 没有 Utf16Decoder
String _decodeUtf16(Uint8List src, {required bool littleEndian}) {
  final Uint8List b = _evenBytes(src);
  final List<int> units = List<int>.generate(b.length ~/ 2, (int i) {
    final int x = b[i * 2], y = b[i * 2 + 1];
    return littleEndian ? (y << 8) | x : (x << 8) | y;
  });
  return String.fromCharCodes(units);
}

/// UTF-16 的字节要成对（奇数长度时丢掉最后那个坏字节，不抛）
Uint8List _evenBytes(Uint8List src) =>
    src.length.isEven ? src : src.sublist(0, src.length - 1);
