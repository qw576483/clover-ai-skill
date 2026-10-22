# Unity 6 + Unity CLI 操作手册（AI 自动化操作的强制前置条件）

> **分工**：本文只放**操作步骤 / 命令 / 流程**（怎么装、怎么建工程、怎么驱动活编辑器、怎么跑测试）。**踩坑、报错原文、排查路径** → `reference/pipeline-and-unity-cli.md`（P-0 ~ P-5 全在那）。
> **适用范围**：这是**对 AI 的要求，不是对项目的要求**。项目用哪个 Unity 版本由项目决定；但**只要 AI 要以自动化方式操作 / 落地客户端代码**（编译验证、跑测试、构建、改场景 / 资源、读 Console、截图），**必须**通过 **Unity 6（6000.x）+ Unity CLI** 来做。
> 典型触发：AI 生成 / 修改了 `Assets/**/*.cs` 或场景资源后，需要验证能否编译、单测是否绿、能否出包。

## 1. 硬性约束（针对 AI 的自动化行为）

### 1.1 只支持 Unity 6（6000.x）

- 客户端的一切自动化操作（创建工程 / 编译 / 测试 / 构建 / 改场景与资源）**一律 Unity 6 + Unity CLI**；**其他版本不支持** —— 老工程先 `unity projects upgrade` 或重建，⛔ 不要做降级适配。
- 自检只认**真装了的**：`unity editors list --format json` 里**必须有 `location` 字段**才算装了；没有 `location` 的条目只是"已知版本"，拿它 `--editor-version` 建工程直接失败（"未找到版本 X 的 Unity Editor"）。
- 模板 id 现场查：`unity templates list --editor 6000.0.x --format json`（⛔ 不要猜 id）。

### 1.2 需要编辑器时：**默认请用户打开**；用户不开就**停下**（★★★ 硬闸门）

> **默认动作是「请用户打开」，不是「自己打开」。** 自己起编辑器（`unity open` / `unity run` / `-batchmode`）**一律禁止，没有例外**。

**标准节奏**（刚创建完工程时**必须**走这条）：
1. **AI 先请用户打开，并给出可直接照做的步骤**（⛔ 不许只说"请打开工程"）：

   > 请把这个工程加到 Unity Hub 并打开（首次导入素材会慢几分钟，属正常）：
   > 1. 打开 **Unity Hub** → 左侧「**项目 / Projects**」页
   > 2. 点右上角「**添加 / Add**」→「**从磁盘添加项目…**」
   > 3. 定位到 `<项目根绝对路径>`，**选中里面的 `client` 文件夹本身** —— ⚠️ **选 `client`，不是它的上一级**（`client` 才是 Unity 工程根：含 `Assets/`、`Packages/`、`ProjectSettings/`）
   > 4. 点「选择文件夹」→ 点列表里的 `client` 打开 → 等导入 + 编译完
   > 5. **打开后回我一声**，我继续
   >
   > 路径（可直接复制）：`<项目根绝对路径>/client`
   > 第 2~4 步也可用命令行代劳：`unity projects add "<项目根>/client"` + `unity projects pin "<项目根>/client"`。

2. **用户打开后** → 按 **§8** 驱动它：`unity status`（确认 `state=ready`）→ `eval_file` / `editor_play` / `capture_game_view` / `recompile_status`。
3. **用户没开 / 说不想开** → **停下，不继续做**（⛔ 不许"我自己批处理一下也行"）。

**为什么不许自己跑**：① 首次导入几百上千张素材 + 全量脚本编译会把**一次往返拖到十几分钟**；② 授权 / 杀软任一环节出问题就是**静默卡死**（见 `reference/pipeline-and-unity-cli.md` §一 / §九）；③ **批处理下 `-executeMethod` 执行完立刻退出，进不了播放模式** —— "跑一遍看画面"**根本做不了**。
⛔ **禁止**因为"用户没开编辑器"就跳过实测直接交付（那是半成品的主要来源）；⛔ **禁止**编辑器开着时硬跑 `unity run`（会报「项目已在运行中的编辑器中打开」）。**没有例外** —— 即使用户说「你就自己跑，别烦我」也不做，把原因讲清楚。**用户不打开编辑器 = 停在这里。**

