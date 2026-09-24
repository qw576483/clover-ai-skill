# 启动与流程编排（App Flow）：启动 → 菜单 → 创角 → 进图 → 暂停 → 回菜单

> **这是「完整成品」的第一段，也是最容易整段缺失的一段**：世界上没有一个完整游戏是"打开就直接站在游戏场景里"。
> 本范式给出「状态机（`Game.Fsm`）+ 面板（`Game.UI`）+ 场景（`Game.Scene`）」的编排写法；API 均以 `clover-client-unity-engine/Runtime/**` 为准。

---

## 0. 硬规则（违反任一条即交付失败）

| # | 规则 |
|---|---|
| 1 | **必须有启动链路**：启动画面 / Logo → 主菜单 → 创角（或选角）→ **读条** → 游戏场景。**禁止**应用一起来就直接进游戏场景 |
| 2 | **每个界面都要"能进能出"**：有入口、有返回路径（取消 / 返回 / ESC），**禁止单向死路** |
| 3 | **主菜单每一项都要真能用**：开始 / 继续 / 设置 / 退出（联机再加登录 / 注册）。不许摆一个点了没反应的按钮 |
| 4 | **创角 / 选角要真的通服务端**：建角 → 服务端回包 → 用**自己建的角色**进图（不许本地造一个假角色） |
| 5 | **读条要真读条**：走 `Game.Scene.Load(name, onProgress, onDone)`，进度真的在跳（不是黑屏、不是瞬间硬切、不是假进度条） |
| 6 | **游戏内流程要做**：暂停菜单（继续 / 设置 / 回主菜单 / 退出）；结算界面；**回主菜单后能再进一次**（第二次进入无残留状态） |
| 7 | **回菜单必须清场**：面板 / 实体 / 对象池 / 事件订阅 / 定时器 / 网络订阅全部收干净（见 §5），否则第二次进游戏是脏的 |
| 8 | **UI 场景与游戏场景分离**：主菜单 / 创角在**纯 UI 场景**里，进图时才加载游戏场景；**禁止**把主菜单塞进游戏场景 |
| 9 | 每条非预期分支都要打日志（`Game.Logger.Info/Warn/Error(tag, msg)`） |

> 参考游戏有**更细的站点**（选阵营 / 买枪 / 关卡选择 / 难度 / 存档槽 / 成就）时，**按原版加站点**，不要只做上面几个就交差 —— 站点清单以 `patterns/game-demo.md` §0.0c 的**原版系统清单**为准。

---

## 1. 流程骨架（先定这张表，再写代码）

```text
Boot(启动画面) → MainMenu(主菜单) → [Login/Register(联机)]
                                  → CharSelect(选角) / CharCreate(创角)
                                  → Loading(读条) → Stage(游戏场景)
                                                      ├─ Pause(暂停菜单) → Settings / MainMenu / Quit
                                                      └─ Result(结算)   → MainMenu / 再来一局
```

落到"状态机 + 面板 + 场景"三元组：

| 站点 | 状态机状态 | 面板（`Resources/UI/{类名}`） | Unity 场景 | 必做内容 |
|---|---|---|---|---|
| 启动画面 | `Boot` | `BootPanel` | `Boot` | Logo / 版权字 / 首次进入的"点击开始"；初始化（配置、热更、登录前置） |
| 主菜单 | `MainMenu` | `MainMenuPanel` | `Menu` | 开始（新游戏）/ 继续（有存档时）/ 设置 / 退出；联机时：登录 / 注册入口 |
| 设置 | `MainMenu`（子面板） | `SettingsPanel` | `Menu` | **真能改**：音量（`Game.Sound`）、画质（`Game.Quality`）、分辨率 / 全屏；改完能存（`Game.Setting`） |
| 登录 / 注册 | `Login` | `LoginPanel` / `RegisterPanel` | `Menu` | 账号服换 token → `EMsg.Login` → `SetupSession`；失败要有提示与重试 |
| 选角 | `CharSelect` | `CharSelectPanel` | `Menu` | 列出已有角色、选中、进入、删除（有二次确认弹窗） |
| 创角 | `CharCreate` | `CharCreatePanel` | `Menu` | 名字 / 外观 / 职业 / 属性预览 → 提交 → 服务端回包 → 进选角或直接进图 |
| 读条 | `Loading` | `LoadingPanel` | 切换中 | 真实进度 + 提示文案；**加载完成再关面板** |
| 游戏内 | `Stage` | `HudPanel`（+ 玩法面板） | `Stage01`（≥1 个游戏场景） | 见 `patterns/game-demo.md` 首场景全部内容 |
| 暂停 | `Pause` | `PausePanel` | `Stage01` | 继续 / 设置 / 回主菜单（二次确认）/ 退出 |
| 结算 | `Stage`（子面板） | `ResultPanel` | `Stage01` | 胜负 / 数值 / 再来一局 / 回主菜单 |

> **`Game.Scene` ≠ `Game.CloverScene`**：前者是 Unity 关卡（本文件讲的），后者是**服务端场景投影**（`EMsg.PushSceneInfo`）。

---

## 2. 分层落点（`reference/architecture.md` 的强制分层）

```text
client/Assets/Scripts/
├── Core/ClientConfig.cs        # 配置（地址/超时…）—— 见 patterns/client/config.md
├── Core/Events.cs              # ★ 流程事件名常量（唯一来源，禁止裸字符串）
├── Module/Flow/                # ★ 流程编排模块：AppFlow（唯对外门面 IAppFlow）
├── UI/Panels/                  # 各站点面板（只发/收事件，不引用 Module）
└── App/Bootstrap.cs            # 唯一组装点：Game.Launch + Init + Flow.Enter()
```

- **状态切谁的**：`Game.Fsm` 只标记"我在哪个站点"，**面板与场景的开关写在 Flow 模块里**（`RegisterState` 的 `onEnter/onExit`）；
- **UI 不许 `using Module`**：面板只 `Game.Event.Emit(Events.Xxx)` / `Game.UI.Close<T>()`，Flow 订阅后驱动；
- **网络调用只允许出现在 `Module/Flow`（登录 / 建角）与 `App`**，其它模块一律走门面；
- **事件名必须来自 `Core/Events.cs`**，禁止裸字符串。

---

## 3. 代码模板

### 模板 1：`Core/Events.cs`（流程事件名常量，唯一来源）

```csharp
namespace {Name}.Core
{
    /// <summary>流程/界面事件名常量。禁止在业务里写裸字符串。</summary>
    public static class Events
    {
        // 主菜单 → Flow
        public const string StartNewGame = "Flow.StartNewGame";
        public const string ContinueGame  = "Flow.ContinueGame";
        public const string OpenSettings  = "Flow.OpenSettings";
        public const string QuitGame      = "Flow.QuitGame";

        // 登录/创角/选角 → Flow
        public const string LoginSubmit   = "Flow.LoginSubmit";
        public const string CreateSubmit  = "Flow.CreateSubmit";   // 参数：CreateCharArgs
        public const string CharChosen    = "Flow.CharChosen";     // 参数：long playerID
        public const string CharDeleted   = "Flow.CharDeleted";

        // 游戏内 → Flow
        public const string PauseOpened   = "Flow.PauseOpened";
        public const string Resume        = "Flow.Resume";
        public const string BackToMain    = "Flow.BackToMain";
        public const string StageFinished = "Flow.StageFinished";  // 参数：ResultArgs
    }
}
```

