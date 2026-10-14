# signing\ —— 本项目专属签名密钥（**永不入版本库**）

本目录按工作区约定放在 `app\` 的**同级**（`app\android\app\build.gradle.kts` 里写的是
`rootProject.file("../../signing")`，**不写绝对路径** → 位置错了不会报错，只会**静默回落到 debug 签名**）。

## 里面会有什么

| 文件 | 说明 |
|---|---|
| `mathlang-release.jks` | 正式签名密钥库（**生成后务必备份两份**） |
| `key.properties` | 密钥库口令与别名（正式版阶段创建） |

## 三条硬约束（沿用流水账的经验教训）

1. **签名密钥永久固定** —— 换了密钥，已安装的用户**无法覆盖升级**（只能卸载重装 → 数据丢失）。
   密钥丢失 = 永远无法给老用户升级。
2. **绝不入版本库**（`.gitignore` 已在仓库级拦掉 `signing/*`；真要提交请先三思）。
3. **发布前必须验签**：APK 时间戳 ≥ 源码、含 `libflutter.so`、签名主体是 `mathlang`
   （防止 debug 签名冒充正式包）。

> 现状：**本目录为空**。正式版阶段（S8）再生成，生成前先跑一次
> `flutter doctor --android-licenses` 并移植流水账的 `build_release.ps1`。
