// C2 守卫（2026-10-28）：**版本号只有一个来源 = `pubspec.yaml`**。
//
// 改前的事故：`app/lib/app_info.dart` 是手写常量，`v1.0.0 / v1.1.0 / v1.1.1` 三个 tag 里
// 都还写着 `1.0.0`，而包版本早就到 1.1.1 → 用户点「设置 → 关于」看到的版本**永远慢两版**。
// 这条守卫把"改版本忘了同步"变成**测试红**，不再靠记性。
//
// 唯一来源：`pubspec.yaml` 的 `version:`；由 `scripts/gen_app_info.ps1` 生成 `app_info.dart`。
// ★ 这个测试靠 `flutter test` 的工作目录 = `app/`（`pubspec.yaml` 就在那儿）。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/app_info.dart';

void main() {
  group('C2 · 版本号单一来源', () {
    test('`kAppVersion` 必须逐字等于 pubspec.yaml 的 version', () {
      final File f = File('pubspec.yaml');
      expect(f.existsSync(), isTrue,
          reason: '跑测试时的工作目录应当是 app/（pubspec.yaml 在那儿）');
      final String pub = f.readAsStringSync();
      final RegExpMatch? m = RegExp(r'^version:\s*(\S+)', multiLine: true)
          .firstMatch(pub);
      expect(m, isNotNull, reason: 'pubspec.yaml 里没有 `version:` 行');
      final String want = m!.group(1)!;
      expect(kAppVersion, want,
          reason: 'app_info.dart 落后于 pubspec.yaml：改完版本请跑 '
              '`powershell -ExecutionPolicy Bypass -File scripts\\gen_app_info.ps1`');
    });

    test('版本名与构建号拆得开，且拼得回去', () {
      expect(kAppVersion, '$kAppVersionName+$kAppBuildNumber');
      expect(RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+$').hasMatch(kAppVersionName), isTrue,
          reason: '版本名必须是 x.y.z（D1「检查更新」要按段比较它）');
      expect(RegExp(r'^[0-9]+$').hasMatch(kAppBuildNumber), isTrue,
          reason: '构建号必须是纯数字');
    });
  });
}
