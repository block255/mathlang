import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/editor/blank_runs.dart';

void main() {
  test('blankRunAfter', () {
    // 甲\n\n乙  ⇒ acceptTo(甲)=1，空行 [2]
    expect(blankRunAfter('甲\n\n乙', 1), <int>[2]);
    // 甲\n\n\n乙 ⇒ 空行 [2,3]
    expect(blankRunAfter('甲\n\n\n乙', 1), <int>[2, 3]);
    // 甲\n\n\n\n乙 ⇒ 空行 [2,3,4]
    expect(blankRunAfter('甲\n\n\n\n乙', 1), <int>[2, 3, 4]);
    // 文首
    expect(blankRunFrom('\n甲', 0), <int>[0]);
    expect(blankRunFrom('\n\n甲', 0), <int>[0, 1]);
    expect(blankRunFrom('甲', 0), isEmpty);
    // 高度
    expect(extraBlankHeight(1, lineHeight: 20), 0);
    expect(extraBlankHeight(2, lineHeight: 20), 20);
    expect(extraBlankHeight(3, lineHeight: 20), 40);
    expect(leadingBlankHeight(2, lineHeight: 20), 40);
  });

  // ★★★ 2026-11-04（用户拍板「甲」）：**只有长度 0 的行才是空行**。
  //   改前用 `trim()`，于是"打了空格的行"仍算空行 ⇒ 走空行槽（不排版）
  //   ⇒ 空行槽只在"光标 == 行首"画竖条 ⇒ **在空行里打空格，竖条当场消失**
  //   （用户实测："打空格光标没了，但空格确实在推进"）。
  //   改前必红：下面 ①②。
  group('甲 · 含空格的行 = 普通段落（不算空行）', () {
    test('① 只有空格的行 ⇒ 空行串在它这里断掉', () {
      // 甲⏎"   "⏎⏎乙 ：第一个换行之后那行是空格行 ⇒ 不是空行
      expect(blankRunAfter('甲\n   \n\n乙', 1), isEmpty,
          reason: '改前：空格行仍算空行 ⇒ 返回 [2, 5]');
    });

    test('② 空格行之后那条真空行 ⇒ 从它重新起算', () {
      expect(blankRunAfter('甲\n   \n\n乙', 5), <int>[6]);
    });

    test('③ 空行（长度 0）仍需照旧算进空行串', () {
      expect(blankRunAfter('甲\n\n乙', 1), <int>[2]);
      expect(blankRunFrom('   \n甲', 0), isEmpty, reason: '文首空格行也不是空行');
    });
  });
}
