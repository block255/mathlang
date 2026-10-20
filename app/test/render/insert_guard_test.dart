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

    test('标记行首 / 行中间 ⇒ 也挪到该行之后', () {
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
}
