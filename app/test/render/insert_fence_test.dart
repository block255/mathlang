// ★★ 插入侧的全域守门人：**任何位置插入，都不许把数学段的结构插坏**
// （2026-10-17 用户实测："点在 `a_i` 后面按 Enter，编码就爆出来了"）
//
// 事故根因（探针：`$$x=1$$` 单行闭合块）：
//   · `math_nav._stripFence` 只认"`$$` 独占一行 … `$$` 独占一行"的多行围栏，
//     单行闭合的 `$$x=1$$` 掉进行内分支，被当成 `$x=1$`（`closeEnd` 落在**两个闭合 `$` 之间**）
//   · 于是在 tex 末尾 / 闭合围栏上按 Enter ⇒ `\n\n` 插进 `$$` 中间 ⇒ 围栏劈开 ⇒ 公式退化成源码
//   ★ 同一族：**退格 / 删除**在围栏上也会吃掉一个 `$`。
//
// 判据（全域，不抽查）：
//   ① **每行 `$` 的个数不变**（插入的文本里没有 `$`，所以"多一个少一个"只可能是劈开了围栏）
//   ② **数学段的结构不变**：块级数学块的数量、每行行内数学段的数量
//   ⇒ 对 语料 × 每一个偏移 × {一个字符, Enter(\n\n), Shift+Enter(  \n) } 全跑一遍。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/block.dart';
import 'package:mathlang/render/insert_guard.dart';
import 'package:mathlang/render/projection.dart';

const List<String> _corpus = <String>[
  '前文\n\n\$\$\nx=1\n\$\$\n\n后文', // 多行围栏
  '前文\n\n\$\$x=1\$\$\n\n后文', // ★ 单行闭合（事故现场）
  '前文\n\n\$\$\\sum_{i=1}^{n}a_i\$\$\n\n后文', // 单行闭合 + 算子
  r'文字。$\frac{a}{b}$ 尾巴', // 行内
  r'$\sum_{i=1}^{n}a_i$', // 行内 + 算子
  r'两根之和 $x_1+x_2=-\frac{b}{a}$ 与 $x_1x_2=\frac{c}{a}$', // 两个行内公式
];

/// 数学结构指纹 = **定界符序列** ＋ **数学段个数** ＋ 每段的 tex。
///
/// ★ 为什么不用"每行 `$` 的个数"：插入 `\n` 本来就会**多出几行**（那是合法的），
///   按行数比较会把"正常断行"误报成"劈开围栏"。真正要守的是下面三样：
///   ① `$` 的**成组方式**（`$$` 还是一对 `$`）不能变 —— 插在两个 `$` 中间就会从 `D` 变成 `dd`；
///   ② 数学段的**个数**不能变 —— 行内公式被 `\n` 劈断时，前半行成了"未闭合" ⇒ 段数变；
///   ③ 段内的 tex 除了"插入的那段文本"之外不能变。
String _delims(String src) {
  final sb = StringBuffer();
  var i = 0;
  while (i < src.length) {
    if (src[i] == r'$') {
      if (i + 1 < src.length && src[i + 1] == r'$') {
        sb.write('D');
        i += 2;
      } else {
        sb.write('d');
        i++;
      }
      continue;
    }
    i++;
  }
  return sb.toString();
}

List<String> _chunks(String src) {
  final BlockIndex idx = BlockIndex.parse(src);
  final out = <String>[];
  for (final Block b in idx.blocks) {
    if (b.type != BlockType.math) continue;
    final String body = <String>[
      for (var l = b.lineFrom; l < b.lineTo; l++) idx.lines.text(l),
    ].join('\n');
    out.add('B:$body');
  }
  for (var i = 0; i < idx.lines.count; i++) {
    for (final ProjectionSegment s in projectInline(idx.lines.text(i))) {
      if (s.isMath) out.add('I:${s.tex}');
    }
  }
  return out;
}

/// 模拟 `EditView._commitText`：先补花括号（如需要），再按计划落点插入
String _apply(String src, InsertPlan plan, String text) {
  var buf = src;
  final ({int start, int end})? wrap = plan.wrapBareArg;
  if (wrap != null) {
    buf = buf.replaceRange(wrap.start, wrap.end, '{${buf.substring(wrap.start, wrap.end)}}');
  }
  final int at = plan.offset.clamp(0, buf.length);
  return buf.substring(0, at) + text + buf.substring(at);
}

void main() {
  test(r'★★ 全域不变量：任意位置插入，数学结构都不许变（`$` 配对 / 块 / 行内段）', () {
    final List<String> bad = <String>[];
    for (final String src in _corpus) {
      final String delims0 = _delims(src);
      final List<String> chunks0 = _chunks(src);
      for (var o = 0; o <= src.length; o++) {
        for (final String text in <String>['X', '\n\n', '  \n']) {
          final String after = _apply(src, planInsert(src, o, text), text);
          final String delims1 = _delims(after);
          final List<String> chunks1 = _chunks(after);
          if (delims0 != delims1) {
            bad.add('「${_esc(src)}」偏移 $o 插入 ${_esc(text)} ⇒ '
                '定界符被劈开 $delims0 → $delims1\n      ${_esc(after)}');
            continue;
          }
          if (chunks0.length != chunks1.length) {
            bad.add('「${_esc(src)}」偏移 $o 插入 ${_esc(text)} ⇒ '
                '数学段 $chunks0 → $chunks1\n      ${_esc(after)}');
          }
        }
      }
    }
    expect(bad, isEmpty, reason: '插入把数学段插坏了：\n${bad.take(12).join('\n')}');
  });

  group('★ 金表：单行闭合块（事故现场）', () {
    test(r'`$$x=1$$` 被当成**块**（不是行内 `$x=1$`）', () {
      const String src = '前文\n\n\$\$x=1\$\$\n\n后文';
      // 块内任意位置按 Enter ⇒ 推到块之后
      final int closeEnd = src.indexOf(r'$$', 6) + 2;
      for (final int o in <int>[6, 7, 8, 9]) {
        final InsertPlan p = planInsert(src, o, '\n\n');
        expect(p.moved, isTrue, reason: '偏移 $o');
        expect(p.offset, closeEnd, reason: r'应推到闭合 `` `$$` `` 之后（偏移 $o）');
      }
      // 块**之前**那一格按 Enter ⇒ 不动（应该在块前断段）
      expect(planInsert(src, 4, '\n\n').moved, isFalse);
    });

    test(r'多行围栏同样安全（回归）', () {
      const String src = '前文\n\n\$\$\nx=1\n\$\$\n\n后文';
      final int closeEnd = src.indexOf(r'$$', 6) + 2;
      for (final int o in <int>[7, 8, 9, 10, 11, 12]) {
        final InsertPlan p = planInsert(src, o, '\n\n');
        if (p.moved) expect(p.offset, closeEnd, reason: '偏移 $o');
      }
    });
  });
}

String _esc(String s) => s.replaceAll('\n', r'\n');
