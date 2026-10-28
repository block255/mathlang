// 1.2.4 守卫：**设置/草稿到底存哪儿**（2026-10-28 两次实测事故）
//
// ① 打包版的 exe 在 `C:\Program Files\WindowsApps\...`（只读）⇒ 写旁边会被 Windows
//    虚拟化到 `Packages\<包族名>\LocalCache\...`；
// ② **`%APPDATA%` 也一样被虚拟化**（实测：应用以为写到
//    `C:\Users\me\AppData\Roaming\mathlang\...`，可那个真文件不存在，字节全在包内）。
//
// ⇒ 口径：**打包版首选 `%USERPROFILE%\mathlang\`**（用户配置根下的自定义文件夹，
//   不在虚拟化名单里 ⇒ 真文件、卸载不删、升级继承）；绿色版仍首选 exe 同目录。
//   `%APPDATA%` 与 exe 同目录**留着当读取候选**，老数据靠它们读出来再迁移。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mathlang/io/session_data.dart';
import 'package:mathlang/io/session_store_native.dart';

String _exeDirCandidate() =>
    '${File(Platform.resolvedExecutable).parent.path}'
    '${Platform.pathSeparator}$kSessionFileName';

void main() {
  late Directory tmp; // 冒充 %USERPROFILE%
  late Directory fakeAppData; // 冒充 %APPDATA%
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mathlang-profile-');
    fakeAppData = Directory.systemTemp.createTempSync('mathlang-appdata-');
  });
  tearDown(() {
    for (final Directory d in <Directory>[tmp, fakeAppData]) {
      try {
        d.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  SessionData sample() => SessionData(
      text: '甲\n', savedText: '甲\n', title: 't', savedAt: DateTime.now());

  NativeSessionStore packaged() => NativeSessionStore(
        forcePackaged: true,
        profileOverride: tmp.path,
        appDataOverride: fakeAppData.path,
      );

  group('落点顺序', () {
    test('打包版：首选 %USERPROFILE%\\mathlang\\（不在虚拟化名单里）', () async {
      final String d = await packaged().describe();
      expect(d, startsWith(tmp.path));
      expect(d, contains('mathlang'));
      expect(d, isNot(_exeDirCandidate()));
      expect(d, isNot(startsWith(fakeAppData.path)),
          reason: '%APPDATA% 会被打包版虚拟化 ⇒ 不能当首选');
    });

    test('绿色版：仍首选 exe 同目录（便携跟着文件夹走）', () async {
      final NativeSessionStore s = NativeSessionStore(
        forcePackaged: false,
        profileOverride: tmp.path,
        appDataOverride: fakeAppData.path,
      );
      expect(await s.describe(), _exeDirCandidate());
    });
  });

  group('打包版真的写在包外', () {
    test('save ⇒ 文件落在 %USERPROFILE%\\mathlang\\，且 describe 指向它', () async {
      final NativeSessionStore s = packaged();
      expect(await s.save(sample()), isTrue);
      final String d = await s.describe();
      expect(d, startsWith(tmp.path));
      expect(File(d).existsSync(), isTrue, reason: '落点必须真的有文件（不是虚拟化幻觉）');
    });

    test('已存在的旧文件能被读出来（升级后的正常路径）', () async {
      await packaged().save(sample());
      final SessionData? back = await packaged().load();
      expect(back, isNotNull);
      expect(back!.text, '甲\n');
    });

    test('老数据在 %APPDATA%（虚拟化那份）⇒ 读出来并迁到 %USERPROFILE%', () async {
      // 造一份"老位置"的文件：%APPDATA%\mathlang\mathlang-session.json
      final Directory oldDir =
          Directory('${fakeAppData.path}${Platform.pathSeparator}mathlang')
            ..createSync(recursive: true);
      final File oldFile =
          File('${oldDir.path}${Platform.pathSeparator}$kSessionFileName');
      oldFile.writeAsStringSync(
          '{"text":"老内容\\n","savedText":"老内容\\n","title":"t",'
          '"savedAt":"${DateTime.now().toIso8601String()}"}');

      final NativeSessionStore fresh = packaged();
      final SessionData? back = await fresh.load();
      expect(back, isNotNull, reason: '老的 %APPDATA% 那份必须能读出来');
      expect(back!.text, '老内容\n');
      // 迁移：读完之后应当已经写到首选位置
      final String now = await fresh.describe();
      expect(now, startsWith(tmp.path), reason: '读到老位置后要迁到 %USERPROFILE%');
      expect(File(now).existsSync(), isTrue);
      expect(oldFile.existsSync(), isFalse, reason: '迁移成功后旧的删掉（它已不权威）');
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
