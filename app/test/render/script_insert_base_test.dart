// ★★ 2026-10-24（批 13）：**`\sqrt[…]` 的次数里不许插结构/脚本**
//
// 用户实测（`\left|{x+1+\sqrt[4]{x}}\right|\left|{x^{2}}\right|`）：
//   在根号里按 `Shift+6` 打指数 ⇒ **变成「公式不完整」**。
// 探针坐实：插入点若落在 `[4]` 里，会得到 `\sqrt[^{}4]{x}` ——
//   可选参数是"次数/尺寸"，里面出现**没有基座的** `^{}` 直接解析失败。
//
// 修法（`insert_guard._neutralInsert`）：结构类载荷（含 `^` `_` `\`）落在 `\sqrt[…]` 里
//   ⇒ **挪到 `]` 之后**（`\sqrt[4]{x}^{}`，合法：给整个根号加指数）。
//   ★ 里面的位点**保留**：点 `4` 改成 `3` 必须能原地改（只有结构类载荷才出槽）。
//
// ⏳ 同一族还剩一条没修（见台账 §14.7 批 13）：插入点被 `neutralPoint` **从基座后面
//   挪进脚本内部**时（`x^{|2}` 那种），仍会得到没有基座的 `x^{^{}2}`。
//   那条要在"落点"那一层问一次"挪完之后还有没有基座"，属于下一批。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/symbol_insert.dart';
import 'package:mathlang/render/caret_sites.dart';
import 'package:mathlang/render/math_nav.dart';

/// 逐个 `^` / `_` 检查：它前面必须是"能当基座的东西"。
String? noBaseReason(String tex) {
  for (var i = 0; i < tex.length; i++) {
    final String ch = tex[i];
    if (ch != '^' && ch != '_') continue;
    if (i == 0) return '串首就是 `$ch`（没有基座）';
    final String prev = tex[i - 1];
    if (prev == '{' || prev == '[') return '位置 $i 的 `$ch` 前面是 `$prev`（没有基座）';
  }
  return null;
}

String inserted(String tex, int rel, String payload) {
  final String doc = '\$$tex\$';
  final MathRegion r = mathRegionAt(doc, 1)!;
  final int caret = r.contentStart + rel;
  final SymbolInsertResult res = applySymbolInsert(
    doc: doc,
    caret: caret,
    selStart: caret,
    selEnd: caret,
    tex: payload,
    template: true,
  );
  return res.doc.substring(1, res.doc.length - 1);
}

void main() {
  const String tex = r'\left|{x+1+\sqrt[4]{x}}\right|\left|{x^{2}}\right|';

  test(r'★★ 根号的**次数**里插 `^{}` ⇒ 挪到 `]` 之后，tex 仍然合法', () {
    final CaretSiteTable t = buildCaretSites(tex);
    final SlotSpan slot =
        t.slots.firstWhere((SlotSpan s) => s.path.isNotEmpty && s.path.last.argIndex == -1);
    // 连 `[` `]` 一起测：`\sqrt` 与 `[` 之间（slot.start-1）、内容区、`]` 之前
    for (int rel = slot.start - 1; rel <= slot.end; rel++) {
      final String out = inserted(tex, rel, r'^{}');
      expect(noBaseReason(out), isNull, reason: 'rel=$rel ⇒ $out');
      expect(out, contains(r'\sqrt[4]{x}'),
          reason: '次数本身一个字符都不许被动：rel=$rel ⇒ $out');
    }
  });

  test(r'★ 对照：根号**内容**里插 `^{}` 仍然就地（`x^{}`），不出槽', () {
    final int xInSqrt = tex.indexOf(r'\sqrt[4]{x}') + r'\sqrt[4]{'.length;
    final String out = inserted(tex, xInSqrt + 1, r'^{}');
    expect(out, contains(r'\sqrt[4]{x^{}}'), reason: '内容里的位点不该被搬走：$out');
    expect(noBaseReason(out), isNull);
  });

  // ★★★ 2026-10-24（批 15 · 用户②）：**脚本内容末尾不许再嵌一层空脚本**
  //   用户实测：`\left|{x^{2}}\right|` 里在 `2` 之后按 Shift+6 ⇒ `x^{2^{}}` ⇒ 公式不完整。
  test(r'★★ 已有指数的内容末尾插 `^{}` ⇒ 挪到对象之后（`x^{2}^{}`），不许嵌套空脚本', () {
    const String t2 = r'\left|{x^{2}}\right|';
    // `2` 之后那一格 = `}` 之前
    final int afterTwo = t2.indexOf(r'x^{2}') + r'x^{'.length + 1;
    final String out = inserted(t2, afterTwo, r'^{}');
    expect(out, contains(r'x^{2}^{}'),
        reason: r'应当在对象层加指数（`x^{2}^{}`），不许得到 `x^{2^{}}`：$out');
    expect(out, isNot(contains(r'^{2^{')),
        reason: '脚本内容里不许再嵌一个空脚本：$out');
  });
}
