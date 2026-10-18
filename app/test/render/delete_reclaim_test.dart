// 数语引擎 · **删除要干脆**（2026-10-18 用户拍板）
//
// 用户口径（原话）：
//   「比如根号结构，分式结构，在它们整个的后面点删除是直接删掉整个结构，而不是留下一个空框。」
//   「`删空留壳` 是针对**数学结构里的子位点**来说的；**直接删整个没有任何留壳回打的义务**。」
//
// 所以有两条互不冲突的规则，本文件把它们分开钉住：
//   ① **子位点**：删掉 `\frac{□}{□}` 里某个槽的内容 ⇒ **槽留着**（空槽占位照画，提醒去填）；
//   ② **整个数学段**：一次删除把它**删空** ⇒ **连定界符一起删**（同一步、一步撤销、不留框）。
//
// ★ 判据是**全域**的：语料 × 每一个偏移 × {Backspace, Delete} ⇒ 删完**不许出现空数学段**
//   （除非删之前就有）。这样"哪些数学语言删不干脆"是被穷举出来的，而不是听人报一个个改。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/auto_expand.dart';
import 'package:mathlang/lang/math_spans.dart';
import 'package:mathlang/lang/symbol_insert.dart';
import 'package:mathlang/lang/word_triggers.dart';
import 'package:mathlang/render/delete_reclaim.dart';
import 'package:mathlang/render/math_nav.dart';
import 'package:mathlang/render/smart_delete.dart';

/// 文档里有没有"内容全空白"的数学段
bool _hasEmptyMath(String doc) =>
    scanMathSpans(doc).any((MathSpan s) => s.tex.trim().isEmpty);

/// 跑一次删除（**走真实链路**：结构感知删除 + «删空回收»）
String _delete(String doc, int caret, {required bool forward}) {
  final SmartEdit e = reclaimEmptiedMath(
    doc,
    smartEditAt(doc, caret, forward: forward),
  );
  if (!e.deletes) return doc;
  return doc.replaceRange(e.from!, e.to!, '');
}

