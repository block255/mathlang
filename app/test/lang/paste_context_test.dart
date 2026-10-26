// ★★ 2026-10-23（批 1）：**跨语境粘贴**的归一规则（纯 Dart）。
//
// 口径（用户 2026-10-23 拍板，见 `notes\design\剪贴板与跨语境粘贴.md` §五）：
//   · 目标在**数学里**（行内 / 行间 / 任何结构槽）⇒ 剥掉外层定界符，只插 tex；
//   · 纯文字照插（与"公式内打中文"同口径：实测 `x+中文+y` 与 `x+\text{中文}+y` 逐像素同尺寸）；
//   · 多行进**行间块** ⇒ 整块内容替换；多行进**行内公式** ⇒ 提升成新块放到本行之后；
//   · 混合文本（里面还夹着 `$…$`）⇒ ★ 2026-10-26（批 37）改口径：**归一成 tex**（剥掉内部
//     成对的 `$`）后就地插；只有**落单**的 `$` 才推到公式之后 ＋ 状态栏说明。
//
// 改前必红：改前根本没有这个函数（粘贴一律跑智能包裹）⇒ 粘 `$x^2$` 进公式会变成 `$` 套 `$`。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/paste_context.dart';

/// 行内公式文档：`前 $x+y$ 后`
const String _inline = r'前 $x+y$ 后';

int get _inInline => _inline.indexOf('x');

/// 空行间块
const String _empty = '\$\$\n\n\$\$';
int get _inEmpty => 3;

