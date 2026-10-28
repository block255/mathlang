// 数语引擎 · **当前进程是按哪种形态在跑**（2026-10-28）
//
// 为什么单开一个文件：这个判断有两处要用，而它一旦写错就会"数据存错地方"或"更新装不上"：
//   ① `io/session_store_native.dart` —— 决定设置/草稿写哪儿；
//   ② `io/update_gateway_native.dart` —— 决定"一键更新"能不能用（绿色版没有包身份）。
//
// 判据只看 exe 路径：MSIX 安装的真身跑在
//   `C:\Program Files\WindowsApps\<包族名>\...\数语引擎.exe`
// 绿色版跑在用户自己解压的目录里。这条不需要权限、也不依赖平台 API。
//
// ★ 为什么这个区分对"存哪儿"至关重要（2026-10-28 实测）：
//   打包版往 exe 目录写会被 Windows **虚拟化**到
//   `%LOCALAPPDATA%\Packages\<包族名>\LocalCache\Roaming\...` —— 看着"存上了"，
//   但那是**包内私有数据**，**卸载就整个删掉**（用户实测：卸载重装后页位/字号全丢）。
//   而 `%APPDATA%\<产品名>\` 是用户的漫游目录，卸载不动、升级继承 ⇒ 应该优先用它。

import 'dart:io';

/// 当前进程是不是跑在 **MSIX 包**里（有包身份）
bool isPackagedApp() {
  try {
    return Platform.resolvedExecutable.toLowerCase().contains('windowsapps');
  } catch (_) {
    return false;
  }
}
