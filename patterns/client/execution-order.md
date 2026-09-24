# 模块执行顺序契约：输入 `-200` → 模拟 `0` → 表现 `LateUpdate`

> **为什么单开一页**：执行顺序不是风格问题，是**"能不能操作 / 打到的是不是本帧那个头"**的前提。
> 放反了**不报错、不崩、日志全绿**，只给你两种"像手感问题"的故障：
> **输入慢一帧**（开火 / 移动"点了没反应"）和**射线打的是上一帧的眼睛位置**。
> 这两种故障在截图与日志里都看不出来 —— 所以必须有一条能机械跑的检查兜着。
>
> 本页给：阶段表（谁属于哪个阶段）+ cs16 实测映射（每个值 `文件:行`）+ **可在任何项目里跑的值域/数量检查**。
> ⛔ 术语钉死：这里的"**表现**"专指**帧末读模拟结果去画**（`LateUpdate`），不是"音效 / 提示"这类事后表现。

---

## 0. 硬规则（违反任一条即交付失败）

| # | 规则 |
|---|---|
| 1 | 顺序**只许**写在代码里的 `[DefaultExecutionOrder(n)]`（挂在类上）；⛔ **不许**用 Editor 的 `Script Execution Order` 面板（那是 ProjectSettings 资产，代码里 grep 不到 ⇒ 下文的检查对它**瞎**） |
| 2 | 全项目只认**四个**值域：`-200` = 输入采集、`-100` = 表现（帧末读）、**不写 attribute**（= `0`）= 模拟与事后表现、`-10000` = 引擎驱动器（**引擎私有**）。其余任何值 = 未登记 = 越界 |
| 3 | **恰好一个** `-200`：它只读输入、只写"意图"（把命令交给模拟），⛔ 不推进权威状态。项目里出现第 2 个 `-200` ⇒ 两者先后**未定义** ⇒ 必须自己串行（一个持另一个的引用），⛔ 不许靠两个同类 attribute 的先后 |
| 4 | 模拟层**一律不写 attribute**（= 默认 `0`）；⛔ 模拟**不许**负值 —— 负值会让它早于输入采集，本帧拿到的是上一帧的意图 |
| 5 | 表现层在 `LateUpdate` 里读模拟结果；⛔ 在 `Update` 里画 = 画面慢一帧（模拟可能还没跑） |
| 6 | 每条非预期分支都要打日志（`Game.Logger.Info/Warn/Error(tag, msg)`）；⚠️ 时序类故障**只在顺序对的时候**才表现为"正常"，所以顺序本身要有断言，别指望日志发现它 |

---

## 1. 阶段表（先定这张表，再写代码）

| 阶段 | `[DefaultExecutionOrder]` | 哪个回调 | 类数 | 干什么 | ⛔ 不许干什么 |
|---|---|---|---|---|---|
| ① 引擎驱动器 | `-10000` | `Update` → `Game.Tick(dt)` | 引擎私有（业务 0） | 推引擎 tick：**输入采样** / 定时器 / 网络重传 | 业务类占这个值 |
| ② 输入采集 | `-200` | `Update` 采集 → 写意图；`LateUpdate` 算相机位姿与视线 | **恰好 1** | 读输入、算相机与射线、把命令交给模拟 | 推进模拟、写权威状态 |
| ③ 模拟 | 不写（`0`） | `Update` | 任意 | 推进权威状态：位移 / 物理 / 战斗 / 经济 / AI | 二次采样输入 |
| ④ 表现（帧末） | `-100` | `LateUpdate` | ≥ 0 | **只读**模拟结果 → 摆位置 / 播动画 / 抬头顶字 / 挂机位 | 写回权威状态 |
| ⑤ 事后表现 | 不写（`0`） | `Update` | 任意 | 音效、提示这类"事后"表现（读本帧已算完的状态） | 被 ② ③ 当时序依赖 |

两条补充，缺一条就会被问"为什么不是随便挑的数字"：

