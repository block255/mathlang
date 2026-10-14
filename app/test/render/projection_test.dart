import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/projection.dart';

void main() {
  group('paragraphIndexMap：段落坐标 → 源坐标（S3-2 点屏幕定位）', () {
    test('纯文字：一一对应', () {
      expect(paragraphIndexMap('abc'), <int>[0, 1, 2, 3]);
    });

    test('数学段在段落里只占 1 个码元（U+FFFC），必须换算', () {
      // 源 `a$x$b`（5 字符）→ 段落 `a␣b`（3 个码元）
      const String src = r'a$x$b';
      final List<int> m = paragraphIndexMap(src);
      expect(m.length, 4, reason: '段落只有 3 个码元 + 1');
      expect(m[0], 0);
      expect(m[1], 1, reason: r"'a' 之后就是那个定界符的位置");
      expect(m[2], 4, reason: r'公式占位符之后 = 整个 $x$ 之后');
      expect(m[3], 5);
    });

    test('两个公式之间的文字不偏位（误差不能累积）', () {
      const String src = r'设 $x^2+1$ 为多项式，$\frac{a}{b}=\sqrt{2}$ 为常数。';
      final List<int> m = paragraphIndexMap(src);
      final int textLen = src.replaceAll(RegExp(r'\$[^$]*\$'), '').length;
      final int mathCount = RegExp(r'\$[^$]*\$').allMatches(src).length;
      expect(m.length, textLen + mathCount + 1);
      expect(m.last, src.length, reason: '表尾必须等于源长度');
    });

    test(r'未闭合的定界符 → 余下全是文字（打字中间态）', () {
      expect(paragraphIndexMap(r'a$b'), <int>[0, 1, 2, 3]);
    });

    test('表非递减（光标映射不能回退）', () {
      for (final String src in <String>[
        'abc',
        r'a$x$b',
        r'$x$',
        r'设 $x^2+1$ 为多项式，$\frac{a}{b}=\sqrt{2}$ 为常数。',
      ]) {
        final List<int> m = paragraphIndexMap(src);
        for (var i = 1; i < m.length; i++) {
          expect(m[i], greaterThanOrEqualTo(m[i - 1]), reason: '$src @$i');
        }
      }
    });
  });
  group('caretParagraphOffset / mathPlaceholderAt（S3-2 光标像素定位）', () {
    test('纯文字：段落下标 = 相对偏移', () {
      expect(caretParagraphOffset('abcdef', 3), 3);
      expect(caretParagraphOffset('abcdef', 0), 0);
      expect(caretParagraphOffset('abcdef', 6), 6);
    });

    test('文字 + 公式：公式在段落里占 1 格，后续文字要补偿', () {
      // 源 `ab$x$cd`：段落 = a b ␣ c d（5 格）
      const String src = r'ab$x$cd';
      expect(caretParagraphOffset(src, 0), 0); // a 之前
      expect(caretParagraphOffset(src, 2), 2); // b 之后 = 公式之前
      expect(caretParagraphOffset(src, 5), 3); // c 之前（公式占掉 1 格）
      expect(caretParagraphOffset(src, 6), 4); // d 之前
      expect(caretParagraphOffset(src, 7), 5); // 全段之后
    });

    test(r'光标在数学段里 → caretParagraphOffset 返回 null（那是另一套机制）', () {
      const String src = r'ab$x$cd';
      expect(caretParagraphOffset(src, 4), isNull); // $x$ 内部
      expect(mathPlaceholderAt(src, 4), 2, reason: '数学段在段落里的下标是 2');
    });

    test(r'mathPlaceholderAt：不在公式附近则为 null', () {
      const String src = r'ab$x$cd';
      expect(mathPlaceholderAt(src, 0), isNull);
      expect(mathPlaceholderAt(src, 7), isNull);
    });
  });

  group('行内投影分段', () {
    test('纯文字', () {
      final segs = projectInline('没有公式');
      expect(segs.length, 1);
      expect(segs.single.isMath, isFalse);
      expect(segs.single.text, '没有公式');
    });

    test('文字 + 公式 + 文字', () {
      final segs = projectInline(r'a$x^2$b');
      expect(segs.length, 3);
      expect(segs[0].text, 'a');
      expect(segs[1].isMath, isTrue);
      expect(segs[1].tex, 'x^2');
      expect(segs[2].text, 'b');
    });

    test('★ 段内偏移是相对 source 的（调用方再加 baseOffset）', () {
      final segs = projectInline(r'ab$cd$ef');
      final math = segs.firstWhere((s) => s.isMath);
      expect(math.start, 3); // 'ab$' 之后才是 tex
      expect(math.end, 5);
      expect(segs.last.start, 6);
    });

    test(r'★ 未闭合的 $ 当普通文字（打字过程中它是常态，不能报错）', () {
      final segs = projectInline(r'a$b');
      expect(segs.length, 1);
      expect(segs.single.isMath, isFalse);
      expect(segs.single.text, r'a$b');
    });

    test('多个公式', () {
      final segs = projectInline(r'$a$ 与 $b$');
      expect(segs.where((s) => s.isMath).length, 2);
      expect(
        segs.where((s) => !s.isMath).map((s) => s.text).join(),
        ' 与 ',
      );
    });

    test('空 source', () {
      expect(projectInline(''), isEmpty);
    });
  });

  // 旧的 `snapCaretInTex`（只防切开命令名）已删除：注入光标一律走
  // `caret_sites.dart` 的位点表 + `injectCursor()`，它的单测在 caret_sites_test.dart 里。
}
