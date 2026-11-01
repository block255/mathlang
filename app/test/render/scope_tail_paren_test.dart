// ★★ 2026-10-24（批 5 · H5）：**作用域不许吞掉用户手写的收尾括号**
//
// 用户实测（`\sum_{i=1}^{n}(x+1)`）：「我想点括号后面删括号，但是**只能点到整体的后面**」
// 探针坐实（2026-10-24，改前）：
//   `off=19  \sum_{i=1}^{n}(x+1)⟨⟩  scopeEnding=[0,19)  backspace=删「\sum_{i=1}^{n}(x+1)」`
// ⇒ 退格一次把整条式子删光，用户拿不到那个 `)`。
//
// 口径（平权 ③「不许实现细节泄漏成地位差异」）：**作用域是派生的**，
// 不许让它改变"删左边最近的墨迹"这条通用规则；收尾是手写括号时按通用规则删那一个字符。
//
// ★ 2026-11-01（反馈 3 · 口径 §3.1–3.2）：**「作用域整块删」整档取消** ——
//   本条 H5 的重心从此变成"结构性成立"（没有作用域可用，通用规则自然删那一个 `）`）；
//   `\sin 2x` / `\sum…a_i` 末尾退格现在都**逐对象**删。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/smart_delete.dart';

String? deletedText(String tex, int rel) {
  final SmartEdit e = smartBackspace(buildCaretSites(tex), rel);
  if (!e.deletes) return null;
  return tex.substring(e.from!, e.to!);
}

void main() {
  const String sumParen = r'\sum_{i=1}^{n}(x+1)';

  test(r'★★ H5：`\sum_{i=1}^{n}(x+1)` 末尾退格 ⇒ 只删那个 `)`', () {
    expect(deletedText(sumParen, sumParen.length), ')',
        reason: '改前删的是整条 `$sumParen`（作用域吃掉了括号）');
  });

  test(r'H5 续：再退一格删 `1`（照"左边最近的墨迹"走）', () {
    expect(deletedText(sumParen, sumParen.length - 1), '1');
  });

  test(r'H5 续：括号**里面**退格一点没变（`(` 之后删 `(`… ）', () {
    // off=15 是 `(` 之后、`x` 之前 ⇒ 左边最近的墨迹 = `(`
    expect(deletedText(sumParen, 15), '(');
    expect(deletedText(sumParen, 16), 'x');
  });

  test(r'★ 对照（2026-11-01 口径）：`\sin 2x` 末尾退格 ⇒ **只删 `x`**', () {
    const String tex = r'\sin 2x';
    expect(deletedText(tex, tex.length), 'x');
  });

  test(r'★ 对照（批 10 收窄）：`\sum_{i=1}^{n}a_i` 末尾退格 ⇒ **只删挂件 `_i`**（大算符不再整块删）', () {
    const String tex = r'\sum_{i=1}^{n}a_i';
    // 乙口径：字形 + 挂件 = 一个对象 ⇒ 先删挂件 `_i`（留着 `a`）
    expect(deletedText(tex, tex.length), '_i');
  });

  test(r'★ 对照：`\sum_{i=1}^{n}(x+1)` 的**中段**（`)` 之前）照旧逐字删', () {
    expect(deletedText(sumParen, 18), '1');
    expect(deletedText(sumParen, 17), '+');
  });
}