- **为什么 `-100` 落在 `-200` 与 `0` 之间**：`[DefaultExecutionOrder]` 对 `Update` 与 `LateUpdate` **同时生效**，同一批类在两条链上保持**同一个相对次序**。于是 `LateUpdate` 里自动得到"相机 `-200` → 视图 `-100`"的顺序 —— 视图读到的永远是**本帧**相机算完的位姿。⛔ 别用别的数字，否则 `Update` 链和 `LateUpdate` 链必然有一条是错的。
- **⛔ 别把"挂载顺序"当"执行顺序"**：`gameObject.AddComponent<A>()` 之后 `AddComponent<B>()` 只决定 **`Awake` / `OnEnable`** 的先后，**不决定 `Update` 的先后**。（cs16 实测就是这么干的：`Bootstrap` 先挂地图模块再挂比赛模块，解决的是 `Awake` 里找门面；谁先 `Update` 由 `[DefaultExecutionOrder]` 说了算。）

---

## 2. cs16 实测映射（2026-09-24 回读源码，逐处带 `文件:行`）

| 类 | 值 | 阶段 | 出处（原文见 §5 锚点表） |
|---|---|---|---|
| `EngineRunner`（引擎侧） | `-10000` | ① 引擎 tick | `clover-client-unity-engine/Runtime/Core/EngineRunner.cs:78` |
| `PlayerModule` | `-200` | ② 输入采集 | `clover-project-cs16/client/Assets/Scripts/Module/Player/PlayerModule.cs:31` |
| `ViewModule` | `-100` | ④ 表现（帧末读） | `clover-project-cs16/client/Assets/Scripts/Module/View/ViewModule.cs:33` |
| `MatchModule` | 不写（`0`） | ③ 模拟 | `clover-project-cs16/client/Assets/Scripts/Module/Match/MatchModule.cs:118` |
| `AudioModule` | 不写（`0`） | ⑤ 事后表现 | `clover-project-cs16/client/Assets/Scripts/Module/Audio/AudioModule.cs:24` |
| `BotModule` | 不写（`0`） | ③ 模拟（AI） | `clover-project-cs16/client/Assets/Scripts/Module/Bot/BotModule.cs:141` |

**cs16 自己的正确性前提（原文照抄，不是我总结的）** —— `PlayerModule.cs:17-21`：

```text
PlayerModule.Update   (order -200)  采集输入 → match.SetLocalInput(cmd)      ← 必须早于模拟 Tick
MatchModule.Update    (order    0)  模拟推进：扣弹/限速/累后坐力/移动解算    ← agent-03
PlayerModule.LateUpdate             ① 相机算位姿与视线 ② 射击队列消费+射线 ③ 写相机
```

> 放反了会得到两种典型故障：输入慢一帧（开火"点了没反应"）、以及"射线打的是上一帧的眼睛位置"。

**"输入采样"到底发生在哪一刻（这条决定 `-200` 是否读得到本帧输入）**：引擎驱动器 `EngineRunner` 挂 `-10000`（最优先），它的 `Update` 第一件事就是 `Input?.Tick()`（`clover-client-unity-engine/Runtime/Core/EngineRunner.cs:78`、`Runtime/Core/Game.cs:754`）⇒ **本帧输入在 `-10000` 就已采样完**，`-200` 的输入采集读到的是**本帧**数据。这正是"引擎 tick 必须排在一切业务之前"的原因。

⚠️ **cs16 有一条注释基于过期前提，照抄前必须知道**：`PlayerMotor.cs:189-190` 写"`Game.Input.Tick()` 由引擎的 `EngineRunner`（**默认执行顺序**）驱动，与业务 `Update` 的先后不保证"，并因此"再直读一次 WASD"来消除移动慢一帧。按当前引擎，`EngineRunner` 的值是 `-10000`、**不是**默认序号，先后是**确定**的（引擎 tick 先跑）⇒ 那段直读属于**冗余保险**，不是必需。
⇒ 结论：**先保证"引擎驱动器 `-10000` 唯一且业务不占"**，再谈输入层；⛔ 不许在输入层假定"引擎 tick 可能后跑"而重复采样（那是用错误前提换来的一份永不被执行的代码路径）。

