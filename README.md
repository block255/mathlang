# 数语引擎（mathlang）

> **一个可视化编辑的数学文档编辑器。**
> 数学公式就在正文里**直接看得见、点得到、改得了** —— 点符号就能写公式，文档以 A4 分页呈现，一键导出 PDF 与图片集；
> 底层用标准 Markdown + LaTeX 存储 —— 纯文本、可版本管理、AI 可以直接读写。

Windows 64 位 · Flutter 桌面应用 · MIT

---

## 它解决什么

| 市面上的现状 | 这里的做法 |
|---|---|
| 写数学要学 LaTeX 语法 | **可视化编辑**：符号面板 + 模板插入 + 占位符跳转，数学编码永不出现 |
| 公式是"卡片"，要进去要出来 | **平权**：一条字符流里文字与数学地位相同，光标、选择、删除都是同一套语义 |
| 导出只能给截图 | **A4 分页**：编辑时的分页 = 导出的 PDF 页 = 图片集的一张图 |
| 换行对齐靠手数 | 多行推导用 `aligned` 模板按等号对齐 |
| 符号面板缺失 / 快捷键不能改 | 分类面板 + 搜索（中文名/别名/拼音/LaTeX）+ **48 条可改键快捷键** |

## 三条最要紧的设计约定

1. **平权**（最高原则）：一条可见流里，汉字、字母、`≥`、分式、整段公式都是**同一层对象** ——
   没有模式、没有"进入/退出"、没有特权区域。数学不是"另一种东西"，只是字符被渲染成了二维。
2. **文档格式 = Markdown + 标准 LaTeX**：唯一事实来源是纯文本，AI 能直接读写；
   规范 md 导入**一字不改**，裸 LaTeX（AI 答案常见形态）会自动包成公式。
3. **静默失败必须可见**：渲染不了的命令、溢出一页的块、解析失败的行，都有提示或「诊断清单」。

设计文档在 [`notes/design/`](notes/design/)（《整体设计》《位点与结构导航》《界面与布局》…），
逐批开发记录在 [`notes/handover/`](notes/handover/)，踩坑经验在 [`notes/dev_log/`](notes/dev_log/)。

## 下载与安装（Windows 10/11 64 位）

到 [Releases](../../releases) 下载 **`mathlang-v1.0.0-win64-setup.zip`**，解压后双击
`数语引擎\双击我安装数语引擎.cmd`：

1. 会弹**一次**管理员授权（把本软件的自签证书放进「受信任人」）→ 点「是」；
2. 自动安装、自动打开，桌面出现「数语引擎」图标。

★ 完成这一步之后，**双击/开始菜单打开都不会再弹 SmartScreen**。
★ 现在用自签证书，所以那一次 UAC 省不掉；换成公共 CA 签名（开源项目可申请 SignPath）后就不需要了 ——
这是**未来的增强**，不是当前的阻塞。

也可以只取 `数语引擎.msix`（已签名）手工 `Add-AppxPackage`。

## 从源码构建

需要 Flutter **3.47.1**（stable）。

```powershell
cd app
flutter pub get
flutter analyze
flutter test          # 全量 1380 通过 + 0 skip
flutter build windows --release
```

打包（Windows）：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build_exe.ps1     # analyze + test + build + 自签 + 归档到 dist\v<版本>\
powershell -ExecutionPolicy Bypass -File scripts\pack_release.ps1  # 便携包 / 安装包 zip
powershell -ExecutionPolicy Bypass -File scripts\pack_msix.ps1     # MSIX + 一键安装脚本 + 分发目录
```

## 键盘

- **写作**：`Enter` 新段落 · `Shift+Enter` 段内换行 · `Ctrl+Z/Shift+Z` 撤销重做 ·
  `Ctrl+1/2/3` 标题 · `Ctrl+Alt+F/R/I/S/L/A/T/X/B` 九种模板 · `Ctrl+Enter` 分页符
- **面板键盘流**：`F6` 进符号面板（方向键移动 / `Enter` 或空格插入 / `1–8` 跳格 / `Tab` 去搜索）
  · `F7` 进快捷栏（`Enter` 赋值 / `Delete` 清空）· `Esc` 回编辑器
- 全部 48 条快捷键在「设置 → 快捷键」里**可改键、可停用**；面板内的局部键以只读形式列在同一页。

## 目录结构

```
app/        Flutter 工程（lib/ 源码 · test/ 1380 条测试）
notes/      设计文档 / 交接快照 / 开发日志（这个项目最贵的资产）
scripts/    构建、打包、签名、热重载脚本
signing/    签名材料（密钥不入库）
test_data/  测试数据（含个人作业样本，不入库）
dist/       发布产物（不入库）
```

## 状态

- 版本 **1.0.0**，Windows 已可用；移动端在路线图里（阶段 6）。
- 测试：`flutter test` **1380 通过 + 0 skip**，`flutter analyze` 零告警。
- 已知限制与有意不做的东西都记在 [`notes/后优化清单.md`](notes/后优化清单.md)。

## 许可

[MIT](LICENSE) © 2026 yizhinaimao (block255)
