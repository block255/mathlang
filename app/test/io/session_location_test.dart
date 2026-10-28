// 1.2.3 守卫：**设置/草稿到底存哪儿**（2026-10-28 实测事故）
//
// 事故现场：打包版（MSIX）的 exe 在 `C:\Program Files\WindowsApps\...`（只读），
// 往它旁边写会被 Windows 虚拟化到 `%LOCALAPPDATA%\Packages\<包族名>\LocalCache\Roaming\`。
// 看着"存上了"（关掉重开设置还在），但那是**包内私有数据，卸载即删** ——
// 用户实测：卸载重装后页位/字号全丢（选"N 保留数据"也没用）。
//
// ⇒ 口径：**打包版优先 `%APPDATA%\mathlang\`**（卸载不动、升级继承）；
//         绿色版仍优先 exe 同目录（便携就该跟着文件夹走）。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/io/session_data.dart';
import 'package:mathlang/io/session_store_native.dart';

String _exeDirCandidate() =>
    '${File(Platform.resolvedExecutable).parent.path}'
    '${Platform.pathSeparator}$kSessionFileName';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('mathlang-loc-'));
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  SessionData sample() => SessionData(
      text: '甲\n', savedText: '甲\n', title: 't', savedAt: DateTime.now());

  group('落点顺序', () {
    test('打包版：首选 %APPDATA%\\mathlang\\（包外、卸载不动）', () async {
      final NativeSessionStore s =
          NativeSessionStore(forcePackaged: true, appDataOverride: tmp.path);
      final String d = await s.describe();
      expect(d, startsWith(tmp.path));
      expect(d, contains('mathlang'));
      expect(d, isNot(_exeDirCandidate()));
    });

    test('绿色版：仍首选 exe 同目录（便携跟着文件夹走）', () async {
      final NativeSessionStore s =
          NativeSessionStore(forcePackaged: false, appDataOverride: tmp.path);
      expect(await s.describe(), _exeDirCandidate());
    });
  });

  group('打包版真的写在包外', () {
    test('save ⇒ 文件落在 %APPDATA%\\mathlang\\，且 describe 指向它', () async {
      final NativeSessionStore s =
          NativeSessionStore(forcePackaged: true, appDataOverride: tmp.path);
      expect(await s.save(sample()), isTrue);
      final String d = await s.describe();
      expect(d, startsWith(tmp.path));
      expect(File(d).existsSync(), isTrue, reason: '落点必须真的有文件');
    });

    test('已存在的旧文件能被读出来（升级/迁移后的正常路径）', () async {
      final NativeSessionStore first =
          NativeSessionStore(forcePackaged: true, appDataOverride: tmp.path);
      await first.save(sample());

      final NativeSessionStore second =
          NativeSessionStore(forcePackaged: true, appDataOverride: tmp.path);
      final SessionData? back = await second.load();
      expect(back, isNotNull);
      expect(back!.text, '甲\n');
    });
  });

  group('写不进去要能说出来（不许静默）', () {
    test('落点被一个"文件"占位 ⇒ save 返回 false（不抛）', () async {
      final File blocker = File('${tmp.path}${Platform.pathSeparator}blocker');
      blocker.writeAsStringSync('x');
      final NativeSessionStore s = NativeSessionStore(
          overridePath: '${blocker.path}${Platform.pathSeparator}$kSessionFileName');
      expect(await s.save(sample()), isFalse,
          reason: '写不进去必须如实返回 false —— 界面据此显示"写入失败"');
    });
  });
}
