// 2026-11-13 反馈 ②：**粘贴的块语义**（纯函数）。
//
// 定稿（本批）：
//   · 单块（分行格式）粘进行内 ⇒ 剥围栏 + 换行压空格 ⇒ **行内 tex**（不再提升成块）；
//   · ≥2 块 ⇒ `blocks`：按块序列落到本行之后；
//   · 单块粘进行间块 ⇒ 仍是"整块内容替换"（老行为不许改坏）；
//   · 普通多行文本粘进行内 ⇒ 仍是 `promoteBlock`（不是块，不许压成一行塞进公式）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/paste_context.dart';

const String _inline = r'前 $x+y$ 后';
int get _caret => _inline.indexOf('x');

/// 拼一个分行格式的行间块（`$$` 独占两行）。
String _block(String tex) => '${r'$$'}\n$tex\n${r'$$'}';

PasteDecision _decide(String payload) => decidePaste(
      doc: _inline,
      caret: _caret,
      selStart: _caret,
      selEnd: _caret,
      payload: payload,
    );

void main() {
  test('单块（分行格式）粘进行内 ⇒ mathTex，载荷单行', () {
    final PasteDecision d = _decide(_block('f(x)=x'));
    expect(d.apply, PasteApply.mathTex);
    expect(d.payload, 'f(x)=x');
    expect(d.payload.contains('\n'), isFalse);
  });

  test('aligned 单块粘进行内 ⇒ 压成单行（\\ 保留）', () {
    final PasteDecision d =
        _decide(_block(r'\begin{aligned}a&=b\\c&=d\end{aligned}'));
    expect(d.apply, PasteApply.mathTex);
    expect(d.payload, r'\begin{aligned}a&=b\\c&=d\end{aligned}');
  });

  test('两块粘进行内 ⇒ blocks，落点在本行之后', () {
    final PasteDecision d = _decide('${_block('A=1')}\n\n${_block('B=2')}');
    expect(d.apply, PasteApply.blocks);
    expect(d.payload.contains(r'$$'), isTrue);
    expect(d.at, _inline.length);
  });

  test('单块粘进行间块 ⇒ 仍是整块内容替换（老行为）', () {
    final String doc = '${_block('')}\n';
    final PasteDecision d = decidePaste(
      doc: doc,
      caret: 3,
      selStart: 3,
      selEnd: 3,
      payload: _block('f(x)=x'),
    );
    expect(d.apply, PasteApply.replaceBlock);
    expect(d.payload, 'f(x)=x');
  });

  test('普通多行文本粘进行内 ⇒ 仍是 promoteBlock（不许压成一行塞进公式）', () {
    final PasteDecision d = _decide('第一行\n第二行');
    expect(d.apply, PasteApply.promoteBlock);
  });
}
