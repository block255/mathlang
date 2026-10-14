// 文本输入面测试（S3-2 输入层重做）
//
// ★ 本文件的用例**不是设计出来的，是真人键盘实测抓出来的真实事件序列** ——
//   数据来自浏览器控制台探针（`text_input_surface.dart` 的 `kProbeInput`，
//   Flutter Web 的 `debugPrint` 走 console，要用 `browser_dock console` 读，**不进 run.log**）。
//   每一条都对应一个真出现过、并且被修掉的 bug。

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/editor/text_input_surface.dart';

TextEditingValue _v(String text, [int? sel, TextRange? composing]) =>
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: sel ?? text.length),
      composing: composing ?? TextRange.empty,
    );

void main() {
  late FocusNode focus;
  late TextInputSurfaceController input;
  late List<String> committed;

  setUp(() {
    focus = FocusNode();
    input = TextInputSurfaceController(focusNode: focus);
    committed = <String>[];
    input.onCommitText = committed.add;
  });

  tearDown(() {
    input.dispose();
    focus.dispose();
  });

  group('组合中间态一个字都不写进缓冲区（设计稿 §11.7）', () {
    test('拼音逐步变长 → 零提交，只更新组合串', () {
      input.updateEditingValue(_v('h', 1, const TextRange(start: 0, end: 1)));
      input.updateEditingValue(_v('ha', 2, const TextRange(start: 0, end: 2)));
      input.updateEditingValue(_v('hao', 3, const TextRange(start: 0, end: 3)));
      input.updateEditingValue(
          _v("hao'd", 5, const TextRange(start: 0, end: 5)));

      expect(committed, isEmpty, reason: '组合中绝不能写进正文');
      expect(input.isComposing, isTrue);
      expect(input.composingText, "hao'd");
    });

    test('组合中退格缩短拼音 → 同样零提交（键交给输入法）', () {
      input.updateEditingValue(_v('zhe', 3, const TextRange(start: 0, end: 3)));
      input.updateEditingValue(_v('zh', 2, const TextRange(start: 0, end: 2)));
      input.updateEditingValue(_v('z', 1, const TextRange(start: 0, end: 1)));

      expect(committed, isEmpty);
      expect(input.composingText, 'z');
    });
  });

  group('★ Chrome 选字的两段式序列（真机实测抓出的 bug）', () {
    test('候选词先以「组合中」到达、再结束组合 → 必须恰好插一次', () {
      // ① 拼音
      input.updateEditingValue(
          _v("hao'de'hao'de", 14, const TextRange(start: 0, end: 14)));
      expect(committed, isEmpty);

      // ② ★ 关键一步：Chrome 把组合串**换成了候选词**，但**仍然标成组合中**
      input.updateEditingValue(_v('好的好的', 4, const TextRange(start: 0, end: 4)));
      expect(committed, isEmpty, reason: '仍标组合中 → 还是一个字都不写');

      // ③ 组合结束，文本与上一步**完全相同**
      input.updateEditingValue(_v('好的好的', 4));
      expect(committed, <String>['好的好的'],
          reason: '★ 若这里是空，就是"刚选中的汉字被自己吃掉"那个 bug：'
              '基线的含义是「缓冲区对应的那份平台文本」，不是"平台此刻装着什么"');
    });

    test('中文标点：同样的两段式序列', () {
      input.updateEditingValue(_v('，', 1, const TextRange(start: 0, end: 1)));
      expect(committed, isEmpty);
      input.updateEditingValue(_v('，', 1));
      expect(committed, <String>['，']);

      input.updateEditingValue(_v('。', 1, const TextRange(start: 0, end: 1)));
      input.updateEditingValue(_v('。', 1));
      expect(committed, <String>['，', '。']);
    });

    test('英文不经过"候选词仍标组合中"这一步 → 逐字提交', () {
      input.updateEditingValue(_v('w', 1));
      input.updateEditingValue(_v('h', 1));
      input.updateEditingValue(_v('y', 1));
      expect(committed, <String>['w', 'h', 'y']);
    });

    test('组合取消（文本退回空）→ 零提交', () {
      input.updateEditingValue(_v('z', 1, const TextRange(start: 0, end: 1)));
      input.updateEditingValue(_v('', 0));
      expect(committed, isEmpty, reason: '取消组合不该产生任何编辑');
      expect(input.isComposing, isFalse);
    });
  });
}
