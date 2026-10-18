// 数语引擎 · **图片式 PDF + md 附件**（S4-d③）
//
// 规格：《S4-语言层与输入层.md》§D：
//   · PDF = **每页 PNG 装进 PDF**（视觉 1:1，所见即所得）；
//   · 同时把 `.md` 全文当 **PDF 内嵌附件**（embedded file）⇒ "自产 PDF 能无损导回"；
//     附件是**独立数据流、不画在页面上**（渲染零影响），zlib 之后大小是噪声级。
//
// ★ 为什么不做"矢量/文本式 PDF"：我们的数学是引擎画出来的，用矢量 PDF 库**重建**这套排版
//   （数学字体 / 间距 / 断行）是另一个大工程 —— 已明确排到 S5（那时目标是"文字可选可搜"）。
//
// ★ 依赖只用了 `pdf` 包的公开 API：`PdfaAttachedFiles` / `PdfaAttachedFile` 是它自带的
//   PDF/A 附件实现（2026-10-18 在 pub 缓存里核对过源码：它会把 `/EmbeddedFiles`
//   挂进文档 catalog 的 name tree，并且**自己**建好 `/Names`）。
//
// **纯 Dart**（不 import Flutter）⇒ 可以在 `flutter test` 里直接断言字节。

import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// 一次 PDF 构建的结果（诊断 / 守卫用）
class PdfExportResult {
  const PdfExportResult({
    required this.bytes,
    required this.pageCount,
    required this.attachmentName,
    required this.attachmentBytes,
  });

  final Uint8List bytes;

  /// 装进去的页数（= 图片张数）
  final int pageCount;

  /// 附件文件名（`文档名.md`）
  final String attachmentName;

  /// 附件内容长度（= md 的 UTF-8 字节数）
  final int attachmentBytes;

  int get size => bytes.length;

  @override
  String toString() => 'PdfExport($pageCount 页, ${(size / 1024).toStringAsFixed(0)} KB, '
      '附件 $attachmentName ${(attachmentBytes / 1024).toStringAsFixed(1)} KB)';
}

/// 把每页 PNG 装成 A4 的图片式 PDF，并把 [markdown] 作为附件内嵌。
///
/// [title] 只用于元数据与附件名（不画在页面上 —— 页眉是页面自己带的）。
/// [compress] 只在测试里关掉（关掉后 `/EmbeddedFiles`、`/Count` 这些字典串在字节里可直接搜到）。
Future<PdfExportResult> buildImagePdf({
  required List<Uint8List> pagePngs,
  required String markdown,
  required String title,
  bool compress = true,
}) async {
  final pw.Document doc = pw.Document(
    compress: compress,
    title: title,
    author: '数语引擎',
    creator: '数语引擎 · mathlang',
    subject: '由 mathlang 导出的图片式 PDF；原始 Markdown 见附件 $title.md',
  );

  for (final Uint8List png in pagePngs) {
    final pw.MemoryImage img = pw.MemoryImage(png);
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (pw.Context c) => pw.Center(
          // contain：我们的页是 793.7×1123 px ≈ A4（差 0.04%），contain 最多留一根发丝边
          child: pw.Image(img, fit: pw.BoxFit.contain),
        ),
      ),
    );
  }

  // ★ 附件：`md` 全文（导出/导入往返靠它）。子类型按 IANA 的 text/markdown。
  //
  // ⚠️ 实测（2026-10-18）：`pdf` 包写 `/EmbeddedFiles` 的**名字树键**时用的是
  //   未转义的 `(...)` 字符串，**非 ASCII 会断言失败**（`PdfStream.putString` 只收 0x00–0x7F）。
  //   ⇒ 附件名取"ASCII 安全"的形式（中文标题退化成 `mathlang.md`）；
  //   中文标题仍然完整保留在**元数据**里（那份走 `PdfString.fromString`，支持 UTF-16）。
  final String attachmentName = pdfAttachmentName(title);
  final List<int> mdBytes = _utf8(markdown);
  PdfaAttachedFiles(doc.document, <PdfaAttachedFile>[
    PdfaAttachedFile(
      name: attachmentName,
      data: markdown,
      subType: '/text/markdown',
      afRelationship: '/Source',
    ),
  ]);

  final Uint8List bytes = await doc.save();
  return PdfExportResult(
    bytes: bytes,
    pageCount: pagePngs.length,
    attachmentName: attachmentName,
    attachmentBytes: mdBytes.length,
  );
}

/// PDF 附件名：**只保留 ASCII**（`pdf` 包的名字树键不支持非 ASCII，见 [buildImagePdf] 的注释）。
///
/// 中文标题 ⇒ `mathlang.md`（标题本身仍在 PDF 元数据里，不丢）。
String pdfAttachmentName(String title) {
  final String ascii =
      title.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
  final String base = ascii.isEmpty ? 'mathlang' : ascii;
  return '$base.md';
}

/// 手写 UTF-8 编码（纯粹为了不在这个文件里引入 `dart:convert` 之外的东西也有意义：
/// `attachmentBytes` 要报"真实的字节数"，而 `String.length` 是 UTF-16 码元数）。
List<int> _utf8(String s) {
  final List<int> out = <int>[];
  for (final int rune in s.runes) {
    if (rune < 0x80) {
      out.add(rune);
    } else if (rune < 0x800) {
      out
        ..add(0xC0 | (rune >> 6))
        ..add(0x80 | (rune & 0x3F));
    } else if (rune < 0x10000) {
      out
        ..add(0xE0 | (rune >> 12))
        ..add(0x80 | ((rune >> 6) & 0x3F))
        ..add(0x80 | (rune & 0x3F));
    } else {
      out
        ..add(0xF0 | (rune >> 18))
        ..add(0x80 | ((rune >> 12) & 0x3F))
        ..add(0x80 | ((rune >> 6) & 0x3F))
        ..add(0x80 | (rune & 0x3F));
    }
  }
  return out;
}

/// 从 PDF 字节里把附件正文读回来（**导入侧**用；读不到就返回 `null`）。
///
/// ★ 只认"我们自己写进去的那种"：`/EmbeddedFile` 数据流 + `/Subtype /text/markdown`。
///   别人的 PDF 走"抽文本 + 智能包裹"那条有损路（《S4》§D）。实现是**字节扫描**而不是完整
///   PDF 解析器（够用且零依赖；真正的解析器留给 S5 的文本式导入）。
///
/// ★ 数据流是**未压缩**写的（`pdf` 包的 `PdfDictStream(compress: false)`）⇒ 可以直接按
///   `stream` … `endstream` 取出来，再按 UTF-8 解码（**中文的字节 ≠ 字符**，不能按 charCodes 拼）。
String? readEmbeddedMarkdown(Uint8List bytes) {
  final String raw = String.fromCharCodes(bytes);
  final int tag = raw.indexOf('/EmbeddedFile');
  if (tag < 0) return null;
  final int s = raw.indexOf('stream', tag);
  if (s < 0) return null;
  var start = s + 'stream'.length;
  if (raw.startsWith('\r\n', start)) {
    start += 2;
  } else if (start < raw.length &&
      (raw[start] == '\n' || raw[start] == '\r')) {
    start += 1;
  }
  final int e = raw.indexOf('endstream', start);
  if (e < 0) return null;
  var end = e;
  // 数据流后面那个换行不属于内容
  if (end > start && raw[end - 1] == '\n') end--;
  if (end > start && raw[end - 1] == '\r') end--;
  if (end <= start) return null;
  return utf8.decode(bytes.sublist(start, end), allowMalformed: true);
}
