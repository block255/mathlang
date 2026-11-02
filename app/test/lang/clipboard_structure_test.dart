// ★★ 2026-11-02（选择边界与剪贴板批）：**复制的片段必须结构完整**。
//
// 口径（讨论定稿，`notes/handover/20261102-选择边界与剪贴板.md` §3.1）：
//   完整 = 壳有主 + 命令参数齐 + 环境成对。
//   「在对象内部」≠「切开了对象」：选 `a1` 在根号里但没碰壳 ⇒ 不扩。
//
// 改前红（2026-11-02 实测）：
//   · `$x]{a_{1}}+…$`（`\sqrt[` 丢了）
//   · `${\sqrt…}{2020}$`（`\frac` 丢了）
//   · `$…\end{cases}$`（孤立 `\end`）
// 本文件第 1 组在旧实现上三条都红；第 3 组全域在旧实现上红一大片。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/clipboard_slice.dart';
import 'package:mathlang/lang/math_spans.dart';
import 'package:mathlang/lang/tex_structure.dart';

const String _userDoc =
    r'11.求极限 $\lim_{x\to+\infty}$ ( $\frac{\sqrt[x]{a_{1}}+\sqrt[x]{a_{2}}}{2}$ ) $^{x}$ ,其中…';

int _dollars(String s) => s.split(r'$').length - 1;

/// 片段里没有任何"开启者在选区外"的壳。
void _expectNoOrphan(String doc, ClipboardSlice sl, String label) {
  final int? owner = orphanOwnerBefore(doc, sl.start, sl.end);
  expect(owner, isNull,
      reason: '$label：选区 [${sl.start},${sl.end}) 仍有缺主人的壳 '
          '（主人 @$owner）⇒ 片段「${sl.text}」');
}

/// 切片正好是某个数学段的**全部内容** ⇒ 源本身就这样，复制不可能更好。
///
/// 用户文档里有一处 `$^{x}$`（游离的上标，base 在围栏外）——那种源内容本来就
/// 不是"结构完整"的；复制只能原样带走整段，不能凭空补一个 base。
bool _isWholeSpanContent(String doc, int s, int e) {
  for (final MathSpan sp in scanMathSpans(doc)) {
    final int pad = sp.display ? 2 : 1;
    if (s == sp.start + pad && e == sp.end - pad) return true;
  }
  return false;
}

