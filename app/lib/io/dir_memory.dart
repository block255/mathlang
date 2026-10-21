// 数语引擎 · **「上次使用的目录」记忆**（F19，2026-10-21 用户实测）
//
// 用户的原话：「现在每次导入导出保存，好像弹出的框强制默认是在软件所在文件夹？
// 但是实际使用的时候用户肯定不会把文件放在软件的文件夹的吧」
//
// 根因：三个原生对话框（打开 / 保存 / 选目录）都**没传 `initialDirectory`** ⇒
//   Windows 用进程的当前目录（= exe 所在目录）当地点。
//
// 本类的职责（只有一个）：给对话框一个**合理**的初始目录 ——
//   · 有记忆 ⇒ 上次用过的那个；
//   · 没记忆 ⇒ 用户的「文档」目录（不是程序目录）；
//   · 都没有 ⇒ 空串（调用方传 null，交给系统）。
//
// ★ 记忆本身落在 `AppSettings.lastDir` 里（跟设置一起持久化），
//   本类只在内存里放一份 + 通过 [onChanged] 通知上层落盘。
//
// **纯 Dart**（只依赖 `dart:io` 的 `Platform` / `Directory`），便于单测。

import 'dart:io';

class DirMemory {
  DirMemory._();

  static String _last = '';

  /// 上次使用过的目录（空串 = 从没选过）
  static String get last => _last;

  /// 兜底目录的来源（**测试可替换**；默认 = 用户的「文档」目录）
  static String Function()? fallback;

  /// 目录变化时通知上层（落盘到 `AppSettings.lastDir`）
  static void Function(String dir)? onChanged;

  /// 启动时从设置恢复；[dir] 为空 ⇒ 当作"没有记忆"
  static void load(String? dir) {
    _last = (dir ?? '').trim();
  }

  /// 测试用：清干净（默认连回调一起清）
  static void reset({String? last, bool keepHooks = false}) {
    _last = last?.trim() ?? '';
    if (!keepHooks) {
      fallback = null;
      onChanged = null;
    }
  }

  /// 对话框的**初始目录**；返回空串 ⇒ 调用方应传 `null`（交给系统默认）
  static String initialDirectory() {
    if (_last.isNotEmpty) return _last;
    return (fallback ?? _documentsDir)();
  }

  /// 用户在对话框里选了一个**文件** ⇒ 记住它所在的目录
  static void rememberFile(String path) {
    final String dir = parentOf(path);
    if (dir.isNotEmpty) rememberDirectory(dir);
  }

  /// 记住一个**目录**（例如"导出图片集"选的目录）
  static void rememberDirectory(String dir) {
    final String d = dir.trim();
    if (d.isEmpty || d == _last) return;
    _last = d;
    onChanged?.call(d);
  }

  /// 路径的父目录（`C:\docs\a.md` ⇒ `C:\docs`；没有分隔符 ⇒ 空串）
  static String parentOf(String path) {
    final int a = path.lastIndexOf('/');
    final int b = path.lastIndexOf(r'\');
    final int i = a > b ? a : b;
    if (i <= 0) return ''; // 0 = 根，或根本没有分隔符
    return path.substring(0, i);
  }

  /// 默认兜底：`%USERPROFILE%\Documents`（不存在就退回用户主目录）
  static String _documentsDir() {
    final String home = (Platform.environment['USERPROFILE'] ??
            Platform.environment['HOME'] ??
            '')
        .trim();
    if (home.isEmpty) return '';
    final String sep = Platform.pathSeparator;
    final String docs = '$home${sep}Documents';
    try {
      if (Directory(docs).existsSync()) return docs;
    } catch (_) {
      // 权限/环境异常一律退回主目录，绝不让"选文件"因为兜底失败而打不开
    }
    return home;
  }
}