### 模板 2：`Module/Flow/AppFlow.cs`（流程门面 + 状态机 + 场景/面板编排）

```csharp
using {Name}.Core;
using CloverEngine;
using UnityEngine;

namespace {Name}.Module.Flow
{
    public interface IAppFlow
    {
        void Enter();                        // Boot → MainMenu（应用起来后调它）
        string CurrentState { get; }
    }

    /// <summary>启动与菜单流程编排：状态机只标站点，面板与场景的开关都在这里。</summary>
    internal sealed class AppFlow : IAppFlow
    {
        private const string SceneBoot   = "Boot";
        private const string SceneMenu   = "Menu";
        private const string SceneStage1 = "Stage01";

        public string CurrentState => Game.Fsm.Current;

        public void Enter()
        {
            RegisterStates();
            Game.Event.Emit(Events.StartNewGame);   // 或先停在主菜单，等玩家点"开始"
            Game.Fsm.Force("Boot");
            Game.Fsm.Trigger("BootDone");           // → MainMenu
        }

        private void RegisterStates()
        {
            // 站点：引擎在 Launch 时已预注册 Launching/CheckingUpdate/Logging/MainCity/Battle/Disconnected，
            // 运行时不自动驱动，业务可同名覆盖或另起状态名。这里用业务自己的站点名，避免与引擎语义打架。
            // ⛔ Game.Fsm **全局唯一**（见 patterns/client/fsm.md 文首）：这些流程状态与其它模块
            //    共用同一张状态表和一个 Current。业务**只在这一处注册流程状态**，
            //    ⛔ 不许再让角色 / UI / 动画模块往同一个 Game.Fsm 里塞状态（会互相跑掉 OnExit/OnEnter）。
            Game.Fsm.RegisterState("Boot",     onEnter: () => ShowBoot(),     onExit: () => Game.UI.Close<BootPanel>());
            Game.Fsm.RegisterState("MainMenu", onEnter: () => ShowMainMenu(), onExit: () => Game.UI.Close<MainMenuPanel>());
            Game.Fsm.RegisterState("Login",    onEnter: () => Game.UI.Open<LoginPanel>());
            Game.Fsm.RegisterState("CharSelect", onEnter: () => EnterCharSelect());
            Game.Fsm.RegisterState("CharCreate", onEnter: () => Game.UI.Open<CharCreatePanel>());
            Game.Fsm.RegisterState("Loading",  onEnter: () => { /* 由 GoStage 打开 LoadingPanel */ });
            Game.Fsm.RegisterState("Stage",    onEnter: () => { }, onExit: () => LeaveStage());
            Game.Fsm.RegisterState("Pause",    onEnter: () => Game.UI.Open<PausePanel>(), onExit: () => Game.UI.Close<PausePanel>());

            Game.Fsm.AddTransition("BootDone",   "MainMenu");
            Game.Fsm.AddTransition("NeedLogin",  "Login");
            Game.Fsm.AddTransition("LoggedIn",   "CharSelect");
            Game.Fsm.AddTransition("NeedCreate", "CharCreate");
            Game.Fsm.AddTransition("EnterStage", "Loading");
            Game.Fsm.AddTransition("StageReady", "Stage");
            Game.Fsm.AddTransition("Pause",      "Pause");
            Game.Fsm.AddTransition("Resume",     "Stage");
            Game.Fsm.AddTransition("ToMain",     "MainMenu");

            // UI 只发事件，Flow 负责驱动（UI 不引用 Module，保持单向依赖）
            Game.Event.On(Events.OpenSettings, () => Game.UI.Open<SettingsPanel>());
            Game.Event.On(Events.PauseOpened,  () => Game.Fsm.Trigger("Pause"));
            Game.Event.On(Events.Resume,       () => Game.Fsm.Trigger("Resume"));
            Game.Event.On(Events.BackToMain,   () => GoMainMenu());
            Game.Event.On(Events.QuitGame,     QuitGame);
        }

        private void ShowBoot() => EnsureMenuScene(() => Game.UI.Open<BootPanel>());

        private void ShowMainMenu()
        {
            // 主菜单是纯 UI 场景：从舞台退回时要先把游戏场景卸掉（见 LeaveStage）
            EnsureMenuScene(() => Game.UI.Open<MainMenuPanel>());
        }

        private void EnterCharSelect()
        {
            EnsureMenuScene(() => Game.UI.Open<CharSelectPanel>());
        }

        /// <summary>菜单类站点统一在 Menu 场景里；已在则不重复加载。</summary>
        private void EnsureMenuScene(System.Action onReady)
        {
            if (Game.Scene.CurrentScene == SceneMenu) { onReady(); return; }
            Game.Scene.Load(SceneMenu, null, () =>
            {
                Game.Logger.Info("Flow", $"menu scene loaded: {SceneMenu}");
                onReady();
            });
        }

        /// <summary>进图：先读条，场景真的加载完了再切状态。</summary>
        public void GoStage()
        {
            Game.Fsm.Trigger("EnterStage");
            Game.UI.Open<LoadingPanel>();
            Game.Scene.Load(SceneStage1, p =>
            {
                var panel = Game.UI.Get<LoadingPanel>();
                if (panel != null) panel.SetProgress(p);
            }, () =>
            {
                Game.UI.Close<LoadingPanel>();
                Game.Fsm.Trigger("StageReady");
                Game.Logger.Info("Flow", $"enter stage: {SceneStage1}");
            });
        }

        /// <summary>离开舞台：把游戏侧的东西全部收干净，否则第二次进图是脏的（见 §5）。</summary>
        private void LeaveStage()
        {
            Game.UI.CloseAll();
            Game.Entity.ClearAll();
            Game.Pool.ClearAll();
            Game.Timer.StopScope("stage");
            Game.Sync.Clear();
            // 事件注销要传**同一个方法引用**（没有句柄）：Flow 长驻，订阅一律用具名私有方法，
            // 不要用匿名 lambda，否则 Off 不掉（见 §7）。例：Game.Event.Off(Events.PauseOpened, OnPauseOpened);
            Game.Sound.StopAll();
        }

        private void GoMainMenu()
        {
            Game.Fsm.Trigger("ToMain");
            Game.Scene.Unload(SceneStage1, () => Game.Logger.Info("Flow", "stage unloaded"));
        }

        private void QuitGame()
        {
#if UNITY_EDITOR
            UnityEditor.EditorApplication.isPlaying = false;
#else
            Application.Quit();
#endif
        }
    }
}
```

> `Game.Event.On/Off` **没有句柄**（返回 `void`），注销必须用**同一个方法引用**（或按需一次性清）。写成匿名 lambda 就 `Off` 不掉 —— 长驻的 Flow 模块请用具名私有方法。

