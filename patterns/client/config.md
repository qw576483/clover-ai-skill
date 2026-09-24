# 范式：客户端配置（config.json + 引擎加载器 + 薄门面）

## 何时使用

只要客户端存在「部署期会变、或不该散落在代码里」的量，就必须走配置文件，**不许写死在业务代码里**：

- 服务器地址 / 端口 / UDP 地址
- **账号服地址（`server.auth_addr`）—— 登录链路的必经依赖，必填**
- 请求超时 / 重连次数
- 开发期测试账号 / 密码 / 线路号
- 轮询间隔 / 默认昵称 / 玩法开关 / 帧率

> **只建 `Configs/` 目录不算完成** —— 必须建出「**配置段类型 + 引擎加载链的注入 + 薄门面**」（§2），
> 否则地址 / 账号 / 密码 / 超时会被硬编码进业务代码，换环境就得改代码重编。

## 目录与文件（固定路径，不要改名）

```
client/Assets/Configs/config.json            # 唯一配置入口
client/Assets/Scripts/Core/ClientConfig.cs   # 项目侧：配置段类型 + 引擎加载链的薄门面（静态类 Cfg）
```

## 1. `config.json` 模板

```json
{
  "server": {
    "addr": "127.0.0.1:8002",
    "udp_addr": "",
    "tls": false,
    "auth_addr": "http://127.0.0.1:8051",
    "call_timeout": 10,
    "max_reconnect_count": 5
  },
  "account": {
    "name_prefix": "p",
    "name_suffix": "_app",
    "password": "123456",
    "line": 0
  },
  "game": {
    "default_nick": "玩家一",
    "poll_interval_ms": 50,
    "res_root": ""
  }
}
```

⚠️ **`server.addr` 必须是网关 TCP 口**（服务端 `server.yaml` 的 `gateway.listen_tcp`，默认 **8002**）。不要填 `8001` —— 那是 `gateway.listen_ws`（WebSocket），Unity 原生客户端走**裸 TCP**，填错的症状是「TCP 连上 → 立刻断开 → 重连耗尽被踢 → 之后所有 `Call` 超时」。详见 `scaffold/new-project.md` §2.4。

`udp_addr` 填 `gateway.listen_udp`（默认 8003）；不需要不可靠通道就留空字符串。

`tls`：线路是否走 TLS（TCP→`SslStream`、WS→`wss://`）。**判断依据是服务端有没有配 `gateway.tls_cert`/`tls_key`**：
- **没配证书 = 服务端明文 ⇒ 客户端必须 `false`**（`scaffold/new-project.md` 的模板就是这个形态，照抄能跑通）；
- 证书**成对配了** ⇒ 客户端 `true`。

⛔ 别再按"`tcp_tls_disabled` 的零值是 `false` ⇒ 客户端取反写 `true`"这条公式 —— 它把"是否配证书"漏掉了，写反的症状是「**连上就断** → 重连耗尽被踢 → 之后所有 `Call` 超时」。证书只走系统信任链，引擎没有跳过校验的开关。

## 2. `ClientConfig.cs`：项目侧只剩「配置段 + 薄门面」

**加载链本身是引擎件。** 控制流 —— **按序试来源 → 读/解析失败就跳过 → 全部来源都不可用 ⇒ 回落 `createDefault()` → `Reload()` 重跑整条链** —— 由
`clover-client-unity-engine/Runtime/Core/ClientConfig.cs` 的 `CloverEngine.ConfigSectionLoader<T>` + `CloverEngine.ConfigSource` 负责
（⛔ **不要再手写一份加载器**；那是每个工程重写一遍的控制流）。

项目侧只写三件事：

1. **自己的配置段类型**（字段 + **字段初始化器里的默认值**）—— `[Serializable]`，**字段名 = JSON 键名**（`JsonUtility` 按字段名映射）；
2. **用 `ConfigSectionLoader<T>` 注入来源与解析**：来源各是一条 `ConfigSource(name, readText, logLabel)`（`Resources/Configs/config` 与磁盘文件各一条），外加 `parse`（**返回 `null` = 本来源解析失败**）与 `createDefault`（`() => new RootSection()`，**默认值的唯一出处**）；
3. **一个薄门面**（惯用名 `Cfg`）暴露 `Cfg.Xxx`。

