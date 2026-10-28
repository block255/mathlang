// D1 判据的守卫（2026-10-28）：比版本 / 限频 / 该不该弹 / Release JSON 解析。
//
// 这些都是**纯函数**，所以能在这里把边界钉死 —— 界面和网络层只许调它们，不许自己判。
// 用户 2026-10-28 定的规则：
//   · 启动后静默检查，没发现不弹、失败不弹；有发现才弹；
//   · 勾「以后不再自动检查更新」⇒ 完全不再自动查（手动仍可用）；
//   · 不勾 + 「暂不更新」⇒ 只跳过这一个版本。

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/core/update_check.dart';
import 'package:mathlang/core/version_ref.dart';

void main() {
  group('VersionRef · 比版本', () {
    test('解析：接受 v 前缀与构建号，忽略后缀', () {
      expect(VersionRef.tryParse('1.2.0'), const VersionRef(1, 2, 0));
      expect(VersionRef.tryParse('v1.2.0'), const VersionRef(1, 2, 0));
      expect(VersionRef.tryParse('v1.2.3+12'), const VersionRef(1, 2, 3));
      expect(VersionRef.tryParse(' 1.2.0 '), const VersionRef(1, 2, 0));
      expect(VersionRef.tryParse('1.2.0-beta.1'), const VersionRef(1, 2, 0));
    });

    test('解析不了就返回 null（不抛）', () {
      for (final String? bad in <String?>['', null, 'v', '1.2', 'a.b.c', '1.2.3.4']) {
        expect(VersionRef.tryParse(bad), isNull, reason: '「$bad」不该被当成版本');
      }
    });

    test('三段各自比较，且 1.10.0 > 1.9.0（不是字符串比较）', () {
      expect(const VersionRef(1, 10, 0).isNewerThan(const VersionRef(1, 9, 0)), isTrue,
          reason: '按字符串比会得出 1.10.0 < 1.9.0');
      expect(const VersionRef(2, 0, 0).isNewerThan(const VersionRef(1, 99, 99)), isTrue);
      expect(const VersionRef(1, 2, 1).isNewerThan(const VersionRef(1, 2, 0)), isTrue);
      expect(const VersionRef(1, 2, 0).isNewerThan(const VersionRef(1, 2, 0)), isFalse);
      expect(const VersionRef(1, 2, 0).isNewerThan(const VersionRef(1, 2, 1)), isFalse);
    });

    test('`1.2.0+6` 与 `v1.2.0` 是同一个版本', () {
      expect(VersionRef.tryParse('1.2.0+6'), VersionRef.tryParse('v1.2.0'));
    });
  });

  group('Release JSON 解析', () {
    Map<String, dynamic> release({String tag = 'v1.2.0', List<Object?>? assets}) =>
        <String, dynamic>{
          'tag_name': tag,
          'body': '· 修了 A\n· 修了 B',
          'html_url': 'https://github.com/block255/mathlang/releases/tag/v1.2.0',
          'assets': assets ??
              <Object?>[
                <String, dynamic>{
                  'name': 'mathlang-v1.2.0-win64-setup.zip',
                  'browser_download_url': 'https://x/setup.zip',
                  'size': 111,
                },
                <String, dynamic>{
                  'name': 'mathlang-1.2.0-x64.msix',
                  'browser_download_url': 'https://x/app.msix',
                  'size': 14252047,
                },
              ],
        };

    test('按后缀找 msix（不拼 URL），并带出说明与发布页', () {
      final UpdateInfo? u = UpdateInfo.tryParse(release());
      expect(u, isNotNull);
      expect(u!.tag, 'v1.2.0');
      expect(u.version, const VersionRef(1, 2, 0));
      expect(u.canInstall, isTrue);
      expect(u.msixUrl, 'https://x/app.msix');
      expect(u.msixSize, 14252047);
      expect(u.pageUrl, contains('releases/tag/v1.2.0'));
      expect(u.notes, contains('修了 A'));
    });

    test('没有 msix 附件 ⇒ 只能去发布页（canInstall = false）', () {
      final UpdateInfo? u = UpdateInfo.tryParse(release(assets: <Object?>[
        <String, dynamic>{
          'name': 'mathlang-v1.2.0-win64-setup.zip',
          'browser_download_url': 'https://x/setup.zip',
        },
      ]));
      expect(u, isNotNull);
      expect(u!.canInstall, isFalse);
    });

    test('tag 不像版本 / 不是 Map ⇒ null（不抛）', () {
      expect(UpdateInfo.tryParse(release(tag: 'latest')), isNull);
      expect(UpdateInfo.tryParse(release(tag: '')), isNull);
      expect(UpdateInfo.tryParse('not a map'), isNull);
      expect(UpdateInfo.tryParse(null), isNull);
    });
  });

  group('限频 · 该不该自动查', () {
    final DateTime now = DateTime(2026, 10, 28, 14, 0);

    test('关掉开关 ⇒ 一次都不查', () {
      expect(
        shouldAutoCheck(enabled: false, lastCheckAt: null, now: now),
        isFalse,
      );
    });

    test('从没查过 ⇒ 查', () {
      expect(shouldAutoCheck(enabled: true, lastCheckAt: null, now: now), isTrue);
    });

    test('24 小时内查过 ⇒ 不查；超过 24 小时 ⇒ 查', () {
      expect(
        shouldAutoCheck(
            enabled: true, lastCheckAt: now.subtract(const Duration(hours: 23)), now: now),
        isFalse,
      );
      expect(
        shouldAutoCheck(
            enabled: true, lastCheckAt: now.subtract(const Duration(hours: 25)), now: now),
        isTrue,
      );
    });

    test('时钟被往回调过（上次检查在未来）⇒ 还是查，别卡死', () {
      expect(
        shouldAutoCheck(
            enabled: true, lastCheckAt: now.add(const Duration(hours: 5)), now: now),
        isTrue,
      );
    });
  });

  group('该不该弹窗', () {
    const VersionRef cur = VersionRef(1, 1, 2);

    test('没有更新 ⇒ 不弹（无论手动还是自动）', () {
      for (final bool manual in <bool>[true, false]) {
        expect(
          shouldPromptUpdate(
              current: cur, latest: const VersionRef(1, 1, 2), manual: manual),
          isFalse,
        );
        expect(
          shouldPromptUpdate(
              current: cur, latest: const VersionRef(1, 0, 9), manual: manual),
          isFalse,
        );
      }
    });

    test('自动检查：「暂不更新」过的那个版本不再弹（只跳过这一个）', () {
      expect(
        shouldPromptUpdate(
            current: cur,
            latest: const VersionRef(1, 2, 0),
            ignoredVersion: '1.2.0',
            manual: false),
        isFalse,
      );
      // 更下一个版本照样提示
      expect(
        shouldPromptUpdate(
            current: cur,
            latest: const VersionRef(1, 3, 0),
            ignoredVersion: '1.2.0',
            manual: false),
        isTrue,
      );
    });

    test('手动点「检查更新」⇒ 无视「已忽略」，该提示就提示', () {
      expect(
        shouldPromptUpdate(
            current: cur,
            latest: const VersionRef(1, 2, 0),
            ignoredVersion: '1.2.0',
            manual: true),
        isTrue,
      );
    });

    test('版本解析失败（null）⇒ 不弹', () {
      expect(
        shouldPromptUpdate(current: null, latest: const VersionRef(1, 2, 0), manual: true),
        isFalse,
      );
      expect(shouldPromptUpdate(current: cur, latest: null, manual: true), isFalse);
    });
  });
}
