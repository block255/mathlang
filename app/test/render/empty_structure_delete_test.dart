// ★★ 2026-10-24（批 4c · D1）：**空结构上退格 ⇒ 整块回收**
//
// 用户口径（D1 的原话）：「当有了个下标框，还删不掉；要么删掉当字，但是重新打一个字下标框又会回来」
// 以及 2026-10-18 那条「删空留壳」的**补集**：
//   · 槽里**有内容**、你把内容删掉 ⇒ 空壳留着（提醒你填）—— 既有口径，不动；
//   · 槽里**本来就没东西** ⇒ 退格该去掉的是**这个结构本身**。
//
// 改前实测（打点）：空结构上退格会去啃**语法字符**（`{` `}` `\left`）⇒ 直接弄坏 tex
//   ⇒ 页面 `[公式不完整]`，用户"删不掉"的体感就是这么来的。
//
// 本文件钉三件：
//   ① 空挂件 `x_{}` / `x^{}` ⇒ 删挂件本身（基座留下）
//   ② 空定界符对 `\left|{}\right|` ⇒ 整对删
//   ③ **有内容**的结构一个字节都不许被这条规则带走（照旧"删内容、留空壳"）

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/math_nav.dart';
import 'package:mathlang/render/smart_delete.dart';

/// 在文档里退格一次（与真实按键同一条路径）
String _back(String tex, int texOffset) {
  final String doc = '\$\$\n$tex\n\$\$';
  final SmartEdit e = smartEditAt(doc, 3 + texOffset, forward: false);
  return e.deletes ? doc.replaceRange(e.from!, e.to!, '') : doc;
}

/// 这条 tex 的花括号/`\left`-`\right` 是否仍然配平（防"删语法字符"）
bool _balanced(String t) {
  var depth = 0;
  for (var i = 0; i < t.length; i++) {
    if (t[i] == r'\') {
      i++;
      continue;
    }
    if (t[i] == '{') depth++;
    if (t[i] == '}') depth--;
    if (depth < 0) return false;
  }
  if (depth != 0) return false;
  var left = 0;
  var right = 0;
  for (var i = 0; i + 4 < t.length; i++) {
    if (t.startsWith(r'\left', i)) left++;
    if (t.startsWith(r'\right', i)) right++;
  }
  return left == right;
}

void main() {
  group('① 空挂件：删挂件本身，基座留下', () {
    test(r'$x_{}$ 在 `}` 后退格 ⇒ `$x$`', () {
      // `x`0 `_`1 `{`2 `}`3 ⇒ 光标 4
      expect(_back(r'x_{}', 4), '\$\$\nx\n\$\$');
    });

    test(r'$x^{}$ 在组内退格 ⇒ `$x$`', () {
      expect(_back(r'x^{}', 3), '\$\$\nx\n\$\$');
    });

    test('带空格的 `x_{ }` 也算空', () {
      expect(_back(r'x_{ }', 5), '\$\$\nx\n\$\$');
    });
  });

  group('② 空定界符对：整对删', () {
    test(r'$\left|{}\right|$ 中间退格 ⇒ 整对没了（段落跟着回收）', () {
      final String got = _back(r'\left|{}\right|', 8);
      expect(got.contains(r'\left'), isFalse, reason: '整对都要走：$got');
      expect(got.contains('|'), isFalse, reason: got);
    });
  });

  group('③ 有内容的结构：一个字节都不许被带走', () {
    test(r'★ `x_{2}` 在内容后退格 ⇒ 只删内容、留合法空壳（§4.1.1 既有口径）', () {
      final String got = _back(r'x_{2}', 5); // 光标在 `2` 之后
      expect(got, '\$\$\nx_{}\n\$\$',
          reason: '花括号形式留 `x_{}` 是刻意的（原地好重打）：$got');
    });

    test(r'★ `x_2`（裸参数）在内容后退格 ⇒ 连 `_2` 一起删', () {
      final String got = _back(r'x_2', 3); // 光标在 `2` 之后
      expect(got, '\$\$\nx\n\$\$',
          reason: '裸参数必须连 `_` 一起删，否则 b^ 这种会报 Parser Error：$got');
    });

    test(r'$\left|{sinx}\right|$ 里退格 ⇒ 只少一个字母', () {
      final String got = _back(r'\left|{sinx}\right|', 11); // `x` 之后
      expect(got, '\$\$\n' + r'\left|{sin}\right|' + '\n\$\$', reason: got);
    });

    test('全域扫：这一批所有用例退格之后都配平（不产生坏 tex）', () {
      const List<String> corpus = <String>[
        r'x_{}', r'x^{}', r'x_{ }', r'\left|{}\right|',
        r'x_{2}', r'\left|{sinx}\right|', r'\frac{x^{3}}{\left|{sinx}\right|}',
        r'\left|{x}\right|', r'\frac{}{}', r'x_2',
      ];
      for (final String tex in corpus) {
        for (var off = 0; off <= tex.length; off++) {
          final String got = _back(tex, off);
          // 只看数学段里的内容是否配平
          final int a = got.indexOf(r'$$') + 3;
          final int b = got.lastIndexOf(r'$$');
          final String inner = (a >= 3 && b >= a) ? got.substring(a, b) : got;
          expect(_balanced(inner), isTrue,
              reason: '`$tex` @$off 退格后不配平 ⇒ `$inner`');
        }
      }
    });
  });
}
