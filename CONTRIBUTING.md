# 贡献指南 · 数语引擎（mathlang）

> Windows 桌面优先。规范的目标不是“流程好看”，而是让改动**可追溯、可验证、可交接**。
> 当前版本：**1.1.0**。文档地图见 [`notes/README.md`](notes/README.md)；AI agent 的额外约束见 [`AGENTS.md`](AGENTS.md)。

## 1. 先读什么

- 用户视角：[`README.md`](README.md)
- 文档索引与权威顺序：[`notes/README.md`](notes/README.md)
- 现役待办：[`notes/后优化清单.md`](notes/后优化清单.md)
- 最近交接：[`notes/handover/会话状态快照-20261024.md`](notes/handover/会话状态快照-20261024.md)

## 2. 环境与常用命令

- Windows 10/11 64 位；Flutter **3.47.1** stable（与 CI 一致）。
- 仓库根是 `mathlang/`，**不是** `app/`；Flutter 命令先 `cd app`。

```powershell
cd app
flutter pub get
flutter analyze
flutter test
```

- 开发实例：双击 `scripts/dev.cmd`（免管理员）。热重载写 `r`；改 assets 写 `x`；**不要用 `R`**（会打死应用）。
- 构建/打包：`scripts/build_exe.ps1` → `scripts/pack_release.ps1` → `scripts/pack_msix.ps1`。
- `pack_msix.ps1` 需要环境变量 `MATHLANG_PFX_PASSWORD`；口令管理见 [`signing/README.md`](signing/README.md)，**绝不写进仓库**。
- 几何类测试若量真实字体，先 `await loadMathFonts()`（`app/test/support/math_fonts.dart`）。

## 3. 代码结构

| 目录 | 职责 |
|---|---|
| `app/lib/core` | 一维 md 缓冲区、块、设置、文档文件 |
| `app/lib/lang` | 语法切分、粘贴、智能包裹、快捷键登记表 |
| `app/lib/render` | 位点表、结构感知删除、叶盒配对、几何与命中 |
| `app/lib/layout` | A4 分页与块高 |
| `app/lib/editor` | 编辑面、光标、输入、视图 |
| `app/lib/ui` | 界面、面板、设置、对话框 |
| `app/lib/io` | 文件、会话、平台存储 |
| `app/test` | 镜像上述分层；`test/support` 放测试夹具 |

`notes/` 放规格与记录，`scripts/` 放构建脚本；`signing/`、`test_data/`、`dist/`、`references/` 不入库。

## 4. 改动流程

- 默认直接提交 `main`；**跨 3 个以上模块或高风险改动**先开短分支。
- 不 force-push `main`；不改写已推送的历史；发布只通过 annotated tag 标记。
- 改动前先确认“行为判据”写在哪条测试/哪份规格里；找不到就先补判据，不要凭记忆实现。
- 改动后必须跑 `flutter analyze` + `flutter test`（0 skip）。
- **修 bug 必须带守卫测试**：先让新测试红，再修到绿；提交正文写“改前红、改后绿”的证据。
- 不新增 `skip`；`app/test/perf/measure_cost_test.dart` 是已知对并发敏感的测量测试（单跑必过），全量偶发超阈值时单独跑并在提交里说明，**不要放宽断言**。

## 5. 提交信息（唯一格式）

```text
type(scope): subject

现象：
根因：
修法：
验证：（测试名 / 命令 / 改前红→改后绿）

Refs: <文档/提交/issue>
AI-Assisted: DeepSeek/DSH
```

- **type**：`feat` `fix` `docs` `test` `refactor` `chore` `build` `ci` `revert`
- **scope**：模块名，如 `render` `editor` `io` `lang` `ui` `docs` `release`。**不要用批次号/时间**（`批36`、`10:3x` 都不行）。
- **subject**：≤72 字符，句末不加句号；中文可以。
- **body**：写“为什么”和证据；批次号、日期、长过程放 body，不进标题。
- **footer**：`Refs:` 指向规格/提交；AI 主导的提交加 `AI-Assisted: DeepSeek/DSH`。
- 标题示例：`fix(render): 删除时不再把 \text 的命令名劈开`
- 标题反例：`fix(批36): ...`、`docs(10:1x): ...`、`S4-b①：...`

一次性配置（提交模板 + 标题校验）：

```powershell
git config commit.template .gitmessage
git config core.hooksPath .githooks
```

`.githooks/commit-msg` 只校验类型/scope，标题超长给提示但不阻塞。历史里的 `mathlang <dev@mathlang.local>` 身份由 [`.mailmap`](.mailmap) 归并显示。

## 6. 文档规则（单一事实源）

- 新文档必须在 [`notes/README.md`](notes/README.md) **登记**，且与内容同一提交。
- 新文档和**现行文档**顶部写清状态（现行规格 / 现行参考 / 历史 / 草稿）与最后核对日期；历史文档允许保留原标题，由 [`notes/README.md`](notes/README.md) 统一标记。过期文档加横幅，不删除。
- 权威顺序：**代码 + 测试 > Release 说明 > design 现行规格 > 台账/路线图 > 交接快照/开发日志 > 草稿**。
- 同一事实只在一处维护：
  - 规格 → `notes/design/`
  - 待办 → `notes/后优化清单.md`
  - 发布说明 → `notes/release/vX.Y.Z.md`
  - 过程记录 → `notes/dev_log/`、`notes/handover/`
  - 其它地方只放链接，不复制整段。
- 会话快照是**历史事实**，不是现行规格；当前事实必须写进规格或台账。
- `notes/release/vX.Y.Z.md` 与 GitHub Release 正文**逐字一致**；改一处必须同步另一处。
- 不新增“第 N 份清单”。要加内容，先判断它属于规格、待办、发布还是日志。

## 7. 安全与隐私

- 永不提交 `signing/*`、`*.pfx`、`*.p12`、`*.jks`、`key.properties`、token、口令、个人作业样本。
- PFX 口令只经 `MATHLANG_PFX_PASSWORD` 传入构建；不写进脚本、文档、提交信息或命令回显。
- 发现泄露：先轮换口令/证书，再清理文档；**删除文件不能消除历史泄露**。
- `test_data/` 可能含真实作业，保持忽略；不要在 issue/文档里贴个人内容。

## 8. 发布

1. bump [`app/pubspec.yaml`](app/pubspec.yaml) 的 `version`。
2. `scripts/build_exe.ps1` → `scripts/pack_release.ps1` → `scripts/pack_msix.ps1`（先设置 `MATHLANG_PFX_PASSWORD`）。
3. 校验签名与 `SHA256SUMS.txt`；`git tag -a vX.Y.Z` 并 push tag。
4. GitHub Release 正文从 `notes/release/vX.Y.Z.md` **逐字**复制；资产名用 ASCII。
5. 更新 [`notes/README.md`](notes/README.md)、[`notes/后优化清单.md`](notes/后优化清单.md)、README 的版本/状态。
6. 发布后核对资产名、大小、签名；把本轮结论写进 `notes/dev_log/`。

## 9. 许可

贡献按 MIT 许可（[`LICENSE`](LICENSE)）。