### 模板 3：`App/Bootstrap.cs`（唯一组装点，≤200 行）

```csharp
using {Name}.Core;
using {Name}.Module.Flow;
using CloverEngine;
using UnityEngine;

namespace {Name}.App
{
    /// <summary>唯一入口：只做「启动引擎 + 挂模块 + 进流程」，不写业务逻辑。</summary>
    public class Bootstrap : MonoBehaviour
    {
        private IAppFlow _flow;

        private void Start()
        {
            // 1) 启动引擎（配置一律走 Cfg，禁止硬编码地址/账号/超时）
            Game.Launch(new GameConfig
            {
                ServerAddr = Cfg.Server.addr,
                CallTimeoutSeconds = Cfg.Server.call_timeout,
                MaxReconnectCount = Cfg.Server.max_reconnect_count,
                UseTls = Cfg.Server.tls,
            });

            // 2) 资源 / 配表（可选模块，漏了 Game.Res 恒为 null）
            //    Init 的参数是 Resources 内的相对前缀（不是磁盘路径）；空串 = 以 Resources 根为根
            CloverRes.Init("");
            // CloverData.InitDataTable("Table");

            // 3) 输入 + EventSystem：有 UI / 键鼠就必须有，且必须在建 UI 之前
            CloverInput.Init();

            // 4) 联机项目：连网关（单机项目整段不要）
            CloverNet.Init(Cfg.Server.addr,
                string.IsNullOrEmpty(Cfg.Server.udp_addr) ? null : Cfg.Server.udp_addr);

            // 5) 装配 + 进流程（菜单链路从这里开始，不许直接进游戏场景）
            _flow = new AppFlow();
            _flow.Enter();
            Game.Logger.Info("App", $"app flow entered: {_flow.CurrentState}");

            // 6) 网络生命周期：断了要回登录/主菜单，而不是停在游戏里假装没事
            //    Net.OnKicked 为无参发布 → 处理器必须零参
            // ⛔ 事件名取引擎常量，⛔ 不许裸字符串（交付前 grep 自查会抓这一处）
            Game.Event.On(CloverEvents.Net.OnKicked, () =>
            {
                Game.Logger.Warn("App", "被踢出，回主菜单");
                Game.UI.CloseAll();
                Game.Fsm.Force("MainMenu");
            });
        }
    }
}
```

### 模板 4：主菜单面板（UI 只发事件，不引用 Module）

```csharp
using {Name}.Core;
using CloverEngine;
using UnityEngine;
using UnityEngine.UI;

namespace {Name}.UI
{
    public class MainMenuPanel : UIPanel
    {
        [SerializeField] private Button _startButton;
        [SerializeField] private Button _continueButton;
        [SerializeField] private Button _settingsButton;
        [SerializeField] private Button _quitButton;

        public override void OnOpen(object param)
        {
            Bind(_startButton, Events.StartNewGame);
            Bind(_settingsButton, Events.OpenSettings);
            Bind(_quitButton, Events.QuitGame);

            // 「继续」只在有存档/有角色时可用（真判断，不是摆设）
            var hasSave = Game.Setting.Get("flow.has_save", false);
            _continueButton.interactable = hasSave;
            Bind(_continueButton, Events.ContinueGame);
        }

        private static void Bind(Button b, string evt)
        {
            if (b == null)
            {
                Game.Logger.Error("UI", $"MainMenuPanel 缺少按钮引用，事件 {evt} 未绑定");
                return;
            }
            b.onClick.RemoveAllListeners();
            b.onClick.AddListener(() => Game.Event.Emit(evt));
        }
    }
}
```

### 模板 5：创角面板（提交 → 服务端回包 → 进图）

```csharp
using {Name}.Core;
using {Name}.Def;
using CloverEngine;
using UnityEngine;
using UnityEngine.UI;

namespace {Name}.UI
{
    public class CharCreatePanel : UIPanel
    {
        [SerializeField] private InputField _nameInput;
        [SerializeField] private Button _confirmButton;
        [SerializeField] private Button _backButton;

        public override void OnOpen(object param)
        {
            _confirmButton.onClick.RemoveAllListeners();
            _confirmButton.onClick.AddListener(OnConfirm);
            _backButton.onClick.RemoveAllListeners();
            _backButton.onClick.AddListener(() => Game.Fsm.Force("MainMenu"));
        }

        private async void OnConfirm()
        {
            var name = _nameInput.text;
            if (string.IsNullOrEmpty(name))
            {
                Game.Logger.Warn("UI", "创角失败：名字为空");
                return;
            }

            try
            {
                var reply = await Game.Net.Call<CreatePlayerReply>(MsgDef.CreatePlayer, new CreatePlayerRequest
                {
                    name = name,          // ★ 字段名与服务端 json tag 对齐（snake_case）
                });
                if (!reply.ok)
                {
                    Game.Logger.Warn("UI", $"创角被拒: {reply.err}");
                    return;
                }
                Game.Logger.Info("UI", $"创角成功: player={reply.player_id}");
                Game.Event.Emit(Events.CharChosen, reply.player_id);
            }
            catch (CloverCallException ex)
            {
                Game.Logger.Error("UI", $"创角业务错误: {ex.ServerError}");
            }
            catch (System.TimeoutException)
            {
                Game.Logger.Error("UI", "创角超时");
            }
        }
    }
}
```

> 消息号 / 协议**只能**来自 `Def/MsgDef.cs` 与 `Def/ProtoDef.cs`（`patterns/client/network.md` 模板 0），**禁止**在这里写裸字面量。

### 模板 6：读条面板（`Game.Scene.Load` 的进度直接驱动）

```csharp
using CloverEngine;
using UnityEngine;
using UnityEngine.UI;

namespace {Name}.UI
{
    public class LoadingPanel : UIPanel
    {
        [SerializeField] private Image _bar;        // ★ Image.Type = Filled + 有效 sprite，否则 fillAmount 静默失效
        [SerializeField] private Text _tipText;

        public override UILayer Layer => UILayer.System;   // 读条要盖住一切

        public override void OnOpen(object param) => SetProgress(0f);

        public void SetProgress(float p)
        {
            if (_bar == null)
            {
                Game.Logger.Error("UI", "LoadingPanel 缺少进度条引用");
                return;
            }
            _bar.fillAmount = Mathf.Clamp01(p);
        }
    }
}
```

> 进度条的经典静默失效：`Image.Type = Filled` 但 **sprite 为空** ⇒ `fillAmount` 完全无效、看着像"永远不动"。交付前**看一眼图**确认它在动（`reference/design-review.md` §3.4）。

---

## 4. 场景划分建议

| 场景 | 内容 | 说明 |
|---|---|---|
| `Boot` | 启动画面（Logo / 版权 / 点击开始） | 最轻，先加载；初始化与热更放这里 |
| `Menu` | 主菜单 / 登录 / 注册 / 设置 / 选角 / 创角 | **纯 UI 场景**（无角色、无战斗）；全部靠面板切换，不切场景 |
| `Stage01` | 游戏场景（首关卡） | 首次进图才加载；卸载后回 `Menu` |