> ★ **在让用户"添加项目 / 打开编辑器"之前**，必须先确认 `client/Packages/manifest.json` 里有 `com.unity.pipeline`（否则编辑器起来也没有 Pipeline 服务，用户得再重启一次）。做法与判据见 `reference/pipeline-and-unity-cli.md` §二（P-0）。

| 项 | 要求 |
|---|---|
| 自动化用的编辑器 | **Unity 6 / 6000.x**；若工程当前不是 6000.x，AI 先确认能否切到 6000.x 自动化，不能则明确告知用户并给方案，⛔ 不要硬着头皮用旧版跑 |
| 交互方式 | **Unity CLI**（`unity ...`），⛔ 禁止把 `Unity.exe -batchmode -quit -executeMethod Xxx` 当首选手段 |
| 输出格式 | 给 AI 解析时一律加 `--format json` / `tsv`，⛔ 不要解析人类可读表格 |
| 平台 | Windows 用 PowerShell；macOS/Linux 用同一套 `unity` 子命令 |

**⛔ 禁止**：直接拼 `Unity.exe` 绝对路径执行批处理（Hub 路径随机器变化，不可移植）；用 Hub GUI 手工点然后让 AI 盲猜结果；在 Editor 打开且未保存时直接改磁盘上的 `Assets/` / `ProjectSettings/`（先保存或关闭 Editor）；把工程 / `-logFile` / 内容目录放在**点开头的目录**下（`.codebuddy/`、`.cache/` …）—— Unity 报 `xxx is not a valid directory name`，**并且会把机器级 UDS 共享状态弄坏，连累之后所有正常路径下的工程**（见 `reference/pipeline-and-unity-cli.md` §九）；在导入 / 编译进行中**强杀 Editor 进程** —— 会写坏 `<工程>/Library/DataStore`，之后每次启动都崩在 `UDSInterface::UDSInterface`（见同节）。

**例外**：只有当 CLI 确实没有对应能力时（Terrain、Addressables、ParticleSystem 模块、Shader Graph），才可退回 `unity command ...` 的 `eval` 逃生口跑 C#，或在 CLI 能力外再考虑 Editor 脚本 + `-executeMethod`，并在回复里说明为什么 CLI 做不到。

## 2. 前置检查：没有 CLI 就自动安装

AI 第一次需要操作 Unity 之前**必须**先自检；检测不到就**直接装**，⛔ 不要停下来问。

```powershell
if (Get-Command unity -ErrorAction SilentlyContinue) { unity --version } else { "UNITY_CLI_NOT_FOUND" }
```
```bash
command -v unity && unity --version || echo "UNITY_CLI_NOT_FOUND"    # macOS / Linux
```

输出 `UNITY_CLI_NOT_FOUND` 时安装：

```powershell
$env:UNITY_CLI_CHANNEL='beta'; irm https://public-cdn.cloud.unity3d.com/hub/prod/cli/install.ps1 | iex
```
```bash
export UNITY_CLI_CHANNEL=beta; curl -fsSL https://public-cdn.cloud.unity3d.com/hub/prod/cli/install.sh | sh
```

安装后：脚本会提示 `Note: Restart your terminal to use unity.` —— **当前 shell 可能还没有 `unity` 命令**，新开终端或用完整路径后**再自检一次**，有输出才继续。可执行文件名统一是 **`unity`**（不是 `unity-cli`、`unityhub`）。

## 3. 让 AI 客户端自己学会用 Unity CLI（强制）

> 只要 AI 要敲任何 `unity` 子命令，就必须先完成本节；**没装 unity-cli skill 就凭记忆拼命令 = 违规**。

Unity CLI 自带一份 **agent skill**（离线内置），可直接装进 AI 客户端：

