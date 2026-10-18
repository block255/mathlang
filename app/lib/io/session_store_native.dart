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
  NativeSessionStore({String? overridePath}) : _overridePath = overridePath; // ignore: prefer_initializing_formals

  /// 测试可以钉死一个路径
  final String? _overridePath;

  String? _resolved;
  int _saveCount = 0;

  @override
  int get saveCount => _saveCount;

  /// 候选路径（按优先级）：exe 同目录 → `%APPDATA%\mathlang\`
  List<String> _candidates() {
    final String? o = _overridePath;
    if (o != null && o.isNotEmpty) return <String>[o];
    final List<String> out = <String>[];
    try {
      final String exeDir = File(Platform.resolvedExecutable).parent.path;
      if (exeDir.isNotEmpty) out.add('$exeDir${Platform.pathSeparator}$kSessionFileName');
    } catch (_) {
      // 忽略：拿不到 exe 目录就只剩兜底
    }
    final String? appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      out.add('$appData${Platform.pathSeparator}mathlang'
          '${Platform.pathSeparator}$kSessionFileName');
    }
    return out;
  }

  /// 已经确定下来的落点（第一次写成功之后就不再变）
  String? get resolvedPath => _resolved;

  @override
  Future<String> describe() async {
    final String? r = _resolved;
    if (r != null) return r;
    final List<String> c = _candidates();
    return c.isEmpty ? '（没有可写的目录）' : c.first;
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
