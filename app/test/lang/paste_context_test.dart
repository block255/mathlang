// ★★ 2026-10-23（批 1）：**跨语境粘贴**的归一规则（纯 Dart）。
//
// 口径（用户 2026-10-23 拍板，见 `notes\design\剪贴板与跨语境粘贴.md` §五）：
//   · 目标在**数学里**（行内 / 行间 / 任何结构槽）⇒ 剥掉外层定界符，只插 tex；
//   · 纯文字照插（与"公式内打中文"同口径：实测 `x+中文+y` 与 `x+\text{中文}+y` 逐像素同尺寸）；
//   · 多行进**行间块** ⇒ 整块内容替换；多行进**行内公式** ⇒ 提升成新块放到本行之后；
//   · 混合文本（里面还夹着 `$…$`）塞不进公式 ⇒ 推到公式之后 ＋ 状态栏说明。
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

    test('混合文本（里面夹 `\$…\$`）⇒ 推到公式之后 + 有说明', () {
      final PasteDecision d = decidePaste(
        doc: _inline,
        caret: _inInline,
        selStart: _inInline,
        selEnd: _inInline,
        payload: r'见 $a$ 式',
      );
      expect(d.apply, PasteApply.pushOut);
      expect(d.at, _inline.lastIndexOf(r'$') + 1, reason: '落点 = 公式之后');
      expect(d.note, isNotNull, reason: '不许静默');
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
  });
}