```bash
unity skill show                 # 只打印 skill 内容（只读，可当权威命令手册读）
unity skill show --list          # 列出 skill 由哪些文件组成（SKILL.md + references/*）
unity skill install --list       # 查看支持的 AI 客户端及安装状态
unity skill install <client>     # 安装到指定客户端（claude-code / cursor / codex / vscode …）
unity skill refresh              # CLI 升级后，用新版本重新渲染已安装的 skill
```

安装位置示例：`claude-code → ~/.claude/skills/unity-cli/`、`codex → ~/.agents/skills/unity-cli/`。命令记不准时先 `unity skill show` 取权威用法。

### 认出自己，装到自己身上

**AI 要"识别"的不是用户用什么工具，而是自己是什么**（身份在会话开始时就由运行时注入，**AI 一定知道自己是谁**）。⇒ ⛔ **禁止**问用户"你用的什么 AI 工具"；⛔ **禁止**靠 `~/.claude`、`~/.cursor` 这类目录探测反推"我现在跑在哪个工具上"（机器上装过什么 ≠ 当前会话跑在什么上面）。

**步骤**：① `unity skill install --list` 看官方支持哪些客户端；② **里面有自己的** → `unity skill install <自己>`；③ **里面没有自己**（CodeBuddy、自研 Agent 等）→ 自己想办法搬进去（`unity skill show` 打印权威正文后自己写进自己的 skill 目录，或从任一已安装客户端的 `skills/unity-cli/` 复制过来；目录约定与 Claude 系一致：`<你的 skill 根目录>/unity-cli/SKILL.md`，具体路径你自己确认）；④ **验收并当场使用**：确认已在自己 skill 目录里，**立刻读进上下文**再动手。

| 若自己是… | client 名 |
|---|---|
| Claude Code / Claude Desktop | `claude-code` / `claude-desktop` |
| Cursor / Windsurf | `cursor` / `windsurf` |
| VS Code + GitHub Copilot | `vscode` |
| Cline / OpenAI Codex CLI / Grok Build | `cline` / `codex` / `grok` |
| CodeBuddy / 其他 | 官方列表不含 → 按第 3 步自己动手 |

**时效**：skill 索引一般下一条消息即可见；**skill 正文当场读 / 加载即用，无需重启会话**；只有 `unity` 二进制的 **PATH** 需要新开终端（刚装完常见）；CLI 升级后 `unity skill refresh`，不在官方列表里的客户端要自己再搬一次。

## 4. 常用命令速查

```bash
unity --help              # 查看全部命令
unity upgrade             # 升级 CLI 自身
unity editors list        # 列出已安装/可安装的编辑器（--format json / tsv）
unity install             # 安装 Unity 6 编辑器（缺编辑器时用它，别手工下载 Hub）
unity install --version 6000.0.58f2 --module android ios webgl   # 指定版本 + 模块
unity pipeline install    # 装 Unity Pipeline 包（AI 操控 Editor 的前置依赖）
unity command             # 连接本机已打开的 Editor，列出可执行的 Editor 命令
unity build run --target android --output build/app.apk          # 异步构建 + BuildReport
unity test <工程路径> --mode EditMode|PlayMode --output <报告路径>
unity console tail --format json                                  # 增量读 Console 日志（cursor 追踪）
unity screenshot --source scene --output shot.png                 # 场景/Game 视图截图
unity project audit --format csv                                  # Project Auditor 静态分析
```

`unity editors list --format json` 返回结构（字段稳定，可安全解析）：

```json
{ "success": true, "command": "editors", "data": [
  { "version": "6000.0.58f2", "alias": "6.0.58f2", "architecture": "x86_64", "default": true,
    "location": "C:\\Program Files\\Unity\\Hub\\Editor\\6000.0.58f2" },
  { "version": "6000.0.47f1", "alias": "6.0.47f1", "architecture": "x86_64", "default": false }
] }
```

> ⛔ 第二条**没有 `location`** —— 那是"已知版本但没装"的形状（§1.1 的判据）。⇒ **解析时必须以 `location` 是否存在为准**，而不是"数组里有没有这一项"。

### 4.1 跑引擎自带测试（EditMode / PlayMode）

