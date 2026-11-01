// 边界归一（保存 / 导出）：**副本上**把每一段数学归一，不动 live 缓冲区。
//
// 口径（2026-11-01）：归一不逐击键跑（会收走空结构、改字节顺序），
//   但落盘给外面（`.md` / 导出 / AI）必须是**单一形态**。
// 本文件的判据：只关心"交给外面的字符串是规范形"，不关心"什么时候归一的"。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/lang/doc_normalize.dart';
import 'package:mathlang/render/normalize.dart';

void main() {
  test(r"① 行内裸撇 ⇒ 规范形（撇在前）", () {
    const String src = r"正文 $f_{-}'$ 结束";
    expect(normalizeDocument(src), r"正文 $f^{\prime}_{-}$ 结束");
  });

  test(r"② 行间两种顺序 ⇒ 同一份字节", () {
    const String a = "\$\$\nf'_{+}\n\$\$\n";
    const String b = "\$\$\nf_{+}'\n\$\$\n";
    expect(normalizeDocument(a), normalizeDocument(b));
  });

  test('③ 普通正文一个字节都不动', () {
    const String src = '今天天气不错，价格 \$100 左右。';
    expect(normalizeDocument(src), src);
  });

  test('④ 幂等：归一再归一不再变', () {
    const String src = r"$f_{-}'$ 和 $$f_{+}'$$";
    final String once = normalizeDocument(src);
    expect(normalizeDocument(once), once);
  });

  test('⑤ 空文档 / 没有数学段 ⇒ 原样', () {
    expect(normalizeDocument(''), '');
    expect(normalizeDocument('纯文字'), '纯文字');
  });

  test('⑥ 与单段归一同一口径（不另造规则）', () {
    const String tex = r"f_{+}'";
    expect(normalizeDocument('\$$tex\$'), '\$${normalizeTex(tex, 0).tex}\$');
  });
}
