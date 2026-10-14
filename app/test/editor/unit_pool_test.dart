// 数语引擎 · 单元 widget 池的不变量测试
//
// 这个池是 S2-3 实测出来的关键技术（空帧 91 ms → 2.8 ms）。
// 它只有**两条**不变量，但破一条就会出大问题，所以单独钉住。

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/editor/unit_pool.dart';

void main() {
  test('跨帧同 key → 复用同一个实例（这就是缓存的全部意义）', () {
    final p = UnitPool();
    p.beginFrame();
    final Widget a = p.widgetFor('k', () => Text('x'));
    p.endFrame();

    p.beginFrame();
    final Widget b = p.widgetFor('k', () => Text('x'));
    p.endFrame();

    expect(identical(a, b), isTrue,
        reason: 'Element.updateChild 靠"同一个实例"才肯整棵子树跳过');
  });

  test('★ 同帧内同 key 出现两次 → 必须给出两个不同实例', () {
    final p = UnitPool();
    p.beginFrame();
    final Widget a = p.widgetFor('k', () => Text('x'));
    final Widget b = p.widgetFor('k', () => Text('x'));
    p.endFrame();

    expect(identical(a, b), isFalse,
        reason: '同一个 widget 实例放到树的两个位置会抛 "Multiple widgets used the same '
            'GlobalKey" —— flutter_math_fork 会把 Line(key: GlobalKey) 这个 widget 记忆化');
  });

  test('同帧第二次出现不入池（不污染缓存）', () {
    final p = UnitPool();
    p.beginFrame();
    final Widget a = p.widgetFor('k', () => Text('x'));
    p.widgetFor('k', () => Text('y')); // 第二次 → 新建、不入池
    p.endFrame();

    p.beginFrame();
    final Widget c = p.widgetFor('k', () => Text('z'));
    p.endFrame();

    expect(identical(a, c), isTrue, reason: '池里仍然是第一次那个实例');
  });

  test('endFrame 丢掉本帧没用到的实例（池子不随历史无限增长）', () {
    final p = UnitPool();
    p.beginFrame();
    p.widgetFor('a', () => Text('a'));
    p.widgetFor('b', () => Text('b'));
    p.endFrame();
    expect(p.size, 2);

    p.beginFrame();
    p.widgetFor('a', () => Text('a'));
    p.endFrame();
    expect(p.size, 1, reason: 'b 这一帧没用到 → 丢掉');
  });

  test('内容变了 → key 变了 → 老老实实新建', () {
    final p = UnitPool();
    p.beginFrame();
    final Widget a = p.widgetFor('段落|甲', () => Text('甲'));
    p.endFrame();

    p.beginFrame();
    final Widget b = p.widgetFor('段落|乙', () => Text('乙'));
    p.endFrame();

    expect(identical(a, b), isFalse);
  });
}