```csharp
using System;
using System.IO;
using CloverEngine;     // Game 门面 + ConfigSectionLoader<T> / ConfigSource / LogThrottle
using UnityEngine;

namespace {Name}
{
    [Serializable]
    public class ServerSection
    {
        public string addr = "127.0.0.1:8002";   // 网关 TCP 口
        public string udp_addr = "";             // 网关 UDP 口，留空=不启用
        public bool tls = false;                 // 线路走 TLS；判据 = 服务端有没有成对配 tls_cert/tls_key
        public string auth_addr = "http://127.0.0.1:8051"; // 账号服 HTTP 地址（必填；登录链路必经依赖）
        public int call_timeout = 10;
        public int max_reconnect_count = 5;
    }

    [Serializable]
    public class AccountSection
    {
        public string name_prefix = "p";
        public string name_suffix = "_app";
        public string password = "123456";
        public int line = 0;
    }

    [Serializable]
    public class GameSection
    {
        public string default_nick = "玩家一";
        public int poll_interval_ms = 50;
        public string res_root = "";             // 资源根；留空 = 纯 Resources 模式（CloverRes.Init 的入参）
    }

    [Serializable]
    public class RootSection
    {
        public ServerSection server = new ServerSection();
        public AccountSection account = new AccountSection();
        public GameSection game = new GameSection();
    }

    /// <summary>客户端配置入口：引擎 <c>ConfigSectionLoader</c> 的薄门面（加载链见引擎件）。</summary>
    public static class Cfg
    {
        private const string Tag = "Cfg";
        private const string RelativePath = "Configs/config.json";
        private const string ResourceKey = "Configs/config";

        private static ConfigSectionLoader<RootSection> _loader;
        private static string _filePath;

        private static ConfigSectionLoader<RootSection> Loader
        {
            get
            {
                if (_loader != null) return _loader;

                // 来源表在**首次访问时**求值（`FilePath` 会碰 `Application.dataPath`）：
                // 静态构造期不读盘、不碰 Unity API。
                _loader = new ConfigSectionLoader<RootSection>(
                    Tag,
                    new[]
                    {
                        // ① 引擎资源模块（跨平台：WebGL / 移动端只能走这条）
                        new ConfigSource("Resources/" + ResourceKey, ReadResourceText),
                        // ② Application.dataPath（Editor / 桌面）；`LogLabel` = 磁盘路径（解析错误点名用）
                        new ConfigSource("文件:" + FilePath, ReadFileText, FilePath),
                    },
                    Parse,
                    () => new RootSection());   // 默认值的唯一出处 = 上面各段的字段初始化器

                return _loader;
            }
        }

        /// <summary>配置来源描述（`Resources/...` / `文件:<路径>` / `默认值`），打日志时带上便于定位。</summary>
        public static string Source => Loader.Source;

        /// <summary>配置文件在磁盘上的绝对路径（Editor / 桌面平台）。取不到时退回相对路径，⛔ 绝不向上抛。</summary>
        public static string FilePath
        {
            get
            {
                if (_filePath != null) return _filePath;

                try
                {
                    _filePath = Path.Combine(Application.dataPath, RelativePath);
                }
                catch (Exception e)
                {
                    // 非预期分支：非 Unity 宿主（纯 C# 进程 / 单元测试）里 Application.dataPath 不可用
                    LogThrottle.ErrorOnce(Tag, "cfg.datapath",
                        $"Application.dataPath 不可用（{e.GetType().Name}）⇒ 退回相对路径 {RelativePath}");
                    _filePath = RelativePath;
                }

                return _filePath;
            }
        }

        /// <summary>根对象（首次访问时加载）。</summary>
        public static RootSection Config => Loader.Value;

        public static ServerSection Server => Config.server;
        public static AccountSection Account => Config.account;

        /// <summary>game 段。⛔ **不要命名为 `Game`** —— 那会遮蔽引擎门面（见「常见问题」）。</summary>
        public static GameSection GameCfg => Config.game;

        /// <summary>重新加载（改完 json 不必重启编辑器）。</summary>
        public static void Reload()
        {
            Loader.Reload();
            Game.Logger.Info(Tag, $"配置已重载，来源={Loader.Source}");
        }

        /// <summary>
        /// 来源 ①：从**引擎资源模块**同步取 `Configs/config`（该路径下的第一个）。
        /// <para>约定：返回 null / 空 = 本来源没有内容（引擎**静默**跳过，改试来源 ②）。</para>
        /// </summary>
        private static string ReadResourceText()
        {
            try
            {
                if (Game.Res == null)
                {
                    // 非预期分支（宿主 / 启动顺序错）：跳过本条来源，退回文件与默认值（不静默）
                    LogThrottle.WarnOnce(Tag, "cfg.res.null",
                        "Game.Res 未初始化（CloverRes.Init 未调用）⇒ 跳过资源模块，改用文件 / 默认值");
                    return null;
                }

                var all = Game.Res.LoadAll<TextAsset>(ResourceKey);
                return all != null && all.Length > 0 ? all[0].text : null;
            }
            catch (Exception e)
            {
                LogThrottle.WarnOnce(Tag, "cfg.res.read",
                    $"资源模块读取 {ResourceKey} 异常：{e.GetType().Name}: {e.Message}");
                return null;
            }
        }

        /// <summary>
        /// 来源 ②：`Application.dataPath/Configs/config.json`。
        /// <para>不存在 / 读不动 ⇒ **Warn + 返回 null**（不抛；引擎改试下一个来源）。</para>
        /// </summary>
        private static string ReadFileText()
        {
            // catch 里**不许再调 FilePath**：失败的操作在 catch 里重演一次 = 异常直接漏出去
            var path = string.Empty;
            try
            {
                path = FilePath;
                if (!File.Exists(path))
                {
                    LogThrottle.WarnOnce(Tag, "cfg.file.missing", $"未找到配置文件 {path}，使用内置默认值");
                    return null;
                }

                return File.ReadAllText(path);
            }
            catch (Exception e)
            {
                LogThrottle.WarnOnce(Tag, "cfg.file.read",
                    $"读取配置文件异常（path=\"{path}\"）：{e.GetType().Name}: {e.Message}");
                return null;
            }
        }

        /// <summary>
        /// 解析一段 json。**返回 null = 本来源不可用**（引擎改试下一个来源 / 回默认值）。
        /// </summary>
        /// <param name="json">该来源的文本。</param>
        /// <param name="from">该来源的日志标签（`Resources/...` 或磁盘路径），用于点名是哪份配置出错。</param>
        private static RootSection Parse(string json, string from)
        {
            try
            {
                var root = JsonUtility.FromJson<RootSection>(json);
                if (root == null)
                {
                    Game.Logger.Error(Tag, $"解析失败（内容为空/不是对象）：{from}");
                    return null;
                }

                // JsonUtility 对 json 里缺失的段会留 null，逐段兜底防下游空引用
                root.server ??= new ServerSection();
                root.account ??= new AccountSection();
                root.game ??= new GameSection();
                return root;
            }
            catch (Exception e)
            {
                Game.Logger.Error(Tag, $"解析异常（JSON 格式错误？）：{from} → {e.Message}");
                return null;
            }
        }
    }
}
```

