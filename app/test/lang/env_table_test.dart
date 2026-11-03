// 2026-11-03「表」批：**源码级单元格模型**（`lang/env_table.dart`）。
//
// 这一层只量源码，不碰渲染：`&` 切列、`\\` 切行、区间是真的源码区间。
// 口径见 `notes/handover/20261102-选择边界与剪贴板.md` §3.2 / §3.6。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/env_table.dart';

import 'table_test_pos.dart';

const String _pm = r'\begin{pmatrix}a&b\\c&d\end{pmatrix}';
const String _vm = r'\begin{vmatrix}a&b&c\\d&e&f\\g&h&i\end{vmatrix}';

String _cell(String tex, EnvTable t, int r, int c) =>
    tex.substring(t.rows[r][c].start, t.rows[r][c].end).trim();

void main() {
  group('切格', () {
    test('2×2：四格、区间与整段原文对得上', () {
      final List<EnvTable> ts = envTablesIn(_pm);
      expect(ts.length, 1);
      final EnvTable t = ts.single;
      expect(t.name, 'pmatrix');
      expect(t.kind, EnvKind.matrix);
      expect(t.rowCount, 2);
      expect(t.maxCols, 2);
      expect(t.textOf(_pm), _pm);
      expect(_cell(_pm, t, 0, 0), 'a');
      expect(_cell(_pm, t, 0, 1), 'b');
      expect(_cell(_pm, t, 1, 0), 'c');
      expect(_cell(_pm, t, 1, 1), 'd');
    });

    test('参差行（外部文档）：行 0 两格、行 1 一格', () {
      const String tex = r'\begin{bmatrix}a&b\\c\end{bmatrix}';
      final EnvTable t = envTablesIn(tex).single;
      expect(t.rowCount, 2);
      expect(t.rows[0].length, 2);
      expect(t.rows[1].length, 1);
      expect(t.maxCols, 2);
      expect(_cell(tex, t, 1, 0), 'c');
    });

    test(r'`{}` 里的 `&` 不是分隔符', () {
      const String tex = r'\begin{bmatrix}\text{a&b}&c\end{bmatrix}';
      final EnvTable t = envTablesIn(tex).single;
      expect(t.rows[0].length, 2);
      expect(_cell(tex, t, 0, 0), r'\text{a&b}');
    });

    test(r'转义 `\&` 不是分隔符', () {
      const String tex = r'\begin{bmatrix}a\&b&c\end{bmatrix}';
      final EnvTable t = envTablesIn(tex).single;
      expect(t.rows[0].length, 2);
      expect(_cell(tex, t, 0, 0), r'a\&b');
      expect(_cell(tex, t, 0, 1), 'c');
    });

    test('嵌套：cases 里套 bmatrix ⇒ 两张表；按偏移取最内层', () {
      const String tex = r'\begin{cases}\begin{bmatrix}1&2\end{bmatrix}\\x\end{cases}';
      final List<EnvTable> ts = envTablesIn(tex);
      expect(ts.length, 2);
      final int innerAt = tex.indexOf('1');
      expect(envTableAt(tex, innerAt)?.name, 'bmatrix');
      expect(envTableAt(tex, tex.indexOf('x'))?.name, 'cases');
      // 外层不会被内层的 `&` 切错列
      final EnvTable outer = ts.firstWhere((EnvTable t) => t.name == 'cases');
      expect(outer.rowCount, 2);
      expect(outer.rows[0].length, 1);
    });

    test(r'行单位：`cases` / `aligned` 认成 rows 类', () {
      const String tex = r'\begin{aligned}&=1\\&=2\end{aligned}';
      final EnvTable t = envTablesIn(tex).single;
      expect(t.kind, EnvKind.rows);
      expect(t.rowCount, 2);
      expect(t.rows[0].length, 2);
    });
  });

  group('选区 → 带（沿流，不是外接矩形）', () {
    test('a→c（跨两行）⇒ 带 = (0,0)..(1,0)，不是 2×2 外接矩形', () {
      final EnvTable t = envTablesIn(_pm).single;
      final int s = cellPos(_pm, 'a');
      final int e = cellPos(_pm, 'c') + 1;
      final CellSpan r = cellsSpanning(t, s, e)!;
      expect(r, (r0: 0, c0: 0, r1: 1, c1: 0));
    });

    test('压在一格中间：单格', () {
      final EnvTable t = envTablesIn(_pm).single;
      final int s = cellPos(_pm, 'd');
      final CellSpan r = cellsSpanning(t, s, s + 1)!;
      expect(r, (r0: 1, c0: 1, r1: 1, c1: 1));
    });

    test('压到分隔符上：归最近一格', () {
      final EnvTable t = envTablesIn(_pm).single;
      final int amp = _pm.indexOf('&');
      final CellSpan r = cellsSpanning(t, amp, amp + 1)!;
      expect(r.r0, 0);
    });

    test('整表覆盖 vs 局部', () {
      final EnvTable t = envTablesIn(_pm).single;
      expect(
        coversAllCells(t, (r0: 0, c0: 0, r1: 1, c1: 1)),
        isTrue,
      );
      expect(
        coversAllCells(t, (r0: 0, c0: 0, r1: 0, c1: 1)),
        isFalse,
      );
    });
  });

  group('载荷', () {
    test('局部 ⇒ 中性 bmatrix；整表 ⇒ 保留原类型', () {
      final EnvTable t = envTablesIn(_pm).single;
      expect(
        cellsPayload(t, _pm, (r0: 0, c0: 0, r1: 0, c1: 1)),
        r'\begin{matrix}a&b\end{matrix}',
      );
      expect(
        cellsPayload(t, _pm, (r0: 0, c0: 0, r1: 1, c1: 1)),
        _pm,
      );
    });

    test('行列式的局部块 ⇒ bmatrix（局部块不是方阵）', () {
      final EnvTable t = envTablesIn(_vm).single;
      expect(
        cellsPayload(t, _vm, (r0: 0, c0: 0, r1: 1, c1: 2)),
        r'\begin{matrix}a&b&c\\d&e&f\end{matrix}',
      );
      // 整张行列式 ⇒ 还是 vmatrix
      expect(
        cellsPayload(t, _vm, (r0: 0, c0: 0, r1: 2, c1: 2)),
        _vm,
      );
    });

    test('行单位：取整行，壳沿用原类型', () {
      const String cases = r'\begin{cases}a\\b\\c\end{cases}';
      final EnvTable t = envTablesIn(cases).single;
      expect(
        cellsPayload(t, cases, (r0: 0, c0: 0, r1: 1, c1: 0)),
        r'\begin{cases}a\\b\end{cases}',
      );
      expect(
        cellsPayload(t, cases, (r0: 0, c0: 0, r1: 2, c1: 0)),
        cases,
      );
    });

    test('aligned 的 `&` 原样留在整行里', () {
      const String al = r'\begin{aligned}&=1\\&=2\\&=3\end{aligned}';
      final EnvTable t = envTablesIn(al).single;
      expect(
        cellsPayload(t, al, (r0: 0, c0: 1, r1: 1, c1: 1)),
        r'\begin{aligned}&=1\\&=2\end{aligned}',
      );
    });

    test('高亮那一带可能**参差**（复制不补空；补空留给粘贴）', () {
      const String tex = r'\begin{bmatrix}a&b&c\\d\end{bmatrix}';
      final EnvTable t = envTablesIn(tex).single;
      // b→d：行 0 带 b,c；行 1 带 d ⇒ 两行格数不同（3×3 里 b→e 是 2+2，不参差）
      expect(
        cellsPayload(t, tex, (r0: 0, c0: 1, r1: 1, c1: 0)),
        r'\begin{matrix}b&c\\d\end{matrix}',
      );
      // 盖住所有**存在**的格 ⇒ 就算整表（原样带走）
      expect(
        cellsPayload(t, tex, (r0: 0, c0: 0, r1: 1, c1: 2)),
        tex,
      );
    });
  });

  group('删格（清内容、留分隔符）', () {
    test('清行 0 两格：只剩 `&`，其余原样', () {
      final EnvTable t = envTablesIn(_pm).single;
      final CellClear c = cellClearPlan(t, _pm, (r0: 0, c0: 0, r1: 0, c1: 1))!;
      final String after = _pm.replaceRange(c.from, c.to, c.replacement);
      expect(after, r'\begin{pmatrix}&\\c&d\end{pmatrix}');
      expect(c.payload, r'\begin{matrix}a&b\end{matrix}');
    });

    test('只清一格：只动那一格的内容', () {
      final EnvTable t = envTablesIn(_pm).single;
      final CellClear c = cellClearPlan(t, _pm, (r0: 1, c0: 0, r1: 1, c1: 0))!;
      final String after = _pm.replaceRange(c.from, c.to, c.replacement);
      expect(after, r'\begin{pmatrix}a&b\\&d\end{pmatrix}');
      expect(c.payload, r'\begin{matrix}c\end{matrix}');
    });

    test('单行清中间一格：左右两格都不许动', () {
      const String tex = r'\begin{bmatrix}a&b&c\\d&e&f\end{bmatrix}';
      final EnvTable t = envTablesIn(tex).single;
      final CellClear c = cellClearPlan(t, tex, (r0: 0, c0: 1, r1: 0, c1: 1))!;
      final String after = tex.replaceRange(c.from, c.to, c.replacement);
      expect(after, r'\begin{bmatrix}a&&c\\d&e&f\end{bmatrix}');
      expect(c.payload, r'\begin{matrix}b\end{matrix}');
    });

    test('跨行清一条带 ⇒ 只清带里的格（行 0 尾巴 + 行 1 开头）', () {
      const String tex = r'\begin{bmatrix}a&b&c\\d&e&f\end{bmatrix}';
      final EnvTable t = envTablesIn(tex).single;
      final CellClear c = cellClearPlan(t, tex, (r0: 0, c0: 1, r1: 1, c1: 1))!;
      final String after = tex.replaceRange(c.from, c.to, c.replacement);
      expect(after, r'\begin{bmatrix}a&&\\&&f\end{bmatrix}');
      expect(c.payload, r'\begin{matrix}b&c\\d&e\end{matrix}');
    });
  });
}