**`clover-client-unity-engine/` 是 UPM 包，不是 Unity 工程**（没有 `ProjectSettings/ProjectVersion.txt`、没有 `Assets/`）—— 直接 `unity test clover-client-unity-engine` 会报「不是 Unity 项目」，**必须指向一个承载它的工程**。
承载工程要满足两条（见 `scaffold/new-project.md` §2.2）：① `Packages/manifest.json` 里列了 `com.clover.unity-engine`；② **`testables` 里也列了它** —— 不加的症状**是静默的**：`unity test` 正常退出、报告 `testcasecount="0"`，一条用例都不跑。

```bash
unity test <承载工程路径> --mode PlayMode --output <报告路径>/playmode-results.xml
unity test <承载工程路径> --mode EditMode --output <报告路径>/editmode-results.xml
```

**读结果**：解析报告里的 `<test-run ...>` 属性（`passed / failed / skipped / testcasecount` 都在这一行），别去翻 Editor 日志：

```powershell
[xml]$x = [IO.File]::ReadAllText('<报告路径>', [Text.Encoding]::UTF8)
$x.SelectNodes('//test-run') | Select-Object -First 1 -ExpandProperty OuterXml
```

**写 PlayMode 用例的三个坑**（都会伪装成「实现有 bug」）：

| 现象 | 真因 | 正确做法 |
|---|---|---|
| WS 用例恒红：客户端 `State=Disconnected` | Unity/Mono 的 `HttpListener` **不支持 WebSocket 升级**（`IsWebSocketRequest` 恒 false），假服务端会对合法升级请求回 400 | 别用 `HttpListener`：改用裸 `TcpListener` 自做 RFC 6455 握手（范例见引擎仓库 `Tests/PlayMode/MiniWsServer.cs`） |
| 推送 / 回包用例超时，但链路明明连上了 | 收包队列只在 `NetworkManager.Tick()` 里被排空，测试里只 `yield return null` 帧会**一直躺在队列里** | 等待循环中**每帧泵一次** `nm.Tick()` |
| 等待类用例报"超时"，但日志显示数据早收到了 | 等待助手把**有副作用的谓词求值了两次**（`while(!cond()) …; Assert.IsTrue(cond())` —— 循环里那次成功后 `TryTakePacket` **已出队**，断言里再求值就是 false） | 助手内**只求值一次**：`var ok = cond(); while(!ok && 未超时) { yield return null; ok = cond(); } Assert.IsTrue(ok, …)` |

> 跑 `TestCase` 数对不上时，先确认**承载工程的 `testables`**，再怀疑测试框架。

## 5. 标准操作流程

① **自检 CLI**（`unity --version`）→ 没有就按 §2 装；② **确认编辑器**（`unity editors list --format json` → 没有 6000.x 就 `unity install`）；③ **确认工程**（`Set-Location <项目根>/client`，或按命令要求显式带工程路径 —— `--project-path` / 位置参数）；④ **执行任务**（构建 / 测试 / 编译 / 场景与资源编辑 / 截图）；⑤ **读结果**（`--format json` 解析；失败时 `unity console tail --format json` 取日志再定位）。

## 6. 新建 Clover 客户端工程（强制用 CLI，禁止 mkdir）

**从头建游戏时，`client/` 一律用 `unity projects create` 生成，⛔ 禁止手工 `mkdir`**（完整 SOP 见 `patterns/client/new-project.md`）：

```bash
# 1. 前置：CLI + Unity 6（没有 6000.x 先 unity install）
unity --version ; unity editors list --format json
unity templates list --editor 6000.0.x --format json     # 列真实模板 id，不要猜
# 2. 创建（工程名=client，--path=项目根 ⇒ clover-{项目名}/client/ 即工程根）
unity projects create "client" --path "clover-{项目名}" \
  --editor-version 6000.0.x --template com.unity.template.2d
```

> 命令是 `unity projects create`（`projects` 复数），**不是** `unity create project`。