**引擎件的两个约定**（照抄时别踩）：

- `ConfigSource.ReadText` 返回 `null` / 空串 / 纯空白 = **本来源没有内容**（引擎**静默**跳过，不打日志）；**抛异常** = 读取失败（引擎记一条 Warn 后改试下一个来源，⛔ **不向上抛**）；
- `ConfigSectionLoader` 的 `parse` 第二参 = 该来源的 `LogLabel`（解析错误时点名是哪份配置）；`parse` **返回 `null` = 本来源解析失败**。

**逐字段兜底 / 裁剪 / 越界告警**（原版手写加载器里那段 `ClampAndWarn`）改挂到 `ConfigSectionLoader` 的可选 `normalize` 参数上：`(root, from) => ClampAndWarn(root.server, from)` —— 它在解析成功、返回给业务之前调用一次；**它抛异常同样只 Warn 并改用下一个来源**。

**只有一个配置段的项目**：段类型只留一个 `RootSection`，来源仍按上面的两条给（跨平台需要 ①），其余一字不改。

## 3. 业务侧怎么用

```csharp
// 启动：全部从配置取
Game.Launch(new GameConfig
{
    ServerAddr = Cfg.Server.addr,
    CallTimeoutSeconds = Cfg.Server.call_timeout,
    MaxReconnectCount = Cfg.Server.max_reconnect_count,
    UseTls = Cfg.Server.tls,
});

// 账号服地址（必填，来自 config.json 的 server.auth_addr）：
// 不设则 CloverAuth.LoginAsync / SignupAsync 会抛 InvalidOperationException
CloverAuth.AuthAddr = Cfg.Server.auth_addr;

CloverNet.Init(Cfg.Server.addr,
    string.IsNullOrEmpty(Cfg.Server.udp_addr) ? null : Cfg.Server.udp_addr);
```

