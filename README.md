# clover-ai-skill

Clover 引擎的 **AI 交付 skill**：把「做游戏 / 写业务代码 / 改引擎 / 配表 / 多 agent 编排 / 交付」固化成可执行的规则、范式与脚手架，供 AI 编码助手（CodeBuddy / Claude / Cursor 等）按章施工。**产出为主、不办验收** —— 只在"不确定 / 用户反复报同一条 / 交付前过一眼"时才去查。

## 从没用过 Clover？

照着 **[新手指南：用 AI 从零做一个 Clover 游戏](https://github.com/qw576483/clover-doc/blob/main/ai/ai-quick-start.md)** 走一遍即可 —— 从装 Unity 6 到让 AI 开出第一个工程，全程不用自己写代码。

用这套流程做出来的成品见 **[游戏 Demo 清单](https://github.com/qw576483/clover-doc/blob/main/ai/game-demo.md)**。

## 交流群

QQ 群：**clover-engine交流1群** `1101150552`

## 内容结构

| 路径 | 内容 |
|---|---|
| `SKILL.md` | **入口**：祈使句 + 成本意识 + 路由表，按「每轮必读」设计 |
| `reference/` | 约定与速查：`rules-full.md`（规则层案例与判据集）、`conventions.md`、`modules.md`、`client-conventions.md`、`engine-mental-model.md`、`workflow-and-standards.md`、`deterministic-gates.md`、`verify-template.md`、`server-env.md`、`unity-cli.md`、`visual-loop.md` 等 |
| `patterns/` | 可复制的范式：服务端（handler / datadef / timer / player-lookup / auth-server …）与客户端（ui / network / resource / fsm / event / timer / app-flow / entity-view …） |
| `scaffold/` | 新项目脚手架与多 agent 任务书模板（`new-project.md`、`agent-impl.md`、`project-skill.md`） |
| `experience/` | 踩坑沉淀（时间黑洞、性能排查、3D MMO 实战等） |
| `scripts/` | **10 个工具，按"什么时候用"分**（用法见 `SKILL.md` 路由表）：**干活时** `table-pipeline.ps1`（配表闭环）/ `compile-check.ps1`（离线编译）/ `play-driver.ps1`（进 Play 跑探针）/ `console-filter.py`（读 Unity 日志）；**交付 / 素材时** `pack-original-assets.ps1`（原版素材可复现打包）/ `readme-shots.ps1`（发布 README 实机图）/ `frame-order-check.py`（精灵帧序离线判）；**找真缺陷** `silent-failures.py`（空 `catch` / 吞异常 / `_ =`）；**环境** `env-check.ps1`（杀软 / 显卡软渲染 / 崩溃风暴）；**只服务本 skill** `skill-health.ps1`、`skill-lint.ps1`（改完 skill 才跑）。⛔ 没有 git hook、也不装 hook |

## 怎么用

**方式一：装到 AI 宿主的 skills 目录**（目录名用 `ai-skill`）

| 宿主 | skill 目录 |
|---|---|
| CodeBuddy | `~/.codebuddy/skills/ai-skill/` |
| Claude Code | `~/.claude/skills/ai-skill/` |
| Cursor | `~/.cursor/skills/ai-skill/` |
| 其他工具 | `<它自己的 skill 根目录>/ai-skill/` |

```bash
git clone https://github.com/qw576483/clover-ai-skill.git
# 复制或软链到上表对应目录
```

装好后，涉及 `clover-*` 仓库、Clover 工程、Unity 客户端或 Go 服务端开发的任务会自动命中该 skill。

**方式二：作为项目级 skill** —— 把内容复制到业务工程的 `tools/ai-skill/`，让 AI 优先读项目自己那份（项目特有的消息号、约定都记在那里）。

## 维护

改完 skill 后**手动**跑一次这两个检查（**⛔ 不装 git hook** —— 挡在提交路径上的检查迟早会被绕，也会拖慢每次提交）：

```bash
pwsh scripts/skill-health.ps1 -RepoRoot <另一份 skill 副本目录>   # 体积 / 路由可达 / 放宽表述 / 副本一致 / 规则层摘要
pwsh scripts/skill-lint.ps1                                       # 节引用可达 / 常量不矛盾 / label 规范
```

> `SKILL.md`（入口，摘要）与 `reference/rules-full.md`（规则层案例与判据集）是同一套规则的两个粒度 —— **改一处必须同步另一处**。

## 相关仓库

| 仓库 | 说明 |
|---|---|
| [clover-server-engine](https://github.com/qw576483/clover-server-engine) | Go 服务端引擎 |
| [clover-client-unity-engine](https://github.com/qw576483/clover-client-unity-engine) | Unity 客户端引擎（UPM 包） |
| [clover-tools](https://github.com/qw576483/clover-tools) | 打表工具等开发期工具 |
| [clover-server-tools](https://github.com/qw576483/clover-server-tools) | 运行时 / 运维工具集 |
| [clover-doc](https://github.com/qw576483/clover-doc) | 框架文档 |

## 许可证

[MIT](LICENSE)
