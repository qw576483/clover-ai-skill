# 工作流与工程规范（用到时再查）

> 本文是**能力 / 详述**。规则原文在 `SKILL.md`。开新工程、写服务端 handler、写客户端网络代码、要跑压测时读对应小节即可。

---

## 1. 动手前第一件事：混合模式找依据（六处同看 + 联网；用户 > 引擎 > 联网 / 自创）

> `patterns/` 与 `experience/*-core-code/` 里的示例都是「从 0→1」的通用写法；而用户项目**往往不是空的**（可能已有自己的 skill、模块 / 管理器 / 入口，同一件事在用户那儿叫别的名字、走别的入口，**整套 API 都可能不同**）。
> ⚠️ **这不是串行漏斗**（别理解成"① 没有就看 ②、② 没有就算了"）—— 那样要么"没找到现成的就不做了"，要么"拿一个没查证的东西硬凑"。
> 正确姿势：**下面这些地方该看的都看一遍（多数只要一两分钟），把信息综合起来判断，然后动手实现。**

| 看哪里 | 它能回答什么 | 优先级 |
|---|---|---|
| **本项目 skill**（`tools/ai-skill/`、`.codebuddy/`、`.cursor/rules`、`AGENTS.md`、`CLAUDE.md` …） | 这个项目特有的**约定与禁止事项** | 🥇 **最高** |
| **本项目文档**（`docs/`、`策划/`、README、验收表 …） | 这个项目**打算怎么做**、已定下的取舍 | 🥇 **最高** |
| **本项目源码**（本项目里已存在的实现） | **既有写法**：API 名、模块入口、目录、日志前缀、错误处理风格 | 🥇 **最高** |
| **引擎源码**（`clover-client-unity-engine/Runtime/**`、`clover-server-engine/**`） | 能力**真实签名与行为**（唯一不会骗人的地方） | 🥈 **其次** |
| **引擎文档**（`clover-doc/`、`*-engine-index.md`、`结构规则.md`） | 机制 / 原理 / 推荐用法 | 🥈 **其次** |
| **引擎 skill（含本 skill）**：`SKILL.md`、`patterns/**`、`experience/**` | 通用做法与形状（**给做法，不给能直接抄的 API**） | 🥈 **其次** |
| **联网搜索** | 以上都没有、或没见过的问题：框架 / 引擎 / 平台的通用解法、报错含义、版本差异 | 🥉 **再次**（参考，不是权威） |
| **自己设计** | 以上全部走完仍没有现成的 | ✅ **允许，而且常常是唯一出路** |

**冲突时以谁为准：用户 > 引擎 > 联网 / 自创。** 用户侧三处之间不一致时，**以用户 skill 的明文约定为准**并告知差异；引擎文档与引擎源码不一致时，**以源码为准**。

### ⛔ 红线（新建项目必守）：别人的 `clover-project-*` 除白名单外一律不许看

上表"用户侧三处"指的是 **本项目自己的** skill / 文档 / 源码。工作区里往往还并排躺着别的 demo 工程（自带 `client/`、`tools/ai-skill/`、`策划/验收表.md`、`Assets/Editor/*.cs` 生成器、素材目录…）。**做新项目时它们不是依据，是污染源。**

| 禁止 | 说明 |
|---|---|
| ❌ 读 / grep / 打开别人的 `clover-project-*` | 源码、Editor 脚本、`tools/ai-skill/`、`策划/`、`docs/`、素材 —— 全算 |
| ❌ 照抄其结构 / 命名 / 验收表 / 生成器 / 配表 / 素材路径 | 包括"隔壁就是这么做的"这种理由 |
| ❌ 沿用其模块名 / 面板名 / 常量名 | 那是**别的游戏**的领域词汇 |

