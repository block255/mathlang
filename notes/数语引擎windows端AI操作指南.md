# 数语引擎 · Windows 端 AI 操作指南

> **状态（2026-10-25 索引）**：**现行操作手册**；命令与路径以当前脚本/代码为准。

> **这份是"怎么用机器操作数语引擎"的操作手册**，写给以后接手的会话（也是写给现在测试优化阶段的我自己）。
> **核心结论**：这个应用**不能靠 UIA 操作**（Flutter 画布对 UIA 是瞎的），要按下面的**三条通道**组合。
> 建立于 2026-10-18，全部条目都是**实测**（证据与探针记录见 `notes\dev_log\2026-10-18开发循环与自测通道.md`）。

---

## 零、三句话记住

1. **读状态 → 语义树**（Flutter 自己的可访问性树，一条 `curl`，零点击）。
2. **点东西 → `PostMessage` 鼠标**（静默、不抢前台、不需要授权；坐标由语义树矩形换算）。
3. **看画面 → 截图**（`computer_see` 的 PrintWindow 对本应用可用；更要紧的细节走语义树文本）。
4. **打字 → 只有真实键鼠**（`computer_act` `interact` 档，会抢前台，需用户授权；`WM_CHAR` 不可靠）。

---

## 一、通道速查

| 要做的事 | 走哪条 | 抢前台？ | 需要授权？ |
|---|---|---|---|
| 找窗口 / 拿 handle / 读标题几何 | `computer_window {filter:"mathlang"}` | 否 | 否 |
| 读界面状态（按钮、文本、页数、字符数、光标） | **VM service 语义树**（`curl.exe`） | 否 | 否 |
| 读渲染树 / 布局细节 | VM service `debugDumpRenderTree` | 否 | 否 |
| 精确点击任意位置 | **`PostMessage` WM_LBUTTONDOWN/UP** | 否 | 否 |
| 截图 | `computer_see {target:"window"}`（PrintWindow） | 否 | 否 |
| 打开/保存/选目录 对话框 | `computer_find` + `message setvalue` + `pattern invoke` | 否 | 否 |
| 摆窗口 / 最小化 / 最大化 | `computer_act {action:"window", windowAction:"set_bounds"…}` | **`restore`/`activate`/`show` 会抢**；`set_bounds` 不会 | 否 |
| 真打字 / 中文输入法 / 拖选 / 滚轮 | `computer_act {action:"type"|"key"|"click"}`，需 `interact` 档 | **会** | **要** |
| 改代码后生效 | `scripts\cmd.txt` 写 `r`（热重载桥） | 否 | 否 |

---

## 二、准备：拿到两个东西

### 2.0 先把应用跑起来（三种入口，都不需要管理员）

| 想要 | 怎么做 |
|---|---|
| **开发实例（可热重载）** | 双击 `scripts\dev.cmd`（= `dev_windows.ps1`）；窗口留着看日志。起来后 `run.log` / `state.json` 就绪 |
| 同上，但用 Web 预览 | `powershell -ExecutionPolicy Bypass -File scripts\dev_windows.ps1 -Device web` |
| **正式形态（双击即开）** | `scripts\build_exe.ps1` 打包 → `scripts\make_shortcut.ps1 -Dev` 建快捷方式 |

`state.json` 里 `phase` 会是 `building` → `running`，`vmService` 就是下面要用的地址。

### 2.1 窗口句柄与客户区

```
computer_window {filter:"mathlang"}
→ handle / title / x,y,width,height / integrity
computer_find {handle:<hwnd>, depth:4}
→ "FLUTTERVIEW" 那个 Pane 就是画布，回执里带 clientRect（客户区原点 + 尺寸）
```
实测：窗口 1920×1080 @(15,15)，`FLUTTERVIEW` 客户区 `(26,60) 1898×1024`，`integrity: Low`（与助手同级，不涉及 UIPI）。

### 2.2 VM service 地址

**首选从 `scripts\state.json` 读**（桥会把它写好）：
```json
{ "phase": "running", "vmService": "http://127.0.0.1:<port>/<auth>=/" }
```
兜底：在 `scripts\run.log` 里搜这一行
```
A Dart VM Service on Windows is available at: http://127.0.0.1:<port>/<auth>=/
```
**它每次启动都变**（端口 + token 都随机）。

> ⚠️ **必须用 `curl.exe`**：PowerShell 的 `Invoke-RestMethod` 打同一地址返回 **403**（实测），
> `curl.exe` 是 **200**。原因未深究，照做即可。

---

## 三、通道 A：语义树（读状态、定位坐标）

```powershell
$b   = 'http://127.0.0.1:<port>/<auth>='
$iso = 'isolates/<id>'          # 从 getVM 拿：isolates[0].id
curl.exe -s "http://$b/getVM"   # → 拿 isolates[0].id
curl.exe -s "$b/ext.flutter.debugDumpSemanticsTreeInTraversalOrder?isolateId=$iso"
```

**返回的是带缩进的文本树**，每节点有：`Rect.fromLTRB(...)`、`label`、`tooltip`、`flags`（`isButton`/`isFocusable`）、`actions`（`tap`/`scrollToOffset`）、`traversalParentIdentifier`。

