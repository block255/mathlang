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
//
// ★★ 2026-10-17 S4-a 补第二份扫描（用户报的"粘多行文本把 `$$` 打坏 ⇒ Parser Error"）：
//   上面那三份载荷**一个 `$` 都没有** ⇒ "载荷自带围栏"这一族从来没进过扫描（这就是漏网原因）。
//   第二份扫描的载荷 = 8 份**含 `$$` 的真实粘贴文本**，判据换成
//   "每个数学段的 tex **不含 `$`** 且**能被 KaTeX 解析**"（`$` 出现在 tex 里正是那条报错的源头）；
//   配合的修法是 `insert_guard` 的**规则 ③（围栏行不可落）／④（整行语法补行边界）**。

import 'package:flutter_math_fork/tex.dart' show TexParser, TexParserSettings;
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/block.dart';
import 'package:mathlang/render/insert_guard.dart';
import 'package:mathlang/render/projection.dart';
import 'package:mathlang/spike/s3_edit/s3_edit_page.dart' show kEditSample;

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
    final List<String> ls = <String>[
      for (var l = b.lineFrom; l < b.lineTo; l++) idx.lines.text(l),
    ];
    out.add('B:${_blockTex(ls)}');
  }
  for (var i = 0; i < idx.lines.count; i++) {
    for (final ProjectionSegment s in projectInline(idx.lines.text(i))) {
      if (s.isMath) out.add('I:${s.tex}');
    }
  }
  return out;
}

/// 与 `doc_view._mathParts` 同一条判据：剥掉 `$$` 围栏（块的行区间**含**围栏行）
String _blockTex(List<String> ls) {
  if (ls.length == 1) {
    var body = ls.first.trim();
    if (body.startsWith(r'$$')) body = body.substring(2);
    if (body.endsWith(r'$$')) body = body.substring(0, body.length - 2);
    return body;
  }
  final bool closed = ls.last.trim().startsWith(r'$$');
  final List<String> inner =
      closed ? ls.sublist(1, ls.length - 1) : ls.sublist(1);
  return inner.join('\n');
}

