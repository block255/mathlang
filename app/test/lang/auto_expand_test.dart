// 数语引擎 · **自动展开**的守卫（S4-c）
//
// 三组：词触发（整词匹配 + 终止符吃掉）· `/`→分式（分子 = 光标前的可见原子）· 缩写。
// 全部是纯函数断言，不碰编辑器。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/auto_expand.dart';
import 'package:mathlang/lang/word_triggers.dart';

/// 只用默认词表
final TriggerSettings kDefault = TriggerSettings.defaults();

AutoExpand? expand(
  String doc,
  int caret,
  String typed, {
  bool slash = true,
  bool words = true,
  bool short = true,
  TriggerSettings? triggers,
}) =>
    planAutoExpand(
      doc: doc,
      caret: caret,
      typed: typed,
      triggers: triggers ?? kDefault,
      slashFraction: slash,
      wordTriggers: words,
      shorthand: short,
    );

void main() {
  group('词触发 · 整词匹配（★ 用户定的边界）', () {
    test('`sqrt` + 空格 ⇒ `\\sqrt{}`，空格被吃掉', () {
      final AutoExpand? e = expand('sqrt', 4, ' ');
      expect(e, isNotNull);
      expect(e!.kind, AutoExpandKind.word);
      expect(e.from, 0);
      expect(e.tex, r'\sqrt{}');
      expect(e.template, isTrue);
      expect(e.keptTerminator, '');
    });

    test('`summer` + 空格 ⇒ **不**触发（整词匹配）', () {
      expect(expand('summer', 6, ' '), isNull);
    });

    test('`xsqrt` + 空格 ⇒ **不**触发（词的一整串必须等于触发词）', () {
      expect(expand('xsqrt', 5, ' '), isNull);
    });

    test('`\\sqrt` + 空格 ⇒ **不**触发（用户是故意写 LaTeX）', () {
      expect(expand(r'\sqrt', 5, ' '), isNull);
    });

    test('`2sqrt` + 空格 ⇒ **不**触发（不是独立的词）', () {
      expect(expand('2sqrt', 5, ' '), isNull);
    });

    test('`frac` / `sum` 之类各自展开成自己的模板', () {
      expect(expand('frac', 4, ' ')!.tex, r'\frac{}{}');
      expect(expand('sum', 3, ' ')!.tex, r'\sum_{}^{}');
      expect(expand('lim', 3, ' ')!.tex, r'\lim_{}');
    });

    test('大小写不敏感（`SQRT` 也认）', () {
      expect(expand('SQRT', 4, ' ')!.tex, r'\sqrt{}');
    });

    test('`Enter` 保留换行（它是块级动作，不像空格那样被吃掉）', () {
      final AutoExpand? e = expand('sqrt', 4, '\n\n');
      expect(e, isNotNull);
      expect(e!.keptTerminator, '\n');
    });

    test('没有终止符就不触发（半截词不动）', () {
      expect(expand('sqrt', 4, 'x'), isNull);
    });

    test('字母后面继续打字母不触发', () {
      expect(expand('sqr', 3, 't'), isNull);
    });

    test('用户把词条停用 ⇒ 不展开', () {
      final TriggerSettings t = TriggerSettings.defaults().withItem(
        0,
        kDefaultWordTriggers[0].copyWith(enabled: false),
      );
      expect(expand('sqrt', 4, ' ', triggers: t), isNull);
    });

    test('用户自己加的词条也生效', () {
      final TriggerSettings t = TriggerSettings.defaults().add();
      final int i = t.triggers.length - 1;
      final TriggerSettings t2 =
          t.withItem(i, const WordTrigger(word: 'mk', tex: r'\begin{pmatrix}{}&{}\\{}&{}\end{pmatrix}'));
      final AutoExpand? e = expand('mk', 2, ' ', triggers: t2);
      expect(e, isNotNull);
      expect(e!.tex.contains(r'\begin{pmatrix}'), isTrue);
    });

    test('词表关掉 ⇒ 一个都不展开', () {
      expect(expand('sqrt', 4, ' ', words: false), isNull);
    });
  });

  group('`/` → 分式 · 分子 = 光标前那个**可见原子**', () {
    test('正文里 `a/` ⇒ `\\frac{a}{}`（模板 ⇒ 光标进分母空槽）', () {
      final AutoExpand? e = expand('a', 1, '/');
      expect(e, isNotNull);
      expect(e!.kind, AutoExpandKind.fraction);
      expect(e.from, 0);
      expect(e.tex, r'\frac{a}{}');
      expect(e.template, isTrue);
    });

    test('前面是空格 ⇒ 不触发（否则会造出 `\\frac{ }{}`）', () {
      expect(expand('a ', 2, '/'), isNull);
    });

    test('文首 `/` ⇒ 不触发', () {
      expect(expand('', 0, '/'), isNull);
    });

    test('公式里取**最后一个可见原子**', () {
      // `$a+b$` 光标停在 `$` 前 ⇒ 分子是 `b`
      final AutoExpand? e = expand(r'$a+b$', 4, '/');
      expect(e, isNotNull);
      expect(e!.tex, r'\frac{b}{}');
      expect(e.from, 3); // `b` 的源偏移
      expect(e.caret, 4);
    });

    test('公式里**命令算一个原子**（`\\beta` 整段进分子）', () {
      final AutoExpand? e = expand(r'$\alpha+\beta$', 13, '/');
      expect(e, isNotNull);
      expect(e!.tex, r'\frac{\beta}{}');
      expect(e.from, 8);
    });

    test('公式里光标在开头（没有可见原子）⇒ 不触发', () {
      expect(expand(r'$x$', 1, '/'), isNull);
    });

    test('分式开关关掉 ⇒ `/` 就是普通斜杠', () {
      expect(expand('a', 1, '/', slash: false), isNull);
    });
  });

  group('缩写：`>=` `<=` `!=` `+-` `->`', () {
    test('`a>=` ⇒ `\\ge`，两格一起换', () {
      final AutoExpand? e = expand('a>', 2, '=');
      expect(e, isNotNull);
      expect(e!.kind, AutoExpandKind.shorthand);
      expect(e.from, 1);
      expect(e.tex, r'\ge');
    });

    test('五条都在表里', () {
      expect(expand('a<', 2, '=')!.tex, r'\le');
      expect(expand('a!', 2, '=')!.tex, r'\ne');
      expect(expand('a+', 2, '-')!.tex, r'\pm');
      expect(expand('a-', 2, '>')!.tex, r'\to');
    });

    test('单个 `>` 不触发（还没有配对）', () {
      expect(expand('a', 1, '>'), isNull);
    });

    test('紧贴在控制词反斜杠后面不触发（别拆用户写的命令）', () {
      // `\>` 里那一格就是反斜杠本身 ⇒ `>=` 会把命令名劈开
      expect(expand(r'\>', 2, '='), isNull);
    });

    test('缩写关掉 ⇒ 原样打字符', () {
      expect(expand('a>', 2, '=', short: false), isNull);
    });
  });

  group('边界', () {
    test('越界光标不做决定', () {
      expect(expand('abc', 99, '/'), isNull);
      expect(expand('abc', -1, '/'), isNull);
    });

    test('多字符载荷（粘贴）一律不触发', () {
      expect(expand('a', 1, '>='), isNull);
      expect(expand('sqrt', 4, ' sqrt'), isNull);
    });
  });
}
