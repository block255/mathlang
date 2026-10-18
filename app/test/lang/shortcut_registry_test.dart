// 数语引擎 · 快捷键登记表（`lang/shortcut_registry.dart`）守卫
//
// ★ 这一批的核心诉求：**设置页不许撒谎**。
//   ⇒ 断言里既守"表本身"（45 条 / 44 条已接入 / id 唯一 / 键可解析），
//     也守"边界"（每动作 ≤2 条、默认项删不得、浏览器独占键拒收、冲突可检出）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/shortcut_registry.dart';

void main() {
  group('① 表本身', () {
    test('43 条动作，其中 42 条已接入（只剩源码视图等 S5）', () {
      expect(kShortcutActions.length, 43);
      expect(ShortcutSettings.total, 43);
      // ★ 2026-10-18 S4-c：整套 Ctrl+Alt+* / Ctrl+↑↓ / Ctrl+1..3 接线完成
      expect(ShortcutSettings.wiredCount, 42);
      final List<ShortcutAction> planned = <ShortcutAction>[
        for (final ShortcutAction a in kShortcutActions)
          if (!a.wired) a,
      ];
      expect(planned.length, 1);
      expect(planned.single.id, 'sourceView');
      expect(planned.single.note, contains('S5'));
    });

    test('id 唯一、分组都在允许的五个类目里', () {
      final Set<String> ids = <String>{};
      for (final ShortcutAction a in kShortcutActions) {
        expect(ids.add(a.id), isTrue, reason: '重复 id: ${a.id}');
        expect(<String>['结构类', '数学类', '结构内', '面板', '编辑类'],
            contains(a.group));
      }
    });

    test('每条默认键都能解析，且 label 能往返', () {
      for (final ShortcutAction a in kShortcutActions) {
        final ShortcutCombo c = ShortcutCombo.parse(a.combo);
        expect(c.isEmpty, isFalse, reason: '${a.id} 的默认键解析成空');
        expect(ShortcutCombo.parse(c.label), c, reason: '${a.id}: ${c.label}');
      }
    });

    test('解析：`Alt+=` / `Ctrl+Shift+Z` 的修饰键与主键分得开', () {
      final ShortcutCombo a = ShortcutCombo.parse('Alt+=');
      expect(a.alt, isTrue);
      expect(a.ctrl, isFalse);
      expect(a.key, '=');
      expect(a.label, 'Alt+=');
      final ShortcutCombo b = ShortcutCombo.parse('ctrl+shift+z'); // 大小写无关
      expect(b.label, 'Ctrl+Shift+Z');
    });

    test('未接入的项都写了批次说明（界面上那句小字）', () {
      for (final ShortcutAction a in kShortcutActions) {
        if (!a.wired) {
          expect(a.note, isNotEmpty, reason: '${a.id} 未接入却没写批次');
        }
      }
    });
  });

  group('② 修改的边界（用户 2026-10-17 确认）', () {
    test('"添加"= 加副绑定，最多 2 条', () {
      final ShortcutSettings d = ShortcutSettings.defaults();
      final ShortcutSettings? one =
          d.addCombo('frac', ShortcutCombo.parse('Ctrl+M'));
      expect(one, isNotNull);
      expect(one!.combosOf('frac').length, 2);
      expect(one.addCombo('frac', ShortcutCombo.parse('Ctrl+N')), isNull,
          reason: '已有 2 条 ⇒ 加不进去');
    });

    test('默认主键**删不得**（只能停用 / 恢复默认）', () {
      final ShortcutSettings d = ShortcutSettings.defaults();
      expect(d.removeCombo('frac', 0), isNull, reason: '主键删不得');
      final ShortcutSettings two = d.addCombo('frac', ShortcutCombo.parse('Ctrl+M'))!;
      expect(two.removeCombo('frac', 1), isNotNull, reason: '副键可删');
    });

    test('停用 / 单条恢复默认 / isModified', () {
      final ShortcutSettings d = ShortcutSettings.defaults();
      expect(d.isModified('frac'), isFalse);
      final ShortcutSettings off = d.toggleEnabled('frac');
      expect(off.isDisabled('frac'), isTrue);
      expect(off.isModified('frac'), isTrue, reason: '停用也算改过');
      final ShortcutSettings back = off.resetOne('frac');
      expect(back.isDisabled('frac'), isFalse);
      expect(back.isModified('frac'), isFalse);
    });

    test('换键后 isModified 成立，恢复默认后消失', () {
      final ShortcutSettings d = ShortcutSettings.defaults();
      final ShortcutSettings c =
          d.withCombo('frac', 0, ShortcutCombo.parse('Ctrl+Alt+K'));
      expect(c.isModified('frac'), isTrue);
      expect(c.resetOne('frac').isModified('frac'), isFalse);
    });
  });

  group('③ 冲突与拒收', () {
    test('把「根号」改成「分式」的键 ⇒ 两条都进冲突集合', () {
      final ShortcutSettings d = ShortcutSettings.defaults();
      final ShortcutSettings c =
          d.withCombo('sqrt', 0, ShortcutCombo.parse('Ctrl+Alt+F'));
      final Set<String> bad = c.conflicts();
      expect(bad, containsAll(<String>['sqrt', 'frac']));
      expect(c.ownerOf(ShortcutCombo.parse('Ctrl+Alt+F'), except: 'sqrt'), '分式');
    });

    test('默认表**自己**不冲突（否则设置页一打开就报红）', () {
      expect(ShortcutSettings.defaults().conflicts(), isEmpty);
    });

    test('停用一条 ⇒ 冲突消失', () {
      final ShortcutSettings c = ShortcutSettings.defaults()
          .withCombo('sqrt', 0, ShortcutCombo.parse('Ctrl+Alt+F'))
          .toggleEnabled('frac');
      expect(c.conflicts(), isEmpty);
    });

    test('浏览器独占键拒收（`Ctrl+Shift+I` 这类页面拦不住）', () {
      final ShortcutSettings d = ShortcutSettings.defaults();
      for (final String k in <String>[
        'Ctrl+Shift+R',
        'Ctrl+Shift+I',
        'Ctrl+W',
        'Ctrl+P',
      ]) {
        expect(d.rejectionOf(ShortcutCombo.parse(k)), '浏览器独占，页面拦不住',
            reason: k);
      }
      expect(d.rejectionOf(ShortcutCombo.parse('Ctrl+Alt+K')), isNull);
      expect(d.rejectionOf(ShortcutCombo.empty), '还没按键');
    });

    test('空副键不参与冲突（用户还没按下去）', () {
      final ShortcutSettings c = ShortcutSettings.defaults()
          .addCombo('frac', ShortcutCombo.empty)!;
      expect(c.conflicts(), isEmpty);
    });
  });
}
