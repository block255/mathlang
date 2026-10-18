// 数语引擎 · 当前文档身份（`core/document_file.dart`）守卫
//
// 一个普通文件编辑器的语义（用户 2026-10-17 定的）：
//   · 能打开电脑里的文件；没保存的只活在内存里；
//   · 标题 = 文件名去扩展名；改标题 = 下次保存要另存（不是偷偷改旧文件）。
// 纯逻辑，所以先把"路径 ↔ 标题 ↔ 文件名"这三件事钉死。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/document_file.dart';

void main() {
  test('标题来自文件名（去扩展名；兼容 `\\` 与 `/`）', () {
    expect(DocumentFile.titleFromPath(r'C:\docs\作业辅导1.md'), '作业辅导1');
    expect(DocumentFile.titleFromPath('/home/u/a/b.md'), 'b');
    expect(DocumentFile.titleFromPath('没有扩展名'), '没有扩展名');
    expect(DocumentFile.titleFromPath('.隐藏'), '.隐藏', reason: '点开头不算扩展名');
    expect(DocumentFile.titleFromPath(''), DocumentFile.kUntitled);
  });

  test('文件名的边角：多点 / 空格', () {
    expect(DocumentFile.titleFromPath(r'C:\a\作业 1.2 答案.md'), '作业 1.2 答案');
    expect(DocumentFile.fileNameOf(r'C:\a\b.md'), 'b.md');
    expect(DocumentFile.fileNameOf('b.md'), 'b.md');
  });

  test('扩展名小写化', () {
    expect(DocumentFile.extensionOf('A.MD'), 'md');
    expect(DocumentFile.extensionOf('a.txt'), 'txt');
    expect(DocumentFile.extensionOf('a'), '');
  });

  test('另存用的建议文件名：标题带扩展名就不重复加', () {
    expect(const DocumentFile(title: '作业1').suggestedFileName(), '作业1.md');
    expect(const DocumentFile(title: '作业1.md').suggestedFileName(), '作业1.md');
    expect(const DocumentFile().suggestedFileName(), '未命名文档.md');
    expect(const DocumentFile(title: 'x').suggestedFileName(ext: 'txt'), 'x.txt');
  });

  test('hasFile / 路径可清空 / 等值', () {
    const DocumentFile a = DocumentFile(title: 'a', path: r'C:\a.md');
    expect(a.hasFile, isTrue);
    expect(a.extension, 'md');
    expect(a.copyWith(clearPath: true).hasFile, isFalse);
    expect(const DocumentFile(), const DocumentFile());
    expect(a == const DocumentFile(title: 'a', path: r'C:\a.md'), isTrue);
  });


  test('SaveOutcome：取消 vs 成功', () {
    expect(const SaveOutcome.cancelled().ok, isFalse);
    expect(const SaveOutcome.cancelled().cancelled, isTrue);
    expect(const SaveOutcome(path: r'C:\a.md').ok, isTrue);
  });
}
