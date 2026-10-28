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

  group('Release JSON 解析', () {    Map<String, dynamic> release({String tag = 'v1.2.0', List<Object?>? assets}) =>
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

    // ★ 2026-10-28 晚：**探针用的假 release** 也必须能被解析 —— 否则"伪造一个检测到新版本"
    // 这条验证手段本身就不成立。JSON 与 `_cache/tmp/probe/latest.json` 同形。
    test('探针假 release（v9.9.9 + 假 msix 资产）照样能解析', () {
      final UpdateInfo? u = UpdateInfo.tryParse(<String, dynamic>{
        'tag_name': 'v9.9.9',
        'name': '9.9.9 探针版（假的，只为验弹窗）',
        'body': '## 这是探针造的假版本',
        'html_url': 'https://github.com/block255/mathlang/releases',
        'assets': <Object?>[
          <String, dynamic>{
            'name': 'probe-fake-x64.msix',
            'browser_download_url': 'http://127.0.0.1:8765/probe-fake-x64.msix',
            'size': 1,
          },
        ],
      });
      expect(u, isNotNull);
      expect(u!.version, const VersionRef(9, 9, 9));
      expect(u.canInstall, isTrue, reason: '有 msix 资产 ⇒ 一键更新按钮可用');
      expect(u.notes, contains('探针'));
    });
  });

  group('启动检查 · 该不该自动查', () {
    // ★★★ 2026-10-28 晚（用户实测推翻限频）：原来按"距上次 ≥24 小时"限频，
    //   结果装完新版启动查过一次（已是最新），几分钟后发了新版本，用户再启动时
    //   **24 小时内不再查** ⇒ 自动弹窗一次都没出现过。
    //   用户原话：「这个软件数学编辑的定位就注定一天之内不会频繁多次打开」
    //   ⇒ **去掉限频，每次启动查一次**。判据函数从此**没有时间参数** ——
    //   这就是最强的守卫：想再塞回限频，必须先改这个签名（会红在这里）。
    test('开关开着 ⇒ 每次启动都查（没有时间参数 = 不可能被限频挡住）', () {
      expect(shouldAutoCheck(enabled: true), isTrue);
    });

    test('关掉开关 ⇒ 一次都不查（这是用户明确意愿，不是限频）', () {
      expect(shouldAutoCheck(enabled: false), isFalse);
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
