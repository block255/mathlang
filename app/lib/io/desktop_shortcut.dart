// 数语引擎 · **桌面快捷方式**（2026-10-19 U6；2026-10-28 晚重写"图标自愈"）
//
// 用户要求：MSIX 装完后"普通用户根本不会去找装在哪" ⇒ **第一次启动就自动建桌面图标**。
// MSIX 的硬限制：安装包**不允许**创建桌面快捷方式（微软只给开始菜单/任务栏）⇒ 只能由应用自己建。
//
// 两条分支：
//   · **MSIX 版**：快捷方式指向 `explorer.exe shell:AppsFolder\<PFN>!App`
//     ——**不能**直接指向 WindowsApps 里的 exe：那条路径带版本号，升级后就失效了；
//   · **绿色版 / 开发版**：直接指向当前 exe（开发版路径本来就不变）。
//
// ★★★ 2026-10-28 晚（用户实测："更新到 1.2.8 后重启，桌面图标变成白纸"）：
//   旧实现有两个 bug ——
//     ① `IconLocation` 用的是 `Platform.resolvedExecutable` ⇒ **写死版本目录**
//        （`…\WindowsApps\MathLang.Editor_1.1.0.0_…\数语引擎.exe`）。版本一升级，图标取不到；
//        之所以之前没暴露，是因为 Windows 的**图标缓存**一直替它兜着，重启刷新缓存后才露白。
//     ② `if (文件已存在) return true;` ⇒ **只建不修**，图标永远停在首次创建时那个版本。
//   ⇒ 现在：
//     · 图标随包带一份**多尺寸 `assets/icon/app.ico`**，运行时拷到**稳定路径**
//       `%USERPROFILE%\mathlang\数语引擎.ico`（不在任何版本目录里）；
//     · `ensureDesktopShortcut()` 改成**幂等自愈**：拿"版本 + 图标指纹"当印戳，
//       印戳对得上且三样都在 ⇒ 什么都不做；否则**重写快捷方式 + 重新拷图标**。
//       于是"安装后 / 一键更新后 / 被手工改坏"三种情况都会在**下次启动**自动修好。
//
// 只在 Windows 上做事；其它平台是 no-op。**不引入任何新依赖**（不碰 ffi）。

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../app_info.dart';

/// 桌面上的快捷方式文件名
const String kDesktopShortcutName = '数语引擎.lnk';

/// 稳定图标文件名（放在数据目录里，不随版本变）
const String kStableIconName = '数语引擎.ico';

/// 印戳文件名（记录"上次是按哪个版本修的"，见 [ensureDesktopShortcut]）
const String kShortcutStampName = 'shortcut.stamp';

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

/// 用户主目录（`%USERPROFILE%`）
String _homeDir() =>
    Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';

/// 桌面目录（`%USERPROFILE%\Desktop`）
String desktopDir() => '${_homeDir()}\\Desktop';

/// 桌面快捷方式完整路径
String desktopShortcutPath() => '${desktopDir()}\\$kDesktopShortcutName';

/// 数据目录（与设置/草稿同一个：`%USERPROFILE%\mathlang`）
String dataDir() => '${_homeDir()}\\mathlang';

/// **稳定图标路径**（快捷方式的 `IconLocation` 永远指这里）
String stableIconPath() => '${dataDir()}\\$kStableIconName';

bool desktopShortcutExists() =>
    Platform.isWindows && File(desktopShortcutPath()).existsSync();

/// 印戳内容：版本 + 图标字节数（版本变了、图标换了，都要重做一次）
String _stampText(int iconBytes) => '$kAppVersion|$iconBytes';

/// 建/修快捷方式（**幂等**）。返回是否最终可用。
///
/// 判据（MSIX 版）：印戳一致 + 快捷方式在 + 稳定图标在 ⇒ 直接返回 true（零开销）；
/// 任一条不满足 ⇒ 重新拷图标 + 重写快捷方式 + 写印戳。
Future<bool> ensureDesktopShortcut() async {
  if (!Platform.isWindows) return false;
  final bool msix = isRunningAsMsix;
  final String link = desktopShortcutPath();
  final String icon = stableIconPath();
  final String stampPath = '${dataDir()}\\$kShortcutStampName';

  // 先确保"图标"就位（MSIX 版才有稳定图标；绿色版直接用 exe 自带图标）
  int iconBytes = 0;
  if (msix) {
    try {
      final ByteData data = await rootBundle.load('assets/icon/app.ico');
      iconBytes = data.lengthInBytes;
      final File f = File(icon);
      final bool same = f.existsSync() && f.lengthSync() == iconBytes;
      if (!same) {
        await Directory(dataDir()).create(recursive: true);
        await f.writeAsBytes(data.buffer.asUint8List(), flush: true);
      }
    } catch (e) {
      debugPrint('写稳定图标失败：$e');
    }
  }

  // 印戳对得上、三样都在 ⇒ 收工（绝大多数启动走这条路）
  if (msix && iconBytes > 0) {
    try {
      final File st = File(stampPath);
      final bool ok = st.existsSync() &&
          st.readAsStringSync().trim() == _stampText(iconBytes) &&
          File(link).existsSync() &&
          File(icon).existsSync();
      if (ok) return true;
    } catch (_) {}
  } else if (!msix && File(link).existsSync()) {
    return true; // 绿色版：存在就不再折腾
  }

  final String exe = Platform.resolvedExecutable;
  final String? pfn = packageFamilyName();
  final String windir = Platform.environment['WINDIR'] ??
      Platform.environment['SystemRoot'] ??
      r'C:\Windows';
  final String target = pfn == null ? exe : '$windir\\explorer.exe';
  final String args = pfn == null ? '' : 'shell:AppsFolder\\$pfn!App';
  final String workDir = File(exe).parent.path;
  // ★ 图标：MSIX 版用**稳定路径那个 ico**；绿色版仍用 exe 自带图标（路径本来就稳）
  final String iconLoc = (msix && iconBytes > 0) ? icon : exe;

  // ⚠️ PowerShell 里 `$` 是变量前缀：这里用**原始字符串拼接**，不靠 Dart 插值进 PS 文本
  final String ps = <String>[
    '\$ErrorActionPreference = "Stop"',
    '\$s = (New-Object -ComObject WScript.Shell).CreateShortcut("$link")',
    '\$s.TargetPath = "$target"',
    '\$s.Arguments = "$args"',
    '\$s.IconLocation = "$iconLoc,0"',
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
    if (msix && iconBytes > 0) {
      try {
        await File(stampPath).writeAsString(_stampText(iconBytes), flush: true);
      } catch (_) {}
    }
    return File(link).existsSync();
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
