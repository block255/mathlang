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
}