（cs16 的客户端引擎包是指向 `clover-client-unity-engine` 的 junction，实测：`clover-project-cs16/client/Packages/com.clover.unity-engine` 的 `LinkType=Junction`、`Target={c:\Work\Server\f-v2\clover-client-unity-engine}` ⇒ 上面读的 `EngineRunner.cs` 就是 cs16 实际跑的那份。）

---

## 3. 机械判据（两条，都可离线跑）

### 3.1 值域 + 数量检查（任何项目都能跑）

规则（与 §0 第 2/3 条一一对应）：

1. 扫 `client/Assets/Scripts/**/*.cs` 里所有 `[DefaultExecutionOrder(...)]`，把参数解析成整数；
2. 每个值必须 ∈ `{-200, -100}`；命中别的值 ⇒ **越界，点名** `类名 文件:行 值`；
3. `-200` 的个数必须**恰好 1**；`0 个` ⇒ **假绿**（输入采集悄悄挪回默认 `0` = 模拟层，顺序从此无人保证），`≥2 个` ⇒ 越界；
4. `client/ProjectSettings/` 下任何文件出现非空 `m_ExecutionOrder` ⇒ **FAIL**（顺序被藏进资产面板，代码里 grep 不到）；
   反之"该 key 全仓 0 命中" ⇒ PASS（cs16 = PASS）。

```powershell
# 值域 + 数量检查（把 $Client 换成你的 client 目录）
$Client = Join-Path $ProjectRoot 'client'
$rows = @()
foreach ($f in Get-ChildItem (Join-Path $Client 'Assets\Scripts') -Recurse -File -Filter *.cs) {
  $n = 0
  foreach ($ln in [IO.File]::ReadAllLines($f.FullName)) {
    $n++
    $m = [regex]::Match($ln, '^\s*\[DefaultExecutionOrder\(\s*(-?\d+)\s*\)\]')
    if ($m.Success) { $rows += [pscustomobject]@{ Value = [int]$m.Groups[1].Value; File = $f.FullName; Line = $n } }
  }
}
$bad = @($rows | Where-Object { $_.Value -ne -200 -and $_.Value -ne -100 })
if ($bad.Count -gt 0) { Write-Output ('FAIL execution-order: ' + ($bad | ForEach-Object { "$($_.File):$($_.Line) value=$($_.Value)" }) -join ' | ') }
$n200 = @($rows | Where-Object { $_.Value -eq -200 }).Count
if ($n200 -ne 1) { Write-Output ("FAIL execution-order: -200 count = $n200 (must be exactly 1: 0 = input moves to the sim phase silently)") }
```

> ⚠️ 上例只认**字面量**（`[DefaultExecutionOrder(-200)]`）。若代码里写成 `[DefaultExecutionOrder(ExecutionOrder)]`（cs16 的 `ViewModule` 就是这么写的：常量是编译期常量，attribute 接受它），脚本要回读**同一个文件里的 `ExecutionOrder` 常量**再判 —— §4 的完整脚本就是这么做的。**自查一下你的解析器能覆盖两种写法**，否则它会静默漏掉一整类（这正是"闸门自己也要被闸"）。

### 3.2 「缺一个阶段值」会被谁抓到

| 你漏了什么 | 谁抓到 | 现象 |
|---|---|---|
| 删掉输入层的 `[DefaultExecutionOrder(-200)]` | §3.1 第 3 条（`-200` 个数 = 0） | 检查转红：输入层静默挪进模拟阶段 |
| 给模拟层写了 `-200` | §3.1 第 3 条（个数 = 2） | 检查转红；两个类的先后未定义 |
| 给模拟层写了负值 | §3.1 第 2 条 | 检查转红 |
| 用 Editor 面板改顺序 | §3.1 第 4 条（`m_ExecutionOrder` 非空） | 检查转红（否则它对面板改动完全瞎） |
| 表现层写成 `Update` 而不是 `LateUpdate` | ⛔ 无机械判据 | **只能靠人**：`Update` 里画 = 画面慢一帧，属于"逐帧表现"，按 `experience/per-frame-jitter-evidence.md` 走逐帧通道 |