void main() {
  group('目标在文字流里 ⇒ 原样（交给智能包裹）', () {
    test('粘到正文', () {
      final PasteDecision d = decidePaste(
        doc: '甲乙',
        caret: 1,
        selStart: 1,
        selEnd: 1,
        payload: r'$\frac{a}{b}$',
      );
      expect(d.apply, PasteApply.asIs);
      expect(d.payload, r'$\frac{a}{b}$');
    });
  });

  group('目标在数学里 ⇒ 剥外层定界符、只插 tex', () {
    test('行内公式里粘 `\$…\$` 片段', () {
      final PasteDecision d = decidePaste(
        doc: _inline,
        caret: _inInline,
        selStart: _inInline,
        selEnd: _inInline,
        payload: r'$\frac{a}{b}$',
      );
      expect(d.apply, PasteApply.mathTex);
      expect(d.payload, r'\frac{a}{b}', reason: '不许把定界符带进公式里');
    });

    test('行内公式里粘 `\$\$…\$\$`（单行）也剥掉', () {
      final PasteDecision d = decidePaste(
        doc: _inline,
        caret: _inInline,
        selStart: _inInline,
        selEnd: _inInline,
        payload: r'$$x^2$$',
      );
      expect(d.apply, PasteApply.mathTex);
      expect(d.payload, r'x^2');
    });

    test('裸 tex / 纯文字 ⇒ 原样插（与打字同口径）', () {
      for (final String p in <String>[r'\alpha+1', '中文说明', 'x']) {
        final PasteDecision d = decidePaste(
          doc: _inline,
          caret: _inInline,
          selStart: _inInline,
          selEnd: _inInline,
          payload: p,
        );
        expect(d.apply, PasteApply.mathTex, reason: p);
        expect(d.payload, p, reason: p);
      }
    });

    // ★★ 2026-10-26（批 37，用户 20261026 反馈 A2）：**混合文本改口径**。
    //
    // 改前（2026-10-23 的 R6）：含 `$` 的混合载荷"拆不动 ⇒ 推到公式之后"。
    // 改后：**归一成 tex**（剥掉内部成对的 `$`）就地插。理由（用户在会话里确认）：
    //   · 文字本来就能待在数学区里（10-23 决定 2 实测：`x+中文+y` 与 `x+\text{中文}+y` 逐像素同尺寸）；
    //   · 当初要挡的**只有 `$`**（tex 里 `$` 非法），而 `$` 可以剥掉 ⇒ 没有理由连文字一起推出去；
    //   · 实测现场：在空行间块里粘这类文段，载荷被推到块后面、空壳还留着；
    //     以文字开头的那种更糟 —— 直接粘在收尾 `$$` 后面，把围栏吃掉 ⇒ 下面整片「公式不完整」。
    test('★★ 批 37：混合文本（里面夹 `\$…\$`）⇒ 归一成 tex，**就地插**', () {
      final PasteDecision d = decidePaste(
        doc: _inline,
        caret: _inInline,
        selStart: _inInline,
        selEnd: _inInline,
        payload: r'见 $a$ 式',
      );
      expect(d.apply, PasteApply.mathTex, reason: '剥掉内部成对的 `\$` 之后就是纯 tex');
      expect(d.payload, '见 a 式', reason: r'tex 里不许出现 `\$`');
      expect(d.note, isNotNull, reason: '替用户剥了定界符，要说明（原则 5：不许静默）');
    });

    test('★ 批 37：整行混合（以文字开头）进空行间块 ⇒ 进块', () {
      final PasteDecision d = decidePaste(
        doc: _empty,
        caret: _inEmpty,
        selStart: _inEmpty,
        selEnd: _inEmpty,
        payload: r'即 $\forall \varepsilon > 0$',
      );
      expect(d.apply, PasteApply.mathTex);
      expect(d.payload, r'即 \forall \varepsilon > 0');
      expect(d.note, isNotNull);
    });

    test(r'★ 批 37（甲口径）：配得上的 `$` 也一律剥 —— `价格 $5 到 $10 元`', () {
      final PasteDecision d = decidePaste(
        doc: _inline,
        caret: _inInline,
        selStart: _inInline,
        selEnd: _inInline,
        payload: r'价格 $5 到 $10 元',
      );
      expect(d.apply, PasteApply.mathTex);
      expect(d.payload, '价格 5 到 10 元');
      expect(d.note, isNotNull, reason: '内容变了（少了两个 \$），必须说出来');
    });

    test(r'★ 落单的 `$` 才推出去，且落点挪到**块所在行之后**（不许贴 `$$`）', () {
      const String doc = '\$\$\nx\n\$\$\n尾段';
      final PasteDecision d = decidePaste(
        doc: doc,
        caret: 3, // 在公式内容 `x` 之后
        selStart: 3,
        selEnd: 3,
        payload: r'价格 $5 到',
      );
      expect(d.apply, PasteApply.pushOut);
      expect(d.at, doc.indexOf('尾段'), reason: '落点必须是下一行行首，不能贴在 `\$\$` 后面');
      expect(d.note, isNotNull);
    });
  });

  group('多行载荷', () {
    const String tex = 'f(x)-f(x_0)\n=f(x+x_0-x_0)-f(x_0)\n=f(x-x_0)';

    test('进空行间块 ⇒ 整块内容替换（仍是一块）', () {
      final PasteDecision d = decidePaste(
        doc: _empty,
        caret: _inEmpty,
        selStart: _inEmpty,
        selEnd: _inEmpty,
        payload: tex,
      );
      expect(d.apply, PasteApply.replaceBlock);
      expect(d.payload, tex);
      expect(d.replaceFrom, 3, reason: '行间块内容起点');
      expect(d.replaceTo, 3, reason: '空块内容长度为 0');
      expect(d.note, isNotNull);
    });

    test('带围栏的多行块 ⇒ 先剥围栏再替换（不许套娃）', () {
      final PasteDecision d = decidePaste(
        doc: _empty,
        caret: _inEmpty,
        selStart: _inEmpty,
        selEnd: _inEmpty,
        payload: '\$\$\n$tex\n\$\$',
      );
      expect(d.apply, PasteApply.replaceBlock);
      expect(d.payload, tex);
    });

    test('进行内公式 ⇒ 提升成新块，落点在**本行之后**', () {
      final PasteDecision d = decidePaste(
        doc: _inline,
        caret: _inInline,
        selStart: _inInline,
        selEnd: _inInline,
        payload: tex,
      );
      expect(d.apply, PasteApply.promoteBlock);
      expect(d.payload, tex);
      expect(d.at, _inline.length, reason: '整行只有这一段，行尾 = 文末');
      expect(d.note, isNotNull);
    });

    // ★★ 2026-10-26（批 37）：多行也要归一成 tex —— 原来整块替换时把 `$` 原样塞进
    //   `$$…$$` 之间 ⇒ tex 里出现 `$` ⇒ 「公式不完整」（与单行那条是同一个病）。
    test('★ 批 37：多行「文字+公式」进行间块 ⇒ 替换时也剥 `\$`', () {
      final PasteDecision d = decidePaste(
        doc: _empty,
        caret: _inEmpty,
        selStart: _inEmpty,
        selEnd: _inEmpty,
        payload: '第一行 \$x\$\n第二行 \$y\$',
      );
      expect(d.apply, PasteApply.replaceBlock);
      expect(d.payload, '第一行 x\n第二行 y');
      expect(d.note, isNotNull);
    });

    test('★ 批 37：多行「文字+公式」进行内公式 ⇒ 提升成块时也剥 `\$`', () {
      final PasteDecision d = decidePaste(
        doc: _inline,
        caret: _inInline,
        selStart: _inInline,
        selEnd: _inInline,
        payload: '第一行 \$x\$\n第二行 \$y\$',
      );
      expect(d.apply, PasteApply.promoteBlock);
      expect(d.payload, '第一行 x\n第二行 y');
      expect(d.note, isNotNull);
    });
  });
}
