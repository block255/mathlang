// 批 40 · **光标归属的全域守卫**（先红后绿）；★★ 2026-11-01 收紧并扩语料。
//
// ## 不变量（2026-11-01 版，用户拍板后的口径）
//   ① 每个偏移**要么恰好一根光标**（它是某个视觉行的行首/行尾），
//      **要么**它是**段落分隔符**（两段之间那个零高度的空行）⇒ 那时**一根都不许有**；
//   ② 「恰好一根」是**计数**，不是"同一行" —— 旧版允许"同一像素叠两根"，
//      正是这条宽松让 F13（块边缘一根 + 空行行首一根）躲过了守卫。
//
// ## 这一版修掉的两个守卫缺陷（2026-11-01 复盘）
//   ① **语料里一份行间块都没有** ⇒ 块的那条分支从来没跑过（F13 就长在那儿）。
//      现在语料里有一半是 `$$…$$`：块前紧贴文字 / 块前空一行 / 两块紧贴 / 块在文首。
//   ② **只数 `Container(width:1.5)`** ⇒ 而**行间块的竖条是 `CustomPaint` 画的**
//      （`MathCaretPainter`），数不到。现在两种都数。
//
// ## 为什么命题是"恰好一根"而不是"至少一根"
//   2026-10-26 那版写的是「每个偏移**至少**有一根」，被 2026-10-28 推翻：
//   分隔符那一格在版面上**没有行盒**（高度 0），它不该有位置；
//   逼着渲染层给它编一个 y，就会变成用户说的"段间距能当一个容器行"。
//   ⇒ 命题必须是**有且只有一根 / 分隔符零根**。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/doc_buffer.dart';
import 'package:mathlang/core/doc_settings.dart';
import 'package:mathlang/core/paragraph_break.dart';
import 'package:mathlang/editor/doc_view.dart';
import 'package:mathlang/render/math_caret.dart';

Future<DocBuffer> _mount(WidgetTester tester, String doc) async {
  tester.view.physicalSize = const Size(900, 5200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final DocBuffer buf = DocBuffer(doc);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: DocView(buffer: buf, settings: DocSettings.defaults),
      ),
    ),
  ));
  for (var i = 0; i < 8; i++) {
    await tester.pump();
  }
  return buf;
}

/// 屏上**所有**竖条的位置：(left, top) ＋ 来源标签。
///
/// 两个来源都要数：
///   · 文本层 / 空行槽 / 末页槽：`Container(width:1.5)`；
///   · **行间块**：`MathCaretPainter`（`CustomPaint` 画的，`Container` 数不到 —— 这正是旧版的漏）。
List<(Offset, String)> _bars(WidgetTester tester) {
  final List<(Offset, String)> out = <(Offset, String)>[];
  for (final Element e in find.byType(Container).evaluate()) {
    final Widget w = e.widget;
    if (w is! Container) continue;
    final BoxConstraints? c = w.constraints;
    if (c == null || c.minWidth != 1.5 || c.maxWidth != 1.5) continue;
    final RenderObject? ro = e.renderObject;
    if (ro is RenderBox && ro.hasSize) {
      out.add((ro.localToGlobal(Offset.zero), 'text'));
    }
  }
  for (final Element e in find.byType(CustomPaint).evaluate()) {
    final CustomPainter? p = (e.widget as CustomPaint).foregroundPainter;
    if (p is! MathCaretPainter || !p.caretVisible) continue;
    final RenderObject? ro = e.renderObject;
    if (ro is! RenderBox) continue;
    out.add((ro.localToGlobal(p.rect.topLeft), 'math'));
  }
  out.sort(((Offset, String) a, (Offset, String) b) => a.$1.dy.compareTo(b.$1.dy));
  return out;
}

/// 文档里**不是位置**的偏移 = 段落分隔符（`core/paragraph_break.dart` 的判据）。
Set<int> _separators(String s) {
  final Set<int> out = <int>{};
  for (var i = 1; i < s.length; i++) {
    if (isParagraphSeparator(s, i)) out.add(i);
  }
  return out;
}