> ⛔ 最后一行要留在验收表里当**已知盲区**，不许假装它也被闸门覆盖了。

---

## 4. 完整检查脚本（值域 + 常量解析 + 资产检查）

```powershell
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
$ErrorActionPreference = 'Stop'
$fail = 0
$scripts = Join-Path $ProjectRoot 'client\Assets\Scripts'
$rows = @()
foreach ($f in Get-ChildItem $scripts -Recurse -File -Filter *.cs) {
  $lines = [IO.File]::ReadAllLines($f.FullName)
  # 同文件里的 int 常量表：attribute 允许写常量名，不解析就会静默漏掉一整类
  $consts = @{}
  foreach ($ln in $lines) {
    $cm = [regex]::Match($ln, 'const\s+int\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(-?\d+)\s*;')
    if ($cm.Success) { $consts[$cm.Groups[1].Value] = [int]$cm.Groups[2].Value }
  }
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $m = [regex]::Match($lines[$i], '^\s*\[DefaultExecutionOrder\(\s*([A-Za-z_][A-Za-z0-9_]*|-?\d+)\s*\)\]')
    if (-not $m.Success) { continue }
    $tok = $m.Groups[1].Value
    if ($tok -match '^-?\d+$') { $v = [int]$tok }
    elseif ($consts.ContainsKey($tok)) { $v = $consts[$tok] }
    else { Write-Output ("FAIL execution-order: $($f.FullName):$($i+1) cannot resolve '$tok' -- a check that cannot resolve a value must fail, not skip"); $fail++; continue }
    $rows += [pscustomobject]@{ Value = $v; File = $f.FullName; Line = ($i + 1) }
  }
}
$bad = @($rows | Where-Object { $_.Value -ne -200 -and $_.Value -ne -100 })
if ($bad.Count -gt 0) {
  $fail++
  Write-Output ('FAIL execution-order: out-of-range value(s) -- only -200 (input) and -100 (late presentation) are registered:')
  $bad | ForEach-Object { Write-Output ("  $($_.File):$($_.Line) value=$($_.Value)") }
}
$n200 = @($rows | Where-Object { $_.Value -eq -200 }).Count
if ($n200 -ne 1) { $fail++; Write-Output ("FAIL execution-order: -200 count = $n200 (exactly 1 required; 0 means the input stage silently fell back to the sim phase)") }
$assetHits = @()
foreach ($f in Get-ChildItem (Join-Path $ProjectRoot 'client\ProjectSettings') -File) {
  $t = [IO.File]::ReadAllText($f.FullName)
  if ($t -match 'm_ExecutionOrder\s*:\s*\r?\n\s*-') { $assetHits += $f.Name }
}
if ($assetHits.Count -gt 0) { $fail++; Write-Output ('FAIL execution-order: order hidden in ProjectSettings asset (code-grep invisible): ' + ($assetHits -join ', ')) }
Write-Output ("===== execution-order: FAIL=$fail  (scanned " + $rows.Count + ' attribute(s)) =====')
exit $(if ($fail -gt 0) { 1 } else { 0 })
```

对 cs16 现状的**期望输出**（本次实测）：`scanned 2 attribute(s)` / `FAIL=0` —— `PlayerModule = -200`、`ViewModule = -100`，`-200` 恰好 1 个，`client/ProjectSettings/` 下 `m_ExecutionOrder` 0 命中。

---

## 5. cs16 锚点表（本文出现的每个 cs16 符号都能在源码里核对）