void main() {
  group('★ 用户现场（2026-11-01 23:5x）', () {
    test(r'① 起点在 \sqrt[x] 的次数上 ⇒ 不许丢 \sqrt[', () {
      final int s = _userDoc.indexOf('x', _userDoc.indexOf(r'\sqrt['));
      final int e = _userDoc.indexOf('}', _userDoc.indexOf(r'a_{2}')) + 1;
      final ClipboardSlice sl = clipboardSlice(_userDoc, s, e);
      expect(sl.text, contains(r'\sqrt['), reason: sl.text);
      expect(sl.text, isNot(contains(r']$')), reason: sl.text);
      expect(sl.text, r'$\sqrt[x]{a_{1}}+\sqrt[x]{a_{2}}$');
      _expectNoOrphan(_userDoc, sl, '①');
      expect(isCompleteFragment(_userDoc.substring(sl.start, sl.end)), isTrue);
    });

    test(r'② 起点在分子参数 { 上、终点到分母 ⇒ 不许丢 \frac', () {
      final int s = _userDoc.indexOf('{', _userDoc.indexOf(r'\frac'));
      final int e = _userDoc.indexOf('2', _userDoc.indexOf(r'}{')) + 1;
      final ClipboardSlice sl = clipboardSlice(_userDoc, s, e);
      expect(sl.text, contains(r'\frac'), reason: sl.text);
      expect(sl.text,
          r'$\frac{\sqrt[x]{a_{1}}+\sqrt[x]{a_{2}}}{2}$');
      _expectNoOrphan(_userDoc, sl, '②');
      expect(isCompleteFragment(_userDoc.substring(sl.start, sl.end)), isTrue);
    });

    test(r'③ 从环境内部起选 ⇒ 不许留孤立的 \end{cases}', () {
      const String doc = '\$\$\n\\begin{cases}x=1\\\\y=2\\end{cases}\n\$\$';
      final int s = doc.indexOf('x=1');
      final int e = doc.indexOf(r'\end{cases}') + r'\end{cases}'.length;
      final ClipboardSlice sl = clipboardSlice(doc, s, e);
      expect(sl.text, contains(r'\begin{cases}'), reason: sl.text);
      expect(sl.text, contains(r'\end{cases}'), reason: sl.text);
      _expectNoOrphan(doc, sl, '③');
      expect(isCompleteFragment(doc.substring(sl.start, sl.end)), isTrue);
    });
  });

  group('★ 不扩到不想选的地方（用户校准）', () {
    test(r'根号参数里的一个字 ⇒ 只复制那个字', () {
      const String doc = r'$\frac{\sqrt[x]{a_{1}}+\sqrt[x]{a_{2}}}{2}$';
      final int s = doc.indexOf(r'\sqrt[x]{a_{1}}') + r'\sqrt[x]{'.length;
      final int e = s + 1; // `a`
      final ClipboardSlice sl = clipboardSlice(doc, s, e);
      expect(sl.text, r'$a$', reason: sl.text);
    });

    test(r'括号里的平方和 ⇒ 不带括号、不带左边', () {
      const String doc = r'$asint(cos^2t+sin^2t)=asint$';
      final int s = doc.indexOf('cos^2t');
      final int e = doc.indexOf(')=asint');
      final ClipboardSlice sl = clipboardSlice(doc, s, e);
      expect(sl.text, r'$cos^2t+sin^2t$', reason: sl.text);
    });

    test(r'整个分子 ⇒ 不带 \frac 壳', () {
      const String doc = r'$\frac{\sqrt[x]{a_{1}}+\sqrt[x]{a_{2}}}{2}$';
      final int s = doc.indexOf(r'\sqrt');
      final int e = doc.indexOf('}{2}');
      final ClipboardSlice sl = clipboardSlice(doc, s, e);
      expect(sl.text, r'$\sqrt[x]{a_{1}}+\sqrt[x]{a_{2}}$', reason: sl.text);
    });
  });

  group('★ 全域：每个 (i,j) 的片段都必须结构完整', () {
    test('8 份语料 × 每一个 (i, j)', () {
      const List<String> docs = <String>[
        _userDoc,
        r'设 $a^2+b^2=c^2$ 成立，其中 $a,b,c$ 为正',
        '\$\$\n\\frac{x}{y} = z\n\$\$',
        r'前 $\sqrt{2}$ 后 $\frac{a}{b}$ 尾',
        r'纯文字，一个公式都没有',
        r'$\frac{a}{b}+x$',
        r'$\sqrt[x]{a_1}+\sqrt[x]{a_2}$',
        '\$\$\n\\begin{cases}x=1\\\\y=2\\end{cases}\n\$\$',
      ];
      for (final String doc in docs) {
        for (var i = 0; i <= doc.length; i++) {
          for (var j = i; j <= doc.length; j++) {
            final ClipboardSlice sl = clipboardSlice(doc, i, j);
            final String label = '选区 ($i,$j)';
            expect(sl.start, lessThanOrEqualTo(sl.end), reason: label);
            _expectNoOrphan(doc, sl, label);
            if (!_isWholeSpanContent(doc, sl.start, sl.end)) {
              expect(isCompleteFragment(doc.substring(sl.start, sl.end)), isTrue,
                  reason: '$label：片段「${sl.text}」结构不完整');
            }
            expect(_dollars(sl.text).isEven, isTrue,
                reason: '$label：奇数个 `\$`：${sl.text}');
            if (!sl.wrapped) {
              expect(sl.text, doc.substring(sl.start, sl.end), reason: label);
            }
          }
        }
      }
    });
  });
}
