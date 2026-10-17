// 位点表测试（S3-1）
//
// 规格：notes/design/位点与结构导航.md §二
// 三条性质（§2.4）：
//   P1 每个位点都是**语法安全的插入点**（插探针字符后仍能解析）
//   P2 位点表严格递增、无重复、落在 [0, len]
//   P3 snap() 的返回值必然 ∈ 位点表

import 'package:flutter_math_fork/tex.dart' show TexParser, TexParserSettings;
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/caret_sites.dart';

/// 引擎能不能解析这段 tex
bool _parses(String tex) {
  try {
    TexParser(tex, const TexParserSettings()).parse();
    return true;
  } catch (_) {
    return false;
  }
}

/// 代表性 tex（P1 的样本集）
const List<String> _batch = <String>[
  r'\frac{a}{b}',
  r'\dfrac{a}{b}',
  r'\frac12',
  r'\frac{1}{\frac{2}{3}}',
  r'x^{2}',
  r'x_1^2',
  r'a_{i,j}',
  r'\sqrt{x}',
  r'\sqrt[3]{x}',
  r'\alpha+\beta',
  r'\sum_{i=1}^{n} i',
  r'\int_{0}^{1} x\,dx',
  r'\lim_{x \to 0} \frac{\sin x}{x}',
  r'\left(\frac{a}{b}\right)',
  r'\text{中文}',
  r'{ab}',
  r'a{}b',
  r'\begin{aligned} a &= b \\ c &= d \end{aligned}',
  r'\begin{pmatrix} 1 & 2 \\ 3 & 4 \end{pmatrix}',
];