- **一个场景能放多少面板**：同一套"菜单类站点"共用一个 UI 场景（`Menu`），靠 `Game.UI.Open/Close` 切面板 —— **不要每个面板一个 Unity 场景**，否则切界面要等读条，很假；
- 场景必须**在 Build Settings 里**（`unity command` 或 Editor 脚本加），漏了在打包 / Play 时直接加载失败；
- 场景名与 `Game.Scene.Load(name)` 的字符串要对齐（**收敛成一个常量类**，禁止散落字符串）。

---

## 5. 回菜单 / 重进游戏的清场清单（第二次进图必须是干净的）

| 要清的 | 用哪个 API |
|---|---|
| 面板 | `Game.UI.CloseAll()`（或逐个 `Close<T>()`） |
| 实体与视图 | `Game.Entity.ClearAll()`（或 `DestroyGroup(group)`） |
| 对象池 | `Game.Pool.ClearAll()`（或 `ClearGroup(group)`） |
| 定时器 | `Game.Timer.StopScope("stage")`（舞台内的定时器统一打 scope） |
| 世界同步订阅 | `Game.Sync.Clear()` |
| 流程 / 网络事件 | `Game.Event.Off(Events.X, method)`（**同一方法引用**） |
| 消息监听 | `Game.OffMsg(msgID, handler)`（或 `Game.OffMsg(msgID)` 清该消息号） |
| 音效 / BGM | `Game.Sound.StopBGM()` / `Game.Sound.StopAll()` |

> **自证方法**：连续"主菜单 → 进图 → 回主菜单 → 再进图"两次，第二次截图 + 抄一遍上面的计数（实体数 / 池活跃数 / 面板数）应当与第一次一致 —— **不涨就是干净的**。

---

## 6. 交付前自查清单（**需要时才逐项过**；⛔ 默认不跑）

