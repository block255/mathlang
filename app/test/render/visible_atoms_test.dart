import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/visible_atoms.dart';

void main() {
  group('可见原子扫描器（源偏移的唯一正确来源）', () {
    test('单字符各自成一个原子', () {
      final a = lexVisibleAtoms('a+b');
      expect(a.length, 3);
      expect(a[0].kind, 'a');
      expect(a[1].kind, '+');
      expect(a[2].kind, 'b');
    });

    test('★ 结构命令本身不是原子，由它的参数贡献', () {
      final a = lexVisibleAtoms(r'\frac{a}{b}');
      expect(a.length, 2);
      expect(a[0].start, 6);
      expect(a[0].end, 7);
      expect(a[1].start, 9);
      expect(a[1].end, 10);
    });

    test('符号命令算一个原子', () {
      final a = lexVisibleAtoms(r'\alpha+\beta');
      expect(a.length, 3);
      expect(a[0].kind, r'\alpha');
      expect(a[0].start, 0);
      expect(a[0].end, 6);
      expect(a[2].kind, r'\beta');
    });

    test('{} ^ _ & 空格 与换行都被跳过', () {
      final a = lexVisibleAtoms(r'x^{2}_{1} & \\ y');
      expect(a.map((v) => v.kind).join(','), 'x,2,1,y');
    });

    test('★ 给出的是真正的源码下标（引擎的 range 不是）', () {
      final a = lexVisibleAtoms(r'\frac{a}{b}=\sqrt{2}');
      expect(a.map((v) => '${v.start}').join(','), '6,9,11,18');
    });

    test('空 tex', () {
      expect(lexVisibleAtoms(''), isEmpty);
    });
  });
}
