// ★★ F19 守卫（2026-10-21，用户实测）：
// 「每次导入导出保存，弹出的框强制默认在软件所在文件夹 —— 用户肯定不会把文件放程序目录」
//
// 根因：三个原生对话框都没传 `initialDirectory` ⇒ Windows 用进程当前目录（= exe 目录）。
// 修法：`DirMemory` 记「上次用过的目录」，没记忆时兜底用户的「文档」目录。
//
// 本文件只测**纯逻辑**（不弹真对话框）：记忆优先级 / 记住父目录 / 兜底 / 通知上层。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/io/dir_memory.dart';

void main() {
  setUp(DirMemory.reset);
  tearDown(DirMemory.reset);

  group('① 初始目录：有记忆用记忆，没记忆用兜底（绝不是程序目录）', () {
    test('没有记忆 ⇒ 用兜底目录', () {
      DirMemory.fallback = () => r'C:\Users\me\Documents';
      expect(DirMemory.initialDirectory(), r'C:\Users\me\Documents');
    });

    test('记忆为空串（设置里从没存过）⇒ 仍然用兜底', () {
      DirMemory.fallback = () => r'D:\作业';
      DirMemory.load('');
      expect(DirMemory.initialDirectory(), r'D:\作业');
    });

    test('有记忆 ⇒ **记忆优先**于兜底', () {
      DirMemory.fallback = () => r'C:\Documents';
      DirMemory.load(r'E:\数学作业');
      expect(DirMemory.initialDirectory(), r'E:\数学作业');
    });

    test('load 会去掉首尾空白', () {
      DirMemory.load('   ');
      DirMemory.fallback = () => r'X:\fallback';
      expect(DirMemory.initialDirectory(), r'X:\fallback');
    });

    test('兜底默认值不是空串（Windows 上应能给出用户目录）', () {
      // 不写死具体路径（机器不同），只要求"有个合理地点"而不是空
      final String d = DirMemory.initialDirectory();
      if (Platform.isWindows) {
        expect(d, isNotEmpty, reason: '兜底不该是空 —— 否则又回落到系统默认（程序目录）');
        final String home =
            Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';
        if (home.isNotEmpty) {
          expect(d.toLowerCase().startsWith(home.toLowerCase()), isTrue,
              reason: '兜底应当落在用户目录下，实际 "$d"');
        }
      }
    });
  });

  group('② 记住目录：选完文件就记它的父目录，并通知上层落盘', () {
    test('rememberFile 取父目录 + 回调一次', () {
      final List<String> got = <String>[];
      DirMemory.onChanged = got.add;
      DirMemory.rememberFile(r'D:\作业\2026\a.md');
      expect(DirMemory.last, r'D:\作业\2026');
      expect(got, <String>[r'D:\作业\2026']);
    });

    test('正斜杠路径也认', () {
      DirMemory.rememberFile('C:/work/a.md');
      expect(DirMemory.last, 'C:/work');
    });

    test('没有分隔符（相对文件名）⇒ 不记、不回调（不污染）', () {
      var called = 0;
      DirMemory.onChanged = (_) => called++;
      DirMemory.rememberFile('a.md');
      expect(DirMemory.last, '');
      expect(called, 0);
    });

    test('记住同一个目录两次 ⇒ 只通知一次（免得每次保存都写设置）', () {
      final List<String> got = <String>[];
      DirMemory.onChanged = got.add;
      DirMemory.rememberFile(r'D:\out\a.md');
      DirMemory.rememberFile(r'D:\out\b.md');
      expect(got, <String>[r'D:\out']);
    });

    test('选目录（导出图片集）同样记住', () {
      final List<String> got = <String>[];
      DirMemory.onChanged = got.add;
      DirMemory.rememberDirectory(r' D:\导出\图片集 ');
      expect(DirMemory.last, r'D:\导出\图片集');
      expect(got, <String>[r'D:\导出\图片集']);
    });
  });

  group('③ parentOf 的形态', () {
    test('盘符路径', () => expect(DirMemory.parentOf(r'C:\a\b'), r'C:\a'));
    test('单层', () => expect(DirMemory.parentOf(r'C:\a'), r'C:'));
    test('正斜杠', () => expect(DirMemory.parentOf('/home/x/a.md'), '/home/x'));
    test('无分隔符', () => expect(DirMemory.parentOf('a.md'), ''));
    test('尾随分隔符不产生空父目录', () {
      // `C:\a\` ⇒ 父目录 `C:\a`（去掉末尾那个分隔符后仍能给一个合法目录）
      expect(DirMemory.parentOf(r'C:\a\'), r'C:\a');
    });
  });
}
