// 插入侧守门人的回归测试（2026-10-15）
//
// 守的是用户实测的那条：「点分式内 → `→` 到行末 → Enter → **分式被拆出编码**」。
// 探针把根因钉死了：那个"行末"其实是**闭合 `$` 之前那一格**（还在公式里），
// 插入 `\n\n` 会把 `$` 配成单数 → 整行退化成源码。
//
// ★ 判据必须**客观**（不许"看着对不对"）：
//   · 落点被调整没有（`moved`）
//   · 调整到了哪里（`offset` == 公式之后的 `closeEnd`）
// ★ 同时钉住**不许误伤**的一面：非换行的插入**必须照旧进公式**
//   （在公式末尾打 `+1` = 继续这段数学，那是要保留的能力）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/insert_guard.dart';

/// 行内公式样本：`文字。$\frac{a}{b}$` + 两个换行 + `尾段`
const String kInline = r'''文字。$\frac{a}{b}$

尾段
''';

/// 行间公式样本（围栏式）
const String kDisplay = r'''$$
x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}
$$

尾段
''';

// 偏移都从源码算出来，不写死数字（少一处会被改坏的魔法数）
final int kInlineTexStart = kInline.indexOf(r'\frac'); // = tex[0]
final int kInlineContentEnd = kInline.indexOf('b}') + 2; // = 闭合 `$` 那一格
final int kInlineCloseEnd = kInlineContentEnd + 1; // = 公式之后
final int kInlineLineStart = kInline.indexOf('\n') + 1;

final int kDispTexStart = kDisplay.indexOf(r'\frac');
final int kDispContentEnd = kDisplay.indexOf('2a') + 2;
final int kDispLineStart = kDisplay.indexOf('\n') + 1; // 紧跟在 `\n` 之后

