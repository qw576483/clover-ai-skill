# REA 安装与自检（逆向取证的前置）

> **REA = Reverse Engineering Anything**：一个本地 MCP 服务 + CLI，把反汇编 / 反编译 / 抓包 / APK / JS 等逆向能力接给 AI。
> **适用**：任何"要看懂原版程序"的活（1:1 复刻、协议分析、二进制取证）。
> **铁律**：没装 ⇒ **先装上再干活**；装不上 ⇒ 记为阻塞项（写清缺什么），⛔ 不许凭印象假装逆过。

---

## 1. 先查是否已装（10 秒）

```bash
rea --version          # 有版本号 = CLI 就绪
rea mcp doctor         # healthy: true 且 tools 数量 = expected，才算 MCP 就绪
```
- 两条都过 ⇒ 直接用，跳到 §4。
- 只有 CLI 没有 MCP ⇒ 走 §3 注册。
- 都没有 ⇒ 走 §2 安装。

---

## 2. 安装 CLI（Windows / macOS / Linux 同）

```bash
node -v                       # 需要 22.19+ / 24.11+ / 26+
npm install --global rea-agents
rea --version
```

---

## 3. 把 REA 注册成 MCP（按宿主选一条）

| 宿主 | 做法 |
|---|---|
| Claude Code / Cursor / Codex / Gemini CLI 等有官方支持的 | `npx rea-agents@latest setup`（交互式，会备份原配置） |
| 其它宿主（含 CodeBuddy / 自研客户端） | 手写用户级 MCP 配置，见下 |

**手写配置（stdio 方式）**：
```json
{
  "mcpServers": {
    "rea": {
      "type": "stdio",
      "command": "/absolute/path/to/node",
      "args": ["/absolute/path/to/npm/node_modules/rea-agents/scripts/rea.mjs", "mcp"],
      "description": "REA reverse-engineering MCP server"
    }
  }
}
```
- **用绝对路径**：宿主子进程的 PATH 常与你终端不同；`command` 一律写 `node` 的绝对路径。
- Windows 下 npm 全局包在 `%APPDATA%\npm\node_modules\rea-agents`。
- 配置目录（用户级）：CodeBuddy `~/.codebuddy/mcp.json`；Cursor `~/.cursor/mcp.json`；Claude Code `~/.claude.json`。
- 改完**重启宿主**，在 MCP 面板看到绿点 / `healthy: true` 才算成。

顺带把 REA 自带的 skill 复制进宿主 skills 目录（可选但推荐）：
```bash
cp -r <npm-global>/node_modules/rea-agents/skills/reverse-engineer-anything ~/.codebuddy/skills/
```

---

## 4. 装好之后怎么用（分工）

| 取证对象 | 用谁 |
|---|---|
| 原生二进制（exe / .so / mach-o）：函数、符号、xref、伪代码 | **REA**（`inspect-binary-layout`、`decompile`、`xrefs`） |
| Electron / JS 打包应用、Web 前端 | **REA**（`analyze-javascript-application`、`recover-javascript-sources`） |
| Android APK / 设备 | **REA**（`inspect-android-package`、adb 系列） |
| 网络协议（抓包） | **REA**（`inspect-pcap-capture`、`inspect-packet-capture`） |
| .NET / Flutter / 固件 / WASM | **REA**（各自对应命令） |
| **游戏资源容器**（CASC / MPQ / PAK / ADT / M2 / WMO / DB2 表） | **自建脚本**（`patterns/reverse-engineering.md`），REA 不管容器格式 |

⚠️ **平台限制**：REA 的原生布局分析在 Windows 上部分能力不可用（Linux x64 专属）；Ghidra 在 Windows 属实验性 ⇒ 需要反汇编时先 `rea inspect-binary-layout` 试一次，报 `capability_unavailable` 就改走 Ghidra/IDA 或只做字符串/结构取证，⛔ 别声称"逆了逻辑"。

---

## 5. 判据（三条全过才算"逆向环境就绪"）

1. `rea --version` 有输出；
2. `rea mcp doctor` → `healthy: true`，tools `expected == observed`；
3. 宿主重启后能看到 `rea` 的工具（随便调一个 target-free 的命令，如 `binary_session`，返回正常）。

缺任一条 ⇒ 环境未就绪，⛔ 不许开始"猜结构"的活。

---

## 6. 常见坑

| 现象 | 原因 / 处理 |
|---|---|
| `npx rea-agents` 装完仍 `rea: command not found` | 全局 bin 目录不在 PATH；用绝对路径调 `node .../rea.mjs` |
| 宿主里 MCP 红点 | 配置里用了相对路径 / 用了 `npx` 而宿主没有网络；改绝对 node 路径并重启 |
| `doctor` 报 tools 数量对不上 | 版本与宿主缓存不一致：`rea update` 后重启宿主 |
| 原生分析报 `unsupported_provider` | 平台不支持（见 §4 限制），换 Ghidra/IDA |
| 一开 MCP 面板就卡 | REA 工具数量多（200+），首次加载慢属正常；面板卡不影响调用 |
