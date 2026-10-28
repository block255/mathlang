// 数语引擎 · **语义化版本**（D1「检查更新」用；2026-10-28）
//
// 为什么单独一个文件：版本比较是**判据**，不是 UI —— 放进 `core` 才能被单测钉住，
// 也不会让网络层/界面各自写一套（"比版本"写错的表现是"永远认为有新版本"或"永远不提示"，
// 而这两种都很难从界面上看出来）。
//
// 口径：
//   · 只比 `x.y.z` 三段；**构建号（`+4`）与 tag 前缀 `v` 不参与比较**
//     （`1.2.0+6` 与 `v1.2.0` 是同一个版本）；
//   · 预发布后缀（`-beta.1`）**先不管** —— 我们目前不发预发布；真发了再说，
//     现在的行为是"忽略后缀、只比三段"，属于保守（不会被 beta 骗着降级）。

/// 一个 `x.y.z` 版本号。
class VersionRef implements Comparable<VersionRef> {
  const VersionRef(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  /// 从字符串解析；解析不了 ⇒ `null`（**绝不抛**，网络来的东西不可信）。
  ///
  /// 接受：`1.2.0` / `v1.2.0` / `1.2.0+6` / `v1.2.3+12` / ` 1.2.0 `
  static VersionRef? tryParse(String? raw) {
    if (raw == null) return null;
    var s = raw.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
    s = s.split('+').first; // 构建号不参与
    s = s.split('-').first; // 预发布后缀先不管
    final RegExpMatch? m = RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(s);
    if (m == null) return null;
    final int? a = int.tryParse(m.group(1)!);
    final int? b = int.tryParse(m.group(2)!);
    final int? c = int.tryParse(m.group(3)!);
    if (a == null || b == null || c == null) return null;
    return VersionRef(a, b, c);
  }

  /// [o] 是不是比自己新（严格大于）
  bool isNewerThan(VersionRef o) => compareTo(o) > 0;

  @override
  int compareTo(VersionRef o) {
    if (major != o.major) return major.compareTo(o.major);
    if (minor != o.minor) return minor.compareTo(o.minor);
    return patch.compareTo(o.patch);
  }

  @override
  bool operator ==(Object other) =>
      other is VersionRef &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}