void main() {
  group('位点表的构造', () {
    test(r'分式 \frac{a}{b}：}{ 之间的偏移 8 不是位点', () {
      final CaretSiteTable t = buildCaretSites(r'\frac{a}{b}');
      expect(t.offsets, <int>[0, 6, 7, 9, 10, 11]);
      expect(t.isSite(8), isFalse, reason: '往 8 插字符会得到 \\frac{a}x{b}');
      expect(t.degraded, isFalse);
      expect(t.slots.length, 2);
      expect(t.slots[0].path.single.label, 'frac#0');
      expect(t.slots[0].isEmpty, isFalse);
    });

    test('分子末尾的位点带 [frac#0]，分母开头的位点带 [frac#1]', () {
      final CaretSiteTable t = buildCaretSites(r'\frac{a}{b}');
      final CaretSite afterNum = t.at(7)!;
      final CaretSite beforeDen = t.at(9)!;
      expect(afterNum.path.single.label, 'frac#0');
      expect(afterNum.indexInSlot, 1);
      expect(afterNum.isMain, isFalse);
      expect(beforeDen.path.single.label, 'frac#1');
      expect(beforeDen.indexInSlot, 0);
    });

    test(r'上下标 x^{2}：^ 与 { 之间的偏移 2 不是位点', () {
      final CaretSiteTable t = buildCaretSites(r'x^{2}');
      expect(t.offsets, <int>[0, 1, 3, 4, 5]);
      expect(t.isSite(2), isFalse);
      expect(t.at(1)!.isMain, isTrue, reason: 'x 之后的位点在主行');
      expect(t.at(3)!.path.single.label, '^#0');
    });

    test(r'紧凑写法 x_1^2 的位点表', () {
      final CaretSiteTable t = buildCaretSites(r'x_1^2');
      expect(t.offsets, <int>[0, 1, 2, 3, 4, 5]);
      expect(t.at(2)!.path.single.label, '_#0');
      expect(t.at(4)!.path.single.label, '^#0');
    });

    test(r'根号可选参数 \sqrt[3]{x}', () {
      final CaretSiteTable t = buildCaretSites(r'\sqrt[3]{x}');
      expect(t.offsets, <int>[0, 6, 7, 9, 10, 11]);
      expect(
        t.slots.map((SlotSpan s) => s.path.single.label).toList(),
        <String>['sqrt[opt]', 'sqrt#0'],
      );
    });

    test(r'空槽 \frac{}{}：每个空槽恰好一个位点', () {
      final CaretSiteTable t = buildCaretSites(r'\frac{}{}');
      expect(t.offsets, <int>[0, 6, 8, 9]);
      expect(t.slots.length, 2);
      expect(t.slots[0].isEmpty, isTrue);
      expect(t.slots[1].isEmpty, isTrue);
      expect(t.at(6)!.path.single.label, 'frac#0');
      expect(t.at(8)!.path.single.label, 'frac#1');
    });

    test('符号命令整体是一个原子：两侧各一个位点', () {
      final CaretSiteTable t = buildCaretSites(r'\alpha');
      expect(t.offsets, <int>[0, 6], reason: r'\alpha 的 5 个字符之间没有位点');
    });

    test('空 tex 只有偏移 0', () {
      expect(buildCaretSites('').offsets, <int>[0]);
    });

    test(r'未闭合的 \frac{a}{ 不降级：分母槽延伸到文末', () {
      final CaretSiteTable t = buildCaretSites(r'\frac{a}{');
      expect(t.degraded, isFalse);
      expect(t.offsets, <int>[0, 6, 7, 9]);
      expect(t.slots[1].isEmpty, isTrue);
    });

    test('多余的 } 触发降级（纯字符级位点表）', () {
      final CaretSiteTable t = buildCaretSites(r'a}b');
      expect(t.degraded, isTrue);
      expect(t.degradeReason, contains('多余的'));
      expect(t.slots, isEmpty);
      expect(t.offsets, <int>[0, 1, 2, 3], reason: '降级后是原子边界 + 首尾');
    });

    test(r'\left( / \right) 与分隔符之间的夹缝不是位点（命令与分隔符一起看）', () {
      final CaretSiteTable t = buildCaretSites(r'\left(\frac{a}{b}\right)');
      expect(t.offsets, <int>[0, 6, 12, 13, 15, 16, 17, 24]);
      expect(t.isSite(5), isFalse,
          reason: r'\left 与 ( 之间：插字符会得到 \left+( ，解析直接坏');
      expect(t.isSite(23), isFalse, reason: r'\right 与 ) 之间');
      expect(t.isSite(6), isTrue, reason: '括号内内容的开头');
    });

    test('多行环境按 & 与 \\\\ 切成格，并带行列', () {
      final CaretSiteTable t =
          buildCaretSites(r'\begin{aligned} a &= b \\ c &= d \end{aligned}');
      expect(t.slots.length, 4);
      expect(
        t.slots
            .map((SlotSpan s) => '${s.path.single.row},${s.path.single.col}')
            .toList(),
        <String>['0,0', '0,1', '1,0', '1,1'],
      );
      expect(t.isSite(16), isTrue, reason: '第一个 a 的开头');
      expect(t.isSite(32), isTrue, reason: r'最后一个 d 的结尾（d 在 31，& 与 = 相邻无空格）');
      expect(t.isSite(46), isTrue, reason: '根区域末尾 = tex.length');
      expect(t.offsets, <int>[
        0, 16, 17, 18, 19, 20, 21, 22, 23, 25, 26, 27, 28, 29, 30, 31, 32, 33, 46,
      ]);
      expect(t.degraded, isFalse);
    });
  });

  group('吸附（snap）', () {
    test(r'落在语法夹缝 8 → 吸附到左边的 7（原来是注入 \cursor{} 会吃掉分母）', () {
      final CaretSiteTable t = buildCaretSites(r'\frac{a}{b}');
      expect(t.snap(8).offset, 7);
    });

    test('左右等距时取左', () {
      final CaretSiteTable t = buildCaretSites(r'x^{2}');
      expect(t.snap(2).offset, 1, reason: '1 与 3 等距 → 取左');
    });

    test('落在位点上则原地不动', () {
      final CaretSiteTable t = buildCaretSites(r'\frac{a}{b}');
      expect(t.snap(9).offset, 9);
    });

    test('★★ 裸参数**末尾**的注入要留在那一行（§11.37：失焦 normalize 会把 `^{n}` 去成 `^n`）', () {
      // 失焦后 tex 变成 `\sum_{i=1}^na_i`，"n 之后"= 12；就地注入会让锚点掉到**主行**
      // ⇒ 必须包成 `^{n…}`，锚点留在**上标那一行**（版面不变）。
      final CursorInjection a = injectCursor(r'\sum_{i=1}^na_i', 12);
      expect(a.tex, r'\sum_{i=1}^{n' + kCursorTex + r'}a_i', reason: '锚点要在花括号内、n 之后');
      final CursorInjection b = injectCursor(r'x^2', 3);
      expect(b.tex, r'x^{2' + kCursorTex + r'}', reason: b.tex);
    });
    test('越界不崩', () {
      final CaretSiteTable t = buildCaretSites(r'\frac{a}{b}');
      expect(t.snap(-5).offset, 0);
      expect(t.snap(999).offset, 11);
    });
  });

  group(r'注入光标（把光标画进数学内部）', () {
    test(r'夹缝 8 → 注入到 7：不会让光标顶掉分母', () {
      final CursorInjection r = injectCursor(r'\frac{a}{b}', 8);
      expect(r.offset, 7);
      expect(r.tex, '\\frac{a$kCursorTex}{b}');
    });

    test('正常位点原地注入', () {
      final CursorInjection r = injectCursor(r'\frac{a}{b}', 9);
      expect(r.offset, 9);
      expect(r.tex, '\\frac{a}{${kCursorTex}b}');
    });

    test('空槽：光标落在槽内', () {
      final CursorInjection r = injectCursor(r'\frac{}{}', 8);
      expect(r.offset, 8);
      expect(r.tex, '\\frac{}{$kCursorTex}');
    });

    test(r'★ 注入点紧跟 ^ 时不能报错，而且**不许顶掉上标**（2026-10-17 升级）', () {
      // 用户实测报错：Parser Error: Got function '\cursor' with no arguments as superscript
      // ★★ 2026-10-17：光"包进 \textcolor 不报错"不够 —— 那样 `^2` 会**改绑到注入的组上**，
      //   而 `\sum` 那族一改绑，上下限就整块散架（用户实测截图）。
      //   现在注入点**挪进上标的组内部**（裸参数先补花括号）：`x^{\textcolor{…}{}2}` ⇒ 渲染一模一样。
      final CursorInjection r = injectCursor(r'x^2', 1);
      expect(r.offset, 3, reason: '`^{` 之内第一格');
      expect(r.tex, 'x^{${kCursorTex}2}');
      expect(_parses(r.tex), isTrue, reason: '注入后必须仍能解析：${r.tex}');
    });

    test(r'★ 文本模式 \text{} 内：拆组注入（\cursor 在文本模式里不被接受）', () {
      const String tex = r'\text{中文}';
      // 偏移 5（\text 与 { 之间）**不再是位点**：那是命令的参数位
      expect(buildCaretSites(tex).isSite(5), isFalse);
      // 偏移 7 = 「中」与「文」之间 → 拆成 \text{中} 光标 \text{文}
      final CursorInjection r = injectCursor(tex, 7);
      expect(r.offset, 7);
      expect(r.tex, '\\text{中}$kCursorTex\\text{文}');
      expect(_parses(r.tex), isTrue);
    });

    test(r'★ 文本模式内任意位点注入后都能解析（含未闭合）', () {
      for (final String tex in <String>[
        r'\text{中文}',
        r'x+\text{当 }x>0',
        r'\text{ab}cd',
      ]) {
        if (!_parses(tex)) continue; // 基准就坏的样本不参与
        final CaretSiteTable t = buildCaretSites(tex);
        for (final int off in t.offsets) {
          final CursorInjection r = injectCursor(tex, off);
          expect(_parses(r.tex), isTrue,
              reason: '「$tex」@$off 注入成「${r.tex}」后解析失败');
        }
      }
    });

    test('★ 每一个位点上注入之后都必须能被解析（这条守住整类 bug）', () {
      for (final String tex in _batch) {
        if (!_parses(tex)) continue;
        final CaretSiteTable t = buildCaretSites(tex);
        for (final int off in t.offsets) {
          final CursorInjection r = injectCursor(tex, off);
          expect(_parses(r.tex), isTrue,
              reason: '「$tex」@$off 注入成「${r.tex}」后解析失败');
        }
      }
    });

    test('★ 注入点必然是位点（P3 的加强版）', () {
      for (final String tex in _batch) {
        final CaretSiteTable t = buildCaretSites(tex);
        for (final int off in t.offsets) {
          final CursorInjection r = injectCursor(tex, off);
          // ★ 2026-10-17：**包花括号的注入**（裸参数开头 §11.31 ②、裸参数末尾 §11.37 ②b）
          //   会让偏移变大，旧表里当然没有那个位置 ⇒ 跳过；它们由"中性性"守
          //   （`caret_neutral_test`：包完之后 Math 盒尺寸必须**完全不变**）。
          if (r.tex.length != tex.length) continue;
          expect(t.isSite(r.offset), isTrue, reason: '$tex @$off');
        }
      }
    });

    test('越界不崩', () {
      expect(injectCursor(r'\frac{a}{b}', -3).offset, 0);
      expect(injectCursor(r'\frac{a}{b}', 99).offset, 11);
    });
  });

  group('三条性质（设计稿 §2.4）', () {
    test('P2：位点表严格递增、无重复、落在 [0, len]', () {
      for (final String tex in _batch) {
        final CaretSiteTable t = buildCaretSites(tex);
        final List<int> o = t.offsets;
        expect(o, isNotEmpty, reason: tex);
        expect(o.first, 0, reason: tex);
        for (var k = 0; k < o.length; k++) {
          expect(o[k], greaterThanOrEqualTo(0), reason: tex);
          expect(o[k], lessThanOrEqualTo(tex.length), reason: tex);
          if (k > 0) expect(o[k], greaterThan(o[k - 1]), reason: '$tex @$k');
        }
        expect(o.last, tex.length, reason: '$tex 的末尾必须是位点');
      }
    });

    test(r'P1：每个位点插入探针「+」后仍能解析（语法安全的插入点）', () {
      for (final String tex in _batch) {
        if (!_parses(tex)) continue; // 基准就解析不了的样本不参与
        final CaretSiteTable t = buildCaretSites(tex);
        for (final int off in t.offsets) {
          final String probed =
              '${tex.substring(0, off)}+${tex.substring(off)}';
          expect(_parses(probed), isTrue,
              reason: '「$tex」在位点 $off 插入 + 后变成「$probed」，解析失败了');
        }
      }
    });

    test('P3：snap() 的结果必然是位点表里的元素', () {
      for (final String tex in _batch) {
        final CaretSiteTable t = buildCaretSites(tex);
        for (var o = -2; o <= tex.length + 2; o++) {
          final CaretSite s = t.snap(o);
          expect(t.isSite(s.offset), isTrue, reason: '$tex snap($o) → ${s.offset}');
        }
      }
    });
  });

  group('★ 已知提交规则缺口（S3-2 必须处理，不是位点表的 bug）', () {
    test(r'命令名后紧跟字母会粘连：\alpha 末尾插字母会变成 \alphax', () {
      const String tex = r'\alpha';
      final CaretSiteTable t = buildCaretSites(tex);
      final int end = t.offsets.last; // 6
      final String merged = '${tex.substring(0, end)}x${tex.substring(end)}';
      expect(merged, r'\alphax');
      expect(_parses(merged), isFalse,
          reason: '所以插入字母前必须补分隔（空格或 {}）—— 这是提交规则的事');
      // 补一个空格就合法了
      expect(_parses(r'\alpha x'), isTrue);
    });
  });
}