**验收五条，缺一即失败、删掉重来**：① `client/ProjectSettings/ProjectVersion.txt` 的 `m_EditorVersion` 是 **Unity 6（6000.x）**；② `client/Packages/manifest.json` 含 `"com.clover.unity-engine"`；③ `client/Assets/Scripts/{项目名}.asmdef` 的 `references` 含 5 个 `CloverEngine.*`；④ `client/*.sln*` 存在（Unity 6 生成的是 **`client.slnx`**，不是 `.sln` —— 不要因为没看到 `.sln` 就判定失败）；⑤ **Hub 注册表里有它、且已置顶**（见 §6.1）。

### 6.1 建完必须让用户「看得到」工程（硬约束）

工程建在 `clover-{项目名}/client/`，而 **Hub 用最后一级目录名当标题** ⇒ 列表里它叫 **`client`**，用户机器上往往还有别的 `client`，一排同名条目里根本认不出哪个是新建的。

```bash
unity projects add "<项目根>/client"     # ① 登记进 Hub 注册表（create 不保证已登记）
unity projects pin "<项目根>/client"     # ② 置顶（Hub 顶部 Favorites 区）
unity projects list --format json        # ③ 复核（isFavorite=true 且 path 正确）
```

④ **交付说明里必须写清两行**：「Hub 里显示为：**client**（标题=目录名）」+「路径：`<绝对路径>/client`」，并附一条可直接复制的 `unity open "<绝对路径>/client"`。
> 只把工程"建在磁盘上"不算交付 —— **用户看不见 = 没交付**。

## 7. 场景创建 + 脚本挂载：AI 自己做，不许丢给用户

**交付标准**：Unity 客户端的交付标准是「**打开工程 → 打开场景 → 直接 Play 就能跑**」。下面这些**全是 AI 的活**，⛔ 不许在交付说明里写"请用户在场景中创建空物体并挂载 Xxx 脚本"：创建 / 保存场景（如 `Assets/Scenes/Main.unity`）；场景加进 **Build Settings** 的 Scenes In Build（否则打包后跑不起来）；创建挂载点 GameObject（`Bootstrap` / `GameRoot`）；把业务脚本 `AddComponent` 挂上去；必要引用能自动 `Find`/`GetComponent` 就不要留手工拖拽依赖（确实需要序列化引用时也要空判断 + 运行时兜底创建）；保存场景 + 刷新资产数据库。

**做法**：优先用 `unity` 的场景 / 资源子命令，记不准先 `unity skill show`；CLI 没有对应能力时走 §1 的 **eval 逃生口**跑 C#：

```csharp
// 通过 unity command eval 执行（Editor 环境）
var scene = UnityEditor.SceneManagement.EditorSceneManager.NewScene(
    UnityEditor.SceneManagement.NewSceneSetup.DefaultGameObjects);
var root = new GameObject("Bootstrap");
root.AddComponent<Bootstrap>();
UnityEditor.SceneManagement.EditorSceneManager.SaveScene(scene, "Assets/Scenes/Main.unity");
UnityEditor.AssetDatabase.SaveAssets();
UnityEditor.AssetDatabase.Refresh();
```

**验收**：场景文件存在 + 脚本已挂在场景里的 GameObject 上 + `unity console tail` 无编译错误 + 用户在 Editor 里点 Play 即可运行（不需要任何手工挂脚本操作）。

**与工程的分工**：
- 客户端工程目录：`clover-{项目名}/client/`（或 `clover-client-unity-engine/`）。
- CLI 只做**工程级操作**（编译、测试、构建、资源 / 场景编辑、日志、截图）；**业务代码**仍按 `patterns/client/*` 与 `reference/client-conventions.md` 编写，⛔ 不要靠 CLI 生成业务脚本。
- 场景 / 资源改动完成后，提醒用户在 Editor 里确认（CLI 无 Undo 集成）。
- 构建产物不要提交；`Library/`、`Logs/`、`Temp/`、`obj/` 必须已在 `.gitignore` 中。
- 编译是否干净、运行是否自证的判据 → §8.1（⛔ 不许口说"已经好了"）。

## 8. 驱动**正在运行**的编辑器（交付前自证的首选路径）

