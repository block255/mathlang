// 实验台入口冒烟测试。
//
// 注意：这里是**测试台**，不是产品界面 —— 只验证入口能起来、第一个入口项在。
// 产品级（A4 页面 / 分页）的测试在 S2-4 之后补。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/main.dart';

void main() {
  testWidgets('实验台入口可以起来', (WidgetTester tester) async {
    await tester.pumpWidget(const MathlangApp());
    expect(find.text('★ 问 0 · 流内数学映射可行性'), findsOneWidget);
  });
}
