// ③-B：**字形之外的落点**（§5.2 归属表的直译）
//
// 用户实测 ①：「点分式右侧的空白，光标会落到分子 / 分母后面」——
// 根因是 `hitTestMathTex` 的兜底是"**几何最近的字形盒**"，在装饰区里最近的是分母。
//
// 本条要求：
//   · 点在**结构盒内**、但不在字形上（分数线 / 根号横 / 括号…）⇒ 归**该结构那一层**：
//       左半 ⇒ 结构之前、右半 ⇒ 结构之后（§5.2）
//   · 点在**所有结构盒之外** ⇒ 字形并集右侧 = 公式之后（tex 末尾）、左侧 = 公式之前（0）
//   · 两者都不是 ⇒ `null`（交回行级落点，③-A 已经让"行末之后的空白"落到行末）

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/render/structure_geometry.dart';

StructureObject _obj(StructureKind kind, int start, int end) => StructureObject(
      kind: kind,
      command: kind.name,
      start: start,
      end: end,
      nodeBacked: true,
    );

void main() {
  // 一个"分式在 (10,0)-(60,30)"、字形并集在 (10,0)-(60,30) 的最小场景
  final StructureObject frac = _obj(StructureKind.frac, 8, 18);
  final List<StructureObject> objects = <StructureObject>[frac];
  final List<Rect?> rects = <Rect?>[const Rect.fromLTRB(10, 0, 60, 30)];
  const Rect hull = Rect.fromLTRB(10, 0, 60, 30);
  const int texLength = 18;

  group('① 结构盒内、字形之外 ⇒ 归该结构那一层', () {
    test('左半 ⇒ **结构之前**（= 结构的 start）', () {
      // x=20 在分式盒 (10..60) 的左半；y=15 不是字形（装饰带）
      expect(
        glyphlessLanding(
          objects: objects,
          rects: rects,
          glyphHull: hull,
          localPos: const Offset(20, 15),
          texLength: texLength,
        ),
        8,
      );
    });

    test('右半 ⇒ **结构之后**（= 结构的 end）', () {
      expect(
        glyphlessLanding(
          objects: objects,
          rects: rects,
          glyphHull: hull,
          localPos: const Offset(50, 15),
          texLength: texLength,
        ),
        18,
      );
    });

    test('★ 嵌套 ⇒ 取**最内层**（面积最小）那个结构', () {
      final StructureObject inner = _obj(StructureKind.sqrt, 11, 15);
      final int? land = glyphlessLanding(
        objects: <StructureObject>[frac, inner],
        rects: <Rect?>[
          const Rect.fromLTRB(10, 0, 60, 30),
          const Rect.fromLTRB(30, 5, 50, 25),
        ],
        glyphHull: hull,
        localPos: const Offset(45, 15), // 内层右半
        texLength: texLength,
      );
      expect(land, 15, reason: '应当归内层根号的 end，而不是外层分式的 end');
    });
  });

  group('② 所有结构盒之外 ⇒ 公式之前 / 之后', () {
    test('字形并集右侧 ⇒ **texLength**（公式之后）', () {
      expect(
        glyphlessLanding(
          objects: objects,
          rects: rects,
          glyphHull: hull,
          localPos: const Offset(80, 15),
          texLength: texLength,
        ),
        texLength,
      );
    });

    test('字形并集左侧 ⇒ **0**（公式之前）', () {
      expect(
        glyphlessLanding(
          objects: objects,
          rects: rects,
          glyphHull: hull,
          localPos: const Offset(0, 15),
          texLength: texLength,
        ),
        0,
      );
    });
  });

  group('③ 什么都不沾 ⇒ null（交回行级落点）', () {
    test('结构化零个 + 没有字形并集', () {
      expect(
        glyphlessLanding(
          objects: const <StructureObject>[],
          rects: const <Rect?>[],
          glyphHull: null,
          localPos: const Offset(80, 15),
          texLength: texLength,
        ),
        isNull,
      );
    });

    test('★ 纵向错开（行间块的上下留白）⇒ null', () {
      expect(
        glyphlessLanding(
          objects: objects,
          rects: rects,
          glyphHull: hull,
          localPos: const Offset(35, 90), // 与并集纵向不重叠
          texLength: texLength,
        ),
        isNull,
      );
    });
  });
}