void main() {
  group('① 结构里的**子位点**：删内容 ⇒ 槽留着（不许连结构一起走）', () {
    test(r'根号里删掉 x ⇒ 留空槽（结构还在）', () {
      const String doc = r'$\sqrt{x}$';
      final int caret = doc.indexOf('x') + 1; // x 之后（闭合定界符之前）
      expect(_delete(doc, caret, forward: false), r'$\sqrt{}$');
    });

    test(r'分式里删掉分母 b ⇒ 分式还在、分子也还在', () {
      const String doc = r'$\frac{a}{b}$';
      final int caret = doc.indexOf('b') + 1;
      expect(_delete(doc, caret, forward: false), r'$\frac{a}{}$');
    });
  });

  group('② 整个数学段：删空 ⇒ 连定界符一起删（一步、不留框）', () {
    test(r'★ 根号整段删 ⇒ 整段消失（不是留空壳）', () {
      const String doc = r'前$\sqrt{}$后';
      const String math = r'$\sqrt{}$';
      final int caret = doc.indexOf(math) + math.length;
      final String after = _delete(doc, caret, forward: false);
      expect(after, '前后', reason: '删完必须什么都不剩（改前：留下一个空框）');
    });

    test(r'★ 分式整段删 ⇒ 整段消失', () {
      const String doc = r'前$\frac{a}{b}$后';
      const String math = r'$\frac{a}{b}$';
      final int caret = doc.indexOf(math) + math.length;
      expect(_delete(doc, caret, forward: false), '前后');
    });

    test(r'★ 公式里只剩一个原子 ⇒ 删掉它整段消失', () {
      const String doc = r'前$x$后';
      const String math = r'$x$';
      final int caret = doc.indexOf(math) + math.length;
      expect(_delete(doc, caret, forward: false), '前后');
    });

    test('公式前面那格用 Delete ⇒ 同样整段消失', () {
      const String doc = r'前$\sqrt{}$后';
      final int caret = doc.indexOf(r'$\sqrt{}$');
      expect(_delete(doc, caret, forward: true), '前后');
    });

    test('删公式外面的文字 ⇒ 不许把公式带走', () {
      const String doc = r'a$\sqrt{}$';
      final String after = _delete(doc, doc.indexOf(r'$'), forward: false);
      expect(after, r'$\sqrt{}$', reason: '删的没碰到公式内容 ⇒ 公式原样');
    });
  });

  group('③ 行间块：删空 ⇒ 整块消失', () {
    test('★ 删掉块里唯一的结构 ⇒ 连围栏一起走，后面的内容不动', () {
      const String doc = '\$\$\n\\sqrt{}\n\$\$\n尾段';
      final int caret = doc.indexOf('\\sqrt{}') + '\\sqrt{}'.length;
      final String after = _delete(doc, caret, forward: false);
      expect(after.contains('\\sqrt'), isFalse, reason: after);
      expect(_hasEmptyMath(after), isFalse, reason: after);
      expect(after.contains('尾段'), isTrue, reason: '别把后面的内容吃掉：$after');
    });

    test('★ 行间块整片扫：每个偏移 × 两个方向 ⇒ 删完不留空段', () {
      final List<String> displayTexes = <String>[
        r'\sqrt{}',
        r'\frac{a}{b}',
        r'\sum_{}^{}',
        r'\begin{cases}&\\&\end{cases}',
        r'\begin{aligned}&=\\&=\end{aligned}',
        r'\alpha',
      ];
      var checked = 0;
      for (final String tex in displayTexes) {
        final String doc = '\$\$\n$tex\n\$\$\n尾段';
        if (_hasEmptyMath(doc)) continue;
        for (var at = 0; at <= doc.length; at++) {
          for (final bool forward in <bool>[false, true]) {
            final String after = _delete(doc, at, forward: forward);
            checked++;
            expect(_hasEmptyMath(after), isFalse,
                reason: 'display tex=$tex @$at ${forward ? 'Del' : 'Bksp'}\n'
                    'before: ${doc.replaceAll('\n', r'\n')}\n'
                    'after:  ${after.replaceAll('\n', r'\n')}');
          }
        }
      }
      expect(checked, greaterThan(200));
    });
  });

  group('④ ★ 全域不变量：任何语料 × 任何偏移 × 两个方向，删完都不许留空数学段', () {
    test('扫全部结构模板 × 全部词触发 × 缩写 × 常见上下文', () {
      const List<String> contexts = <String>[
        '',
        '甲乙丙',
        r'甲$x$乙',
        '\$\$\ny=1\n\$\$',
      ];
      final List<String> texes = <String>[
        r'\sqrt{}',
        r'\sqrt[]{x}',
        r'\frac{}{}',
        r'\frac{a}{b}',
        r'^{}',
        r'_{}',
        r'\sum_{}^{}',
        r'\int_{}^{}',
        r'\lim_{}',
        r'\log_{}',
        r'\vec{}',
        r'\hat{}',
        r'\overline{}',
        r'\left|{}\right|',
        r'\left({}\right)',
        r'\binom{}{}',
        r'\begin{cases}&\\&\end{cases}',
        r'\begin{aligned}&=\\&=\end{aligned}',
        r'\alpha',
        r'\pm',
      ];
      final List<String> fromTriggers = <String>[
        for (final WordTrigger t in TriggerSettings.defaults().triggers)
          if (t.enabled) t.tex,
      ];
      final List<String> fromShorthand = kShorthandTex.values.toList();

      var checked = 0;
      for (final String tex in <String>[
        ...texes,
        ...fromTriggers,
        ...fromShorthand,
      ]) {
        for (final String ctx in contexts) {
          final SymbolInsertResult ins = applySymbolInsert(
            doc: ctx,
            caret: ctx.length,
            selStart: ctx.length,
            selEnd: ctx.length,
            tex: tex,
            template: tex.contains('{}'),
          );
          final String doc = ins.doc;
          if (_hasEmptyMath(doc)) continue; // 插入本身没造出空段才是正常语料
          for (var at = 0; at <= doc.length; at++) {
            for (final bool forward in <bool>[false, true]) {
              final String after = _delete(doc, at, forward: forward);
              checked++;
              expect(_hasEmptyMath(after), isFalse,
                  reason: 'tex=$tex ctx="${ctx.replaceAll('\n', r'\n')}" '
                      '@$at ${forward ? 'Delete' : 'Backspace'}\n'
                      'before: ${doc.replaceAll('\n', r'\n')}\n'
                      'after:  ${after.replaceAll('\n', r'\n')}');
            }
          }
        }
      }
      expect(checked, greaterThan(3000), reason: '扫描规模太小说明语料没跑起来');
    });
  });

  group('⑤ 一步撤销能回来（同一次操作，不是两次）', () {
    test('回收定界符 = 一个 SmartEdit（区间替换）', () {
      const String doc = r'前$\sqrt{}$后';
      const String math = r'$\sqrt{}$';
      final int caret = doc.indexOf(math) + math.length;
      final SmartEdit e = reclaimEmptiedMath(
        doc,
        smartEditAt(doc, caret, forward: false),
      );
      expect(e.deletes, isTrue);
      expect(doc.substring(e.from!, e.to!), math,
          reason: '范围必须把两个定界符都包进去');
    });
  });
}