实测能读到的东西（这就是"断言抓手"）：
- 顶栏每个按钮的 `label`（`文件` / `导入` / `保存` / `导出` / `快捷栏` / `符号` / `设置`）+ `tooltip`（带快捷键说明）
- 文档块文本：`label: "例 1 · 一元二次方程"`、`label: "设 … 为多项式，… 为常数，求 … 的值。"`
- **数学原子各自的节点**：`x` / `2` / `+` / `1` 是分开的节点（正好可以验"同权"：公式不是一坨）
- 状态栏：`共 1 页 · 201 字符 · 光标 201 · 0 次编辑`
- 空的快捷栏格子：`tooltip: "第 1 格（空）· 点一下再选符号"`

### ★ 坐标换算（点击前必算）
语义树里的 `Rect` 是**逻辑像素**（页面基准 `1265.3 × 682.7`），`SemanticsNode#1` 会写 `scaled by 1.5x`。
```
客户区坐标 = 逻辑坐标 × dpr        # 本机 dpr = 1.5
屏幕坐标   = 客户区坐标 + clientRect 原点
```

---

## 四、通道 B：静默点击（`PostMessage`）

```powershell
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class Click {
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
}
'@
$view = [IntPtr]<FLUTTERVIEW 的 nativeHandle>
$lp   = [IntPtr]((($y -shl 16) -bor ($x -band 0xFFFF)))   # 客户区物理像素
[Click]::PostMessage($view, 0x0201, [IntPtr]1, $lp)       # WM_LBUTTONDOWN
[Click]::PostMessage($view, 0x0202, [IntPtr]0, $lp)       # WM_LBUTTONUP
```

**实测**：往页面 (450,450) 发一次 ⇒ 光标从 `0` 跳到 `201`；`GetForegroundWindow()` **前后相同**（没抢前台）。
⇒ 可以"读语义树 → 算坐标 → 点一下 → 再读语义树"做闭环断言，全程不碰用户的鼠标键盘。

**规矩**：
- 按下与抬起**必须成对**，中间隔 ~100ms；只发按下会让应用一直处于"按住"状态。
- 坐标是**客户区物理像素**，不是屏幕坐标、也不是逻辑像素。
- 点到页面外（`FLUTTERVIEW` 之外）无效。

---

## 五、通道 C：看图

```
computer_see {target:"window", handle:<hwnd>, label:"..."}   → 只回 PNG 路径
→ 再用视觉模型读图（见 `see_image`）
```
实测 `source: "printwindow"`，**能截到完整文档**（不是黑屏），Impeller/GL 表面也没问题。
⚠️ 视觉模型**读坐标不准**（守则 §五），画面只用于"看内容/样式"，坐标一律算出来。

---

## 六、系统对话框（文件读写唯一可靠的自动化口）

UIA 对**原生对话框**是完整的（对 Flutter 画布才是瞎的）。

```
computer_find {handle:<对话框 hwnd>}    → "文件名(N):" 编辑框 + "保存(S)" 按钮
computer_act {action:"message", handle:<编辑框 nativeHandle>, messageKind:"settext", text:"D:\...\x.md"}
computer_act {action:"pattern", patternAction:"invoke", name:"保存(S)"}
```
⇒ 全程静默、不抢前台、不需要 `interact` 档。**这是验收"打开/保存/另存为/导出"的正路。**

---

## 七、已知限制（别再试，都是实测死的）

| 限制 | 证据 |
|---|---|
| **UIA 看不到画布内部** | mathlang 窗口只回 8 个元素（Window/FLUTTERVIEW/TitleBar/菜单/最小化/最大化/关闭） |
| **`evaluate` 不可用** | `code 113: No compilation service available; cannot evaluate from source.` ⇒ 不能"注入 Dart 去点按钮/读字段"；纯读取的 `getInstances`/`getObject` 仍可用 |
| **`WM_CHAR` 不能打字** | 发 `'a'` 状态不变；再发 `'b'` 明确无效（唯一一次 200→201 无法归因）⇒ Flutter 只在视图有焦点时收字符 |
| **`Invoke-RestMethod` 打 VM service 得 403** | 同一 URL 用 `curl.exe` 是 200 |
| **`computer_find` 的坐标为 0 的元素** | 标题栏系统按钮 `nativeHandle: 0`，只能坐标点，不能 pattern |

---

## 八、一次完整验收的骨架（可直接照抄）

```
1) computer_window {filter:"mathlang"}                 → handle
2) 从 scripts\run.log 抓 VM service URL
3) curl getVM                                          → isolateId
4) curl 语义树                                          → 记下基线（页数/字符/光标）
5) 在语义树里找目标按钮的 Rect → ×dpr → 客户区坐标
6) PostMessage down/up                                  → 点击
7) curl 语义树                                          → 断言变化（例：光标位置 / 面板出现）
8) computer_see 截图                                    → 交视觉核对（可选）
9) 要改代码 ⇒ 写 scripts\cmd.txt 一个 'r'               → 热重载，回到 4)
```

---

## 九、与其它文档的关系

| 想知道 | 看 |
|---|---|
| 这些结论怎么测出来的（探针与数字） | `notes\dev_log\2026-10-18开发循环与自测通道.md` |
| 启动 / 构建 / 热重载 / 权限 | 同上 §一、§二 |
| 要测什么（验收清单） | `notes\进度与优化清单.md` §4 |
| 插件本体的用法（权限档、信任、槽位） | `全局笔记\dsh-computer-operate-使用指南.md` |
