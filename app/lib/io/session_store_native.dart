// 数语引擎 · **本地暂存（桌面实现）**：写一个 JSON 到 exe 同目录（S4-e-①）
//
// 位置（用户拍板"exe 同目录"）：
//   `<exe 所在目录>\mathlang-session.json`
// 兜底（写不进去时，例如装在 Program Files）：
//   `%APPDATA%\mathlang\mathlang-session.json`
//
// 三条实现纪律：
//   ① **原子写**：先写 `.tmp` 再 `rename` —— 断电/崩溃不会留下半个 JSON 把下次启动带崩；
//   ② **安静失败**：任何 IO 异常都吞掉并返回 `false`（只影响"这次没存上"，绝不能打断编辑）；
//   ③ 文件**是人可读的 UTF-8**（用户想手改/备份都行）。

import 'dart:convert';
import 'dart:io';

import 'install_kind.dart';
import 'session_data.dart';
import 'session_store.dart';

/// 会话文件名（两个位置用同一个名字）
const String kSessionFileName = 'mathlang-session.json';

/// ★ 自动清理策略（2026-10-18 用户提出"暂存要有自动清理"）
///
/// 全部在**启动读取时**顺带做（不另开定时器）：
///   ① **残留 `.tmp`**：原子写的中间文件（崩溃/断电留下的）⇒ 直接删；
///   ② **过期**：[kSessionMaxAge] 没动过 ⇒ 不恢复 + 删除；
///      已保存且干净的那份更早清（[kCleanSessionMaxAge]）—— 内容已经在用户文件里了；
///   ③ **超大**：正文超过 [kSessionMaxBytes] ⇒ **不写**（安静失败），
///      免得一份几 MB 的 JSON 每 800ms 被整个重写。
///
/// ★ 固定文件名、只存一份 ⇒ **不会堆积**（这是"不攒垃圾"的前提）。
const Duration kSessionMaxAge = Duration(days: 30);
const Duration kCleanSessionMaxAge = Duration(days: 7);
const int kSessionMaxBytes = 8 * 1024 * 1024;

SessionStore createSessionStore() => NativeSessionStore();

class NativeSessionStore implements SessionStore {
  NativeSessionStore({
    String? overridePath,
    bool? forcePackaged,
    String? appDataOverride,
    String? profileOverride,
  })  : _overridePath = overridePath, // ignore: prefer_initializing_formals
        _forcePackaged = forcePackaged, // ignore: prefer_initializing_formals
        _appDataOverride = appDataOverride, // ignore: prefer_initializing_formals
        _profileOverride = profileOverride; // ignore: prefer_initializing_formals

  /// 测试可以钉死一个路径
  final String? _overridePath;

  /// 测试用：强制"打包版 / 绿色版"两种形态（真机上是 [isPackagedApp] 判的）
  final bool? _forcePackaged;

  /// 测试用：把 `%APPDATA%` 换成临时目录（**绝不要在测试里真写用户的 APPDATA**）
  final String? _appDataOverride;

  /// 测试用：把 `%USERPROFILE%` 换成临时目录
  final String? _profileOverride;

  String? _resolved;
  int _saveCount = 0;

  @override
  int get saveCount => _saveCount;

  /// 落点候选（**顺序按形态走**）。
  ///
  /// ★★★ 2026-10-28 **两次实测纠正**（都写在这里，别再踩）：
  ///   ① 打包版的 exe 在 `C:\Program Files\WindowsApps\...`（只读），往旁边写会被
  ///      Windows **虚拟化**到 `Packages\<包族名>\LocalCache\...`；
  ///   ② **`%APPDATA%` 也一样被虚拟化** —— 实测：应用里认为写到了
  ///      `C:\Users\me\AppData\Roaming\mathlang\...`，可那个真文件**不存在**，
  ///      字节全在 `Packages\...\LocalCache\Roaming\mathlang\...`。
  ///      （所以我上一版"改成 %APPDATA% 就出包了"的结论是错的，这里改掉。）
  ///
  /// ⇒ **只有"用户配置目录根下的自定义文件夹"不在虚拟化名单里**，所以打包版首选
  ///   **`%USERPROFILE%\mathlang\mathlang-session.json`** —— 真文件、卸载不删、升级继承。
  ///   仍然把 `%APPDATA%` 与 exe 同目录留在候选里：**读**它们能把老数据读出来
  ///   （读会被虚拟化指回包内），于是"迁移到新落点"自动成立。
  ///   绿色版继续首选 exe 同目录（便携就该跟着文件夹走）。
  List<String> _candidates() {
    final String? o = _overridePath;
    if (o != null && o.isNotEmpty) return <String>[o];
    final String sep = Platform.pathSeparator;
    final List<String> exe = <String>[];
    try {
      final String exeDir = File(Platform.resolvedExecutable).parent.path;
      if (exeDir.isNotEmpty) exe.add('$exeDir$sep$kSessionFileName');
    } catch (_) {
      // 忽略：拿不到 exe 目录就只剩兜底
    }
    final List<String> appData = <String>[];
    final String? ad = _appDataOverride ?? Platform.environment['APPDATA'];
    if (ad != null && ad.isNotEmpty) {
      appData.add(<String>[ad, 'mathlang', kSessionFileName].join(sep));
    }
    final List<String> profile = <String>[];
    final String? prof = _profileOverride ?? Platform.environment['USERPROFILE'];
    if (prof != null && prof.isNotEmpty) {
      profile.add(<String>[prof, 'mathlang', kSessionFileName].join(sep));
    }
    final bool packaged = _forcePackaged ?? isPackagedApp();
    return packaged
        ? <String>[...profile, ...appData, ...exe]
        : <String>[...exe, ...appData, ...profile];
  }