const Map<String, String> kDocs = <String, String>{
  // ── 纯文本（旧语料，保留：末页槽 / 分页符 / 文首文末空行）──────────────
  '① 单行': '甲\n',
  '② 两段': '甲\n\n乙\n',
  '③ 文末空行': '甲\n\n乙\n\n',
  '④ 分页符夹中间': '甲\n<!-- pagebreak -->\n乙\n',
  '⑤ 页尾空行 + 分页符': '甲\n\n乙\n\n\n\n\n<!-- pagebreak -->\n丙\n',
  '⑥ 分页符在文末': '甲\n<!-- pagebreak -->\n\n\n',
  '⑦ 用户那份单页': 'aa\n\nbb\n\ncc\n\n啊啊\n\n你好\n',
  '⑨ 打字中（无尾换行）': 'aa\n\nbb\n\ncc',
  '⑩ 单字无尾换行': '甲',
  '⑪ 文首两个空行': '\n\n甲\n',
  '⑫ 段间两行空行': '甲\n\n\n\n乙\n',
  // ── ★★ 行间块（2026-11-01 新增：旧语料一份都没有 ⇒ F13 从没被这条守卫覆盖）──
  'Ⓐ 块前紧贴文字': '甲\n\$\$\nx\n\$\$\n乙\n',
  'Ⓑ 块前空一行（分隔符）': '甲\n\n\$\$\nx\n\$\$\n\n乙\n',
  'Ⓒ 块前真空行（k=3）': '甲\n\n\n\$\$\nx\n\$\$\n\n\n乙\n',
  'Ⓓ 两块紧贴': '甲\n\n\$\$\nx\n\$\$\n\$\$\ny\n\$\$\n\n乙\n',
  'Ⓔ 两块之间空一行': '甲\n\n\$\$\nx\n\$\$\n\n\$\$\ny\n\$\$\n\n乙\n',
  'Ⓕ 块在文首': '\$\$\nx\n\$\$\n\n乙\n',
  'Ⓖ 块在文末': '甲\n\n\$\$\nx\n\$\$\n',
  'Ⓗ 三块紧贴': '\$\$\na\n\$\$\n\$\$\nb\n\$\$\n\$\$\nc\n\$\$\n',
};

void main() {
  for (final MapEntry<String, String> d in kDocs.entries) {
    testWidgets('★ 光标归属：${d.key}', (WidgetTester tester) async {
      final DocBuffer buf = await _mount(tester, d.value);
      final Set<int> seps = _separators(d.value);
      final List<String> dead = <String>[];
      final List<String> dup = <String>[];
      final List<String> onSep = <String>[];
      for (var off = 0; off <= d.value.length; off++) {
        buf.setCaret(off);
        await tester.pump();
        await tester.pump();
        final List<(Offset, String)> bars = _bars(tester);
        if (seps.contains(off)) {
          if (bars.isNotEmpty) {
            onSep.add('$off→${bars.map(((Offset, String) b) => b.$2).join('+')}');
          }
          continue;
        }
        if (bars.isEmpty) dead.add('$off');
        if (bars.length > 1) {
          dup.add('$off→${bars.length}根 '
              '${bars.map(((Offset, String) b) => '${b.$2}(${b.$1.dx.toStringAsFixed(0)},'
                  '${b.$1.dy.toStringAsFixed(0)})').join(' ')}');
        }
      }
      expect(onSep, isEmpty,
          reason: '⚠️ 段落分隔符那一格画了光标（它零高度、不是位置）：${onSep.join('、')}');
      expect(dead, isEmpty, reason: '⚠️ 死区（一根光标条都没有）：${dead.join('、')}');
      expect(dup, isEmpty,
          reason: '⚠️ 同一偏移出现多根竖条（双光标）：${dup.take(20).join(' , ')}');
    });
  }
}
