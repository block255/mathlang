// 数语引擎 · **本地暂存的后端抽象**（S4-e-①，2026-10-18）
//
// 为什么抽象：① 测试要能注入**假 store**（不能真写磁盘）；② 平台要分叉。
//
// ★ 用户拍板的落点：**exe 同目录**（原话"可以 exe 同目录"）。
//   实现里仍留一条兜底：写不进去（例如装在 Program Files 里）就退到
//   `%APPDATA%\mathlang\session.json`，并把**实际用的路径**告诉界面（设置页「高级」里显示）。
//
// ★ 失败一律**不打断编辑**：写失败只是"这次没存上"，不弹错、不抛（原则 5 只要求"可疑要可见"，
//   而这里已经用"暂存位置 + 上次保存时间"两行读数把它变可见了）。

import 'session_data.dart';

/// 会话快照的存取
abstract class SessionStore {
  /// 读上次的会话；没有 / 坏了 ⇒ `null`
  Future<SessionData?> load();

  /// 写一份快照（失败也要**安静地**返回 `false`，不抛）
  Future<bool> save(SessionData data);

  /// 清掉本地暂存（设置页「高级 → 清除本地暂存」）
  Future<void> clear();

  /// 给人看的落点说明（`C:\...\session.json` / `浏览器 localStorage`）
  Future<String> describe();

  /// 已经存过几次（测试与诊断用）
  int get saveCount;
}

/// 一次**都不落盘**的实现（Web 开发预览用；正式端是 Windows/Android）
class NoopSessionStore implements SessionStore {
  const NoopSessionStore();

  @override
  int get saveCount => 0;

  @override
  Future<void> clear() async {}

  @override
  Future<String> describe() async => '未启用（Web 预览不写本地文件）';

  @override
  Future<SessionData?> load() async => null;

  @override
  Future<bool> save(SessionData data) async => false;
}
