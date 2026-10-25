# signing\ —— 本项目专属签名密钥（**永不入版本库**）

> ⚠️ **2026-10-25 安全事件（已处置）**：旧版本文档与 `scripts/pack_msix.ps1` 曾把 PFX 口令以明文写入仓库
> （`signing/README.md` / 脚本的 signtool 调用 / 一份旧交接快照）。**该口令应当作已泄露**：
> 仓库是公开的，而且这串口令从初始提交 `3fe48a5` 起就在历史里（删文件不能从历史里消除）。
>
> **已做的处置（2026-10-25 18:4x）**
> 1. 明文全部移除（PR #1，合并 `9ff14ff`）：脚本改读 `$env:MATHLANG_PFX_PASSWORD`，缺就报错退出；
> 2. **PFX 口令已轮换**：用新随机口令重新导出了 `mathlang-selfsign.pfx`——**同一把私钥 / 同一张证书**，
>    指纹仍是 `93FAAFAD89470D121BD77321FB96104A29254BFA` ⇒ 已发布的 exe / msix 签名照旧有效、
>    已装用户**不用重新信任**；**旧口令 `mathlang-selfsign` 已失效**；
> 3. **`pack_msix.ps1` 改成直接走证书库**（`signtool /sha1 <指纹>`；本机实测**无口令、无弹窗**、
>    签名 `Valid`）⇒ **彻底不需要口令**。pfx 只剩"别的机器 / CI"用的可选路径（那时才用
>    `MATHLANG_PFX_PASSWORD`）。目录里那份 `mathlang-selfsign.pfx` 因此**已用不上**（口令未知也无所谓），
>    私钥仍在 `Cert:\CurrentUser\My`（指纹 `93FAAFAD…`）。
>
> 4. **历史不重写**（私钥从未入库 ⇒ 旧口令单独没有价值；重写要改 100+ 提交 SHA + 重建 tag + 重传资产）。
>
> 验证：`flutter analyze` 零告警 · 全量 1615 通过 · 用新口令重跑 `scripts\pack_msix.ps1`，
> msix 签名 `Valid · CN=数语引擎（自签）`。

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

> 现状：仓库里的 `signing/` **只保留本 README + .gitkeep**；`.jks` / `.pfx` / `key.properties` 都在本机、被
> `.gitignore` 拦掉。Android 正式版阶段（S8）再生成密钥库，生成前先跑一次
> `flutter doctor --android-licenses` 并移植流水账的 `build_release.ps1`。

### Windows 自签证书（2026-10-19，U4）

Windows 11（build 26200）对**未签名 exe** 一律弹「已保护你的电脑」——与语言/打包方式无关，
实测同事的 PyInstaller 程序同样被拦。⇒ exe 必须签名。

| 项 | 值 |
|---|---|
| 证书主体 | `CN=数语引擎（自签）` |
| 指纹 | `93FAAFAD89470D121BD77321FB96104A29254BFA` |
| 有效期 | 到 2036-10-19（10 年；签名**带公网时间戳**，过期后已签的 exe 仍有效） |
| 私钥 | `mathlang-selfsign.pfx`（口令由 `MATHLANG_PFX_PASSWORD` 提供；**本目录已被 .gitignore 拦掉**） |
| 公钥 | `数语引擎-自签证书.cer`（随发布包分发） |
| 受信任位置 | `当前用户\受信任的根证书颁发机构`（**不需要管理员**） |
| 签名方式 | PowerShell `Set-AuthenticodeSignature`（本机没装 Windows SDK 的 signtool） |

**重新生成**（只在证书丢失时做）：

```powershell
$cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject 'CN=数语引擎（自签）' `
  -KeyUsage DigitalSignature -KeyExportPolicy Exportable -NotAfter (Get-Date).AddYears(10) `
  -CertStoreLocation Cert:\CurrentUser\My -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3')
# 口令只从密码管理器取；这里交互输入，绝不写进脚本/仓库
$pfxPwd = Read-Host -AsSecureString 'PFX 口令'
Export-PfxCertificate   -Cert $cert -FilePath .\mathlang-selfsign.pfx -Password $pfxPwd
Export-Certificate      -Cert $cert -FilePath .\数语引擎-自签证书.cer
# 装进受信任根（会弹一次"是否信任"，点"是"）
Import-Certificate -CertStoreLocation Cert:\CurrentUser\Root -FilePath .\数语引擎-自签证书.cer
```

**口令存放（2026-10-25 起）**

- PFX 口令用密码管理器生成/保存，**不要**用 `setx` 持久化明文。
- 本地打包只在当前 PowerShell 会话里设置，结束就删除：

  ```powershell
  $env:MATHLANG_PFX_PASSWORD = Read-Host 'PFX 口令'
  powershell -ExecutionPolicy Bypass -File scripts\pack_msix.ps1
  Remove-Item Env:MATHLANG_PFX_PASSWORD
  ```

- `scripts\pack_msix.ps1` 缺这个变量会直接报错退出；不要把口令写回脚本或文档。
- 如果 PFX 曾离开本机，或旧口令已被提交过：**重新生成证书**（并接受已装用户需要重新信任一次），不要只改口令。

**发布流程**：`scripts\build_exe.ps1`（自动签名）→ `scripts\pack_release.ps1`（改名 + 打包）→
`scripts\pack_msix.ps1`（MSIX + 安装包，需要 `MATHLANG_PFX_PASSWORD`）。
发布包里 `启动数语引擎.cmd` 会先 `certutil -user -store Root <指纹>` 查证书，没装就
`certutil -user -addstore Root 证书.cer`（系统弹一次"是"）再启动 ⇒ 首次打开不再被拦。

**边界（写清免得误判）**：
- **本机**装根后彻底不弹；**别人的机器**要装一次 `.cer`（启动脚本代劳），否则仍弹；
- 自签没有第三方背书，少数安全软件仍可能提示；
- 将来走 SignPath（开源免费签名）后，发布者会变成 "SignPath Foundation"，这张自签证书退休。
