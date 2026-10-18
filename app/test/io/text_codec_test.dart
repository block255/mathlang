// 数语引擎 · 导入/导出的字节编解码（`io/text_codec.dart`）守卫
//
// 为什么这条重要：导入的文件**可能是别人给的**（Windows 记事本存的 UTF-8 BOM、
// 老程序存的 UTF-16、甚至 GBK）。这里守三件事：
//   ① BOM 认得出；② UTF-8 严格优先、失败才容错**并如实报告**；③ 写出去永远是 UTF-8 无 BOM + LF。

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/io/text_codec.dart';


void main() {
  test('纯 UTF-8：原样读回，不报 lossy', () {
    final DecodedText d = decodeTextBytes(utf8.encode(r'甲乙 $x^2$ 丙'));
    expect(d.text, '甲乙 \$x^2\$ 丙');
    expect(d.lossy, isFalse);
    expect(d.encoding, 'utf-8');
  });

  test('UTF-8 BOM：要去掉 BOM，且标出来源', () {
    final DecodedText d = decodeTextBytes(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode('a')]);
    expect(d.text, 'a');
    expect(d.encoding, contains('bom'));
  });

  test('UTF-16 LE / BE（带 BOM）：都能解', () {
    // "甲" = U+7532
    final DecodedText le = decodeTextBytes(<int>[0xFF, 0xFE, 0x32, 0x75]);
    expect(le.text, '甲');
    expect(le.encoding, 'utf-16le');
    final DecodedText be = decodeTextBytes(<int>[0xFE, 0xFF, 0x75, 0x32]);
    expect(be.text, '甲');
    expect(be.encoding, 'utf-16be');
  });

  test('★ 不是 UTF-8（例如 GBK 的"甲"）：容错读入 + 如实报 lossy', () {
    // "甲" 的 GBK 编码是 0xBC 0xD7
    final DecodedText d = decodeTextBytes(<int>[0xBC, 0xD7]);
    expect(d.lossy, isTrue, reason: '★ 不许悄悄吞掉编码错误（原则 5：可疑要可见）');
    expect(d.text.isNotEmpty, isTrue, reason: '内容不丢结构（替换成 U+FFFD）');
  });

  test('写出：UTF-8 无 BOM + LF（CRLF/CR 统一）', () {
    final Uint8List out = encodeTextForExport('a\r\nb\rc\nd');
    expect(utf8.decode(out), 'a\nb\nc\nd');
    expect(out[0], isNot(0xEF), reason: '不写 BOM');
  });

  test('往返：导出再导入 = 逐字节一致的文本（S4-d 的验收线）', () {
    const String src = '# 例 1\n\n设 \$x^2+1\$ 为多项式。\n\n\$\$\ny = 2\n\$\$\n';
    final Uint8List bytes = encodeTextForExport(src);
    final DecodedText back = decodeTextBytes(bytes);
    expect(back.text, src);
    expect(back.lossy, isFalse);
  });
}