**✅ 白名单**：`clover-doc` 的[游戏 Demo 清单](https://github.com/qw576483/clover-doc/blob/main/ai/game-demo.md) 里列出的 `clover-project-*`（引擎 + skill 交付出来的成品）**允许读、允许对照**其做法与形状（目录组织、验收表交付口径、生成器组织方式）。边界只有一条：**取做法与形状，不取领域内容**。
**允许抄的只有三处**：① 本项目自己的 skill 与源码；② 引擎源码 / `clover-doc` / 本 skill 的 `patterns`、`scaffold`、`experience`（只有通用形状，示例代码不得当 API 用）；③ 白名单里的成品工程。
**新项目的一切从 0 自己设计**（目录、模块、面板、生成器、配表、素材来源），新引入的设施在交付说明里标注"**本项目新增**"。**另一个例外**：用户本轮明确点名"参考 / 沿用某个已有工程"—— 那时才允许，且只在点名范围内。

### 硬约束：不许编造 API

**任何 API / 类名 / 字段名，必须能在「用户 skill / 用户文档 / 用户源码 / 引擎源码 / clover-doc」里指出出处。** 看不出处 = 不许写。
**但"没有现成的"不等于"不能做"** —— 三条正确出路：① **用通用原语自己拼**；② **联网**找成熟方案读懂后按本项目风格落地；③ **自己设计**，写清意图、边界与取舍。
⚠️ 无论选哪条，**新引入的东西必须明确标注"这是本项目新增的，不是引擎既有 API"** —— ⛔ 不许写得像引擎本来就有（那会让下一个人去查一个不存在的 API，然后怀疑是自己环境坏了）。

---

## 2. 遇到不确定时怎么办：skill 文档 → clover-doc → 源码 → 问用户

> **硬约束：不许编造任何 API。** "不知道"不等于"可以随便编一个" —— 未查证的 API / 字段名 / 配置项，能编过编译期，然后在运行时炸。
> 冲突时以 **用户 > 引擎** 为准；全都找不到就走 §1 的三条出路。

### 第 1 步：先查**项目级 skill**，再查 skill 内文档

> **第一步永远是**：在项目根找 `tools/ai-skill/`，有就先读它的 `SKILL.md` —— 那里记的是本项目特有的约定，优先级**高于**下面所有通用文档 —— **⛔ 但全局 skill 的规则层（§0~§7）不可被项目级覆盖**：项目文档**只能加严**；冲突时**照全局做，并把冲突那一行改掉**。

| 想知道 | 去看 |
|---|---|
| **本项目特有的约定**（消息号、已有 handler / 面板、约束） | **`<项目根>/tools/ai-skill/SKILL.md`** ← 先读它 |
| 做 X 用哪个包 / 哪个入口 | `reference/modules.md`、`reference/client-modules.md` |
| 团队约定（消息号、命名、Ctx 边界） | `reference/conventions.md`、`reference/client-conventions.md` |
| 代码怎么写 | `patterns/**`、`patterns/client/**` |
| 工程 / 文件模板 | `scaffold/new-project.md` |

### 第 2 步：skill 不够 → 查 clover-doc（权威业务文档，必查）

仓库根：`clover-doc/`（`mint.json` / `docs.json` 是导航，`STANDARDS.md` 是文档规范）。

| 想知道 | 去看 |
|---|---|
| 服务端概念 / 术语 / 机制原理 | [`clover-doc/server/concepts/`](https://github.com/qw576483/clover-doc/tree/main/server/concepts) |
| 服务端开发指引（handler / 配表 / 挂载…） | [`clover-doc/server/development/`](https://github.com/qw576483/clover-doc/tree/main/server/development) |
| 服务端上手 | [`clover-doc/server/quickstart.md`](https://github.com/qw576483/clover-doc/blob/main/server/quickstart.md)（依赖环境 → 配置 → 启动 → 登录） |
| WorldSync / MMO | [`clover-doc/server/concepts/mmo-worldsync.md`](https://github.com/qw576483/clover-doc/blob/main/server/concepts/mmo-worldsync.md) |
| 服务端示例 / 运维 / 工具 / 安全 | [`clover-doc/server/{examples,operations,tools,security}/`](https://github.com/qw576483/clover-doc/blob/main/server/{examples,operations,tools,security}/.md) |
| 客户端概念 / 开发 / 示例 / 参考 / 工具 | [`clover-doc/client/{concepts,development,examples,reference,tools}/`](https://github.com/qw576483/clover-doc/blob/main/client/{concepts,development,examples,reference,tools}/.md) |

> **优先级**：具体机制 / 原理 / 用法以 **clover-doc 为准**（skill 只是速查，可能过时）；只有涉及**团队约定**（消息号段、命名、Ctx 边界）时以 `reference/conventions.md` 为准，并告知用户差异。

### 第 3 步：clover-doc 还说不清 → 读源码，把逻辑搞懂

| 想知道 | 去看 |
|---|---|
| 引擎架构 / 模块总览 | [`clover-server-engine/clover-server-engine-index.md`](https://github.com/qw576483/clover-server-engine/blob/main/clover-server-engine-index.md)、`结构规则.md` |
| 某模块实现（data / master / log / auth / mmo / room / object） | `clover-server-engine/internal/<模块>/`、`pkg/domain/<模块>/` |
| 消息号 / 线格式 / 协议 | `pkg/shared/proto/{msg,push}.go`（消息号真身）、`internal/shared/proto/reply.go` |
| 客户端 API 真实用法 | [`clover-client-unity-engine/Samples~/`](https://github.com/qw576483/clover-client-unity-engine/tree/main/Samples~)、`Tests/` |
| 客户端 API 签名 / 类名 | `clover-client-unity-engine/Runtime/<模块>/*.cs` |
| Unity CLI 命令 | `unity skill show`、`unity --help` |

**"搞懂"的判定标准**（答不出就是没懂，回去继续查）：① 数据从哪来到哪去（请求 → handler → 存储 / 广播 → 客户端 → 表现）；② 调用链每一跳用的**哪个类、哪个方法**（名字能在源码里指出来）；③ 谁负责回包 / 推送，失败与异常怎么处理；④ 有没有**同类实现**能照着写。

### 第 4 步：查完还不确定 → 停下来问用户（必须问，不许含糊过去）

问的时候要说清「我查过 skill 的 X、clover-doc 的 Y、源码的 Z，没找到 / 没确认 X」，便于用户直接给答案。该问的：需求 / 玩法规则有歧义（胜负判定、数值、流程顺序、边界情况）；clover-doc 与源码冲突（以源码为准，但告知差异）；引擎确实没这个能力（业务层绕 vs 动引擎）；逻辑链走不通；环境缺失且影响联服验证。
**没搞懂逻辑就不许动手写** —— 宁可多问一句，也不要交一份"看起来像那么回事"的代码。

### 硬约束：不许编造 API（再列一次，逐条记）

- 任何 API 名、类名、方法签名、字段名、配置项，**必须能在 clover-doc 或源码里指出出处**。
- ⛔ 禁止推测式命名；⛔ 禁止把别的框架 / 引擎的 API 风格套到 Clover 上；⛔ 禁止把不确定藏进 `// TODO` 而不告知用户；⛔ 禁止用「框架已预留，暂未实现」交差；⛔ 禁止查不到就说"不支持"（先确认是真不支持，还是自己没查到）。

### 模板缺口怎么办（skill 自我进化）

① 先查 `clover-doc/` 对应章节，再按第 3 步读源码，照着同类实现写；② 仍无解 → 问用户；③ 实现完成后，若该范式可复用，**建议把它补进 `patterns/`**（附引擎源码出处）。

---

## 3. 错误处理与日志（硬约束，服务端 + 客户端都适用）

> 一句话：**凡是"没按预期走"的分支，必须留下一条日志。** 不写日志的失败 = 将来无人能查的事故。依据 [`clover-doc/server/development/error-handling.md`](https://github.com/qw576483/clover-doc/blob/main/server/development/error-handling.md)。

**必须打日志的分支（逐条自查）**：出错返回（`return err` / 任何"和预期不符"的提前 `return`）；兜底与防御（`x == nil`、空集合、空字符串、`v, ok := x.(T)` 的 `!ok`）；参数校验失败 / 非法状态迁移 / 越界 / 重复操作 / 找不到目标对象；`switch` 的 `default` 分支（尤其"理论上不可能走到"的）；**客户端**：网络失败、反序列化失败、资源加载失败、查不到 UI 控件 / 预制体、未登录却触发操作；**定时器 / 每帧 / 高频回调**里的异常：**必须打，但要防刷屏**。

| 侧 | 用法 | 出处 |
|---|---|---|
| 服务端 | `logger.Infof / Warnf / Errorf(...)`，来自 [`pkg/foundation/logger`](https://github.com/qw576483/clover-server-engine/blob/main/pkg/foundation/logger/README.md) | [`clover-doc/server/examples/timer.md`](https://github.com/qw576483/clover-doc/blob/main/server/examples/timer.md) |
| 客户端 | `Game.Logger.Info / Warn / Error(tag, msg)`（**永不为 null**） | [`clover-client-unity-engine/Runtime/Core/Logger.cs`](https://github.com/qw576483/clover-client-unity-engine/blob/main/Runtime/Core/Logger.cs) |

- ⛔ **禁止**服务端用标准库 `log.Printf`、客户端用裸 `Debug.Log` 打业务日志。
- 日志必须带**可定位信息**：谁（playerID / roomID）、哪个消息号、关键参数、期望值 vs 实际值。

**高频路径：不刷屏，但也⛔ 不许静默**

```csharp
catch (Exception e)
{
    if (!_failLogged)                     // 只报一次，避免断网时刷屏
    {
        _failLogged = true;
        Game.Logger.Warn("Net", "操作发送失败（同类错误不再重复打印）: " + e.Message);
    }
}
```

**收尾自检（需要时自查；⛔ 默认不跑，`SKILL.md` §4）**：① 搜本次改动的文件里 `catch` / `if err != nil` / 提前 `return` / `default:`，逐条确认都有日志；② 确认**没有空 `catch`**、没有吞异常后静默返回；③ 高频回调里的日志有防刷屏处理；④ 日志前缀统一（服务端模块名、客户端 `[模块名]`）。

---

## 4. 项目脚手架（必须遵守）

```
clover-{项目名}/
├── tools/ai-skill/                  # ★ 项目级 skill（入口 + conventions / registry / constraints）
├── server/                          # 服务端（Go）—— ★ 仅形态=联机时才有（单机项目不建）
│   ├── configs/all/server.yaml
│   ├── game/{datadef,def,logic,master_logic,table}/
│   ├── sqls/  main.go  go.mod  go.sum
├── client/                          # Unity 客户端（由 unity-cli 创建，不要手写目录树）
│   └── Assets/{Configs, Resources/UI, Scripts/{Def,Core,Module/*,UI,App}}
│                                    # ⛔ 这里不该有 Screenshots/ —— 取证截图落 <项目根>/.ai-tmp/screenshots/
├── 策划/{数值文档, 策划案, 验收表.md}
├── 原版资源/                        # ★ 下载/解包素材唯一来源（不进 git）
└── .ai-tmp/                         # ★ 一切一次性产物（test/ 探针、hosts/ 自检宿主）—— 用完即删，不进 git
```

> ⚠️ `client/Assets/Scripts/` 的**分层**以 `reference/architecture.md` 为准（`Def / Core / Module/* / UI / App`，依赖单向）；完整文件模板以 `scaffold/new-project.md` 为准。⛔ 历史文档里出现过的 `Scripts/{Def,Core,Network,Room,Table,UI}/` 是**旧骨架，已作废**。
> **文件模板来源**：每个文件的完整内容（`go.mod` / `main.go` / `server.yaml` / `def` / `logic` / `manifest.json` / `asmdef`）一律以 `scaffold/new-project.md` 为准，直接复制；项目级 skill 模板见 `scaffold/project-skill.md`。

**⛔ 禁止**：手写 `client/Assets/Scripts/...` 目录树冒充 Unity 工程（客户端工程**必须用 unity-cli 创建**）；在 `server/` 根目录放业务代码、在 `game/` 外创建 `handler/`、`service/` 等目录；在 `client/Assets/` 外放游戏代码；使用非标准目录名（`src/`、`app/`、`UIScripts/`）。
**必须**：服务端配置放 `configs/all/`、消息号放 `game/def/`、schema 放 `game/datadef/`、Handler 放 `game/logic/`；客户端业务消息号放 `Assets/Scripts/Def/MsgDef.cs`（⛔ 禁止散落在 `GameManager` / UI 脚本里）；**数据一律走配表**；**建项目时必须生成项目级 skill** `<项目根>/tools/ai-skill/`；**动任何项目代码前先读 `<项目根>/tools/ai-skill/SKILL.md`**。

---

## 5. 数据一律走配表（同质化配置禁止硬编码）

> **游戏里绝大多数数据都是配表**（技能伤害 / 等级经验 / 怪物属性 / 道具 / 掉落 / 关卡 / 地图表 / 商店 / 成就…），共同点是**同质化**。完整模板与硬规则见 **`patterns/table.md`**。

**判定：满足任一 ⇒ 必须抽表** —— 同一套字段要重复很多条（20 个技能 / 60 级 / 30 张地图）；代码里出现成排的同质化常量、大 `switch`、大 `map` 字面量；数值会被策划改、会随版本增长；客户端与服务端都要读同一份数据。⛔ 例外：一两行、永不变的纯逻辑常量（协议号、枚举）可留代码。

**三步闭环（一个都不能省）**：

```text
① 同质化配置抽成源表 txt   →  <项目>/策划/数值文档/<表名>_cs.txt   tab 分隔 + 4 行表头
② txt 反推 xlsx（给策划改） →  cd table/core && go run ./cmd/table -pack -config config.yaml -batch
③ xlsx 打表出两端可读产物   →  go run ./cmd/table -config config.yaml -batch
                              （tsv + 强类型代码，客户端 C# / 服务端 Go 各一份）
```

**硬性要求**：源表名必须带 `_cs` / `_c` / `_s` 后缀，放 `策划/数值文档/`（**单层扫描**，不许再套子目录）；⛔ **禁止把配表数值硬编码进业务代码**，运行时只走强类型访问器（客户端 `Tables.Default.X.Get(id)`、服务端 `table.Default.X.Get(id)`）；**改了表结构必须重跑第 ③ 步**；`-pack` 默认不覆盖策划改过的 xlsx，需要覆盖时显式 `-force` 并先与用户确认。

---

## 6. 开工前置检查（先查环境，再写代码）

**第 0 步：先判定这个任务要不要服务器**（决定查不查环境）：

| 任务形态 | 服务器环境检查 |
|---|---|
| 联服玩法 / 要写服务端 handler / 要跑通 C2S 回路 | **必查** |
| 用户明确说"单机 / 纯本地 / 不要服务器 / 只要客户端 demo" | **跳过**（单机项目客户端初始化见 `scaffold/new-project.md` §2.5：**不生成 `server/`，`Game.Launch` + `CloverInput.Init()` 即可，不调 `CloverNet.Init`**） |
| 需求没提服务器 | ⛔ **不许默认联服** —— 先做闸门 0：① 联网搜**原版形态** → ② 用户本轮是否明确要联机 → ③ 都没有 ⇒ **按原版形态做**；原版是单机就做单机并**跳过环境检查** |

> 用户**明确指定**单机的，不算"静默降级"；AI **自己**把联服改成单机才算。

**1) 服务器环境**（仅上表"必查"时做，详见 `reference/server-env.md` §0）：`clover-server-tools/windows-env/core/env.exe info`（未起 → `start`；整个目录不存在 → 停下来问用户）。
**2) Unity 环境**（无论单机还是联服，只要动客户端工程都做，详见 `reference/unity-cli.md`）：`unity --version` + `unity editors list --format json`。

**不许静默降级**（违反即交付失败）：环境不可用时⛔ 禁止把联服功能改成单机 / 离线 / 模拟模式、⛔ 禁止注释 `server.yaml` 依赖来"简化"、⛔ 禁止用"框架已预留，暂未实现"交差。先把情况告知用户并等其选择：① 装 / 起环境；② 明确同意做离线版（须在交付说明首行标注「⚠️ 离线版：联服未验证」）；③ 只交代码不起服。

---

## 7. 服务端工作流

0. **不确定先查，搞懂再写**（见 §2）；⛔ **禁止编造任何 API**。
1. **定位包**：先查 `reference/modules.md` 的速查表。
2. **套范式**：从 `patterns/` 取对应模板（handler / datadef / mount / timer / crossnode / player-lookup / signup-login）。
3. **守约定**：生成代码前必读 `reference/conventions.md`。
4. **校验**：业务消息号必须 `>= 10001`；数据结构 / 消息号用 `E` 前缀（引擎常量）/ `Msg` 前缀（业务别名）；**每条非预期分支都要打日志**。
5. **环境故障**：按 `reference/server-env.md` 排障；**不主动下载组件**。

## 8. 客户端工作流

0. **环境自检**：需要编译验证 / 测试 / 构建 / 改场景资源 / 读日志时，先 `unity --version`；不存在就**自动安装** Unity CLI，再 `unity editors list --format json` 确认有 **Unity 6（6000.x）**。
1. **确定模块**（Network / Entity / UI / Resource 等）。
2. **先建 Def/**：**写任何网络代码之前**必须先创建 `Assets/Scripts/Def/`（模板见 `patterns/client/network.md` 模板 0）—— `MsgDef.cs`（业务消息号常量，唯一定义处）+ `ProtoDef.cs`（协议结构体）。
3. **套范式**：从 `patterns/client/` 取模板；没有对应模板时先查 [`clover-doc/client/`](https://github.com/qw576483/clover-doc/tree/main/client)，再看 `Samples~/`、`Tests/`、`Runtime/**/*.cs`。
4. **守约定**：生成代码前必读 `reference/client-conventions.md`。
5. **校验**：**每条非预期分支都要打日志**，统一用 `Game.Logger.*`，⛔ **禁止裸 `Debug.Log` 打业务日志**。
6. **可运行交付（不许丢手工活给用户）**：场景由 AI 创建并保存、加进 Build Settings，业务脚本由 AI `AddComponent` 挂上，编译无错才算完成。⛔ **禁止**在交付说明里写"请用户在场景中创建空物体并挂载 Xxx 脚本"。
7. **写资源欠缺文档**：引用了外部资源（图 / 音 / 动画 / 模型 / 字体 / 美术预制体）就在 **`client/资源欠缺清单.md`**（**client 根目录**）登记；占位资源也要登记。

> **测试策略（本仓库硬约定）**：**新功能先不写单测**（功能优先）；AI 不要把「补单测」当待办项反复汇报，也不要以「缺测试」阻塞交付；但**既有的 `Tests/` 套件要保持能编译、能跑过**。

---

## 9. 集群编排与端到端验证（`manager`）

| 想做什么 | 命令 |
|---|---|
| 开工自检：etcd 通不通 + 每个节点活不活 | `manager doctor --json` |
| 看全集群拓扑 | `manager nodes --json` |
| 看某节点存活 / drain 进度 | `manager status <node> --json` |
| 灰度下线 | `manager drain <node> --target <新地址> --stop-after --yes --wait --json` |
| 滚动发布 | `manager rollout --nodes a,b --target x --launch "<起新进程的命令>" --yes --json` |

**AI 调用约定（硬约束）**：一律加 `--json`（结果 = stdout 的单个 JSON 对象；进度在 stderr 且 `--json` 下静默）；破坏性操作**必须**带 `--yes`（不带会立即返回退出码 `2`，不会挂住等输入）；**靠退出码判断成败**（`0` 成功 / `1` 运行失败 / `2` 用法错误 / `3` 部分成功）；**起新进程不是引擎的活**（`rollout` 用 `--launch` 交给 systemd / k8s / ssh，没有可用拉起方式就先告诉用户，⛔ 别把 `drain` 当"重启"用）。
跨机管理要求节点把 `admin.listen_addr` 配成内网可达地址**并同时配置 `admin.token`**：「非回环 + 无 token」会被 `AdminConfig.Normalize` 判为不安全配置、**拒绝启动**；且 manager 本身**不发**令牌头，被管节点一启用 token，其 `drain` / `shutdown` / `upstream` 即被 **401 拒绝**。完整说明见 [`clover-doc/server/tools/manager.md`](https://github.com/qw576483/clover-doc/blob/main/server/tools/manager.md)。

---

## 10. 压测与容量验证（`robot`）

| 想做什么 | 命令 |
|---|---|
| 开工自检：网关 + 账号服通不通 | `robot doctor --json` |
| 铺 N 个压测账号 | `robot signup --start 1 --count 100 --yes` |
| N 个并发登录 | `robot run --robots 100 --json` |
| 在线承载压测 | `robot run --robots 100 --ramp 20 --duration 60s --msg 10001 --body '{"n":"r{i}"}'` |
| 验完整链路（登录 + 建角 + 进游戏） | `robot run --robots 50 --setup '10001:{"name":"r{i}"}' --require-fullsync` |

**AI 调用约定**：一律加 `--json`；写数据的操作**必须**带 `--yes`；**靠退出码判断成败**（0 全成功 / 1 全军覆没 / 2 用法错误 / 3 部分成功）；**账号 = 前缀 + 序号**（默认 `robot_1`…），压测前必须已存在或让 `--signup` 自动注册。

**下结论前必须知道的四个坑**（否则会把"环境没配好"读成"服务端不行"）：
1. **登录成功按 `ELoginReply.success` 判，不按有没有收到 `EPushPlayerFullSync`** —— 账号没有角色时登录本就是成功的，只是引擎不推全量同步。要验完整链路得显式加 `--require-fullsync`（并配 `--setup`）。
2. **网关的连接级准入 ≠ 服务端容量上限**：新建连接速率限流 / `gateway.max_conns` / `queue_cap` 超限时，网关在**首帧**就关连接（服务端日志 `gwcore: admission rejected ... (rate/queue)`）。**注意区分"被拒"与"在排队"**：开了 `queue_cap` 时网关不拒而是发 `EMsgQueuePosition`。
3. **消息级限流**：网关默认单连接 **64 帧 / 秒**，`--interval` 小于约 15ms 就会撞上 —— 那不是服务端吞吐上限。
4. 报告里 `dropped` / `unmatched_reply` / `pending_overflow` 不为 0 时结论要打折；另外服务端对「没注册 handler 的消息号」**不回包**，所以 `sent > recv` 属正常。

完整说明见 [`clover-doc/server/tools/robot.md`](https://github.com/qw576483/clover-doc/blob/main/server/tools/robot.md)。

---

## 11. 服务端关键约束

- `Ctx` 只有纯数据访问器 + `MarkReplied(body []byte)` 纯写入；`Reply` / `Push` / `Alert` / 事件发送全部在 `Game`（`g.Reply(c, v)` / `g.PushToPlayerJSON(playerID, msgID, v)` / `g.Alert(c, &proto.EAlertNotify{...})` / `g.SendEventToPlayer(c, ...)`）。准确签名见 `patterns/handler.md`。
- 写入模型是 **Load-Modify-Return**：`g.LoadStruct(c, schema, id, &v)` 读出后直接改字段，handler 返回后引擎自动 Commit，无需显式 Save。
- 业务只依赖 `clover-server-engine/pkg/*` 转发层，不引 `internal/*`。
- **定时任务**：到点必须发生的事（行军到达 / 建造 / 征兵 / 挂机产出）**deadline 落数据**，定时器只做加速器（内存定时器随重启丢失）；**离线也要跑的任务 scope 禁止用 `owner`**（见 `patterns/timer.md`）。
- **多网关部署**：客户端是**静态配网关地址、不走服务发现**的 ⇒ 多网关必须由外部 LB 提供单入口，且用 **L4**（长连接 + 私有二进制协议）而不是 L7；可靠通道**不要求会话粘性**。**唯一例外是裸 UDP**：绑定令牌与端点表是**网关进程本地**的，同一玩家的 TCP 与其 UDP 包必须落到同一网关进程。详见 [`clover-doc/server/operations/deployment.md`](https://github.com/qw576483/clover-doc/blob/main/server/operations/deployment.md)。

---

## 12. 客户端关键约束

**Game 门面**：所有模块通过 `Game` 门面访问，不直接实例化。

```c#
Game.Net.Send(EMsg.Xxx, msg);
Game.Res.LoadAsset<GameObject>("xxx", go => { /* 使用 go */ });
```

**网络 API 语义**：

| 操作 | 服务端 Go | 客户端 C# |
|---|---|---|
| 注册监听 | `g.OnMsg(msgID, handler)` | `Game.OnMsg(EMsg.Xxx, handler)`（**客户端唯一入口**；同名，不另起 `OnPush`） |
| 可靠发送 | - | `Game.Net.Send(EMsg.Xxx, msg)` |
| 请求-回包 | - | `await Game.Net.Call<T>(EMsg.Xxx, msg)`（按 requestID 配对，不注册回调） |

**消息号约定**：

```c#
// 引擎消息号 CloverEngine.EMsg：1 - 10000（封闭 static class，业务不许往里加）
// 业务三段各从独立起点起。引擎的硬约束只有一条「业务 C2S > 10000」，
// 起点数字是本仓库约定（见 reference/conventions.md），不要自创其它起点：
// 业务 C2S   1000101 起   server/game/def/msg.go     ↔ client/Assets/Scripts/Def/MsgDef.cs
// 业务回包   **不占消息号**   server/game/def/reply.go   ↔ 只定义回复体结构（回包帧 msgID 恒为 0）
// 业务推送   3002001 起   server/game/def/push.go    ↔ 同上
```

业务消息号**只能**定义在 `client/Assets/Scripts/Def/MsgDef.cs`，协议结构体放同目录 `ProtoDef.cs`，与服务端 `game/def/` 逐条对齐。⛔ **禁止**在 `GameManager.cs` / UI / 任意业务类里写消息号常量或裸字面量。

---

## 13. 文档一致性自检（**想查时过一遍；文档不是"写完就算"**）

> **为什么单列**：一个项目交上来时**代码全绿、文档全错**，错法都是"改了 A 没改 B"，而且**都不报错**所以没人发现：验收表的证据格指向 `tools/<某自检宿主>/` 而该宿主**已搬到 `.ai-tmp/hosts/`**（**引用断裂 = 等于没有证据**）；`docs/交接-下一棒.md` 说「还没做」而实际早就做完（下一棒照它做就白做）；源码注释引用 `docs/agents/agent-NN-*.md` 而该文件已不存在。
> ⇒ 这三条**值得自己过一遍**（它们都在"要查时的 3 招"的引用可达里；⛔ **默认不查**，⛔ 也**不要**为它建汇总对账 / 表格统计）。

| # | 检查 | 怎么查 | 通过标准 |
|---|---|---|---|
| 1 | **引用可达** | 把交付文档里出现的每个 `<路径>` / `<文件>:<行号>` 逐个 `Test-Path` / 打开 | **全部可达**（⛔ 文档里不引用一次性截图 —— 它在 `.ai-tmp/screenshots/`，交付后即删） |
| 2 | **无悬空引用** | 对项目文档与代码注释 grep `` `[\w./\\-]+\.(md\|cs\|go\|yaml\|json)` ``，逐个 `Test-Path` | **0 个不存在的路径**（改过文件名 / 目录 ⇒ 旧名全局 grep 归零） |
| 3 | **无交接类文档 / 不与规则层冲突** | ① grep `交接\|进度\|NEXT\|下一棒` 的 `.md` ② 对 `tools/ai-skill/` 与 `docs/` grep `以本项目为准\|优先于全局\|优先于通用` | ① **0 命中** ② 命中处**逐条判加严还是放宽**，**放宽的一律改掉** |

> **一条推论**：**搬目录 = 一次全局改名** —— 任何目录 / 文件改名后必须对全项目（含文档、注释）grep 旧名，**命中归零**才算搬完。

---

## 14. 规则层的否决权（**任何项目文档都不得覆盖本 skill 的规则层**）

> 规则原文（层级表 + 「项目约定优先」的正确含义 + 冲突时的三步动作）在 **`reference/rules-full.md` 的「规则层的否决权」**，此处不重复。
> **要点**：项目约定**只在**「本 skill 没写」或「明说可自选」的地方优先（技术选型、命名、目录细分、消息号分段、配表字段名）；凡本 skill 标了 `⛔` / 硬规则 / 硬闸门的地方，项目约定一律不得冲突 ⇒ 照全局做 + 把冲突那份项目文档改掉 + 必要时回报用户。
> **想查时的自检**（⛔ 默认不查）：对 `tools/ai-skill/` 与 `docs/` grep 差异词，命中处逐条判加严还是放宽，**放宽的一律改掉**。

---

## 15. 临时文件与产物位置（**不许遍地拉屎**）

> 规则原文（一次性产物只放 `.ai-tmp/test/`、一律绝对路径、收尾清场）在 **`SKILL.md` 的「写码清单」第 5 条**与 **`reference/rules-full.md` 的「临时测试文件规范」**。
> **分类判据（一句话，用来决定"放哪"）**：它**下次改完还会不会再跑一次**？
> **会**（探针外壳、Play 驱动、离线编译检查、量法/解码脚本…）⇒ 进 `tools/probes/` **并提交**；**不会**（一次性切片脚本、一次性输出快照）⇒ 只落 `.ai-tmp/`，**用完删**。
> ⚠️ **别拿"删了还能重新判定吗"当判据** —— 那句话对**任何**脚本都成立，结果就是 `tools/probes/` 长到 200~360 个文件（实测：4 个工程合计 700+，里面躺着白名单 / 对账 / 自检 / 台账的整个上一代验收机器）。
> ⚠️ 反面教材（真实）：把 281 KB 的**探针外壳**按"一次性产物"删掉 ⇒ 复验能力归零，只能从回收站捞。（探针外壳 ≠ 切片脚本，前者留、后者删。）位置表：

| 位置 | 只放什么 |
|---|---|
| `tools/` | **只放正式工具**：会被反复长期使用的资产（素材解码器、打表配置…）。⛔ 不许把测试宿主堆这里 |
| `.ai-tmp/hosts/` | **一切测试 / 自检程序**（`*check` 宿主、验证小程序、跑测试的脚本）—— **用完删** |
| `<项目根>/.ai-tmp/screenshots/` | **取证截图（一次性）**：验收后即删（跟 `.ai-tmp/` 一起被 gitignore）。⛔ 不许放 `client/Assets/**` |
| `<项目根>/tools/probes/` | **只放"下次改完还会再跑一次"的资产**：探针外壳 `.cs`、Play 驱动 `.ps1`、离线编译检查、量法 / 解码脚本。⛔ **不许**堆一次性切片脚本（带片名/slice id 的那些）与输出快照 —— 它们用完即删（判据一句话：**下次还会不会再跑它**） |
| `策划/` | 策划文档、验收表、素材调研 |
| `.ai-tmp/test/` | **其它一切一次性的东西**（用完删） |

⚠️ **例外**：参考物那一侧的图（A 的原版截图 / 对照图）**不是**取证截图，按 `策划/基线图/`、`策划/自审对比/` 长期保留。