  /// 已经确定下来的落点（第一次写成功之后就不再变）
  String? get resolvedPath => _resolved;

  @override
  Future<String> describe() async {
    final List<String> c = _candidates();
    final String r = _resolved ?? (c.isEmpty ? '' : c.first);
    if (r.isEmpty) return '（没有可写的目录）';
    // ★★ 1.2.4：**校验这个路径上真的有文件**。
    //   打包版有"文件系统虚拟化"：应用以为写到了 A，字节其实在
    //   `Packages\<包族名>\LocalCache\...`（实测：%APPDATA% 也被重定向）。
    //   只显示路径就是骗人 —— 所以写成功之后要回头看一眼文件在不在。
    try {
      final bool wrote = _resolved != null;
      if (wrote && !File(r).existsSync()) {
        return '$r（⚠ 系统已重定向：这个文件其实不在那儿，可能落在包内目录）';
      }
    } catch (_) {
      // 检查本身失败就别吓人，照常显示路径
    }
    return r;
  }

  @override
  Future<SessionData?> load() async {
    for (final String path in _candidates()) {
      // ★ 清理 ①：原子写留下的 `.tmp`（崩溃/断电的残骸）
      try {
        final File tmp = File('$path.tmp');
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {
        // 删不掉就算了（下次写会覆盖它）
      }
      try {
        final File f = File(path);
        if (!await f.exists()) continue;
        final String src = await f.readAsString();
        final SessionData? d = SessionData.tryParse(src);
        if (d == null) {
          // 坏文件（半个 JSON 之类）⇒ 删掉，别每次启动都白读一遍
          try {
            await f.delete();
          } catch (_) {}
          continue;
        }
        // ★ 清理 ②：过期
        if (_expired(d)) {
          try {
            await f.delete();
          } catch (_) {}
          continue;
        }
        // ★★ 1.2.3：**从"非首选"落点读到的 ⇒ 迁移到首选落点**。
        //   现场：打包版的设置在 `Packages\<包族名>\LocalCache\Roaming\mathlang\`
        //   （exe 目录被虚拟化的结果），卸载就删。现在首选是 `%APPDATA%\mathlang\`
        //   ⇒ 老用户第一次跑新版时把旧文件**搬**出来，然后删掉旧的（它已不权威）。
        final String preferred = _candidates().first;
        if (path != preferred) {
          if (await _writeAtomic(preferred, src)) {
            _resolved = preferred;
            try {
              await f.delete();
            } catch (_) {}
            return d;
          }
          // 搬不过去也没关系：这次先按老位置用，下次 save 会再试首选
        }
        _resolved = path;
        return d;
      } catch (_) {
        // 坏文件 / 读不了 ⇒ 试下一个候选
      }
    }
    return null;
  }

  /// 这份暂存该不该自动清掉？
  bool _expired(SessionData d) {
    final DateTime? at = d.savedAt;
    if (at == null) return false; // 老版本没写时间 ⇒ 当成"刚存过"，不清
    final Duration age = DateTime.now().difference(at);
    if (age > kSessionMaxAge) return true;
    // 已保存且干净（内容在用户文件里）⇒ 更早清
    if (!d.dirty && age > kCleanSessionMaxAge) return true;
    return false;
  }

  @override
  Future<bool> save(SessionData data) async {
    final String json = _encode(data);
    // ★ 清理 ③：超大就别写（安静失败）—— 免得每 800ms 重写一个几 MB 的文件
    if (json.length > kSessionMaxBytes) return false;
    // 已确定的落点优先；否则按候选顺序试（第一次成功就记住）
    final List<String> order = <String>[
      ?_resolved,
      ..._candidates().where((String p) => p != _resolved),
    ];
    for (final String path in order) {
      if (await _writeAtomic(path, json)) {
        _resolved = path;
        _saveCount++;
        return true;
      }
    }
    // 所有候选都写不进去 ⇒ 返回 false（调用方据此把"写入失败"显示出来）
    return false;
  }

  @override
  Future<void> clear() async {
    for (final String path in <String>[
      ?_resolved,
      ..._candidates(),
    ]) {
      try {
        final File f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {
        // 删不掉就算了（下次 save 会覆盖）
      }
    }
  }

  /// 原子写：`.tmp` → `rename`
  Future<bool> _writeAtomic(String path, String json) async {
    try {
      final File f = File(path);
      final Directory dir = f.parent;
      if (!await dir.exists()) await dir.create(recursive: true);
      final File tmp = File('$path.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(path);
      return true;
    } catch (_) {
      return false;
    }
  }

  String _encode(SessionData d) => jsonEncode(d.toJson());
}