void main() {
  group('★ 行内公式：任何换行都不许落在里面', () {
    test(r'★ 用户踩的那一格（闭合 `$` 之前）→ 推到公式之后', () {
      final InsertPlan p = planInsert(kInline, kInlineContentEnd, '\n\n');
      expect(p.moved, isTrue,
          reason: r'★ 这一格必须被推出去，否则 `$` 配成单数、整行退化成源码');
      expect(p.offset, kInlineCloseEnd);
    });

    test('公式里**任何**位置插入换行都被推出去（不是只修那一格）', () {
      for (int o = kInlineTexStart; o <= kInlineContentEnd; o++) {
        final InsertPlan p = planInsert(kInline, o, '\n\n');
        expect(p.moved, isTrue, reason: '偏移 $o 在公式里，插入换行必须被推出去');
        expect(p.offset, kInlineCloseEnd);
      }
    });

    test('公式**外**的换行一律不动（正常断块）', () {
      for (final int o in <int>[0, 1, 2, kInlineCloseEnd, kInlineLineStart]) {
        expect(planInsert(kInline, o, '\n\n').moved, isFalse,
            reason: '偏移 $o 不在公式里，不该被动');
      }
    });

    test('★★ 不许误伤：非换行的插入**照旧进公式**（在末尾打 `+1` = 继续这段数学）', () {
      for (int o = kInlineTexStart; o <= kInlineContentEnd; o++) {
        final InsertPlan p = planInsert(kInline, o, '+1');
        expect(p.moved, isFalse, reason: '偏移 $o：打字不是换行，不该被推出公式');
        expect(p.offset, o);
      }
    });

    test('换行夹在别的字符里（多字符粘贴）同样被推出去', () {
      expect(planInsert(kInline, kInlineTexStart + 3, 'a\nb').moved, isTrue);
    });
  });

  group('★ 行间公式：只挡"会产生空行"的那种', () {
    test('`\\n\\n`（= Enter，断块）在里面 → 推出去（TeX 里空行 = \\par，数学模式会报错）', () {
      final InsertPlan p = planInsert(kDisplay, kDispContentEnd, '\n\n');
      expect(p.moved, isTrue);
      expect(p.offset, greaterThan(kDispContentEnd));
    });

    test('★ 不许误伤：单个 `\\n`（= Shift+Enter 的块内硬换行）**放行** —— 多行公式要用', () {
      // 挑一个前后都不挨着 `\n` 的位置
      final int o = kDispTexStart + 8;
      expect(kDisplay[o - 1] == '\n' || kDisplay[o] == '\n', isFalse,
          reason: '这个测试位置必须不紧邻换行，否则它本来就会拼出空行');
      expect(planInsert(kDisplay, o, '  \n').moved, isFalse);
    });

    test('但紧邻已有换行时，单个 `\\n` 也会拼出空行 → 推出去', () {
      expect(planInsert(kDisplay, kDispLineStart, '  \n').moved, isTrue,
          reason: '插在行首 + 后面已有 `\\n` → 拼出一个空行');
    });

    test('行间公式**外**的换行不动', () {
      final int after = kDisplay.lastIndexOf('尾段');
      expect(planInsert(kDisplay, after, '\n\n').moved, isFalse);
    });
  });

  group('边界', () {
    test('空文本 / 不带换行的文本 → 一律不动（守门人只干这一件事）', () {
      expect(planInsert(kInline, kInlineContentEnd, '').moved, isFalse);
      expect(planInsert(kInline, kInlineContentEnd, 'abc').moved, isFalse);
    });

    test(r'★ 单独插入 `$` **不拦** —— 那正是用户新建公式的路径', () {
      expect(planInsert(kInline, 0, r'$').moved, isFalse);
    });

    test('越界偏移会被夹回范围内（不抛异常）', () {
      expect(planInsert(kInline, 9999, '\n\n').moved, isFalse);
      expect(planInsert(kInline, -5, '\n\n').moved, isFalse);
    });
  });

  // ★★★ 2026-10-20（T-A 实战测试 F7，用户可见）：**分页符行里不许落载荷**。
  //
  // 改前现场：插入分页后光标停在标记行末（`block_ops._planPageBreak` 故意这么放，
  // 好让顶栏立刻变成"取消分页"）⇒ 接着从符号面板插一个符号 ⇒ 文档变成
  // `<!-- pagebreak -->$\frac{}{}$` ⇒ 那一行不再是"整行正好是标记" ⇒ 渲染退回普通段落
  // ⇒ **页面上直接露出 HTML 注释编码**。
  //
  // 判据（全域）：任何落点 × 任何载荷，落地之后**分页符那一行必须还是一个完好的分页符**。
  group('★ F7：分页符行不是载荷的合法落点（会把标记吃掉、露出编码）', () {
    const String pb = '\n<!-- pagebreak -->\n';
    final int atMarkerEnd = pb.indexOf('-->') + 3; // = 插入分页后的光标位置
    final int nextLine = pb.indexOf('\n', 1) + 1;

    test('标记行末（最常见路径）⇒ 挪到该行之后', () {
      final InsertPlan p = planInsert(pb, atMarkerEnd, r'$\frac{}{}$');
      expect(p.moved, isTrue);
      expect(p.offset, nextLine);
      final String out =
          pb.replaceRange(p.offset, p.offset, p.padText(r'$\frac{}{}$'));
      expect(out.split('\n').contains('<!-- pagebreak -->'), isTrue);
      expect(out, '\n<!-- pagebreak -->\n'
          r'$\frac{}{}$');
    });

    test('标记行中间 ⇒ 挪到该行之后；★ **行首不再挪**（批 47：行首插安全，内容留在标记之前）', () {
      for (final int at in <int>[1, 5, 12]) {
        final InsertPlan p = planInsert(pb, at, 'x');
        final String out = pb.replaceRange(p.offset, p.offset, p.padText('x'));
        expect(out.split('\n').contains('<!-- pagebreak -->'), isTrue,
            reason: '@$at ⇒ ${out.replaceAll('\n', r'\n')}');
      }
    });

    test('文末那一行分页符（后面没有换行）⇒ 挪到行尾 + 补一个换行', () {
      const String tail = 'x\n<!-- pagebreak -->';
      final InsertPlan p = planInsert(tail, tail.length - 3, 'y');
      final String out =
          tail.replaceRange(p.offset, p.offset, p.padText('y'));
      expect(out.split('\n').contains('<!-- pagebreak -->'), isTrue,
          reason: out.replaceAll('\n', r'\n'));
      expect(out.contains('<!-- pagebreak -->y'), isFalse);
    });

    test('★ 全域：每个落点 × 五种载荷 ⇒ 分页符行永远是完好的标记', () {
      const List<String> payloads = <String>[
        'x',
        r'$\frac{}{}$',
        r'$\sum_{i=1}^{n}a_i$',
        'a\nb',
        '  \n',
      ];
      for (final String payload in payloads) {
        for (var at = 0; at <= pb.length; at++) {
          final InsertPlan p = planInsert(pb, at, payload);
          final String out =
              pb.replaceRange(p.offset, p.offset, p.padText(payload));
          expect(
            out.split('\n').contains('<!-- pagebreak -->'),
            isTrue,
            reason: 'payload="${payload.replaceAll('\n', r'\n')}" @ $at ⇒ '
                '"${out.replaceAll('\n', r'\n')}"',
          );
        }
      }
    });
  });

  // ★★ 2026-10-26（批 37，用户 20261026 反馈 B1）：**块级载荷不许劈开"行首标记 + 内容"**。
  //
  // 改前现场（探针实测，`doc = '上一段\n### T2\n正文'`）：
  //   行首+1 ⇒ `#` / 页 / `## T2`（标题 3 级变 2 级）
  //   行首+3 ⇒ `###` / 页 / ` T2`（`###` 没空格 ⇒ 不是标题）
  //   行首+4 ⇒ `### ` / 页 / `T2`  ← 用户点"标题文字最前面"就是这个落点（`### ` 不可见）
  //   行首+5 ⇒ `### T` / 页 / `2`（标题与正文各切一半）
  // 口径（用户 2026-10-26 拍板）：落点在**带行首标记的块行内部** ⇒ 吸到行首，整行连标记一起搬；
  //   **纯段落不吸**（段落中间插分页 = 正常分段）。
  group('★ B1：块级载荷落在标题/列表/引用行内部 ⇒ 吸到行首', () {
    const String pb = '\n<!-- pagebreak -->\n';
    const String heading = '上一段\n### T2\n正文';
    final int lineStart = heading.indexOf('###');
    final int lineEnd = lineStart + '### T2'.length;

    test('★ 用户那一格（`### ` 之后）⇒ 落点吸到行首，标题整行走', () {
      final InsertPlan p = planInsert(heading, lineStart + 4, pb);
      expect(p.offset, lineStart);
      final String out = heading.replaceRange(p.offset, p.offset, p.padText(pb));
      expect(out.split('\n').contains('### T2'), isTrue, reason: '标记必须与内容在同一行');
      expect(out.contains('### \n'), isFalse, reason: '不许留下一个空标题');
    });

    test('★ 全域：标题行内每个落点 ⇒ `### T2` 永远还是完好的一行', () {
      for (var at = lineStart + 1; at < lineEnd; at++) {
        final InsertPlan p = planInsert(heading, at, pb);
        final String out = heading.replaceRange(p.offset, p.offset, p.padText(pb));
        expect(out.split('\n').contains('### T2'), isTrue,
            reason: '@$at ⇒ ${out.replaceAll('\n', r'\n')}');
      }
    });

    test('两端（行首 / 行尾）**不吸**：那里本来就是块边界', () {
      expect(planInsert(heading, lineStart, pb).offset, lineStart);
      expect(planInsert(heading, lineEnd, pb).offset, lineEnd);
    });

    test('★ 纯段落**不吸**：段落中间插分页 = 正常分段', () {
      const String para = '第一行的文字\n第二行的文字';
      final int mid = para.indexOf('第二行') + 1;
      expect(planInsert(para, mid, pb).offset, mid);
    });

    test('列表行 / 引用行同样吸到行首', () {
      for (final String doc in <String>['前\n- 一条内容\n后', '前\n> 引用内容\n后']) {
        final int ls = doc.indexOf('前\n') + 2;
        expect(planInsert(doc, ls + 3, pb).offset, ls, reason: doc);
      }
    });

    test('非块级载荷（不带换行）**不吸** —— 在标题里打字是正常编辑', () {
      expect(planInsert(heading, lineStart + 4, '甲').offset, lineStart + 4);
    });
  });

  // ★★ 2026-10-26（批 37，用户 20261026 反馈 A2）：**载荷贴在围栏行上会把围栏吃掉**。
  //
  // 现场：在空行间块里粘「即 $\forall…$」⇒ 载荷被推出去、落点 = 收尾 `$$` 之后那一格
  // ⇒ 文档变成 `$$即 $\forall…$` ⇒ 那一行**以 `$$` 开头却没有 `$$` 收尾** ⇒
  // 块模型找不到闭合 ⇒ 一路吞到下一个 `$$` ⇒ 用户看到「公式不完整」占满下面一片。
  // 判据（全域）：落点 × 载荷，插入之后**原来那个块必须一字不变**。
  group(r'★ A2：贴在收尾 `$$` 后面的载荷 ⇒ 补前换行，别把围栏吃掉', () {
    const String doc = '\$\$\nx\n\$\$\n尾段';
    const String block = '\$\$\nx\n\$\$';
    final int closeEnd = doc.indexOf('\$\$\n', 2) + 2; // 收尾 `$$` 之后那一格

    test('★ 以文字开头的载荷（旧 bug 的那一种）⇒ 落到下一行', () {
      const String payload = r'即 $\forall \varepsilon > 0$';
      final InsertPlan p = planInsert(doc, closeEnd, payload);
      final String out = doc.replaceRange(p.offset, p.offset, p.padText(payload));
      expect(out.contains(block), isTrue,
          reason: '块必须一字不变：${out.replaceAll('\n', r'\n')}');
      expect(out.split('\n')[2], '\$\$', reason: r'收尾围栏那一行必须还是纯 `$$`');
    });

    test(r'★ 全域：任何落点 × 含 `$` 的载荷 ⇒ 两个围栏行都还是纯 `$$`', () {
      for (final String payload in <String>[
        r'即 $x$',
        r'$x$ 之后',
        r'价格 $5',
        'a\nb',
      ]) {
        for (var at = 0; at <= doc.length; at++) {
          final InsertPlan p = planInsert(doc, at, payload);
          final String out =
              doc.replaceRange(p.offset, p.offset, p.padText(payload));
          final int fences =
              out.split('\n').where((String l) => l.trim() == '\$\$').length;
          expect(fences, 2,
              reason: 'payload="$payload" @$at ⇒ ${out.replaceAll('\n', r'\n')}');
        }
      }
    });
  });

  // ★★★ 批 47（2026-10-26，用户实测"在原页页尾空白打字，字跑到下一页"）：
  //   落在分页符行**行首**时不许挪位 —— 行首插是安全的（补一个后缀换行，
  //   内容自成一行落在**标记之前**，标记仍独占一行）。
  group('★ 批 47：分页符行**行首**插入 ⇒ 内容留在本页（标记之前）', () {
    const String doc = '甲\n<!-- pagebreak -->\n乙\n';
    final int pbStart = doc.indexOf('<!--');

    test('★ 行首插一个字符 ⇒ 落点不动，字符在标记**之前**，标记完好', () {
      final InsertPlan p = planInsert(doc, pbStart, 'x');
      expect(p.offset, pbStart, reason: '行首不许被挪走');
      final String out = doc.replaceRange(p.offset, p.offset, p.padText('x'));
      expect(out.indexOf('x'), lessThan(out.indexOf('<!--')),
          reason: '字符必须在分页符之前：${out.replaceAll('\n', r'\n')}');
      expect(out.split('\n').contains('<!-- pagebreak -->'), isTrue,
          reason: '标记必须完好：${out.replaceAll('\n', r'\n')}');
    });

    test('★ 行首插 `\\n\\n`（Enter）⇒ 新段在标记之前，标记完好', () {
      final InsertPlan p = planInsert(doc, pbStart, '\n\n');
      final String out = doc.replaceRange(p.offset, p.offset, p.padText('\n\n'));
      expect(out.split('\n').contains('<!-- pagebreak -->'), isTrue,
          reason: out.replaceAll('\n', r'\n'));
      expect(out.indexOf('<!--'), greaterThan(pbStart),
          reason: '标记应当被推到内容之后（内容在它之前）：${out.replaceAll('\n', r'\n')}');
    });

    test('★ 行内插（非行首）⇒ 仍然挪到该行之后（老口径不许退化）', () {
      final InsertPlan p = planInsert(doc, pbStart + 3, 'x');
      expect(p.moved, isTrue);
      expect(p.offset, greaterThan(pbStart + '<!-- pagebreak -->'.length));
    });
  });
}
