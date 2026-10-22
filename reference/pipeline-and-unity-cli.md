# Unity CLI / Pipeline 踩坑全记录（卡住时再查）

> **分工**：操作步骤 / 命令速查 / 建工程 SOP / 驱动活编辑器 / PlayMode 用例 → `reference/unity-cli.md`；本文只讲"**为什么、怎么排查、报错长什么样**"。
> 规则原文在 `SKILL.md` §1（闸门 1 / 闸门 2）—— 本文**不是规则层**，只有真的遇到问题时才需要读。

---

## 一、闸门 1：360（及同类国产杀软）必须关闭

**为什么**：360 会拦截 Unity 的安装目录与辅助进程。症状是 `Unity.Licensing.Client` **进程在、但通道永远拒绝连接**（其内部在崩），编辑器于是无限重连：

```
[Licensing::IpcConnector] Connection to channel LicenseClient-XXX refused
[Licensing::Module] Timed-out after 60.00s, waiting for channel
Another instance of Unity.Licensing.Client is already running.
```

**每一次重连烧 60 秒且会一直循环**，表现是"创建工程静默卡死"、"跑一小时没动静"。**这不是慢，是根本起不来。**

**做法**：开工前先问用户一句「**360 关了吗？**」；用户说没关 ⇒ **别创建工程**（也创建不了）；**不确定 = 按没关处理**；已经卡住了才发现 ⇒ 别硬等，回到这条闸门去问。

### 同一症状族的另外两个成因（都已确认）

| 成因 | 关键证据 | 处置 |
|---|---|---|
| **杀软拦 Licensing 客户端**（"编辑器启动"与"batch 出包"一起卡） | 刷 `Failed to acquire global mutex Unity-LicenseClient-DXXX` / `Connection to channel … refused`；batch 一直卡在 early init（进程 100~600MB、CPU 几乎不动、日志 60s 一循环） | ① 关掉**所有** Unity 编辑器与 **Unity Hub**（Hub 会反复拉起 licensing 客户端，互相抢全局互斥）；② 强杀残留客户端 —— `Stop-Process` 常报 **Access denied**（该进程提权），改用 WMI：`Get-CimInstance Win32_Process -Filter "Name='Unity.Licensing.Client.exe'" \| ForEach-Object { Invoke-CimMethod -InputObject $_ -MethodName Terminate }`（`ReturnValue=0` 即成功）；③ 重跑，日志里应出现 `Licensing is initialized (took NN.Ns)` 且**不再**刷 mutex 报错 |
| **杀软拦 Unity 的内存映射数据库（DataStore）** | `<工程>/Logs/UDS-Service.log` 报 `Failed to open database: 5 : Input/output error`；`Editor-UDS.log` 报 `Service connected: false`；Editor 日志报 `Fatal Error! Failed to initialise UDS client in the Editor`。**决定性特征**：日志出现 `Launching Unity Data Store`，但进程表里**从来没有** `Unity.DataStore.exe` | ① 请用户把这几处加入白名单（编辑器安装目录、工程所在目录、`%LOCALAPPDATA%\Unity`、`%LOCALAPPDATA%\Temp\Unity`）；② 或临时关闭主动防御后重试；③ 或请用户用 Hub / Editor **手工打开一次**工程（GUI 启动路径对 UDS 没那么敏感），导入完成后 AI 再回到 CLI |

> ⚠️ `unity license status` 显示「已激活」**不代表客户端进程健康** —— 许可证有效 ≠ licensing 客户端没卡。
> 判断机器上有没有这类套件：`Get-Process | Where-Object { $_.ProcessName -match '360|ZhuDongFangYu|HuoRong|QQPCRTP|HipsTray' }`。

---

## 二、P-0：Pipeline 包必须在**让用户添加项目 / 打开编辑器之前**就位

> Pipeline 的 HTTP 服务**只在编辑器启动 / 域重载时拉起** —— 对一个**已经跑着的**编辑器**毫无作用**：`unity pipeline list --json` 的 `instances` 恒为 `[]`、`unity status` 永远空表。等用户开好了才写 manifest ⇒ 用户必须**再重启一次** Unity。
> ⚠️ **但「空表」不只这一个原因** —— 装包时机正确、服务也确实在跑，**依然可能空表**（那就是 P-1 工作目录的坑）。**先按 P-1 排除，再怀疑装包时机。**

**硬性做法（二选一，都必须在"让用户添加项目 / 打开编辑器"之前做完）**：

| 方式 | 做法 | 说明 |
|---|---|---|
| ① 手写 manifest（推荐） | `client/Packages/manifest.json` 的 `dependencies` 加 `"com.unity.pipeline": "0.7.0-exp.1"`，并补 `"com.unity.modules.screencapture": "1.0.0"` | 与写引擎包同一批做，零额外步骤 |
| ② CLI 安装 | `unity pipeline install --project-path "<项目根>/client"` | 建完工程立刻跑 |

