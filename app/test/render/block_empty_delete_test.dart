// 2026-11-01（用户三张图）：**删掉一个"只有间距"的行间块，不许动别人的行尾**。
//
// ## 现场
// 用户点了虚线小框（可见的空块）按 ⌫：
//   ① 第二个鬼删完：`只能f'(0)=0` 与 `---` **粘成一行**（`只能f'(0)=0|---`）；
//   ② 第一个鬼删完：**整段 T1 崩成裸源码**，一串 `[公式不完整]`。
//
// ## 根因（一处，两副面孔）
// `reclaimEmptiedMath` 在"删空了一个行间块"时，把**围栏前面那个换行也吃了**
// （`if (a > 0 && doc[a-1] == '\n') a -= 1;`）⇒ 上一行的行尾和块后面那一行被缝在一起：
//   · `只能f'(0)=0` ⏎ `$$…$$` ⏎ `---` ⇒ `只能f'(0)=0---`
//   · 块**紧贴**下一个块时 ⇒ `…上一行文字$$` ⇒ 那个 `$$` 跑到行中间、不再是围栏
//     ⇒ 后面所有块的配对全体错位 ⇒ 裸源码（这就是"崩成一片"的机制）。
//
// ## 口径
// 块占的是**自己的行**：删掉它只该少一行，**不许动别人的行尾**。
// 所以要吃的只有"块后面那个换行"（避免原地留空行），前面那个换行必须留着。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/block.dart';
import 'package:mathlang/render/delete_reclaim.dart';
import 'package:mathlang/render/math_nav.dart';
import 'package:mathlang/render/smart_delete.dart';

int _mathBlocks(String doc) =>
    BlockIndex.parse(doc).blocks.where((b) => b.type == BlockType.math).length;

/// 用 `smartEditAt` + `reclaimEmptiedMath` 走一遍真实的删除链（与 `edit_view._applyEdit` 同序）。
String _deleteAt(String doc, int caret, {bool forward = false}) {
  final SmartEdit raw = smartEditAt(doc, caret, forward: forward);
  final SmartEdit ed = reclaimEmptiedMath(doc, raw);
  if (!ed.deletes) return doc;
  return doc.replaceRange(ed.from!, ed.to!, '');
}

void main() {
  group('删"只有间距"的块', () {
    test('★ 块后面跟分割符 ⇒ 只少一行，不许把 `---` 粘到上一行', () {
      const String doc = '只能f(0)=0\n\n\$\$\n\\ \\ \\ \n\$\$\n---\n';
      final int blockStart = doc.indexOf(r'$$');
      final int caret = displayTexStartAt(doc, blockStart)!;
      final String after = _deleteAt(doc, caret);
      expect(after, '只能f(0)=0\n\n---\n',
          reason: '★ 改前：`只能f(0)=0---`（两行粘成一行）');
    });

    test('★★★ 块紧贴下一个块 ⇒ 下一个块必须活着（围栏不许被缝到行中间）', () {
      // 用户文档第 6–8 行那个空块，后面第 9 行就是下一个块的 `$$`
      const String doc = '设t\n\n\$\$\n\\ \\ \\ \n\$\$\n\$\$\nx\n\$\$\n\n后\n';
      expect(_mathBlocks(doc), 2);
      final int blockStart = doc.indexOf(r'$$');
      final int caret = displayTexStartAt(doc, blockStart)!;
      final String after = _deleteAt(doc, caret);
      expect(_mathBlocks(after), 1,
          reason: '只该少那一个空块；后面那个公式块必须还在');
      expect(after.contains('设t\$\$'), isFalse,
          reason: '★ 改前：上一行文字与下一个块的 `\$\$` 被缝成一行 ⇒ 那一行不再是围栏 '
              '⇒ 后面所有块配对错位、整段裸源码');
      expect(after.split('\n').first, '设t');
      expect(after.contains('\$\$\nx\n\$\$'), isTrue, reason: '后面的块原样保留');
    });

    test('★ 块前后都是文字 ⇒ 只少一行，两边的行都还在', () {
      const String doc = '前\n\n\$\$\n\\ \n\$\$\n后\n';
      final int blockStart = doc.indexOf(r'$$');
      final int caret = displayTexStartAt(doc, blockStart)!;
      final String after = _deleteAt(doc, caret);
      expect(after, '前\n\n后\n');
    });

    test('★ 有墨迹的块**不走这条**（内容要一个字一个字删）', () {
      const String doc = '甲\n\n\$\$\n\\ x\n\$\$\n\n乙\n';
      final int blockStart = doc.indexOf(r'$$');
      final int caret = displayTexStartAt(doc, blockStart)!;
      final String after = _deleteAt(doc, caret);
      expect(_mathBlocks(after), greaterThan(0),
          reason: '有内容时删一个字不该把整块带走');
    });
  });
}