> 格式：`| 符号 | 域 | 出处 | 该行必须出现的原文 |`。
> 域 = `cs16`（被上浮的项目，路径相对工作区根）或 `引擎`（API 出处）。
> 校验方式：**回读该 `文件:行`，断言行内含「必须出现的原文」，且符号能在对应源码树里 grep 到**；任一不成立即点名 FAIL。
> 负控（必做）：往这张表里塞一行**不存在的符号名** ⇒ 检查必须转红并点名该行 ⇒ 删掉复绿。没有负控的锚点检查等于没做（它可能一直在"未解析就跳过"）。

<!-- cs16-symbol-roots: AppFlow,IAppFlow,Bootstrap,PlayerModule,PlayerMotor,ViewModule,MatchModule,AudioModule,BotModule,CsMapModule,CsHudSnapshot,CsMatchConfig,CsTeam,CsConst,SceneNames,ResPaths,Events,State,Trigger,GameKey,CsPlayerSettingsStore,CloverRes,CloverInput,ICsMatch,ICsMap -->

| 符号 | 域 | 出处 | 该行必须出现的原文 |
|---|---|---|---|
| `DefaultExecutionOrder` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Player/PlayerModule.cs:31` | `[DefaultExecutionOrder(-200)]` |
| `ExecutionOrder` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Player/PlayerModule.cs:37` | `public const int ExecutionOrder = -200;` |
| `PlayerModule` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Player/PlayerModule.cs:17` | `(order -200)` |
| `LateUpdate` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Player/PlayerModule.cs:19` | `PlayerModule.LateUpdate` |
| `MatchModule` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/View/ViewModule.cs:18` | `MatchModule.Update` |
| `ViewModule` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/View/ViewModule.cs:33` | `[DefaultExecutionOrder(ExecutionOrder)]` |
| `ExecutionOrder` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/View/ViewModule.cs:39` | `public const int ExecutionOrder = -100;` |
| `LateUpdate` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/View/ViewModule.cs:138` | `private void LateUpdate()` |
| `MatchModule` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Match/MatchModule.cs:118` | `private void Update()` |
| `AudioModule` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Audio/AudioModule.cs:24` | `执行顺序` |
| `BotModule` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Bot/BotModule.cs:141` | `private void Update()` |
| `Bootstrap` | cs16 | `clover-project-cs16/client/Assets/Scripts/App/Bootstrap.cs:107` | `地图模块必须先于比赛模块` |
| `EngineRunner` | 引擎 | `clover-client-unity-engine/Runtime/Core/EngineRunner.cs:78` | `[DefaultExecutionOrder(-10000)]` |
| `EngineRunner` | 引擎 | `clover-client-unity-engine/Runtime/Core/EngineRunner.cs:205` | `private void Update()` |
| `Game.Tick` | 引擎 | `clover-client-unity-engine/Runtime/Core/EngineRunner.cs:207` | `Game.Tick(Time.deltaTime);` |
| `Game.Tick` | 引擎 | `clover-client-unity-engine/Runtime/Core/Game.cs:750` | `public static void Tick(float dt)` |
| `Input?.Tick()` | 引擎 | `clover-client-unity-engine/Runtime/Core/Game.cs:754` | `try { Input?.Tick(); }` |
| `PlayerMotor` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Player/PlayerMotor.cs:189` | `Game.Input.Tick()` |

---

## 6. 与其他文档的关系

- **流程站点 / 面板与场景的编排** → `patterns/client/app-flow.md`（其 §9 是 cs16 实测骨架，与本页同批上浮）；
- **逐帧现象（抖 / 飘 / 慢一帧这类）怎么取证** → `experience/per-frame-jitter-evidence.md`（本页 §3.2 最后一行那个盲区就靠它）；
- **事件名唯一来源 / 分层（UI 不引 Module）** → `reference/architecture.md`、`reference/client-conventions.md`；
- **引擎能力表（`Game.Fsm` / `Game.Scene` / `Game.Timer` 的签名）** → `clover-client-unity-engine/Runtime/Core/**`、`Runtime/Presentation/**`（本页所有 API 断言都落到这两处）。
