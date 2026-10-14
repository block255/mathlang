// 平台文本值 → 缓冲区编辑的换算测试（S3-1b / S3-2 地基）

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/editor/platform_text_diff.dart';
import 'package:mathlang/spike/ime_input/ime_input_page.dart';

void main() {
  group('diffPlatformText：两次平台文本值 → 一次替换', () {
    test('没变 → null', () {
      expect(diffPlatformText('abc', 'abc'), isNull);
    });

    test('中间插入一个字符', () {
      final PlatformEdit e = diffPlatformText('ac', 'abc')!;
      expect(e.start, 1);
      expect(e.end, 1);
      expect(e.removed, '');
      expect(e.inserted, 'b');
    });

    test('末尾追加', () {
      final PlatformEdit e = diffPlatformText('ab', 'abcd')!;
      expect(e.start, 2);
      expect(e.end, 2);
      expect(e.inserted, 'cd');
    });

    test('删除一段', () {
      final PlatformEdit e = diffPlatformText('abcd', 'ad')!;
      expect(e.start, 1);
      expect(e.end, 3);
      expect(e.removed, 'bc');
      expect(e.inserted, '');
    });

    test('★ IME 提交：拼音串被整段换成汉字（一次替换，不是 5 次插入）', () {
      // 「设 $x$zhong」：设=0 空格=1 $=2 x=3 $=4 z=5 → zhong = [5,10)
      final PlatformEdit e = diffPlatformText(r'设 $x$zhong', r'设 $x$中')!;
      expect(e.start, 5);
      expect(e.end, 10);
      expect(e.removed, 'zhong');
      expect(e.inserted, '中');
    });

    test('中文插入（多字节，按 UTF-16 码元计）', () {
      final PlatformEdit e = diffPlatformText(r'$x$', r'$x$为多项式')!;
      expect(e.start, 3);
      expect(e.end, 3);
      expect(e.inserted, '为多项式');
      expect(e.inserted.length, 4);
    });

    test('粘贴一大段 → 仍是一次编辑', () {
      const String pasted = r'$\frac{a}{b}=\sqrt{2}$';
      final PlatformEdit e = diffPlatformText('前后', '前$pasted后')!;
      expect(e.start, 1);
      expect(e.end, 1);
      expect(e.inserted, pasted);
      expect(e.inserted.length, pasted.length);
    });

    test('全量替换（选中全部再打字）', () {
      final PlatformEdit e = diffPlatformText('abcdef', 'xyz')!;
      expect(e.start, 0);
      expect(e.end, 6);
      expect(e.removed, 'abcdef');
      expect(e.inserted, 'xyz');
    });

    test('公共后缀不会被误当成"没变"', () {
      // a b c → a x c：前缀 1、后缀 1，中间 bb→x
      final PlatformEdit e = diffPlatformText('abbc', 'axc')!;
      expect(e.start, 1);
      expect(e.end, 3);
      expect(e.removed, 'bb');
      expect(e.inserted, 'x');
    });

    test('清空', () {
      final PlatformEdit e = diffPlatformText('abc', '')!;
      expect(e.start, 0);
      expect(e.end, 3);
      expect(e.inserted, '');
    });

    test('两空串相等 → null', () {
      expect(diffPlatformText('', ''), isNull);
    });
  });

  group('B 路端到端：平台输入 → 缓冲区（widget 测试）', () {
    testWidgets('在镜像输入框里输入中文，缓冲区跟着变（Q1 的管道验证）', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: ImeInputPage()));

      // 初始缓冲区的样子
      expect(find.textContaining(r'设 $x^2+1$ 为多项式'), findsWidgets);

      // ★ 走**平台文本输入通道**（等价于 IME 提交 / 粘贴产生的 updateEditingState）
      await tester.enterText(find.byType(TextField), '中文输入');
      await tester.pump();

      // 缓冲区（唯一真相）已更新，且日志里有记录
      expect(find.text('「中文输入」'), findsOneWidget);
      expect(find.textContaining('+「中文输入」'), findsWidgets);
      expect(find.textContaining('已收到 1 次平台编辑'), findsOneWidget);
    });

    testWidgets('纯按键事件收不到文本（对照：enterText 不走 onKeyEvent）', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: ImeInputPage()));
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();

      // A 路（按键事件）计数保持 0 —— 文本是走文本输入通道来的，不是按键
      expect(find.textContaining('按键 0 次'), findsOneWidget);
      expect(find.text('（还没有输入）'), findsOneWidget);
    });
  });
}
