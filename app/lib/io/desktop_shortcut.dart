// 数语引擎 · **桌面快捷方式**（2026-10-19，U6）
//
// 用户要求：MSIX 装完后"普通用户根本不会去找装在哪" ⇒ **第一次启动就自动建桌面图标**。
// MSIX 的硬限制：安装包**不允许**创建桌面快捷方式（微软只给开始菜单/任务栏）⇒ 只能由应用自己建。
//
// 两条分支：
//   · **MSIX 版**：快捷方式指向 `explorer.exe shell:AppsFolder\<PFN>!App`
//     ——**不能**直接指向 WindowsApps 里的 exe：那条路径带版本号，升级后就失效了；
//   · **绿色版 / 开发版**：直接指向当前 exe。
//
// 只在 Windows 上做事；其它平台是 no-op。**不引入任何新依赖**（不碰 ffi）。

import 'dart:io';

import 'package:flutter/foundation.dart';

/// 桌面上的快捷方式文件名
const String kDesktopShortcutName = '数语引擎.lnk';

/// 当前是否跑在 MSIX 包里（exe 位于 `…\WindowsApps\<包名>\`）
bool get isRunningAsMsix {
  if (!Platform.isWindows) return false;
  return Platform.resolvedExecutable
      .toLowerCase()
      .contains(r'\windowsapps\');
}

/// MSIX 包族名（`MathLang.Editor_5sk0te2wpbgej`）；非 MSIX 时为 `null`。
///
/// 从安装路径反推：目录名形如 `Name_Version_Arch_[ResourceId_]PublisherId`，
/// 包族名 = `Name_PublisherId`（去掉版本/架构/资源 ID）。
String? packageFamilyName() {
  if (!isRunningAsMsix) return null;
  final List<String> parts = Platform.resolvedExecutable
      .split(RegExp(r'[\\/]'))
      .firstWhere((String s) => s.startsWith('MathLang.'),
          orElse: () => '')
      .split('_');
  if (parts.length < 3) return null;
  return '${parts.first}_${parts.last}';
}

/// 桌面目录（`%USERPROFILE%\Desktop`）
String desktopDir() =>
    '${Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? ''}'
    '\\Desktop';

/// 桌面快捷方式完整路径
String desktopShortcutPath() => '${desktopDir()}\\$kDesktopShortcutName';

bool desktopShortcutExists() =>
    Platform.isWindows && File(desktopShortcutPath()).existsSync();

/// 建快捷方式（**已存在就不重建**）。返回是否最终存在。
Future<bool> ensureDesktopShortcut() async {
  if (!Platform.isWindows) return false;
  final String path = desktopShortcutPath();
  if (File(path).existsSync()) return true;

  final String exe = Platform.resolvedExecutable;
  final String? pfn = packageFamilyName();
  final String windir =
      Platform.environment['WINDIR'] ?? Platform.environment['SystemRoot'] ??
          r'C:\Windows';
  final String target = pfn == null ? exe : '$windir\\explorer.exe';
  final String args = pfn == null ? '' : 'shell:AppsFolder\\$pfn!App';
  final String workDir = File(exe).parent.path;

  // ⚠️ PowerShell 里 `$` 是变量前缀：这里用**原始字符串拼接**，不靠 Dart 插值进 PS 文本
  // 注：`\$` 是 Dart 的转义，落进 PS 文本后是 `$s`（PS 变量）——两边都要写成原始字面量
  final String ps = <String>[
    '\$ErrorActionPreference = "Stop"',
    '\$s = (New-Object -ComObject WScript.Shell).CreateShortcut("$path")',
    '\$s.TargetPath = "$target"',
    '\$s.Arguments = "$args"',
    '\$s.IconLocation = "$exe,0"',
    '\$s.WorkingDirectory = "$workDir"',
    '\$s.Description = "数语引擎"',
    '\$s.Save()',
  ].join('; ');

  try {
    final ProcessResult r = await Process.run(
      'powershell.exe',
      <String>['-NoProfile', '-NonInteractive', '-Command', ps],
    );
    if (r.exitCode != 0) {
      debugPrint('建桌面快捷方式失败：${r.stderr}');
      return false;
    }
    return File(path).existsSync();
  } catch (e) {
    debugPrint('建桌面快捷方式异常：$e');
    return false;
  }
}

/// 删掉快捷方式（设置页「删除」用）
bool removeDesktopShortcut() {
  if (!Platform.isWindows) return false;
  final File f = File(desktopShortcutPath());
  if (!f.existsSync()) return true;
  try {
    f.deleteSync();
    return true;
  } catch (_) {
    return false;
  }
}