// 「表」批测试共用的小工具：按**单元格内容**定位偏移。
//
// 为什么不能直接 `doc.indexOf('a')`：`\begin{pmatrix}` 里就有 `a`（pm**a**trix），
// 一开始我这么写过，量出来的是环境名里的字母，白红了一场。

import 'package:flutter_test/flutter_test.dart';

/// 找单元格内容 [name] 的第一个字符的偏移（`}a` / `&a` / `\\a` 三种前缀都试）。
int cellPos(String doc, String name) {
  for (final String lead in <String>['}', '&', r'\\']) {
    final int i = doc.indexOf('$lead$name');
    if (i >= 0) return i + lead.length;
  }
  fail('找不到格「$name」');
}