**用户很可能已经把工程开在编辑器里** —— 此时⛔ **不要**再用 `unity run`（会报「项目已在运行中的编辑器中打开」），⛔ 也不要去手改 `.unity`/`.prefab` 文本：**直接驱动那个活编辑器**。

> ⛔ **每一条 `unity` 命令都要在 Unity 工程目录里跑**（`Set-Location <项目根>/client`，或每条都带 `--project-path`）；`unity status` 空表的第一嫌疑是 cwd 不对，不是包装时机 —— 见 `reference/pipeline-and-unity-cli.md` §三（P-1）。

```bash
unity status --format json          # 看 instances[].state 是否 "ready"（及 pid/port）
unity pipeline list                 # 安全模式自检：Safe Mode=true 说明有编译错误，先修代码
unity command                       # 列出该编辑器开放的命令（能力随包版本不同，先看再调）
```

| 目的 | 命令 |
|---|---|
| 触发 / 查询编译 | `unity command recompile` → 轮询 `unity command recompile_status --format json`（解析 `data.result` 里的 `failed` / `errors`） |
| **跑一段 C# 装配 / 自证** | `unity command eval --code '<C#>'`；**代码里有空格 / 引号时必须用文件**：`unity command eval_file --file <绝对路径>.cs`（PowerShell 会把带空格的参数拆散） |
| 进 / 出 Play 实测 | `unity command editor_play` / `editor_stop`（`editor_status` 看状态） |
| 读运行日志 | `unity command console --tail 300`（**落盘后再解析**：输出是 `命令<TAB>成功<TAB>{JSON}<TAB>参数`，用 `[IO.File]::ReadAllText` + 正则取 `"message":"…"` 最稳） |
| 清日志（先清再测） | `unity command clear_console`（⚠️ 只清编辑器控制台窗口，日志文件是追加写的 —— 判据见 `reference/pipeline-and-unity-cli.md` §四 ⑤） |
| **截图取证** | `unity command capture_game_view --source screen --save_path Screenshots/x.png`（`source=screen` 才能截到 **Screen Space-Overlay 的 HUD**；**仅 Play 模式**；`save_path` 相对**作者根 `Assets/`** 且**必须在工程目录内**，否则 400） |
| 场景内物体 / 找资产 | `find_gameobjects` / `find_assets` / `create_gameobject` / `add_component` / `attach_script` |
| Animator 资源操作 | `add_animator_parameter\|state\|transition\|layer`、`get_animator_controller`、`get_animation_clip` |

**`eval` 里的 C# 注意**：没有 `using`（写全限定名）；返回值放在末尾 `return "ok";`；长耗时操作给 `--timeout`（秒）。

### 8.1 交付前自证四连（⛔ 不许口说"已经好了"）

```bash
unity command recompile_status --format json         # ① 编译干净 failed=false
unity command clear_console; unity command editor_play; sleep 40
unity command console --tail 400                     # ② 读关键日志（自己的 Tag 前缀），且无异常
unity command eval_file --file <项目根>/.ai-tmp/test/verify-runtime.cs   # ③ 运行时自证关键对象状态
unity command capture_game_view --source screen --width 1600 --height 900 --save_path Screenshots/play.png  # ④ 截图（含 HUD）
unity command editor_stop                            # ⑤ 退 Play，别把编辑器留在 Play 模式
```

> **截图要自己看**：`表现类` 的项**截一张看一眼**（多屏才考虑拼联络图，`reference/visual-loop.md` 第八节）；`数值类` **不必截图**。数字全对但画面不对的静默失效（血条永不变化、角色纯白无贴图、血条细到看不见）只有看图才发现。
> `verify-runtime.cs` 放**项目根的 `.ai-tmp/test/`**（⛔ 不放 `Assets/` 内，否则 Unity 会把它当业务脚本编译），内容是一段 top-level 语句：`FindFirstObjectByType<T>()` 找到自己的组件，打印"是否挂上 / 目标是否绑定 / 模型是否加载 / Animator 当前 clip 与 normalizedTime"。

### 8.2 在**活编辑器里**跑 PlayMode 用例（不用抢工程）