**判定标准**：在**让用户去添加项目 / 打开编辑器之前**，先自己确认 manifest 里已经有 `com.unity.pipeline`。没命中就别催用户开（开了也白开，他还要再重启一次）。前提是本机 `unity` CLI 已装（`Get-Command unity`），没装就**先装**（见 `reference/unity-cli.md` §2）再建工程。

**Hub 添加步骤话术** → 照抄 `reference/unity-cli.md` §1.2（含"选的是 `client`、不是上一级"与"第 5 步只能用户做"）。
**为什么不能自己开编辑器 / 不能批处理顶替** → 同节"为什么不许自己跑"（首次导入十几分钟 + 授权/杀软静默卡死 + `-executeMethod` 执行完即退出、进不了 Play）。

---

## 三、P-1：`unity status` 空表 —— **第一嫌疑是工作目录，不是编辑器**

> 闸门 2 完全遵守（包在用户开编辑器**之前**就在 manifest 里）、编辑器也确实开着（`Temp/UnityLockfile` 存在、`Unity` 进程在跑），但 `unity status` **依然空表**，并抛出误导性话术 `No Unity Editor instances found with reachable Pipeline servers. Make sure: • Editor is running • Pipeline package is installed • HTTP server is running` —— **这三条全是假警报**。
> **真因**：**shell 的 cwd 不在工程里**。

**根因**：`unity` CLI 的编辑器发现是**相对 cwd** 的 —— 它只去 `<当前目录>/Library/Pipeline/.unity-pipeline-port` 找描述文件。cwd 不在 Unity 工程内 ⇒ **一个都发现不了**（它不会说"目录不对"，只会说"没找到编辑器"）。

**⛔ 硬规定：每一条 `unity` 命令都必须在「Unity 工程目录」里执行**（这是前置，不是排查手段）。

```powershell
# ① 切目录（推荐：驱动脚本一律先 Set-Location，写绝对路径）
Set-Location "<项目根>/client"     # 有 Assets/ 与 ProjectSettings/ 的那一层
unity command <name> ...
# ② 不切目录时，每条命令显式带 --project-path（不能只带第一条）
unity command <name> --project-path "<项目根>/client"
```

**证据形态**（拿 `unity status` 当"编辑器活着"的证据时必须同时给）：`<项目根>/client/Library/Pipeline/.unity-pipeline-port` 存在且端口可达；`unity status --project-path "<项目根>/client"` 返回的**工程路径 = `<项目根>/client`**（⛔ 不是工作区根、不是别的 `clover-*` 工程）。

⛔ **禁止**：在**工作区根 / 上一级 / 别的项目目录**里跑 `unity`（哪怕只是"看一眼"）；用 `cd ..` 之类相对跳转后再跑（**一律绝对路径**）；把"空表"直接判成"包没装 / 装晚了"。

**怎么区分「目录错」和「服务真没起」—— 不要靠猜**：

| 判据 | 结论 |
|---|---|
| 编辑器菜单 `Window → Pipeline`：**Start Server 是灰的、只有 Stop Server 可点** | 服务**在跑** ⇒ 问题在**发现**（多半是 cwd） |
| 同上，但 **Start 可点** | 服务确实没起 ⇒ 点它，Console 会打 `Pipeline Server started on port xxxxx` |
| 工程 `Library/Pipeline/.unity-pipeline-port` 存在 | 服务写过描述文件 ⇒ 基本可判定它在跑 |

**要铁证就直接问服务**（绕过 CLI 的发现逻辑）：

```powershell
$d = Get-Content "<项目根>/client/Library/Pipeline/.unity-pipeline-port" -Raw | ConvertFrom-Json
Invoke-WebRequest -Uri "http://127.0.0.1:$($d.port)/api/status" `
  -Headers @{ Authorization = "Bearer $($d.evalToken)" } -UseBasicParsing