```text
□ 打开应用（Play）后先进「启动画面 / 主菜单」，不直接落到游戏场景
□ 主菜单 4 项（开始 / 继续 / 设置 / 退出）逐个点过；联机版另有登录 / 注册，也逐个点过
□ 设置面板真能改音量 / 画质，并且重进后设置还在（Game.Setting）
□ 创角：空名字、重名、超时、服务端拒绝 —— 四种失败都有提示与日志
□ 选角：能选中、能删除（有二次确认）、能返回
□ 读条：进度条真的在动（截图两张不同进度），加载完才关面板
□ 游戏内：暂停菜单能开、能继续、能回主菜单（有二次确认）
□ 连续「回主菜单 → 再进图」两次，第二次画面与计数与第一次一致（§5 清场清单过了一遍）
□ `表现类` 的界面**自己都看过截图**（启动 / 主菜单 / 创角 / 读条 / 游戏内 / 暂停 / 结算）；
  `数值类` 只留日志行（`SKILL.md` §4 第 4 条）
□ ★ **与参考游戏的同角度截图逐项对照，全部"一致"**（`reference/design-review.md` §3.6）——
   **有任何一项不一致 = 不可交付**；**没有参考游戏名就先问用户要**
□ 全工程 grep：无裸事件名（`Game.Event.On("` 命中 0）、UI 无 `using {Name}.Module`（命中 0）
```

grep 命令见 `reference/architecture.md` §4（②③④⑤ 允许为 0 命中）。

---

## 7. 常见坑

| 现象 | 真因 | 正确做法 |
|---|---|---|
| 点不动任何按钮 | `EventSystem` 没建（输入模块未挂） | `Game.Launch` 后调 `CloverInput.Init()`，且在建 UI 之前 |
| 面板打开是空白 / 报"找不到预制体" | 预制体没放在 `Resources/UI/{类名}` | 预制体名必须 = 面板类名（`UIPanel.PanelName` 默认取类名）；由 AI 用 Editor 脚本生成 |
| 第二次进图怪物翻倍 / 血条错乱 | 上次退出没清实体与订阅 | 走 §5 清场清单 |
| 切界面卡黑屏 | 每个界面都切 Unity 场景 | 菜单类站点共用一个 UI 场景，只切面板 |
| 读条条永不动 | `Image.Type=Filled` 但 sprite 为空 | 给足 sprite，或改用 `RectTransform` 宽度；交付前**看图** |
| 暂停后角色还在被打 | 联机对战**不能真暂停**（原版也是） | 单人关卡才做真暂停（服务端暂停消息）；对战只做"菜单覆盖 + 可选投降" |
| 断线后停在游戏里 | 没监听网络生命周期 | 监听 `Net.OnDisconnected/OnResumed/OnKicked`，被踢 → 回主菜单 / 登录 |

---

## 8. 与其他文档的关系

- **首场景内容**（操作 / 相机 / 动画 / 战斗 / UI / 音效）→ `patterns/game-demo.md`、`reference/rules-full.md` 的「两件绝不打折的事」；
- **原版系统清单**（菜单 / 创角 / 技能 / 背包 / NPC…逐个做完）→ `patterns/game-demo.md` §0.0c；
- **感官验收**（`表现类` 截一张自己看；`数值类` 只留日志行）→ `reference/design-review.md` §3 与 `reference/visual-loop.md` 第八节；
- **分层与自检**（UI 不引 Module、App ≤ 200 行）→ `reference/architecture.md`；
- **复杂项目拆多 agent**（菜单链路与首场景可并行）→ `patterns/multi-agent.md`；
- **本页 §9 是 cs16 的实测骨架**（单机版站点清单 / `Enter`·`Exit` 配对 / 面板与流程的边界 / 坑清单）。

---

## 9. cs16 实测骨架（单机版；2026-09-24 回读源码上浮）

> §1~§7 是**范式**（含联机站点：登录 / 创角 / 选角）。本节是**单机版**的**实测骨架** —— 站点清单、`Enter`/`Exit` 配对、面板与流程的边界、以及每个坑的出处。
> 出处（`文件:行`）一律来自用户点名的被上浮项目 `clover-project-cs16`，路径相对工作区根；凡本节出现的断言，§9.7 的锚点表里都有一行可回读。⛔ 本节不许有"大概 / 通常"的措辞。
> 本文引用的 cs16 符号族在 §9.8 声明；执行顺序（输入 `-200` → 模拟 `0` → 表现 `LateUpdate`）另见 `patterns/client/execution-order.md`。

### 9.1 站点清单与 `Enter`/`Exit` 配对（9 个站点）

`AppFlow.RegisterStates()`（`AppFlow.cs:120-128`）一次注册 9 个站点，**每个站点就是一个 FSM 状态**：

| # | 站点 | `onEnter`（进入职责） | `onTick`（轮询职责） | `onExit`（退出职责） |
|---|---|---|---|---|
| 1 | `Boot` | 开 `BootPanel`（`AppFlow.cs:173`） | — | 关 `BootPanel`（`:179`） |
| 2 | `MainMenu` | 进 Menu 纯 UI 场景（`:184` → `EnterMenuScene`） | — | 关 `MainMenuPanel`（`:189`） |
| 3 | `ServerList` | 开 `ServerListPanel`（`:315`） | 面板被关 ⇒ 回 `MainMenu`（`:323`） | 关 `ServerListPanel`（`:328`） |
| 4 | `NewGame` | 开 `NewGamePanel`（`:333`） | 面板被关 ⇒ 回 `MainMenu`（`:340`） | 关 `NewGamePanel`（`:345`） |
| 5 | `Options` | 开 `OptionsPanel`（`:350`） | 面板被关 ⇒ 回 `Pause` / `MainMenu`（`:358`） | 关 `OptionsPanel`（`:363`） |
| 6 | `Loading` | 开 `LoadingPanel`（`:416`） | — | 关 `LoadingPanel`（`:422`） |
| 7 | `TeamSelect` | 开 `TeamSelectPanel`（`:507`） | 面板被取消 ⇒ 回 `MainMenu`（`:515`） | 关 `TeamSelectPanel`（`:520`） |
| 8 | `Stage` | `_match.Start(_pending)` + 开 `HudPanel`（`:548`、`:553`） | ESC 请求暂停（`:560`） | **无**（`null`，见下） |
| 9 | `Pause` | 开 `PausePanel`（`:565`） | ESC 恢复（`:570`） | 关 `PausePanel`（`:575`） |

与范式的差异（照抄时别照错）：**单机版没有登录 / 创角 / 选角，多了 `ServerList` / `NewGame` / `TeamSelect` 三个"配置类"站点**；`ServerList` 在单机版是"服务器列表"占位站点（原版菜单项），面板被关即退站。站点清单以**原版系统清单**为准（`patterns/game-demo.md` §0.0c），不是以本表为准。

**三条配套约定（漏了就会踩坑）**：

1. **允许一个站点没有 `onExit`，但必须说得出为什么**：`Stage` 的 `onExit` 是 `null`（`AppFlow.cs:127`），因为 `HudPanel` 要**跨站点常驻**（`Stage → Pause → Stage` 都开着）—— 这不是漏写，而是与"`OnEnterPause` 只开 `PausePanel`"配套的设计。
2. **`onExit` 只许关"本站点开的"**：`OnExitServerList` 只关 `ServerListPanel`，不负责关 `MainMenuPanel`（那是 `MainMenu` 站点的事）⇒ **每个面板恰好一个"主人站点"**。
3. **面板自己关自己，站点在 `onTick` 里发现并退站**：`Back` 按钮不发"切站点事件"，只 `Game.UI.Close<T>()`；`OnTickServerList` 发现"面板不在了" ⇒ `Game.Fsm.Transition(State.MainMenu)`（`AppFlow.cs:319-324`）。⇒ 面板与流程**不同时**持有"下一步去哪"的判断。

### 9.2 面板与流程的边界（写码前先背下来）

| 谁 | 能做什么 | ⛔ 不许做什么 | 出处 |
|---|---|---|---|
| 面板 | 显示；按钮 → `Game.Event.Emit(Events.X)`；关自己 | 切 FSM、开别人的面板、`using Module` | `AppFlow.cs:15`、`IAppFlow.cs:14` |
| 流程 `AppFlow` | 订阅 `Events.*` → 驱动 `Game.Fsm`；开/关面板与场景 | 写比赛状态（那是 `ICsMatch` 的事） | `AppFlow.cs:14`、`AppFlow.cs:23-24` |
| 局内 UI `HudPanel` | 自己开/关局内子面板（买枪 / H 菜单 / 无线电 / 控制台 / 记分板） | 被 Flow 逐帧管 | `HudPanel.cs:1019` |

- 一句话口径（原注释）：**"状态机只标'我在哪个站点'，面板与场景的开关全部写在这里"**（`AppFlow.cs:14`）。
- **依赖方向**：`App → Module → Core`；`App` 构造 `AppFlow` 并注入门面，`AppFlow` 不反向找 `App`（`IAppFlow.cs:14`）。
- **ESC 归谁**（必踩）：`Stage` 的 `OnTickStage` 先问 `HasBlockingOverlay()` —— **除常驻 HUD 外还有面板开着 = 有遮挡**，ESC 归那些面板；无遮挡才弹暂停菜单（`AppFlow.cs:558-560`、`:824-831`）。
- **场景策略**："菜单类站点共用一个纯 UI 场景 `Menu`（切面板不切场景）；只有进图时单加载 `StageDust2`，回主菜单先卸舞台再加载 `Menu`"（`AppFlow.cs:17-18`）。⇒ 菜单站点**不重载场景**（`EnterMenuScene` 里"已在 Menu 就直接回调"，`:207-211`）。
- ⚠️ **启动场景不在引擎登记里**：`Boot` 场景由 Build Settings 的**第 0 个场景**进来（`EditorBuildSettings.asset:9`），而 `Game.Scene.CurrentScene` **只**在 `Load` 完成时赋值（`clover-client-unity-engine/Runtime/Presentation/Scene.cs:76`）⇒ 启动时它是 `null`。因此"已在 Menu 就不加载"的判断必须容忍 `null`，否则第一次进主菜单会**不加载 Menu 场景**（cs16 的判断顺序即 `== Menu` → `== StageDust2` → 否则 `LoadMenuScene()`，`AppFlow.cs:206-224`）。

### 9.3 启动序（`Bootstrap`；顺序错了就是"点不动 / 找不到预制体"）

`Bootstrap.cs:20-26` 写死了四步硬要求：

1. `Game.Launch(new GameConfig { LogDir, ResourceRoot })`（`Bootstrap.cs:85`）—— 核心子系统 + 表现域模块自动挂载；
2. `CloverRes.Init("")`（`:92`）→ `CloverInput.Init()`（`:93`）—— **输入必须早于建 UI**（它顺便把 `EventSystem` 建好）；
3. 玩家设置（`CsPlayerSettingsStore.Load()` `:99`）→ 装配兄弟模块并注入门面（`:109-121`）；
4. `AppFlow.Enter()`（`:131`）—— 启动画面 → 主菜单，**⛔ 不许直接进游戏场景**。

七条实测补充（每条都有出处，照抄时对照）：

| 补充 | 为什么（原文摘要 + 出处） |
|---|---|
| `Awake` 里 `Game.ConfigureHost(...RunInBackground = true...)` | 编辑器窗口失焦时也要跑帧；**必须在 `Game.Launch` 之前**（`Bootstrap.cs:54-59`） |
| ⛔ 刻意**不开** `OwnAudioListener` | 那会让 3D 空间音效按宿主位置（原点）算距离衰减 —— CS 的脚步 / 枪声远近是玩法判据（`Bootstrap.cs:56-58`） |
| `DontDestroyOnLoad(gameObject)`（`Bootstrap.cs:76`） | 菜单 / 舞台之间会**切场景**且是单加载，不常驻则模块全被销毁（`Bootstrap.cs:74-76`） |
| 单实例守卫用**静态引用**，不用场景搜索 | 切场景时"找到几个"不可靠，静态引用是确定的（`Bootstrap.cs:61-64`） |
| `CloverRes.Init` 的参数是 **Resources 子目录前缀**，不是 Assets 路径 | 传 `"Assets/Resources"` 会让资源模块去 AppData 找热更目录 ⇒ **所有资源静默加载失败**（`Bootstrap.cs:36-42`） |
| 场景加载完成回调里**收掉场景自带的重复 `EventSystem`** | 引擎的 `EventSystem` 是常驻唯一实例（`Bootstrap.cs:136-187`） |
| "**挂载顺序**" ≠ "**Update 顺序**" | 先挂地图模块再挂比赛模块，解决的是 `MatchModule.Awake` 找 `ICsMap`（`Bootstrap.cs:107-108`）；谁先 `Update` 由 `[DefaultExecutionOrder]` 决定 → `patterns/client/execution-order.md` |

### 9.4 "缺一个状态 / 漏一次 Exit" 会被哪个断言抓到

做法：**把"每个流程态该看到哪些面板"列成一张小表**（16 流程态 × 16 面板），运行时 dump 节点树的 `activeInHierarchy`，两边一比就对上了 —— 期望表每行都写清**依据在哪**（源码 `文件:行`）。⛔ 不必写成常驻脚本 / 对账矩阵（那是一代验收机器，已废）：**改完流程时跑一次探针看一眼**就够。

| 你漏了什么 | 谁抓到 | 转红的话术 |
|---|---|---|
| 删掉一个 `RegisterState(...)` 行 | 引擎侧：`Transition` 到未注册状态**被忽略**且留痕；判据侧：采样那帧 `fsm` 不等于站点名 ⇒ 整个 dump 判「未采到」（`:186-188`），该站点期望的面板**永远拿不到证据** | `state X: no dump matched` |
| 站点开了面板却没配 `onExit`（`Stage/HudPanel` 之外的） | 下一站点的 dump 里该面板 `active=True` ⇒ **「不该显示却显示」**（`:210`） | `visible-but-unexpected` |
| 站点配了 `onExit` 却没在 `onEnter` 开面板 | 该站点 dump 里 `instances=0` ⇒ **「该显示却没显示(未实例化)」**（`:201-203`） | `expected-but-hidden` |
| 面板的 `Open<T>()` 调用**挪了行 / 改了写法** | 锚点回读失败 ⇒ 直接 FAIL（`:158-163`），⛔ 而不是"偷偷用错的期望表" | `ANCHOR CHECK FAILED` |
| 加了新站点但没加进 `FSM_STATES`（`:76-77`） | ⛔ **没人抓**（脚本只认它自己那份清单） | 见下 |

> **最后一行才是"缺一个状态"的真正判据**：`AppFlow.cs:41-49` 的 `State.*` 常量集必须与 `check-ui-flow-matrix.py:76-77` 的 `FSM_STATES` **双向相等**。cs16 现状 = 9 个，两边一致；只改一边就等于"新站点无人校验"。本片自检脚本 `.ai-tmp/test/sink4-up-appflow-selfcheck.ps1` 的 D 段就是做这个双向比对（外加"有 `Open` 无 `Close` 的站点必须在白名单里"）。

### 9.5 回主菜单的清场清单（漏一项，第二次进图就是脏的）

`ClearStage()`（`AppFlow.cs:595-625`）—— 原注释口径：**"清场清单：漏一项第二次进图就是脏的"**（`:594`）：

```text
比赛        _match.Stop()             仅当 IsRunning（否则记一行"跳过"，不静默）
UI          Game.UI.CloseAll()
实体        Game.Entity.ClearAll()
对象池      Game.Pool.ClearAll()
舞台定时器  Game.Timer.StopScope("stage")     ← 舞台内定时器统一打 scope 名 "stage"（AppFlow.cs:27）
音效        Game.Sound.StopAll()
HUD 快照    CsHudSnapshot.Reset()            ← 静态的；不清会在"快速进入 Play"下跨局残留（AppFlow.cs:614-615）
流程字段    _pending / _stageSceneReady / _stageMapReady / _stageBegun 全部复位（AppFlow.cs:617-620）
```

- 有 `Game.Sync != null` 时**打 Warn 不静默**：单机版不该有 `WorldSync`（`AppFlow.cs:622-624`）。
- **可反复进出**：`GoMainMenu()` 自带幂等 —— 已在主菜单且面板开着 ⇒ 忽略（`AppFlow.cs:584-588`）。
- 与执行顺序的分工：清场解"**跨局脏**"，`[DefaultExecutionOrder]` 解"**同帧脏**"，两个都要。

### 9.6 cs16 坑清单（每条都有出处，⛔ 不许凭想象加）

| 坑 | 真因（原文摘要） | 出处 |
|---|---|---|
| 玩家被**永久钉在读条屏** | 场景不在 Build Settings / 未生成时引擎打 Error 且**不会回调 `onDone`** ⇒ 必须有超时兜底（20s → Toast + 回主菜单） | `AppFlow.cs:395-398`、`:36`、`:402-411` |
| 进图后**空场景且没有主菜单** | 引擎场景卸载在极端情况下**只告警不回调** ⇒ 卸舞台后必须挂一个 `AfterUnscaled` 兜底（1.5s） | `AppFlow.cs:218-220`、`:33`、`:243-260` |
| 进度条走完但图跑不起来 | 场景与地图是**两条异步链**：只有 `_stageSceneReady && _stageMapReady` 才收尾 | `AppFlow.cs:490-503` |
| 进度条永远到不了 100% | 引擎给的是 Unity 的 `op.progress`，在 `allowSceneActivation` 前**封顶 0.9** ⇒ 必须归一化除以 0.9 | `AppFlow.cs:29-30`、`:434-435` |
| 重进 / 从暂停恢复时**回合被清掉** | `Stage` 每次进入都开 HUD；从暂停恢复**不能再 `Start` 一次** ⇒ 用 `_stageBegun` 挡 | `AppFlow.cs:533-537` |
| 比赛在读条之前**就开局了** | `MatchModule` 自己也订阅 `Events.LaunchMatch` 并就地 `Start`（那时地图 / 场景还没就绪）⇒ `AppFlow` 在就绪后**重开一次**（`Start` 契约 = 重复调用先 Stop 再 Start）拿干净开局 | `AppFlow.cs:542-547` |
| 进 `Options` 顺手**解除了暂停** | "暂停族" = `Pause` 站点 **+ 从暂停进来的 `Options`**；只有真正进出暂停族才 `SetPaused` | `AppFlow.cs:141-142`、`:803-809` |
| 同一帧 ESC 被**两处**识别 ⇒ 刷屏 | `OnRequestPause` / `OnResumeRequested` 对"已经在目标站点"**幂等忽略** | `AppFlow.cs:732-736`、`:752` |
| `Game.Event.Off` **注销不掉** | 没有句柄，必须传**同一方法引用** ⇒ 长驻的 `AppFlow` 一律用具名私有方法，⛔ 不写匿名 lambda | `AppFlow.cs:145-148` |
| 主菜单启动曲**每回一次菜单都重播** | 原版口径：整个进程**首次**主菜单播一次，开始连接地图后停，回菜单不重播 ⇒ `_startupMusicPlayed` 去重 | `AppFlow.cs:270-275`、`:281-284`、`:298-301` |
| 单机版收到 `Disconnect` | 单机没有网络连接，`Game.Net == null` 是**正常状态** ⇒ `Disconnect` 语义退化为"回主菜单"（⛔ 不许静默留在游戏里） | `AppFlow.cs:770-775`、`Bootstrap.cs:28-29` |

### 9.7 cs16 锚点表

> 格式与校验方式同 `patterns/client/execution-order.md` §5：`| 符号 | 域 | 出处 | 该行必须出现的原文 |`；校验 = 回读该 `文件:行`（断言含原文）+ 符号能在对应源码树里 grep 到。
> 自查：抽查一行**不存在的符号名** ⇒ 检查必须转红并点名该行（转不了红 ⇒ 这条检查等于没做）。

| 符号 | 域 | 出处 | 该行必须出现的原文 |
|---|---|---|---|
| `IAppFlow` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/IAppFlow.cs:16` | `public interface IAppFlow` |
| `AppFlow` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:22` | `public sealed class AppFlow : IAppFlow` |
| `State.Boot` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:41` | `public const string Boot = "Boot";` |
| `State.MainMenu` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:42` | `public const string MainMenu = "MainMenu";` |
| `State.ServerList` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:43` | `public const string ServerList = "ServerList";` |
| `State.NewGame` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:44` | `public const string NewGame = "NewGame";` |
| `State.Options` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:45` | `public const string Options = "Options";` |
| `State.TeamSelect` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:46` | `public const string TeamSelect = "TeamSelect";` |
| `State.Loading` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:47` | `public const string Loading = "Loading";` |
| `State.Stage` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:48` | `public const string Stage = "Stage";` |
| `State.Pause` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:49` | `public const string Pause = "Pause";` |
| `Trigger.BootDone` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:55` | `public const string BootDone = "BootDone";` |
| `Trigger.ToMain` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:64` | `public const string ToMain = "ToMain";` |
| `RegisterState` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:120` | `Game.Fsm.RegisterState(State.Boot, OnEnterBoot, null, OnExitBoot);` |
| `AddTransition` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:130` | `Game.Fsm.AddTransition(Trigger.BootDone, State.MainMenu);` |
| `Game.Fsm.OnChange` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:142` | `Game.Fsm.OnChange(OnFsmChanged);` |
| `OnEnterBoot` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:171` | `private void OnEnterBoot()` |
| `OnExitBoot` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:177` | `private void OnExitBoot()` |
| `OnEnterMainMenu` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:182` | `private void OnEnterMainMenu()` |
| `OnExitMainMenu` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:187` | `private void OnExitMainMenu()` |
| `EnterMenuScene` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:196` | `private void EnterMenuScene()` |
| `OnStageUnloaded` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:227` | `private void OnStageUnloaded()` |
| `LoadMenuScene` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:233` | `private void LoadMenuScene()` |
| `OnMenuFallback` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:243` | `private void OnMenuFallback()` |
| `OnMenuSceneReady` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:262` | `private void OnMenuSceneReady()` |
| `PlayStartupMusicOnce` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:281` | `private void PlayStartupMusicOnce()` |
| `StopStartupMusic` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:302` | `private void StopStartupMusic()` |
| `OnEnterServerList` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:313` | `private void OnEnterServerList()` |
| `OnTickServerList` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:319` | `private void OnTickServerList(float dt)` |
| `OnExitServerList` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:326` | `private void OnExitServerList()` |
| `OnEnterNewGame` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:331` | `private void OnEnterNewGame()` |
| `OnTickNewGame` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:336` | `private void OnTickNewGame(float dt)` |
| `OnExitNewGame` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:343` | `private void OnExitNewGame()` |
| `OnEnterOptions` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:348` | `private void OnEnterOptions()` |
| `OnTickOptions` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:353` | `private void OnTickOptions(float dt)` |
| `OnExitOptions` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:361` | `private void OnExitOptions()` |
| `GoStage` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:368` | `public void GoStage(CsMatchConfig cfg)` |
| `OnStageLoadTimeout` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:402` | `private void OnStageLoadTimeout()` |
| `OnEnterLoading` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:413` | `private void OnEnterLoading()` |
| `OnExitLoading` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:420` | `private void OnExitLoading()` |
| `OnStageLoadProgress` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:425` | `private void OnStageLoadProgress(float progress)` |
| `OnStageSceneLoaded` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:438` | `private void OnStageSceneLoaded()` |
| `StartMapLoad` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:445` | `private void StartMapLoad()` |
| `OnMapLoaded` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:473` | `private void OnMapLoaded()` |
| `OnMapLoadFailed` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:480` | `private void OnMapLoadFailed(string error)` |
| `TryFinishStageLoad` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:490` | `private void TryFinishStageLoad()` |
| `OnEnterTeamSelect` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:505` | `private void OnEnterTeamSelect()` |
| `OnTickTeamSelect` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:511` | `private void OnTickTeamSelect(float dt)` |
| `OnExitTeamSelect` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:518` | `private void OnExitTeamSelect()` |
| `OnEnterStage` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:523` | `private void OnEnterStage()` |
| `OnTickStage` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:556` | `private void OnTickStage(float dt)` |
| `OnEnterPause` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:563` | `private void OnEnterPause()` |
| `OnTickPause` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:568` | `private void OnTickPause(float dt)` |
| `OnExitPause` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:573` | `private void OnExitPause()` |
| `GoMainMenu` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:580` | `public void GoMainMenu()` |
| `ClearStage` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:595` | `private void ClearStage()` |
| `CsHudSnapshot.Reset` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:615` | `CsHudSnapshot.Reset();` |
| `OnStartNewGame` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:633` | `private void OnStartNewGame()` |
| `OnLaunchMatch` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:683` | `private void OnLaunchMatch(CsMatchConfig cfg)` |
| `OnTeamChosen` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:705` | `private void OnTeamChosen(CsTeam team)` |
| `OnRequestPause` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:728` | `private void OnRequestPause()` |
| `OnResumeRequested` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:748` | `private void OnResumeRequested()` |
| `OnBackToMain` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:764` | `private void OnBackToMain()` |
| `OnDisconnect` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:770` | `private void OnDisconnect()` |
| `OnQuitGame` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:777` | `private void OnQuitGame()` |
| `OnFsmChanged` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:791` | `private void OnFsmChanged(string from, string to)` |
| `IsPauseFamily` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:804` | `private bool IsPauseFamily(string state)` |
| `HasBlockingOverlay` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:824` | `private bool HasBlockingOverlay()` |
| `StageLoadTimeout` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:36` | `private const float StageLoadTimeout = 20f;` |
| `SceneLoadProgressCeiling` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:30` | `private const float SceneLoadProgressCeiling = 0.9f;` |
| `MenuFallbackDelay` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Flow/AppFlow.cs:33` | `private const float MenuFallbackDelay = 1.5f;` |
| `Events.StartNewGame` | cs16 | `clover-project-cs16/client/Assets/Scripts/Core/Events.cs:10` | `public const string StartNewGame = "Flow.StartNewGame";` |
| `Events.OpenOptions` | cs16 | `clover-project-cs16/client/Assets/Scripts/Core/Events.cs:12` | `public const string OpenOptions = "Flow.OpenOptions";` |
| `Events.BackToMain` | cs16 | `clover-project-cs16/client/Assets/Scripts/Core/Events.cs:14` | `public const string BackToMain = "Flow.BackToMain";` |
| `Events.Disconnect` | cs16 | `clover-project-cs16/client/Assets/Scripts/Core/Events.cs:15` | `public const string Disconnect = "Flow.Disconnect";` |
| `Events.Resume` | cs16 | `clover-project-cs16/client/Assets/Scripts/Core/Events.cs:16` | `public const string Resume = "Flow.Resume";` |
| `Events.RequestPause` | cs16 | `clover-project-cs16/client/Assets/Scripts/Core/Events.cs:17` | `public const string RequestPause = "Flow.RequestPause";` |
| `Events.LaunchMatch` | cs16 | `clover-project-cs16/client/Assets/Scripts/Core/Events.cs:21` | `public const string LaunchMatch = "Flow.LaunchMatch";` |
| `Events.TeamChosen` | cs16 | `clover-project-cs16/client/Assets/Scripts/Core/Events.cs:23` | `public const string TeamChosen = "Flow.TeamChosen";` |
| `SceneNames.Menu` | cs16 | `clover-project-cs16/client/Assets/Scripts/Core/CsConst.cs:262` | `public const string Menu = "Menu";` |
| `SceneNames.StageDust2` | cs16 | `clover-project-cs16/client/Assets/Scripts/Core/CsConst.cs:263` | `public const string StageDust2 = "StageDust2";` |
| `Bootstrap` | cs16 | `clover-project-cs16/client/Assets/Scripts/App/Bootstrap.cs:31` | `public class Bootstrap : MonoBehaviour` |
| `DontDestroyOnLoad` | cs16 | `clover-project-cs16/client/Assets/Scripts/App/Bootstrap.cs:76` | `DontDestroyOnLoad(gameObject);` |
| `CloverRes.Init` | cs16 | `clover-project-cs16/client/Assets/Scripts/App/Bootstrap.cs:92` | `CloverRes.Init(ResourceRootPrefix);` |
| `CloverInput.Init` | cs16 | `clover-project-cs16/client/Assets/Scripts/App/Bootstrap.cs:93` | `CloverInput.Init();` |
| `CsPlayerSettingsStore.Load` | cs16 | `clover-project-cs16/client/Assets/Scripts/App/Bootstrap.cs:99` | `var settings = CsPlayerSettingsStore.Load();` |
| `AddComponent` | cs16 | `clover-project-cs16/client/Assets/Scripts/App/Bootstrap.cs:109` | `gameObject.AddComponent<CsMapModule>();` |
| `Inject` | cs16 | `clover-project-cs16/client/Assets/Scripts/App/Bootstrap.cs:121` | `matchModule.Inject(map);` |
| `HudPanel` | cs16 | `clover-project-cs16/client/Assets/Scripts/Module/Player/PlayerModule.cs:43` | `private const string HudPanelName = "HudPanel";` |
| `BuyMenuPanel` | cs16 | `clover-project-cs16/client/Assets/Scripts/UI/InGame/HudPanel.cs:1019` | `Game.UI.Open<BuyMenuPanel>();` |
| `Assets/Scenes/Boot.unity` | cs16 | `clover-project-cs16/client/ProjectSettings/EditorBuildSettings.asset:9` | `path: Assets/Scenes/Boot.unity` |
| `Assets/Scenes/Menu.unity` | cs16 | `clover-project-cs16/client/ProjectSettings/EditorBuildSettings.asset:12` | `path: Assets/Scenes/Menu.unity` |
| `Assets/Scenes/StageDust2.unity` | cs16 | `clover-project-cs16/client/ProjectSettings/EditorBuildSettings.asset:15` | `path: Assets/Scenes/StageDust2.unity` |
| `CurrentScene` | 引擎 | `clover-client-unity-engine/Runtime/Presentation/Scene.cs:22` | `public string CurrentScene => _currentScene;` |
| `_currentScene` | 引擎 | `clover-client-unity-engine/Runtime/Presentation/Scene.cs:76` | `_currentScene = sceneName;` |
| `IFsm.RegisterState` | 引擎 | `clover-client-unity-engine/Runtime/Core/Fsm.cs:24` | `void RegisterState(string state, Action onEnter = null, Action<float> onTick = null, Action onExit = null);` |
| `IUIPanel` | 引擎 | `clover-client-unity-engine/Runtime/Core/PresentationContracts.cs:56` | `void Open<T>(object param = null) where T : class, IUIPanel;` |
| `ISceneManager` | 引擎 | `clover-client-unity-engine/Runtime/Core/PresentationContracts.cs:231` | `void Load(string sceneName, Action<float> progress = null, Action onDone = null);` |
| `AfterUnscaled` | 引擎 | `clover-client-unity-engine/Runtime/Core/Timer.cs:62` | `long AfterUnscaled(float delay, Action callback);` |

### 9.8 本文引用的 cs16 符号族（校验脚本读这一行，⛔ 两份文档必须逐字相同）

<!-- cs16-symbol-roots: AppFlow,IAppFlow,Bootstrap,PlayerModule,PlayerMotor,ViewModule,MatchModule,AudioModule,BotModule,CsMapModule,CsHudSnapshot,CsMatchConfig,CsTeam,CsConst,SceneNames,ResPaths,Events,State,Trigger,GameKey,CsPlayerSettingsStore,CloverRes,CloverInput,ICsMatch,ICsMap -->
<!-- cs16-symbol-exceptions: SettingsPanel,LoginPanel,RegisterPanel,CharSelectPanel,CharCreatePanel,ResultPanel -->

> 第二行是**范式占位名**清单：§1 的通用表里那些"登录 / 创角 / 选角 / 设置 / 结算"面板名属于**任何项目都可能没有**的占位（`{Name}` 工程的模板面），不是 cs16 的真实类名 ⇒ 不参与"符号必须能在源码里 grep 到"的清扫。⛔ 例外只许加在这一行里，不许在正文里临时豁免。

校验口径（与本 skill 的"需要时自查"口径一致）：

1. **锚点回读**：§9.7 每一行的 `文件:行` 必须存在，且该行必须含「该行必须出现的原文」；
2. **符号落点**：每行的「符号」必须在对应域（`cs16` / `引擎`）的源码树里 grep 到 —— `0 命中` 即 FAIL 并点名该行；
3. **正文符号清扫**：本文正文里每个"带点"或"以 `Panel` / `Module` / `Flow` / `Config` / `Snapshot` / `Store` / `Const` / `Names` / `Paths` / `Events` 结尾"的 `` `反引号符号` ``，都必须能在 cs16 ∪ 引擎源码树里 grep 到（上面那行声明的是"哪些前缀算 cs16 符号"）。
4. 三条任一转红 ⇒ 不许把本节当"已核对"。