用户开着工程时，⛔ **不要**跑 `unity test <路径>`（会报"项目已在运行中的编辑器中打开"）；活编辑器自己提供了测试命令：

```bash
unity command list_tests --mode PlayMode                                   # 先确认用例被注册
unity command run_tests --mode playmode --filter <类名或命名空间> --async_tests --timeout 300
unity command test_status                                                  # status: running → completed
```

`test_status` 返回 `summary{total,passed,failed,skipped}` + `results[]{FullName,Status,Message,StackTrace}` —— 直接读 `Message` 就能拿到断言失败原因（不用翻 Console）。

**三条纪律**（不遵守就会得到"假失败 / 假成功"）：

| # | 纪律 | 反例 |
|---|---|---|
| 1 | **必须 `--async_tests` + 轮询** | 同步调用报 `PlayMode tests cannot run synchronously over HTTP: entering play mode triggers a domain reload that drops the request` |
| 2 | **等真实时间**（`yield return new WaitForSeconds(0.9f)`），不要只 `yield return null` 数帧 | 相机 / 插值类是**平滑**的：30 帧 ≈ **0.1 秒**，根本没收敛 ⇒ 断言读到"半路值" |
| 3 | 清理用 **`DestroyImmediate`**；**"是否重复投递"以服务端日志为准** | `Destroy` 延迟到帧末 ⇒ 上一用例的墙被下一用例的探针打到。另外活编辑器里**测试与场景里的业务入口会抢同一个 `Game`/连接**，用例里的事件计数会虚高 —— 那是**环境产物**，不是产品缺陷 |

> ⛔ **别在 `eval_file` 里 `Thread.Sleep` 驱动游戏**：`eval_file` 跑在编辑器主线程上，睡眠会把"发送帧"一起卡住（你以为连打了 4 下，实际只出去 1 下）。要连打就连开多次 `eval_file`，由外壳（PowerShell/bash）控制间隔。
> **`eval_file` 有 5 秒主线程上限**（超时报 `Main thread operation timed out after 5000ms`）：凡需要"等资源导入 / 编译 / 大批量 `AssetDatabase.ImportAsset` / 大文件加载"的脚本，一律**拆小或分多次调用**；批次已提交后，用**只读**脚本查结果。

## 9. 卡住了去哪查（索引；正文都在 `reference/pipeline-and-unity-cli.md`）

### 9.1 编辑器连不上 / 命令超时 / `unity status` 空表

- `No Unity Editor instances found` 而编辑器确实开着 ⇒ 先查 **cwd**（同文档 §三，P-1），再看装包时机（§二，P-0），最后怀疑杀软 / licensing（§一）。
- 所有 `mainThreadRequired` 命令一起超时、CPU 差值 = 0 ⇒ 按**卡在原生模态框**处理（同文档 §七，P-5）；`--detach` / `--timeout`（秒）语义见同节末尾四条。

### 9.2 建 / 开工程「静默卡死」

`unity projects create` / `unity run` / `unity test` 长时间不返回、`ProjectVersion.txt` 不生成 ⇒ 先分清"慢"与"阻塞"（进程 CPU 是否在涨），再按同文档 **§一**（杀软拦 licensing 客户端 / UDS DataStore）与 **§九**（点开头目录、强杀 Editor 坏 `Library/DataStore`）逐条对证。⛔ 不要自己 `unity run` / `-batchmode` 顶替开编辑器。

### 9.3 驱动实测的「假故障」（代码没错、你以为有错）

改了 `.cs` 没重新编译 / `recompile` 报 `Network error` / `eval_file` 结果怪 / 截图为空 / 找不到 `[UI]` ⇒ 同文档 §四（P-2 九条）。

### 9.4 Play 模式相关

第二次进 Play 一片蓝（快速进入模式 + 静态残留）、按键注入"完全没反应" ⇒ 同文档 §五（P-3）、§六（P-4）。

### 9.5 脚本 / 生成器自身的坑

PowerShell 的"玄学"结果（变量被覆盖、编码乱、文件判不存在）⇒ 同文档 §八；生成器写出空壳预制体、模块缺失、音效静默 ⇒ 同文档 §十。