# → {"status":"ready","lastHeartbeat":"…","capabilities":[…]}   服务一直是健康的
```

> ⚠️ 描述文件里的 `lastHeartbeat` **可能是陈旧的**（停在启动那一刻）—— **它不刷新 ≠ 服务死了**，别拿它当死亡判据。

**该端口上的端点**（都在 `127.0.0.1`，全都要 `Authorization: Bearer <evalToken>`）：`/api/status`、`/api/editor_status`、`/api/commands`（列出全部命令）、`/api/exec`（**POST**，真正执行命令）、`/api/dialog`、`/api/progress`、`/api/job` —— CLI 走的就是这些；**CLI 发现不了时，直接打 HTTP 一样能驱动编辑器**。

> **排查顺序**：`cd` 进工程 → `unity status` → 还空表？看 `Window → Pipeline` 菜单灰不灰 → 还不行？读 `.unity-pipeline-port` 打 `/api/status`。**明确讲给用户听**："这不是包装晚了，不用重启"。

---

## 四、P-2：驱动编辑器做「实测」时必踩的坑

> 这几条全是**「代码没问题、但你以为有问题」**那一类 —— 共同特征是**没有任何编译错误**，却让你在错误的方向上查很久。

### ① 编辑器窗口失焦 → 帧循环【完全停住】（最坑的一条）

- **症状**：启动画面的定时器永不触发；流程卡在 Boot / Menu 不再推进；日志停在某一条之后再无输出；`Time.frameCount` **跑了两分钟只有 2**。看起来完全像"状态机坏了"，**实际游戏代码一行都没错**。
- **判据**：`eval_file` 打印 `UnityEngine.Time.frameCount`，隔 10 秒再打一次 —— 数字没变 ⇒ 就是它（正常应是几百上千）。
- **对策（根治，别只在验证时临时开）**：游戏侧在 `Awake` 里设 `Application.runInBackground = true;`。用 eval 临时打开的值**域重载就没了**，下一次重编译后又开始"卡死"，会让人误判成回归。

### ② 窗口失焦 → Unity 不会自动扫到外部文件改动 → `recompile` 误报「无需编译」

- **症状**：改了 `.cs` 后 `unity command recompile` 回 `{"status":"up_to_date","message":"No scripts needed recompilation."}`，但 `Library/ScriptAssemblies/*.dll` 的**时间戳还是旧的**。
- **判据**：**比对 dll 时间戳 vs 源码时间戳**。不要信 `recompile_status` —— 它报的是"**上次**编译结果"，在"有改动但没触发编译"时它一样回 `failed:false`，极具误导性。
- **对策**：先刷资产库、**再**编译，顺序不能反：
  ```powershell
  # 1) probe.cs（eval_file 执行，内容是方法体语句）
  #    UnityEditor.AssetDatabase.Refresh(UnityEditor.ImportAssetOptions.ForceUpdate);
  unity command eval_file --file "<工程>/client/probe.cs"
  # 2) 然后才编译
  unity command recompile
  ```

### ③ `recompile` 回 "Network error" —— 十有八九是正常的

编译会触发**域重载**，域重载会把 Pipeline 的 HTTP 连接掐断，于是 CLI 报 `Network error: An error occurred while sending the request.`。**判据**：看 `ScriptAssemblies/*.dll` 时间戳有没有更新 —— 更新了 = 编译成功，那条报错直接忽略。同理：**Play 模式会因为域重载而自动退出**（日志里有 `Loaded scene 'Temp/__Backupscenes/0.backup'` 就是退出 Play 后的场景还原），发现 `playMode: stopped` 别慌，重新 `editor_play` 即可。

### ④ `capture_game_view --source screen` 只在 Play 模式可用

编辑模式下回 400：`capture_game_view with source="screen" requires Play Mode: Screen Space - Overlay UI only composites to the backbuffer at runtime. Use source="camera" in Edit Mode.` ⇒ **拍 UI / 拍游戏画面必须在 Play 里做**；编辑模式想截图就用 `--source camera`。

### ⑤ `clear_console` 清的是【编辑器控制台窗口】，日志文件里的历史行仍在

⛔ **别用 `clear_console` + grep 日志文件来判断"这次编译过没过"** —— 文件是追加写的，上一轮的错误行都还在，`Select-Object -Last N` 抓到的很可能全是历史行，于是**明明已经修好、却看起来还在失败**。
**判据只用权威状态**：`unity command recompile_status --format json` 的 `failed` / `errors` / `compilationFailed` 三个字段；再配合 `Library/ScriptAssemblies/*.dll` 的时间戳（**编译失败时 Unity 不会更新 dll**）。

### ⑥ `eval_file` 的代码是【方法体】，不是完整类

只能写**语句**（不能有 `using` / `class` / 方法声明），结尾要给一个 `return` 值；想用 `UnityEngine` 就直接写全名（包装器会补 using）。
**长代码一律走 `eval_file` 读文件**，不要内联塞进 `eval`：内联字符串里的空格会让 CLI 把它拆成多个位置参数，报 `eval 的参数无效：…没有对应的位置`（看起来像"你的 JSON 写错了"，其实是命令行被拆了）。
探针文件放**项目根的 `.ai-tmp/test/`**（如 `<项目根>/.ai-tmp/test/probe.cs`），⛔ **不要放进 `Assets/`** —— 会被 Unity 当资产导入并参与编译，一个语法错就让整个工程进 Safe Mode。

### ⑦ 逐步式驱动的步号文件【不会自重置】—— 每轮 runner 必须先归零

驱动常见形态：读一个 `*-step.txt` 决定这次做哪一步，自己 `step+1` 写回，`eval_file` 反复调用推进一条链路。⛔ **它自己不会把步号归零** —— 上一轮跑到 step 18，下一轮就从 19 起，所有 `step == N` 分支都不匹配 ⇒ **永远停在第一步**（表现为"点不动 / 一直 poll"），日志看着完全正常，只有 `action=poll (no matching node for step 19)` 这一行是线索。**runner 在 `editor_play` 之前必须把步号文件写成 `0`。**
同类陷阱：驱动里的 `OutFile` / `StepFile` 是**硬编码常量** —— runner 里把读证据的路径写成别的名字就会**永远读到空**，看不出任何错。要么读驱动自己写的路径，要么把路径改成命令行可传。

### ⑧ 采图判定尺寸【不要读 `Screen`】—— 它在同一局 Play 内会漂移

真对局中同一局内逐步读 `Screen.width×height`，会时而 `1080x1920`、时而 `1366x578`、`1810x345`。**原因**是 Game View 没锁固定分辨率（自由缩放 / 被停靠面板 resize），`Screen` 报的是当时窗口尺寸 —— 很容易被误判成"工程配错了竖版分辨率"。
**对策**：采图时**显式强制目标尺寸**（`capture_game_view --width 1080 --height 1920`），或用自己的宽高常量，⛔ **不要用 `Screen` 或 `PlayModeView.GetMainPlayModeViewTargetSize()`**（后者返回的是**窗口**像素，含黑边，不是渲染目标尺寸）。

### ⑨ 遍历场景根【看不到 `[UI]`】—— UI 画布在 DontDestroyOnLoad 里

`SceneManager.GetActiveScene().GetRootGameObjects()` 只会给你场景内根节点（相机 / 入口物体），⛔ **不含**引擎 `UIManager` 的画布 `[UI]` —— 它是 `DontDestroyOnLoad` 的，**不在场景根里**。
**正确写法**：`UnityEngine.Object.FindObjectsOfType<Canvas>(true)` / `GameObject.Find("[UI]")` 再往下走 —— 否则会得出"UI 是空的"这种**探针自己的盲区造成的假结论**。

---

## 五、P-3：第二次进 Play 就是一片蓝 —— 查「快速进入 Play 模式」

> **症状**：第一次进 Play 一切正常；**停掉再进第二次，整个屏幕只剩相机的纯色背景**（比如一片天蓝），UI 一个字都没有，日志里连报错都没有。**典型的"只有非首次运行才复现"** —— "我跑一次是好的"不能用来否掉这个 bug。

> **真因**：工程开了 **Enter Play Mode Options / 不重载域**（`ProjectSettings/EditorSettings.asset` 里 `m_EnterPlayModeOptions: 1` = DisableDomainReload）⇒ **所有 `static` 字段跨 Play 局残留**。典型是两道静态闸门叠加：① 业务入口自己的 `_launched` 还是 `true` → 新一局自毁，什么都不初始化；② 引擎 `Game.Launch` 里的 `if (IsRunning) { LogWarning("Already running"); return; }` —— `IsRunning` 也是静态的，同样残留。两条叠加 = 没有 UI、没有流程、只有相机底色，**而且它不报错**。

> **判据**（一条命令定位）：
> ```powershell
> Select-String -Path ProjectSettings\EditorSettings.asset -Pattern 'EnterPlayMode'
> # m_EnterPlayModeOptionsEnabled: 1 且 m_EnterPlayModeOptions: 1  ← 就是它
> ```
> 运行时判据：`eval_file` 打印 `Game.Fsm.Current` —— 第二次进 Play 直接是上一局的终态（如 `GameOver`）而不是 `Boot`，那就是静态状态残留，不是"菜单没做"。

> **对策（二选一）**：
> - **能改工程设置（推荐）**：关掉快速进入模式 —— 用编辑器 API 改比手改文件可靠（手改 `.asset` 会被 Unity 覆写）：
>   ```csharp
>   // eval_file：内容是一段语句
>   UnityEditor.EditorSettings.enterPlayModeOptionsEnabled = false;
>   UnityEditor.AssetDatabase.SaveAssets();
>   UnityEditor.EditorApplication.ExecuteMenuItem("File/Save Project");
>   ```
> - **不能改设置**：每个静态状态都要自己复位（`[RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)] static void ResetStatics() => _launched = false;`），但这只解决你自己那份；**引擎侧的静态闸门你改不了**，所以这条通常救不回来。

> ⚠️ **判据优先看"那一句分支日志有没有打"，不要只看"UI 空不空"** —— 空 UI 的候选成因很多，只有日志能证伪。

> **高危连带坑：输入注入的两个反面**（一个症状是"乱响应"，另一个是"完全不响应"）。每次 `InputSystem.AddDevice<Keyboard>()` 都会留下一个设备（每局残留一条，越测越多），残留的按键按下状态会污染引擎读数（表现为"没注入跳却在跳 / 原地反复跳 / 掉穿地面"）。
> ⚠️ **但"注入前先移除所有非真实键盘设备"这条旧建议只对了一半**：`RemoveDevice()` 之后 `Keyboard.current` **仍然指向那个已销毁的对象** ⇒ ① 往它投事件等于投进黑洞（注入**完全没反应**）；② 访问 `kb.name` 会抛 `NullReferenceException`（这个 NRE 会把人引到完全无关的方向）。→ 完整结论见 **P-4**，**写注入脚本前先读它**。

---

## 六、P-4：按键注入（**照抄这套，别再自己发明**）

> **症状**：用 `eval_file` 往 InputSystem 队列里投按键（`QueueStateEvent`），**日志一切正常**（Timer 回调执行了、`fsm` 也对），**但游戏就是不响应**。

### ✅ 正确做法（注入后流程能推进一屏即视为链路通）

```csharp
// ① 两个设置都要改（只在探针脚本里改，不要写进工程设置）
var s = UnityEngine.InputSystem.InputSystem.settings;
s.backgroundBehavior = UnityEngine.InputSystem.InputSettings.BackgroundBehavior.IgnoreFocus;
s.editorInputBehaviorInPlayMode =
    UnityEngine.InputSystem.InputSettings.EditorInputBehaviorInPlayMode.AllDeviceInputAlwaysGoesToGameView;

// ② 清掉所有【残留】的自建键盘（不能省）
foreach (var d in UnityEngine.InputSystem.InputSystem.devices.ToArray())
    if (d is UnityEngine.InputSystem.Keyboard k && k.name != "Keyboard")
        UnityEngine.InputSystem.InputSystem.RemoveDevice(k);

// ③ 新建一条键盘并投状态（新建后它就是 Keyboard.current）
var kb = UnityEngine.InputSystem.InputSystem.AddDevice<UnityEngine.InputSystem.Keyboard>();
UnityEngine.InputSystem.InputSystem.QueueStateEvent(kb,
    new UnityEngine.InputSystem.LowLevel.KeyboardState(UnityEngine.InputSystem.Key.Space));  // 按下
// 松开：同样一句，换成无参的 new KeyboardState()

// ④ 【不要】手动调 InputSystem.Update()（没有带参重载；默认模式下无参调用还会 NRE）——
//    交给播放循环自己那一帧 Dynamic 更新去处理就行。
```

### ⛔ 判定"注入到底有没有生效"的唯一正确方式

**看游戏自己的反应** —— 流程日志（`[Flow] →` 有没有推进）、角色位移、HUD 数值变化。
⛔ **绝对不要**在 `eval_file` 里读 `kb.spaceKey.isPressed` 或 `Game.Input.GetKey(...)` 来判定：`eval_file` 跑在**编辑器更新**上下文里，读的是**编辑器那一套状态缓冲**；游戏跑在**播放循环**里，读的是 **Dynamic 缓冲**。**这是两套独立的状态** —— 编辑器里读到 `False` **完全不代表游戏没收到**。**判据选错，比不测更糟**（会在"注入无效"的错误结论上绕很多轮）。
同理：`InputState.Change(control, value)` 对按键这类**位域控件**会直接抛 `Cannot change state of bitfield control` —— 别指望用它绕过去。

### 三个坑（叠在一起，任一个都能让注入失效）

- **① 窗口失焦 → 设备被禁用 → 状态被直接丢弃**（AI 驱动时**永远**是失焦的）：`backgroundBehavior` 默认是 `ResetAndDisableNonBackgroundDevices`，窗口一失焦设备就被禁用，`QueueStateEvent` 投进去的状态**被丢掉**。判据：日志里带上 `Application.isFocused`（会是 `false`）。对策即上面①（**只在探针脚本里设**）。
- **② `Keyboard.current` 可能是【已被 RemoveDevice 掉的死对象】**：往它身上投事件 = 投进黑洞，读 `.name` 还会 NRE。对策：**先把残留的全 RemoveDevice 掉，再 AddDevice 一条新的**。
- **③ 残留设备必须清、不要"复用"**：累积的自建键盘会互相干扰（可能带着"按下未松开"的状态，也可能让 `current` 指向已失效对象）。**正确做法就是上面那句：清空所有非 OS 键盘 → 新建一条 → 只往这条投。**
- **④ ⚠️ 绝对不要动 `InputSystem.settings.updateMode`**（代价最大的一条）：把它设成 `ProcessEventsManually` 想"手动驱动输入"，结果 **`CloverEngine.Game.Input` 直接变成 `null`**，整个游戏收不到任何输入（菜单、跳跃、暂停全都失灵），而报错为零、日志正常 —— 差点被当成"引擎坏了"。它改的是 `InputSystem` 的全局设置 ScriptableObject，**在同一个 Play 会话内一直生效**；工程没有 `.inputsettings` 资产时，重进 Play / 域重载会恢复默认，**但"没落盘"是靠不住的保险**（有的工程就是有这个资产）。
  **硬规矩：探针只许改 `backgroundBehavior` 和 `editorInputBehaviorInPlayMode` 这两项（且每次注入前都显式设一次），`updateMode` 碰都不许碰。** 排查完顺手把这两项还原成默认值。

> **附带两个同样误导的坑**：
> - **`GameObject.Find("XxxPanel")` 查 UI 面板永远查不到** —— 实例名带 `(Clone)`。要么查 `"XxxPanel(Clone)"`，要么用子串扫描 `FindObjectsByType<GameObject>` 判 `name.Contains(...)`。
> - **只是想让游戏"到达某个状态"来做验证时，不要硬走按键**：直接发工程自己的事件（`Game.Event.Emit("StartNewGame")` / `Emit<int>("CharChosen", 1)`）一步到关卡 —— 稳定、不受上述坑影响。**按键注入只用于专门验证输入链路本身。**

---

## 七、P-5：Editor 脚本弹**原生模态框** ⇒ 编辑器**静默卡死**、之后所有命令都超时

> **症状（极具误导性）**：AI 让编辑器跑一个耗时的 Editor 脚本（场景 / 资产生成器）之后，**所有** `mainThreadRequired` 命令都超时（连 `editor_status` 都超时）。而各项自查**全是绿的**，把排查引到完全错误的方向：

| 自查项 | 读数 | 误导出来的结论 |
|---|---|---|
| `/api/status` | `ready`，**心跳还是新鲜的** | "服务活着 ⇒ 肯定是 CLI 没连上" |
| `/api/dialog` | `active:false`、`dialogs:[]` | "没有对话框挡着" |
| `/api/progress` | `active:false` | "没有长任务在跑" |
| `unity status` / `pipeline list` | 空表 | "编辑器没开 / Pipeline 包装晚了" |
| 进程 `Responding` | `True` | "编辑器没死" |
| 进程 `CPU`（两次采样） | **差值 = 0** | 被读成"脚本很慢，再等等" |

> **真因**：Editor 脚本里调用了**会弹原生模态对话框**的 API。最典型的是 `EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo()`（弹 **"Scene(s) Have Been Modified" → 再弹 "Save Scene"**）；同类还有 `EditorUtility.DisplayDialog*`、模态 `EditorWindow`、资源冲突对话框。模态框**阻塞编辑器主线程** ⇒ Pipeline 的 Dispatcher 工作项**永远不返回** ⇒ 之后所有命令排队超时。而 **Pipeline 看不见原生框**（`/api/dialog` 只报它自己包装的那类）⇒ 自查全绿、无一条报错。
> **为什么"CPU 差值 0"是分水岭**：脚本真在跑会吃 CPU；**CPU 不动却命令不通 = 等待式阻塞**（模态框 / 锁），不是在计算。

**判据（一条命令区分"卡死"与"慢"）**：

```powershell
Get-Process -Id <unityPid> | Select-Object CPU, Responding, MainWindowTitle
Start-Sleep -Seconds 15
Get-Process -Id <unityPid> | Select-Object CPU, Responding, MainWindowTitle
```

**CPU 差值 = 0 且命令不通 ⇒ 按"卡在模态框"处理**，不要再等。

**铁证（不问 CLI、不问 Pipeline，直接问 Windows）**：用 Win32 `EnumWindows` 枚举该进程的顶层窗口 —— 命中一个**类名 `#32770`**（Windows 标准对话框类）、标题形如 `Scene(s) Have Been Modified` / `Save Scene` 的窗口；同时主窗口（`UnityContainerWndClass`）会变成 **`Enabled = False`**（这一条就是"存在模态子窗口"的铁证）。

**处置（AI 自己就能点掉，不必麻烦用户）**：点某个按钮 ⇒ `EnumChildWindows` 找按钮文本（`Don't Save` / `取消`）→ 给按钮发 **`BM_CLICK` (0x00F5)**；整体取消 ⇒ 直接给对话框窗口发 **`WM_CLOSE` (0x0010)**。
⚠️ **点 "Save" 而当前场景又没有路径 ⇒ 立刻再弹一个"另存为"文件对话框**（`DUIViewWndClassName` / `DirectUIHWND` 那一套）—— **又卡一次**。要么别点 Save，要么准备连点两次。点掉后 `editor_status` **立刻**恢复，无需重启编辑器。

**根治（规则层见 `SKILL.md` §1 的闸门 2）**：⛔ Editor 脚本（生成器 / 构建器 / 批量工具）在自动化路径上不许调用任何会弹原生模态框的 API；需要处理"当前场景可能有未保存修改"时**静默处理 + 打一条 Warn 日志**，不许调 `SaveCurrentModifiedScenesIfUserWantsTo()`（`EditorSceneManager.NewScene(..., NewSceneMode.Single)` **本身不弹框**，直接用它覆盖即可）。

**顺带钉死四条**：
1. **`unity status` / `unity pipeline list` 空表 ≠ 连不上**：先 `cd` 进工程，或显式 `--project-path`；仍空表就**直接读 `Library/Pipeline/.unity-pipeline-port`、打 HTTP `/api/status` 当铁证**。某些 CLI 版本与 Package 版本的组合下**实例枚举坏了，但 `unity command <name> --project-path <p>` 完全可用** —— ⛔ 不要因为 status 空表就判定"连不上"、就重启编辑器或麻烦用户。
2. `unity command` 的 **`--timeout` 单位是「秒」**（默认 30），且**只影响 CLI 侧等待**，**不会**放宽服务端命令自身的预算；另有 **`--detach`**（提交为分离作业、立刻返回 job id）。
3. **`eval_file` 的服务端预算只有 5 秒**（`timeout` 默认 5000ms），而且**超时会中断**正在跑的主线程代码（不是"继续跑完"）⇒ **长任务不能用 `eval_file`**：走 `menu`（CLI 侧默认 30 秒、可 `--timeout` 放大），或把工作**切片 / 改成增量**。
4. **`GET /api/commands` 能拿到每条命令的 JSON schema**（参数名 / 类型 / 默认值）—— **用它，别猜参数名**。`/api/exec` 对**带参命令**的 body 形态很难猜（`args` / `parameters` / `arguments` / `params` / 平铺全试过 = 400）⇒ **别在 HTTP 上纠缠，用 CLI `unity command`**；真正好用是那几个 **GET 端点**：`/api/status`、`/api/dialog`、`/api/progress`、`/api/commands`。

---

## 八、★ 驱动工具链时 **PowerShell 本身**的坑

> 这些坑的症状都很"玄学"（莫名的结果、莫名的类型错），但成因都在这张表里。

| # | 坑 | 症状 | 规矩 |
|---|---|---|---|
| 1 | 变量名**大小写不敏感** —— `$Out` 和 `$out` 是**同一个**变量 | 先 `param([string]$Out)` 声明输出路径，后面又 `$out = New-Object ...` ⇒ **把参数覆盖了** ⇒ 报 `[System.String] 不包含名为 "Add" 的方法`、`Set-Content 参数 Path 为空字符串` 这类完全指错方向的错 | `$out` / `$input` / `$args` / `$pid` / `$home` / `$error` / `$host` 这类名字**一律别用**（`$pid` 是**只读自动变量**，赋值直接报错） |
| 2 | `$Matches` 会被**下一个**正则覆盖 | 一个条件里连用两个 `-match`，后面用 `$Matches[2]` 时它已经是**第二个**正则的捕获组 ⇒ 解析出的字典"条目数对、内容全空" | **一次 `-match` 立刻把 `$Matches` 落到局部变量**；更稳的是**不在一个条件里连用两个 `-match`** |
| 3 | `New-Object T(a, b)` **不是**构造函数调用 | 参数会被当成**一个数组**传，或类型不对时**返回 null 且不报错**（如 `[math]::Ceiling()` 返回 `double`，而 `Bitmap(double,double)` 没有重载 ⇒ null）⇒ 后面报"无法对 Null 值表达式调用方法" | 一律用 `[Type]::new(...)`，并**显式 `[int]` 转换** |
| 4 | PowerShell 5.1 按 **ANSI** 读**无 BOM** 的 `.ps1` | 脚本里写中文注释 / 字符串（尤其 `→`、`★` 这类符号）会把字符串**截断** ⇒ 报一堆莫名的"缺少终止符" | **唯一口径 = 文件里有没有非 ASCII 字节**：没有 ⇒ 不需要 BOM；**有**（代码 / 注释 / 输出都算）⇒ **整个文件必须存成 UTF-8 with BOM**（推荐仍正文全 ASCII、中文从数据文件读） |
| 5 | `Set-Content` 改文件有**编码风险** | 中文变乱码，或直接被工具拦下 | 优先用编辑工具；非要脚本写就用 `[System.IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($false)))` |
| 6 | `Get-Content` **不带编码** | Windows 上可能按 GBK 解码 UTF-8 文本 ⇒ 中文乱码 / 匹配不上 | 读日志用 `Select-String`（自带编码探测）或显式 `-Encoding UTF8`；大文件用 `search_content` |
| 7 | 长命令后面接 `Select-Object -Last N` | 它会把输出**全部缓冲到进程结束**，期间一个字都不显示 ⇒ 人和 AI 都会以为程序死了 | 长命令**后台启动 + 自己轮询** |
| 8 | 相对路径 + cwd 不对 | 明明在盘的文件 / 目录被判"不存在"（尤其中文目录名），下游结论全错 | 验证存在性只用**绝对路径** + `Test-Path -LiteralPath`；列文件用 `-Recurse -File -Filter`（不用 `-Include`）；⛔ 不吞 `-ErrorAction SilentlyContinue` 的错 |

---

## 九、建 / 开工程「静默卡死」的其余成因

**症状**：`unity projects create` / `unity run` / `unity test` 长时间不返回、CLI 一个字都不输出；`ProjectVersion.txt` 始终不生成。**这类问题几乎都不是 Unity 慢，而是 Editor 起不来在死等。**

> **★ 先回到"预防"，别上来就排查**：① 工程还没创建 → **先问用户 360 关了吗**（没关就别建，见 §一）；② 工程已创建 → **请用户自己在 Hub 里打开**，⛔ 不要自己跑 `unity run` / `-batchmode`。本节列的是"已经卡住了怎么救"。

**9.1 先分清「慢」和「阻塞」**：

```powershell
Get-Process -Name Unity -ErrorAction SilentlyContinue |
  Select-Object Id, @{n='CPU秒';e={[math]::Round($_.CPU,0)}}, @{n='内存MB';e={[math]::Round($_.WorkingSet64/1MB,0)}}
# CPU 时间在涨 = 慢（正在导入/编译）；几乎不动 = 阻塞（在等 I/O 或某个服务）
```

**9.2 两个已确认的成因**（杀软拦截的两种形态见 §一，不重复）：

**(1) 工程 / 日志放在点开头的目录**：报 `Error: .codebuddy is not a valid directory name.`。**危害不只是"这次失败"** —— 它会让 UDS 的机器级共享状态进入坏状态，**之后放在正常路径下的工程也会一起失败**（踩过一次后，把工程挪到正常路径并不能立刻恢复）。

**(2) 中途强杀 Editor**：导入被强杀（超时 / 取消 / `Stop-Process`）会写坏 `<工程>/Library/DataStore`，此后每次启动都崩在 `UDSInterface::UDSInterface` / `InitializeAssetDatabaseV2`。**修法**：把 `Library` 整体**挪走**（改名即可）让它重建（`Move-Item "<工程>/Library" "<工程>/Library-dead-$(Get-Date -Format HHmmss)"`）。**预防**：不要给 Editor 设很短的超时（首次导入含包解析几分钟属正常），需要等待就用**后台进程 + 轮询**。

> 排查时**别看 `Editor.log` 判断"卡在哪"**：这几种情况在日志尾部长得都很像 —— 认准关键字：UDS 看 `UDSInterface::UDSInterface`、licensing 看 `Failed to acquire global mutex`、导入看 `[Bee]`/`Import` 步骤在动。

**9.3 导入阶段的调用姿势（避免「看起来卡死」）** —— 仅用于建工程 / 首次导入的排查，⛔ 不是日常驱动手段（日常一律驱动用户已打开的编辑器）：

```powershell
# ❌ 长命令后面不要接 Select-Object -Last N：它会把输出全部缓冲到进程结束，期间一个字都不显示
# ✅ 后台启动，自己轮询：
$p = Start-Process -FilePath 'unity' `
     -ArgumentList @('run','<工程>','--editor-version','6000.0.x','--timeout','1500','--non-interactive','--no-banner',
                     '--','-nographics','-logFile','<工程>/Logs/editor.log') `
     -RedirectStandardOutput '<工程>/Logs/cli.log' -RedirectStandardError '<工程>/Logs/cli.err' `
     -WindowStyle Hidden -PassThru
"PID=$($p.Id)"
```

随后每隔 1~2 分钟用**短命令**检查四项：进程是否存活 / CPU 是否在涨 / `<工程>/Library` 体积是否在变大 / 日志尾部。**判断导入真的在推进**：`Library` 体积持续增长（空 3D 模板首次导入通常几分钟）；体积长时间不变**且** CPU 不动 = 阻塞，回到 9.1 / §一。
另注：`unity run` 的 `-quit` / `-batchmode` 是 CLI 自己管理的保留参数，放在 `--` 之后会报 `conflicts with a reserved Unity flag`，去掉即可。

---

## 十、Unity **编辑器 API** 的坑（写生成器 / 导入器 / 批处理时会撞上）

| # | 坑 | 症状 | 修法 |
|---|---|---|---|
| 1 | `TextureImporter.spriteAlignment` **不在** `TextureImporter` 上 | 直接赋值编译不过 | 走**往返**：`var s = new TextureImporterSettings(); importer.ReadTextureSettings(s); s.spriteAlignment = (int)SpriteAlignment.Custom; s.spritePivot = new Vector2(0.5f, 0f); importer.SetTextureSettings(s);` |
| 2 | `AssetDatabase` **未同步**时 `SaveAsPrefabAsset` 会写出**空壳** | 预制体文件在、`m_Name` 也对，但 `m_Script: {fileID: 0}` ⇒ 运行时 `Component X not found on prefab` ⇒ **面板永远打不开**（成因：同一次批处理里脚本刚编译完，`MonoScript` 还没被导入） | 存之前用 `MonoScript.FromMonoBehaviour` **自检**，解析不到就**报错跳过**（⛔ 不要安静地生成一个废预制体）。⚠️ `Refresh(ForceSynchronousImport)` 能修但会**重新导入整个工程** ⇒ 直接跑到超时；用轻量 `Refresh()` + 自检 |
| 3 | `ScreenCapture` 属于 `com.unity.modules.screencapture` | manifest 没引这个模块就用不了 | 改用 `Texture2D.ReadPixels` + `EncodeToPNG`（在 Core / ImageConversion 里，通常已引） |
| 4 | 场景里**没有 `AudioListener`** | ① 每秒刷一条 `There are no audio listeners in the scene`；② **所有音效静默** —— 而那条刷屏会把"音效没做"这个**真问题淹掉**（第②条才致命） | 在入口物体（`Bootstrap`）里**运行时保证有一个**（比依赖"生成场景时记得挂"可靠） |
| 5 | 批处理模式下 `-executeMethod` **执行完立刻退出** | **进不了播放模式** ⇒ 想驱动 Play 模式只能走 **PlayMode 测试**（`unity test`）或驱动**已打开**的编辑器（`reference/unity-cli.md` §8） | — |

> 写生成器 / 导入器脚本时，**每个非预期分支都要打日志**：这类失败（空壳预制体、模块缺失、静默音效）的共同点是**编译期全对、运行期静默**，不打日志就只能靠猜。
