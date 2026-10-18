// ★★ S4-d③：**图片式 PDF + md 附件**的守卫（《S4》§D）
//
// 判据（全部在字节层面看，不依赖阅读器）：
//   ① 是合法 PDF（`%PDF-` 头 + `%%EOF` 尾）；
//   ② 每页一张图 ⇒ 页数 = 图片张数；
//   ③ **`.md` 真的内嵌进去了**（`/EmbeddedFiles` + `/Filespec`），而且能**读回来**
//      —— 这条就是"自产 PDF 能无损导回"的全部承诺；
//   ④ 页数与图片张数一致、且随张数变化（不是写死 1 页）。
//
// ★ 测试用的 PNG 由**引擎自己**画出来（`dart:ui`），不手写 base64 ——
//   手写字节一旦不被 `image` 包接受，报的是 "Unable to decode image"，排查成本高。

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/io/pdf_builder.dart';

/// 画一张 [w]×[h] 的白图并编码成 PNG
Future<Uint8List> _png([int w = 4, int h = 6]) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  final ui.Image image = await recorder.endRecording().toImage(w, h);
  try {
    final ByteData? bd = await image.toByteData(format: ui.ImageByteFormat.png);
    return bd!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

String _ascii(Uint8List b) => String.fromCharCodes(b);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const String md = '# 例 1\n\n设 \$x^2+1\$ 是式子。\n';

  test('★ 两张图 ⇒ 两页 PDF，头尾合法', () async {
    final Uint8List px = await _png();
    final PdfExportResult r = await buildImagePdf(
      pagePngs: <Uint8List>[px, px],
      markdown: md,
      title: '作业',
      compress: false,
    );
    expect(r.pageCount, 2);
    final String raw = _ascii(r.bytes);
    expect(raw.startsWith('%PDF-'), isTrue, reason: '没有 PDF 头');
    expect(raw.trimRight().endsWith('%%EOF'), isTrue, reason: '没有 EOF 尾');
    expect(RegExp(r'/Count\s+2').hasMatch(raw), isTrue,
        reason: '页数不是 2（找不到 /Count 2）');
  });

  test('★ md 内嵌成附件：`/EmbeddedFiles` + `/Filespec` 都在', () async {
    final PdfExportResult r = await buildImagePdf(
      pagePngs: <Uint8List>[await _png()],
      markdown: md,
      title: '作业',
      compress: false,
    );
    final String raw = _ascii(r.bytes);
    expect(raw.contains('/EmbeddedFiles'), isTrue);
    expect(raw.contains('/Filespec'), isTrue);
    expect(raw.contains('/EmbeddedFile'), isTrue);
    // ★ 名字树键只能是 ASCII（pdf 包的限制）⇒ 中文标题退化成 mathlang.md
    expect(r.attachmentName, 'mathlang.md');
  });

  test('ASCII 标题 ⇒ 附件名 = 标题.md', () async {
    final PdfExportResult r = await buildImagePdf(
      pagePngs: <Uint8List>[await _png()],
      markdown: md,
      title: 'homework1',
      compress: false,
    );
    expect(r.attachmentName, 'homework1.md');
  });

  test('★★ 往返：附件正文能读回来，且与原文逐字符相同', () async {
    final PdfExportResult r = await buildImagePdf(
      pagePngs: <Uint8List>[await _png()],
      markdown: md,
      title: '作业',
      compress: false,
    );
    final String? back = readEmbeddedMarkdown(r.bytes);
    expect(back, isNotNull, reason: '读不出附件 ⇒ "自产 PDF 能无损导回"这句就是假的');
    expect(back, md);
  });

  test('附件字节数 = md 的 UTF-8 长度（不是 UTF-16 码元数）', () async {
    final PdfExportResult r = await buildImagePdf(
      pagePngs: <Uint8List>[await _png()],
      markdown: md,
      title: '作业',
      compress: false,
    );
    expect(r.attachmentBytes, utf8.encode(md).length);
    expect(r.attachmentBytes, isNot(md.length), reason: '中文的字节数 ≠ 字符数');
  });

  test('页数跟着图片张数走（3 张 ⇒ 3 页）', () async {
    final Uint8List px = await _png();
    final PdfExportResult r = await buildImagePdf(
      pagePngs: <Uint8List>[px, px, px],
      markdown: md,
      title: 'x',
      compress: false,
    );
    expect(r.pageCount, 3);
    expect(RegExp(r'/Count\s+3').hasMatch(_ascii(r.bytes)), isTrue);
  });

  test('空文档也能导出（0 张图 ⇒ 0 页，不抛）', () async {
    final PdfExportResult r = await buildImagePdf(
      pagePngs: const <Uint8List>[],
      markdown: '',
      title: '空',
      compress: false,
    );
    expect(r.pageCount, 0);
    expect(_ascii(r.bytes).startsWith('%PDF-'), isTrue);
  });
}