/// 模拟 `EditView._commitText`：先补花括号（如需要）、按计划落点插入，**并应用规则 ④ 的补行边界**
String _apply(String src, InsertPlan plan, String text) {
  var buf = src;
  final ({int start, int end})? wrap = plan.wrapBareArg;
  if (wrap != null) {
    buf = buf.replaceRange(wrap.start, wrap.end, '{${buf.substring(wrap.start, wrap.end)}}');
  }
  final int at = plan.offset.clamp(0, buf.length);
  final String payload = plan.padText(text);
  return buf.substring(0, at) + payload + buf.substring(at);
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

  // ══════════════════════════════════════════════════════════════════════
  // ★★ 第二份扫描（2026-10-17 S4-a）：**载荷自带围栏**的多行文本
  // ══════════════════════════════════════════════════════════════════════
  group(r'★★ 全域：含 `$$` 的多行载荷插到任意偏移后，数学段必须仍可解析', () {
    test('每一段 tex 都不许含 `\$`、且必须能解析（1840 组）', () {
      final List<String> bad = <String>[];
      for (final String src in _pasteCorpus) {
        for (var o = 0; o <= src.length; o++) {
          for (int pi = 0; pi < _pastePayloads.length; pi++) {
            final String text = _pastePayloads[pi];
            final String after = _apply(src, planInsert(src, o, text), text);
            final String? why = _firstBrokenSegment(after);
            if (why != null) {
              bad.add('语料#${_pasteCorpus.indexOf(src)} 偏移 $o 载荷#$pi ⇒ $why\n'
                  '      结果=「${_esc(after)}」');
            }
          }
        }
      }
      expect(bad, isEmpty,
          reason: r'多行粘贴把数学段插坏了（`$$` 配乱 ⇒ Parser Error）：'
              '\n${bad.take(12).join('\n')}');
    });

    test(r'D 口径：句子中间粘**纯文字**多行 ⇒ 一个换行都不补（原样进门）', () {
      const String src = '前文 甲乙丙 后文';
      final InsertPlan p = planInsert(src, 5, '第一行\n第二行');
      expect(p.padding.any, isFalse);
      expect(p.moved, isFalse);
      expect(_apply(src, p, '第一行\n第二行'), '前文 甲乙第一行\n第二行丙 后文');
    });

    test(r'规则 ④：句子中间粘 AI 答案（首/尾行是 `$$`）⇒ 两侧各补一个 `\n`', () {
      const String src = '前文 甲乙丙 后文';
      const String payload = '\$\$\nx=1\n\$\$';
      final InsertPlan p = planInsert(src, 5, payload);
      expect(p.padding.prefixNewline, isTrue);
      expect(p.padding.suffixNewline, isTrue);
      final String after = _apply(src, p, payload);
      expect(after, '前文 甲乙\n\$\$\nx=1\n\$\$\n丙 后文');
      expect(_firstBrokenSegment(after), isNull);
    });

    test(r'规则 ④：尾行是普通文字时**只补前**（后侧无害就不动文档）', () {
      const String src = '前文 甲乙丙 后文';
      const String payload = '\$\$\nx=1\n\$\$\n答案';
      final InsertPlan p = planInsert(src, 5, payload);
      expect(p.padding.prefixNewline, isTrue);
      expect(p.padding.suffixNewline, isFalse);
    });

    test(r'规则 ③：粘在**围栏行末尾**（`$$` 之后、换行之前）⇒ 挪到围栏行之后', () {
      const String src = '前文\n\n\$\$\nx=1\n\$\$\n\n后文';
      final int closingFenceEnd = src.indexOf(r'$$', 6) + 2; // 闭合 `$$` 之后、`\n` 之前
      final InsertPlan p = planInsert(src, closingFenceEnd, '第一行\n第二行');
      expect(p.moved, isTrue);
      expect(p.offset, closingFenceEnd + 1, reason: '应跳到围栏行的下一行行首');
      expect(_firstBrokenSegment(_apply(src, p, '第一行\n第二行')), isNull);
    });

    test(r'规则 ③ 不误伤既有行为：`\n\n` / `  \n` 落在围栏行末尾仍按老规则', () {
      const String src = '前文\n\n\$\$\nx=1\n\$\$\n\n后文';
      final int closingFenceEnd = src.indexOf(r'$$', 6) + 2;
      expect(planInsert(src, closingFenceEnd, '\n\n').offset, closingFenceEnd);
      expect(planInsert(src, closingFenceEnd, '  \n').offset, closingFenceEnd);
    });
  });
}

/// 第二份扫描的语料（含真实样本）
const List<String> _pasteCorpus = <String>[
  kEditSample,
  r'文字 $x$ 尾巴',
  '',
  '前文\n\n\$\$\nx=1\n\$\$\n\n后文',
];

/// 第二份扫描的载荷 = 8 份"粘贴进来的一段"（都含围栏；最后一档是 CRLF）
const List<String> _pastePayloads = <String>[
  '第一行\n\n\$\$\nx=1\n\$\$\n最后一行', // 空行包裹
  '所以：\n\$\$\ny=2\n\$\$', // ★ 文字紧接着围栏（无空行）
  '\$\$\nx=1\n\$\$', // 纯块
  '\$\$x=1\$\$', // 单行闭合
  '设 \$a\$ 与 \$b\$\n\n\$\$\n\\frac{a}{b}\n\$\$\n\n所以', // 混排行内 + 行间
  '答案：\$x=1\$\n\$\$\n\\therefore x=1\n\$\$', // 行内紧接行间
  '**解**：\n\n\$\$\nx=\\frac{-b\\pm\\sqrt{b^2-4ac}}{2a}\n\$\$\n', // AI 输出常见形
  '第一行\r\n\r\n\$\$\r\nx=1\r\n\$\$\r\n最后一行', // ★ CRLF 载荷
];

/// 第一段"坏了"的数学段（tex 含 `$` 或解析失败）；全好返回 null
String? _firstBrokenSegment(String src) {
  for (final String tex in _chunks(src)) {
    final String body = tex.substring(2); // 去掉 `B:` / `I:`
    if (body.contains(r'$')) return 'tex 里出现了 `\$`：${_esc(body)}';
    try {
      TexParser(body, const TexParserSettings()).parse();
    } catch (e) {
      return '解析失败（${_esc(body)}）：$e';
    }
  }
  return null;
}

String _esc(String s) => s.replaceAll('\n', r'\n');
