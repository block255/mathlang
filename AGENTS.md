# AGENTS.md · 给 AI agent 的工作规则

> 人类规范在 [`CONTRIBUTING.md`](CONTRIBUTING.md)：提交格式、测试要求、文档规则都以它为准。
> 本文件只写 agent 容易犯错的额外约束，**不要在这里复制第二份规范**。

## 开始前

1. 读 [`README.md`](README.md) → [`notes/README.md`](notes/README.md) → [`notes/后优化清单.md`](notes/后优化清单.md) → 最新交接快照。
2. 确认改动属于哪份**现行规格**；找不到就先把问题记进台账，不要凭记忆补规格。
3. 检查工作树：不要覆盖/提交 `dist/`、`signing/`、`test_data/`、`references/`，也不要动别人未提交的改动。

## 硬约束

- **先证据后结论**：说“通过/修好”必须给出命令、测试名或 `文件:行`；没跑就明确说没跑。
- **修 bug 先红后绿**：新增/修改守卫测试并确认改前失败；不许用 skip、放宽断言或删除断言来“变绿”。
- **提交格式**：`type(scope): subject`，≤72 字符；scope 用模块名，不用批次号/时间；body 写现象/根因/修法/验证；AI 主导时加 `AI-Assisted: DeepSeek/DSH`。详见 CONTRIBUTING §5。
- **文档单一事实源**：改行为 → 改对应现行规格/台账；新文档登记到 `notes/README.md`；过期文档加横幅，不删除、不复制整段。
- **不改写历史**：不 force-push、不 rebase 已推送提交、不改已发布 tag/Release；要修正就追加提交。
- **不碰密钥**：`signing/*` 只读；PFX 口令只从 `MATHLANG_PFX_PASSWORD` 读；不把口令写进任何文件或命令回显。
- **少即是多**：不做与任务无关的大规模格式化/重命名；不把设计文档整段复制进代码注释；不引入新依赖除非有明确理由。
- **保持分层**：`core / lang / render / layout / editor / ui / io` 的依赖方向不要反转；UI 不写进 render/core。

## 工作循环

1. **定位**：先看现有测试与规格；必要时写探针，但探针不留在生产代码。
2. **写红**：最小守卫测试，覆盖用户看到的现象，而不只是内部实现。
3. **修**：最小改动，沿用既有判据（平权 / 同层对象 / 围栏不是对象边界）。
4. **跑绿**：`cd app && flutter analyze && flutter test`；几何测试先 `loadMathFonts()`；perf 测试单独跑。
5. **文档**：更新权威规格/台账/索引日期；历史快照只追加“发生了什么”。
6. **提交**：按格式；正文给证据；不要把整张批次表复制进提交。

## 常用命令

```powershell
cd app
flutter pub get
flutter analyze
flutter test
flutter test test/render/<name>_test.dart
```

- 改 `app/assets/symbols.json` 后热重载用 `x`。
- 新增文档后，从 `notes/README.md` 必须能点得到；提交前检查相对链接。

## 交接

结束时在回复里写清：改了什么、验证命令/结果、没做什么、下一步入口（指向台账条目）。
若更新了 `notes/README.md` 的“最后核对”，说明核对了哪些文件。
