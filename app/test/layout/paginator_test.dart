import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/layout/paginator.dart';

FlowItem item(String id, double h,
        {double gap = 0, bool brk = false, String? label}) =>
    FlowItem(
        id: id, height: h, leadingGap: gap, breakBefore: brk, label: label);

void main() {
  test('基本装箱：高 300 的三个 item，页正文 700 → 2 + 1', () {
    final r = paginate(
      items: <FlowItem>[item('a', 300), item('b', 300), item('c', 300)],
      bodyHeight: 700,
    );
    expect(r.pageCount, 2);
    expect(r.pages[0].map((s) => s.item.id).toList(), <String>['a', 'b']);
    expect(r.pages[1].map((s) => s.item.id).toList(), <String>['c']);
    expect(r.pages[0][0].y, 0);
    expect(r.pages[0][1].y, 300);
    expect(r.pages[1][0].y, 0); // 新页从 0 开始
    expect(r.overflow, isEmpty);
  });

  test('正好放下不算溢出（边界）', () {
    final r = paginate(
      items: <FlowItem>[item('a', 350), item('b', 350)],
      bodyHeight: 700,
    );
    expect(r.pageCount, 1);
  });

  test('★ 块间距在页首丢弃（与 Word 一致）', () {
    final r = paginate(
      items: <FlowItem>[
        item('a', 400, gap: 0),
        item('b', 280, gap: 20), // 400+20+280 = 700 → 正好放下
        item('c', 400, gap: 20), // 放不下 → 换页，且页首不留 20
      ],
      bodyHeight: 700,
    );
    expect(r.pageCount, 2);
    expect(r.pages[0].length, 2);
    expect(r.pages[1][0].y, 0, reason: '页首不留段前距');
  });

  test('同页内块间距计入 y', () {
    final r = paginate(
      items: <FlowItem>[item('a', 100, gap: 0), item('b', 100, gap: 30)],
      bodyHeight: 700,
    );
    expect(r.pages[0][1].y, 130);
  });

  test('★ 分页符强制换页（breakBefore）', () {
    final r = paginate(
      items: <FlowItem>[
        item('a', 100),
        item('b', 100, brk: true),
        item('c', 100),
      ],
      bodyHeight: 700,
    );
    expect(r.pageCount, 2);
    expect(r.pages[0].map((s) => s.item.id).toList(), <String>['a']);
    expect(r.pages[1].map((s) => s.item.id).toList(), <String>['b', 'c']);
  });

  test('breakBefore 落在页首时不产生空页', () {
    final r = paginate(
      items: <FlowItem>[item('a', 100), item('b', 700, brk: true)],
      bodyHeight: 700,
    );
    // b 正好满一页；虽然它要求换页，但 a 之后本来就要换
    expect(r.pageCount, 2);
    expect(r.pages[1].single.item.id, 'b');
  });

  test('★ 高于一页的 item：不切断，单独占页 + 记入告警', () {
    final r = paginate(
      items: <FlowItem>[
        item('a', 100),
        item('big', 1200, label: '公式块'),
        item('c', 100),
      ],
      bodyHeight: 700,
    );
    expect(r.overflow.length, 1);
    expect(r.overflow.single.id, 'big');
    expect(r.overflow.single.label, '公式块');
    expect(r.pageCount, 3);
    expect(r.pages[1].single.item.id, 'big');
    expect(r.pages[1].single.y, 0);
    expect(r.pages[2].single.item.id, 'c');
  });

  test('空文档也给一页', () {
    final r = paginate(items: <FlowItem>[], bodyHeight: 700);
    expect(r.pageCount, 1);
    expect(r.pages.single, isEmpty);
  });

  test('页正文高必须为正', () {
    expect(() => paginate(items: <FlowItem>[], bodyHeight: 0),
        throwsArgumentError);
  });

  test('顺序与 y 单调递增', () {
    final items = <FlowItem>[
      for (var i = 0; i < 20; i++) item('i$i', 90, gap: 10),
    ];
    final r = paginate(items: items, bodyHeight: 700);
    final seen = <String>[];
    for (final pg in r.pages) {
      var lastY = -1.0;
      for (final s in pg) {
        expect(s.y, greaterThanOrEqualTo(lastY));
        lastY = s.y;
        seen.add(s.item.id);
      }
    }
    expect(seen.length, 20);
    expect(seen.toSet().length, 20, reason: '不能重复也不能丢');
  });
}
