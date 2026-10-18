// 数语引擎 · 词触发（`lang/word_triggers.dart`）守卫
//
// 与快捷键表**不同**的地方（用户 2026-10-17 确认的边界）：
//   词是用户自己编的 ⇒ **可以加行、可以删行**（快捷键表只能给已有动作加副绑定）。
// 另外守：空词 / 空目标 / 同名词 ⇒ 无效（界面上标红，S4-c 接线时以这里为准）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/word_triggers.dart';

void main() {
  test('默认 8 条，全部有效', () {
    final TriggerSettings t = TriggerSettings.defaults();
    expect(t.triggers.length, 8);
    expect(t.allValid, isTrue);
    expect(t.triggers.map((WordTrigger w) => w.word),
        containsAll(<String>['sqrt', 'frac', 'sum', 'int', 'lim']));
  });

  test('加一行（空白行）⇒ 立刻无效（词不能为空）', () {
    final TriggerSettings t = TriggerSettings.defaults().add();
    expect(t.triggers.length, 9);
    expect(t.isValid(8), isFalse);
    expect(t.allValid, isFalse);
  });

  test('删一行', () {
    final TriggerSettings t = TriggerSettings.defaults().removeAt(0);
    expect(t.triggers.length, 7);
    expect(t.triggers.first.word, 'frac');
    // 越界删：原样返回
    expect(t.removeAt(99).triggers.length, 7);
  });

  test('同名词 ⇒ 两条都无效', () {
    final TriggerSettings t =
        TriggerSettings.defaults().withItem(0, const WordTrigger(word: 'frac', tex: r'\sqrt{}'));
    expect(t.isValid(0), isFalse);
    expect(t.isValid(1), isFalse, reason: 'frac 与 frac 撞了');
    expect(t.isValid(2), isTrue);
  });

  test('目标空的也无效', () {
    final TriggerSettings t =
        TriggerSettings.defaults().withItem(0, const WordTrigger(word: 'xx', tex: '  '));
    expect(t.isValid(0), isFalse);
  });

  test('改词后能过（可编辑）', () {
    TriggerSettings t =
        TriggerSettings.defaults().withItem(0, const WordTrigger(word: 'xx', tex: ''));
    expect(t.allValid, isFalse);
    t = t.withItem(0, t.triggers[0].copyWith(tex: r'\sqrt{}'));
    expect(t.allValid, isTrue);
  });
}