## 铁律

1. 业务代码里**不许**出现地址 / 端口 / 账号 / 密码 / 超时 / 重连次数等字面量 —— 一律 `Cfg.xxx`。
2. 同一项配置**只允许一处默认值** —— 唯一出处是**配置段类型里的字段初始化器**（`createDefault: () => new RootSection()` 拿到的就是它），业务里不要再写第二遍，⛔ 也不要在引擎件之外再写一份默认值。
3. 文件缺失 / 解析失败 → 回退默认值 + 打一条可定位的警告，**绝不许抛异常**（配置问题不该让游戏起不来）—— 这条由引擎件保证，项目侧的 `readText` / `parse` 也要守住（**失败返回 `null`，不抛**）。
4. 单机项目同样适用：把 `server` 段留作未使用即可，其它段照常读。
5. ⛔ **不要写名为 `Game` 的成员**（见「常见问题」）。

## 平台注意

`File.ReadAllText + Application.dataPath` 只适用于 **Editor 与桌面平台**。要出 **WebGL / Android / iOS** 时靠 §2 模板里的**来源 ①**兜住：把 `config.json` 放进某个 `Resources` 目录（路径收敛为 `Resources/Configs/config` 这个键），`Application.dataPath` 在这些平台上不可读。

## 常见问题

| 问题 | 现象 | 解法 |
|---|---|---|
| **配置类里有 `static Game` 成员，遮蔽了引擎的 `Game`** | 写 `Game.Logger.Info(...)` 编译报 `CS1061: "GameSection" 未包含 "Logger" 的定义` | 别把 game 段叫 `Game`（模板里叫 `GameCfg`）；已撞上就写全名 `CloverEngine.Game.Logger.Info(...)` |
| 引擎启动前就读配置并打日志 | `Game.Logger` 为 `null` 时直接调用会空引用；用 `?.` 则**日志被静默丢弃** | **已由引擎保证**：`Game.Logger` 现在永不为 null（未 Launch 时走写 Unity Console 的兜底实现）。配置类直接 `Game.Logger.Info(...)` 即可，**不需要**再自己加 `UnityEngine.Debug` 兜底层 |
| 用裸 `Debug.Log` 打业务日志 | 绕过引擎的日志级别与落盘 | 统一 `Game.Logger.Info/Warn/Error(tag, msg)` |
| **自己又手写了一份加载器 / 重试链** | 各工程各一套"试来源 → 回退"的控制流，行为互不一致 | 加载链用引擎 `ConfigSectionLoader<T>`；项目侧只留**段类型 + 来源/解析注入 + 薄门面** |

## 自检清单

```
□ client/Assets/Configs/config.json 存在，且 server.addr 是 TCP 口（8002，不是 8001）
□ server.auth_addr 已填（账号服地址）—— 留空则登录 / 注册必失败
□ server.tls 与服务端是否配了 gateway.tls_cert/tls_key 一致（没配证书 ⇒ false）
□ client/Assets/Scripts/Core/ClientConfig.cs 存在：**配置段类型 + ConfigSectionLoader 注入 + 薄门面**（⛔ 没有手写的加载链）
□ 全工程 grep 不到硬编码的 127.0.0.1 / 账号 / 密码 / 超时数字 / 重连次数
□ 删除 config.json 后仍能启动（回退默认值 + 警告）
```
