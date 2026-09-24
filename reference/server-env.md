# 服务器本地开发环境（windows-env）— 初始化与排障速查

> 位置：[`clover-server-tools/windows-env/`](https://github.com/qw576483/clover-server-tools/tree/main/windows-env)。开发 `clover-server-engine` 及其上层业务工程所需的 etcd / nats / redis / mysql 由 `core/env.exe`（Go 编译的 CLI）统一管理，**不要自己手工起服务**。
> 本页只在**首次初始化 / 环境出故障**时查阅。详细说明见 `windows-env/core/README.md`。

## 0. AI 开工前环境自检（强制）

**触发时机**：任何需要「起服 / 连服 / 跑通主循环」的任务，在**写第一行代码之前**先自检，不要等到交付时才发现连不上服。
**不触发**：用户明确要求「单机 / 纯本地 / 不需要服务器」的客户端任务 —— 那是需求如此，**不是环境缺失**，不做本自检，也⛔ 不许反过来劝用户装环境。判定不清时按"要联服"处理并问一句。

```bash
clover-server-tools\windows-env\core\env.exe info      # 拿状态（服务/端口/PID/组件就绪）
clover-server-tools\windows-env\core\env.exe start     # 未起则起
```

| 检查结果 | 处理 |
|---|---|
| `env.exe` 在 + etcd/nats/redis/mysql 就绪 | 继续 |
| 在但未运行 | `env.exe start` 后 `info` 复检 |
| 组件缺失（未下载） | 让用户下载（§2），AI 只做校验 / 放置 / 启动 |
| `windows-env\` 整个不存在 | 环境未安装 → **停下来问用户**，不许绕过 |

**⛔ 不许做的事（违反即交付失败）**：为了让 demo"看起来能跑"，把服务端改成单机 / 只依赖 redis、注释掉 mysql / etcd / nats；客户端加"连不上就切模拟模式 / 本地 AI 托管"的兜底；用户点名的联服玩法只做一半（"框架已预留，暂未实现"）；未经同意擅自下载或重装组件。
**环境不可用时**把情况告诉用户并让其三选一：① 装 / 起环境；② 明确同意做离线版（须在交付说明首行标注「⚠️ 离线版：联服流程未验证」，并把"联服验证"写进 `client/资源欠缺清单.md`）；③ 只交代码 + `go build` 验证，不起服。

## 1. 环境长什么样

```
windows-env/
├── core/env.exe      # 环境管理 CLI（唯一入口）
├── core/my.ini       # MySQL 基准配置（提交维护，工具只读）
├── etcd/  nats/  redis/  mysql/     # 四组件（缺失时 env.exe 打印下载地址）
└── core/logs/ core/run/             # 日志与 PID（运行后自动生成）
```

默认端口与引擎配置完全对齐：etcd 2379、nats 4222、redis 6379、mysql 3306。默认账号：mysql `root` / **空密码**；etcd / nats / redis 无密码，只监听 `127.0.0.1`。

## 2. 首次初始化

**⛔ 禁止擅自去 GitHub / dev.mysql 批量下载几百 MB**（用户已明确不做自动化下载）。标准做法：
1. 运行 `env.exe info`（或 `start`），缺失组件时它会打印**官方下载地址 + 应命名为什么**；
2. 把下载好的 Windows ZIP 解压后按名放入 `windows-env/` 同级：mysql ZIP → `mysql/`；`etcd-v*-windows-amd64.zip` → `etcd/`；`nats-server-v*-windows-amd64.zip` → `nats/`；redis msys2 ZIP → `redis/`；
3. 然后 `core/env.exe start` 启动全部；MySQL 首次会自动初始化数据目录并生成生效 `my.ini`。

> 国内网络下 GitHub 下载可能失败，可提示用户给下载链接配 ghproxy 类镜像（`https://ghfast.top/` 等）。**下载动作交给用户**，AI 负责校验、放置、启动与排障。

## 3. 常用命令（env.exe 子命令）

| 命令 | 说明 |
|------|------|
| `env.exe start [etcd\|nats\|redis\|mysql]` | 启动（缺省全部） |
| `env.exe stop / restart [name]` | 停止 / 重启 |
| `env.exe info`（别名 `status`） | 状态 + 端口 + PID + 就绪情况（**排障先跑它**） |
| `env.exe cmysql` / `mysql-cmd [-e "…"]` | MySQL 客户端（无参交互，带参直跑） |
| `env.exe credis` / `redis-cmd ping` | redis-cli（同上） |

验证：`mysql\bin\mysql.exe -uroot -e "SELECT VERSION();"`、`redis\redis-cli.exe -p 6379 ping`（PONG）、`etcd\etcdctl.exe endpoint health`、`env.exe info`。

## 4. 故障速查

| 现象 | 处理 |
|------|------|
| MySQL 启动弹控制台窗 / 关终端服务被带掉 | 用的旧版 `env.exe`；用新版（vbs 隐藏启动），重编译：`cd core && go build -o env.exe .` |
| 命令无反应 / 报错 | 进 `cmd` 手动跑 `core\env.exe info` 看完整报错（通常是组件缺失或端口被占） |
| `mysqld` 初始化失败 | 删 `mysql\data` 与根目录 `my.ini`（含 `back.*.my.ini`）后重跑 `start` 重新初始化 |
| 端口被占用 | `env.exe info` 看哪个端口被占 → 多半上次没正常停止 → `stop` 后再 `start` |
| 业务工程报 MySQL `connection refused` | `env.exe info` 确认 mysql「运行中」，再看 `core\logs\mysql.log` |
| 中文乱码 | 新版已内置 UTF-8 控制台；还乱就确认在用最新 `env.exe` |
| 想持久改 MySQL 参数 | 只改 `core/my.ini`（基准），不要只改根目录 `my.ini`（每次 start 会被基准覆盖 / 备份） |

## 5. 证书（mkcert / WebTransport）— 基本不用管

位置：[`clover-server-tools/mkcert/`](https://github.com/qw576483/clover-server-tools/blob/main/mkcert/README.md)。**日常开发不用管**；WebTransport 证书（`wt.pem`）由网关自动签发 / 轮换。出问题直接看 `mkcert/排障.md`。几条铁律：
- 证书**每台机器独立，绝不跨机器拷贝**（A 机拷到 B 机必报 `tls: unknown certificate`）。
- `server.pem` 覆盖 TCP 8002 / WS 8001 / QUIC 8003 / msg-web 3020；过期（SAN localhost/127.0.0.1/::1）重签：`.\mkcert-v1.4.4-windows-amd64.exe -install` → `-cert-file certs\server.pem -key-file certs\server-key.pem localhost 127.0.0.1 ::1` → `Copy-Item` 同步到**你的业务工程** `server/certs/`，**改完重新编译并重启网关**。
- 页面出现「回退到 WebSocket…」= WT 证书固定失效，按 `排障.md` 查；代码里 `wt_pin: true` 本地必须开。

## 6. AI 收到"环境有问题"时的处理顺序

① 先 `env.exe info` 拿状态（服务 / 端口 / PID / 组件是否就绪），别盲猜；② 再看对应 `core\logs\{etcd,nats,redis,mysql}.log`；③ 命中 §4 速查直接处理；④ 都无效再把完整报错给用户，给出 2-3 个最可能原因 + 对应命令，⛔ **不要未经同意就去重装 / 下载组件**。

## 7. 真实链路联调：用探针，别只用静态检查

**两端协议一致性光靠静态检查是不够的**（那只比「消息号数值」），它看不出帧格式、登录门禁顺序、UDP 令牌、重连绑定这类**只有真发包才暴露**的问题。

```powershell
# 1) 起服（先确认 §0 的中间件都在跑）
cd <你的业务服务端目录>
go build -o server.exe . ; .\server.exe -config configs/all/server.yaml   # 后台起，日志看 ./logs/{date}-all.log

# 2) 跑探针（脱离 Unity；链接的是真实引擎源码）
cd .codebuddy/doc-audit/tools/client-link-probe
dotnet run -c Release
```

探针覆盖：账号服 signup 换 JWT → TCP 建连 → `EMsg.Login` → `UDPBindGrant/BindUDP` → 建角 → `PushPlayerFullSync`/`PushDataSync` → 业务 Call 配对 → 全服广播推送 → **链路意外断开 → 退避重连 → `ResumeSession`** → `wss://` TLS 正向握手。

**三个必须知道的坑**：

| 坑 | 真因 | 做法 |
| --- | --- | --- |
| `Call` 一调就超时 | 收包队列只在 `NetworkManager.Tick()` 里排空，`await` 期间没人泵 Tick | **等待 Call 完成时必须并行泵** `nm.Tick()` + `Game.Dispatcher?.Flush()` |
| 想测会话恢复却测不出来 | `Disconnect()` 内部会 `_session.Clear()`，`IsResuming` 变 false ⇒ **主动断开在语义上就不该重连** | 制造**意外**断开：探针自带 `TcpProxy`，把客户端挂在代理后面，`DropClientSide()` 掐链路 |
| 收不到 `PushPlayerFullSync` | 它是「**进入游戏（有角色）**」时才下发，不是登录后 | 先走选角（建角 / 进游戏这套消息） |

### 证书与 TLS 正向握手

`mkcert/certs/server.pem` 由 mkcert 签发，其 CA **已装进系统信任链** ⇒ `wss://127.0.0.1:8001/ws` 能**在不设任何证书校验回调**的前提下握手成功 —— 这就是「TLS 正向握手」的验证方式，**不需要自己造证书**。

> 服务端 `server.yaml` 跑的是 **`tcp_tls_disabled: false`（TCP 口也走 TLS）**，客户端 `config.json` 里 `server.tls: true` 与之匹配 —— **这两个开关必须相反**，改一边不改另一边就是"连上就断"。排障时先对齐这两个值，再怀疑证书。
> TCP / WS 的 TLS 下限已放宽到 **1.2**（QUIC/WT 仍是 1.3），所以只支持 1.2 的原生 `SslStream` 也能握上手。若显式设成 `tcp_tls_disabled: true`（保留明文 TCP），服务端启动日志会打一条告警 —— 那是降级形态，不是默认。
> 另外：TCP 口**探针 / robot 工具已自动适配**（进程内首次连接判定 TLS 还是明文），不需要额外配置。

## 8. 多节点 / 发布验证 → 用 `manager`；容量 / 并发验证 → 用 `robot`

> 命令、AI 调用约定（一律 `--json`、破坏性操作用 `--yes`、**靠退出码判成败**）、以及"读报告前必须知道的坑"，统一见 **`reference/workflow-and-standards.md` §9 / §10`**（本节不重复）。
> 本章要补两条**前提**：

- **manager 的前提**：节点必须上报 admin 地址（引擎启动时把 `admin.listen_addr` 写进 `clover/nodes/<nodeID>`）。admin 默认只绑回环 ⇒ **跨机管理要把 admin 配成内网可达地址，并同时配置 `admin.token`** —— 「非回环 + 无 token」会被 `AdminConfig.Normalize` 拒绝启动，否则 `doctor` 会报 DOWN。另注意 manager 自身**不发**令牌头：被管节点一启用 token，`drain` / `shutdown` / `upstream` 会被 401 拒绝。
- **robot 的前提**：压测账号 = **前缀 + 序号**（默认 `robot_1`…），必须先 `signup` 或让 `run --signup` 自动注册。
