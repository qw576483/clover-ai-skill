# 一键复检脚本模板（`tools/verify.ps1`）

> **为什么要有这个文件**：`reference/rules-full.md` 的「收尾机械自检」 的 8 条机械自检 + `reference/rules-full.md` 的「判定权与证据契约」 的证据契约，如果只写成"规则"，
> 执行者会忘、会解释着绕过去。**做成脚本，它每次都会跑，不依赖任何人的记性。**
> **能算出来的东西，不要写成规则 —— 写成脚本。**

## 怎么用

1. 新项目开工时把下面的骨架复制成 **`<项目根>/tools/verify.ps1`**（编码用 **UTF-8 无 BOM**）。
2. 交付前跑一次：`powershell -NoProfile -ExecutionPolicy Bypass -File tools/verify.ps1`
3. **逐行读输出**，只允许三种结论：`PASS` / `FAIL` / `HUMAN-ONLY`。
   - 出现任何 `FAIL` ⇒ **不许出现"完成 / 交付 / 实测通过"字样**（见 `SKILL.md`「交付清单」的"交付前跑一次 `tools/verify.ps1`"）。
   - `HUMAN-ONLY` 是"只能由人或多模态判"的项，**必须由人过目**，不许执行者代签（见 `SKILL.md`「取证清单」的"判定权三分"与"证据必须有锚点 + 分级"）。
4. 用户**只跑这一次**，不陪执行者逐点调参。

## ⛔ 写这个脚本时的两个硬坑（必须在模板里避开）

1. **`.ps1` 必须 ASCII-only，或者存成 UTF-8 带 BOM。**
   Windows PowerShell 5.1 在没有 BOM 时按 **ANSI/GBK** 解析 `.ps1` —— 文件里的中文会被解码成乱码，
   **直接导致解析失败**（报 `Unexpected token` / `Missing closing ')'`，而错误行看起来完全是 ASCII 的，极难定位）。
   最省事的做法：**脚本正文一律 ASCII**，对外输出也用英文短语。
2. **非 ASCII 的路径不要在脚本里写字面量**（如 `策划/验收表.md`）。
   用**码点拼**，源码仍是 ASCII：
   ```powershell
   $planDir  = Join-Path $root ([string]::Concat([char]0x7B56,[char]0x5212))                       # ce hua
   $specName = ([string]::Concat([char]0x9A8C,[char]0x6536,[char]0x8868)) + '.md'                    # yan shou biao
   $refName  = ([string]::Concat([char]0x5BF9,[char]0x7167,[char]0x8868)) + '.md'                    # dui zhao biao
   ```
3. **`Select-String` 会给注释行也报命中**：要过滤 `//` / `///` / `*` 开头的行，否则规则命中数虚高。
4. **别用 `Get-Content` 不带 `-Encoding`**（会被宿主当作破坏性操作拦下）：读文本一律用
   `[System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)`。

## 实测效果（第一次跑就抓到的三类问题）

- `FAIL reference-table`：项目**从没产出过**"原版值 / 我们的值 / 差值"对照表 ⇒ 说明"照抄"这件事根本没发生过。
- `FAIL evidence-freshness`：**全部截图都比最后一次代码改动旧** ⇒ 验收表里所有"已实测"**当场作废**。
  **这一类作弊无法用规则防住，但一行 mtime 比较就能抓出来。**
- `FAIL no-escaped-artifacts`（第 13 条）：一次性产物落到了**工程外**（宿主会话产物目录 / 工作区根）——
  **工程内扫描永远看不到它**，所以这一类只能靠"**区域清单 + 工程标识**"去认（走法见第 13 条）。

## 必查项（对应 `reference/rules-full.md` 的「收尾机械自检」 八条 + `reference/rules-full.md` 的「判定权与证据契约」 契约）

| # | 查什么 | 判据 |
|---|---|---|
| 1 | 散落临时文件（`_dev` / `_assets_src` / `_assets_tmp` 下的 `*.cs`） | 计数 = 0 |
| 2 | 硬规则命中（`Debug\.Log` / `Resources\.Load` / `PlayerPrefs` / `(?<!Game\.)Input\.` / `GameObject\.Find` / `FindObjectOfType` / `Instantiate\(`） | **每条命中都能在验收表「允许的差异」里找到对应行** |
| 3 | 验收表自洽（汇总数字 vs 表体行数） | 相等 |
| 4 | 「允许的差异」每行含"为什么 / 出处 / 何时消除" | 缺任一 ⇒ FAIL |
| 5 | 路径可达（验收表里的 `路径:行`、截图路径） | 全部存在 |
| 6 | **证据新鲜度**（`reference/rules-full.md` 的「判定权与证据契约」 第 3 条）—— **按因果作废，不许一改就全废** | 每条"已实测"引用的产物 **mtime 晚于**被验证代码/资产；**作废范围 = 这次改动真能影响到的那几行**（同模块 / 同一功能链 / 同一屏），⛔ **不是"工程里任何文件一变就全量作废"**（改一行 UI 文案触发 59 张截图全量重拍，一个字的成本被放大成几十张图） |
| 6c | **mtime 类红项的"具名裁决"登记处**（`reference/rules-full.md` 的「收尾机械自检」 第 4 条：例外必须有登记处） | 第 6 项与本项（`freeze-before-capture`）这类**按 mtime 机械判**的检查，允许一条**具名裁决**：在 `.ai-tmp/test/dispatch-log.tsv` 写 `# adjudicated: <检查名> -- <理由（≥12 字）>` ⇒ 该检查降为 `HUMAN-ONLY` 并**把理由打印出来**。⛔ 理由为空/短于 12 字 ⇒ 忽略、仍然 FAIL；⛔ 不许拿它当"消红手段"—— 它只负责把"**人已经判过的假阳性**（例：只改了注释的 1 行、而行为联络图不可能因此变化；或分层改造期实现文件持续变动）"登记在案，便于复查 |
| 6b | **上一条的"范围表"必须被两个地方共用** | 本项里那张 **area/panel → 文件** 映射表（见下方骨架的 `$areaRoots` / `$panelOf`），**同时也是"重采哪些场景"的唯一数据源** | **重采工具只接受范围表算出来的场景**（`reference/rules-full.md` 的「改动回路：批次流水线」 第 6 条）；⛔ 不许出现"闸门按因果判、重采却全量跑" —— 那正是"规则一条、动作另一条"，必然被最省事的写法击败（4 个点状 bug 触发 21 个场景全量重拍） |
| 7 | 一键复检入口存在（本脚本自身） | 存在且能跑 |
| 8 | **原版对照表存在**（§2：`策划/对照表.md`） | 存在，且每行有"原版值(出处) / 我们的值 / 差值" |
| 9 | 无交接/进度类文档（`reference/rules-full.md` 的「收尾闸门」 第 8 条） | `docs/交接-*.md` / `NEXT.md` / `docs/进度*.md` 均不存在 |
| 10 | 引擎自称（`reference/rules-full.md` 的「品牌与署名」）—— **判据是"渲染出来的"，不是"源码里有没有"** | ① 源码/文档里**逐字**是 `clover-engine`；② **首页画面上**那一行是 `by clover-engine`，判据取**运行时 UI 节点树里那个标签的实际文本 + 实际字体**（或对截图做字形比对），⛔ 不是 grep 源码字符串 —— **源码里有 ≠ 画面上有、也 ≠ 画面上是这个大小写**；③ **大小写也算**：像素字体只有大写时会渲染成 `BY CLOVER-ENGINE`，那**不合规**（`reference/rules-full.md` 的「品牌与署名」 只说常量/环境变量可用全大写）；要逐字就要给它一个有小写的字体或字形 |
| 11 | **检查项的作用域 / 时间窗**（防假阳性） | 只判"**本次任务**产生的痕迹"；历史残留（很久以前的目录 / 文件 / 会话）**不计 FAIL** |
| 12 | **验收表是否标了类别**（`SKILL.md` 的「取证清单」第 9 条） | 每行都有 `数值类` / `表现类`；`表现类` 的行**能在联络图索引表里查到格号** |
| 13 | **工程外产物**（`SKILL.md` 的「派活清单」.8：一次性产物只许 `<项目根>/.ai-tmp/test/`） | **工作区根 + 宿主会话产物目录**里，"24h 内新建且名字带本工程标识"的文件数 = 0 |
| 14 | **采样器自检**（`SKILL.md` 的「取证清单」 第 5 条：跑场景**前**一秒就能查完的东西） | `.ai-tmp/**/*.ps1` 每个文件：**语法 0 错**，且 **非 ASCII 字节 = 0 或带 BOM**（无 BOM + CJK ⇒ PS 5.1 按 ANSI 解析 ⇒ `-match` 静默失效 ⇒ 白等满超时） |
| 15 | **实现由执行者产出**（`SKILL.md` 的「初始化清单」第 11 条 / `reference/rules-full.md` 的「收尾机械自检」 第 8 条） | 本次时间窗内改动的实现文件，**逐个**能在 `.ai-tmp/test/dispatch-log.tsv` 里找到派活行（文件落在该行声明的范围内 **且** 派活时间 ≤ 文件 mtime）；**对不上 ⇒ 主 agent 自己动手了**。**例外（按 §5 的"小改动"例外）**：主 agent 直接做的小改动用一行 `# direct-fix: <路径> -- <理由>; 用户原话="..."` 留痕即算通过（**⛔ 不许拿它给多文件/改数据格式/新增行为的改动洗白**） |
| 16 | **进 Play 必须记账（⛔ 不设次数上限）**（`SKILL.md` 的「交付清单」第 7 条） | `.ai-tmp/test/play-log.tsv`：**每进一次 Play 一行**（`ISO时间 / 执行者 / 片名 / 为什么必须进这条链`）。判据：① **第 4 列非空**（写不出理由 ⇒ 说明本可以用离线断言）；② 项目有实机证据但**没有账本** ⇒ FAIL（没记账 = 无从判定"为什么进"）。⛔ **本项不判"行数多不多"** —— 曾经的"行数 ≤ 预算（默认 5）"被读成了**停工的许可证**（验到第 5 次就收手、剩下不验），**已废除**：**没有 `$playBudget`、没有裁决通道、没有"用尽即停"**。**为什么改成这样**：用户的判断是"**约束完，ai 更偷懒了**" —— 次数限额省下的重复劳动，远小于"该验不验、验到一半收手"的代价 |
| 17 | **采集后冻结**（`SKILL.md` 的「取证清单」 **④**：采集即冻结，之后再改代码 ⇒ 证据作废） | **本批次证据里最早那张的 mtime = T0**，其中"本批次证据" = **最新那张联络图索引 `*.index.tsv` 引用到的 png**（无索引才退回"窗口内新增的 `Screenshots/*.png`"）；**T0 之后不许再有实现文件**（`client/Assets/Scripts/**`、引擎 `Runtime/**`）被改动。⛔ **不许**直接用"6h 窗口内最旧的新 png"当 T0 —— 它会把**历史批次**的图算进来 ⇒ **必然误报 FAIL**。违反 ⇒ FAIL 并列文件。**为什么要有它**：实测"先采证据、后修代码"会让同一批证据反复作废（同一条链被采了 3 遍），而旧版只规定"改后只重采受影响行"、**没有规定"采集必须在实现冻结之后"** |
| 18 | **证据经济性**（`SKILL.md` 的「取证清单」 T0：⛔ 不许逐行截图、不许逐项进出 Play） | 验收表 `表现类` 行数 ≥ 1 时：① **必须存在联络图索引**（`Screenshots/*.index.tsv`，格号 ↔ 行号）；② **没进任何联络图**的独立 `png` 数 ≤ `max(12, 表现类行数 × 2)`。超出 ⇒ FAIL（逐行截图嫌疑）。⛔ **被 `*.index.tsv` 引用过的 png = 联络图的组成部分**，必须从计数里排除（否则瓦片被重复计数 ⇒ **误报**，实测 65 > 46 而其实只有 32 张散图）。**为什么要有它**：把 T0 从"祈使句"变成**可算的数字** —— 否则"验收表 47 行"永远会被读成"要拍 47 张图" |
| 19 | **渲染设备不是软件渲染**（`SKILL.md` 的「初始化清单」 闸门 ②；配方 `experience/perf-triage.md`） | 读 `client/Logs/Editor.log` 里 Unity 启动时写的 `[D3D12 Device Filter] Device Name:`（或 `Renderer:`）。**命中 `Microsoft Basic Render Driver` / `Basic Display` / `WARP` ⇒ FAIL** —— 那是纯 CPU 软件光栅化，**此时任何"帧率 / 卡顿"结论都无效**（GPU 255ms/帧、3.5 fps，而业务脚本只占 1.6ms）。日志里没有这一行 ⇒ `HUMAN-ONLY`（改用手工 `SystemInfo.graphicsDeviceName`）。**为什么要有它**：2026-09-20 实测为定位"卡"跑满 6 次 Play，而根因就在第 1 条命令里；本条把"先证伪环境"从祈使句变成**能测红的一行** |
| 20 | **T0 覆盖矩阵**（`SKILL.md` T0；口径 `patterns/full-coverage-audit.md`） | 五条子判据：① `coverage-rows` = `策划/实体清单.tsv`（脚本枚举产出）行数 **==** `策划/验收表.md` 判定行数（**缺清单 ⇒ FAIL**）；② `coverage-filled` = 每行都有 `一致`/`不一致` 判定（**零空行**）；③ `coverage-diff` = `不一致` 计数 **= 0**；④ `coverage-dimensions` = **12+3 个维度代号（D1..D12/S1..S3）在清单里各出现 ≥1 次**（缺维度 = 未判）。**为什么要有它**：只要"检查过"不是一个数，工作就会退化成**症状驱动**（用户报一条修一条、没报的全漏），而**漏检没有代价** |
| 21 | **规模档位已声明**（`SKILL.md` T0；档位表 `patterns/full-coverage-audit.md` §9.5） | `策划/策划案/*.md` 顶部必须写明档位 `S`（1-way）/ `M`（2-way pairwise）/ `L`（3-way + 全状态全边界）；**判一次，只许上调**。**为什么要有它**：一个 3 天 demo 套 AAA 级全量穷举是**过杀**（NIST：2~3-way 已覆盖绝大多数缺陷）；反过来"没声明档位"就等于**默认全量**，会被执行者读成"做不完"从而整体规避 |
| 22 | **修 bug 的影响域已登记**（`SKILL.md` 的「派活清单」；口径 `patterns/full-coverage-audit.md` §9） | `.ai-tmp/test/impact-radius.tsv` 每行 ≥3 列：`维度 / 因果链 / 受影响行`；文件不存在 ⇒ `HUMAN-ONLY`（在回报里写清是"本次无 bug 修复"还是"没登记"）。**为什么要有它**：修 bug 既**不该全量扫**（成本爆炸），也**不能只修症状**（拆东墙补西墙 —— 为开门把门板从网格摘除，直接变成"该有门却没有门"）；唯一正确口径是**显式写出爆炸半径** |
| 23 | **证据锚点可解析**（`reference/anti-gaming.md` 三） | 每条判定行带 `anchor:` 指向**机器产物**；① 该文件存在；② 该位置内容**匹配该行期望值**（不是"有内容"就算过）；③ ⛔ 指向 `md` / 回报 / 代码注释 ⇒ FAIL（那等于没有锚点）。**为什么要有它**：闸门判不了"这段叙述是不是编的" —— 实测最贵的一次是连续几十次拿到「图像已省略」的占位文本，仍然逐条写出了画面描述。**产物可以是编的；指向真实运行记录第 N 行的锚点很难编**。<br>⚠️ **口径（实测校准过，⛔ 勿按字面追溯）**：只判**本次任务新增 / 改动的判定行**（**增量口径**，⛔ 不追溯历史行）；**合法锚点两类** —— ① **机器产物位置**（`文件:行` 或字段名，其内容须**匹配该行期望值**）② **原版载体引用**（原版 `.res` / `.cfg` / 原版 `.cpp` / `hud.txt` 等**仓外载体**的 `文件:行`）；⛔ 指向 `md` 叙述 / 回报 / 代码注释**不算**。**为什么要写这个口径**：实测某项目可解析锚点仅 **2 / 136**（验收行 70 + 允许的差异 64），按字面 required 会一次压出 **134 行 FAIL** —— 其中 64 行「允许的差异」本就是"**原版值对照**"性质，**根本不该有运行产物锚点**；字面执行会把一条好规则变成噪音源，进而让人学会忽略整个闸门 |
| 24 | **闸门版本同步**（`reference/anti-gaming.md` 五；脚本 `scripts/gate-sync.ps1`） | 本项目实现的检查项 **⊇** 模板 `GATE-ITEMS` 要求的清单。**为什么要有它**：模板声明了 22 项，几个项目**分别只落了 18 / 19 项且子集不同**，连名字都漂移了（`play-ledger` vs `play-budget`、`handoff-doc-found` vs `no-handoff-docs`）⇒ **规则写完了、闸门没接上，而且没人发现**。这是"谁来维护闸门"这个问题的唯一机械答案 |
| 25 | **判据防凑数**（`reference/anti-gaming.md` 二） | 覆盖矩阵的每一行必须能在某个探针输出里**按行 id 命中**；⛔ 只比行数 ⇒ 可被"把两边凑相等"通过。**为什么要有它**：第 20 项判的是**结果**（两个数字相等），而**凑相等比真的逐行检查一遍便宜太多** —— 一旦指标成为目标，它就不再是好指标 |
| 26 | **取证截图不许进 `client/Assets/`**（`SKILL.md` 的「派活清单」.8 第 6 条） | `client/Assets/Screenshots` **目录存在 ⇒ FAIL**。⛔ **不许按"`client/Assets/**` 下有 png 就 FAIL"判** —— 实测三个项目各有 1 个**正式美术** png，那样判是**假红**。**为什么要有它**：某项目 197 张取证截图落在 `client/Assets/Screenshots/`（6.4 MB），交付前才清理、并回头改了验收表 18 处引用。**已过两次自检**（真实项目基线 PASS + 注入 `Screenshots/` 后 FAIL） |

<!-- GATE-ITEMS-BEGIN -->
# name | alias | required|planned | one-line what
stray-temp-files||required|one-off .cs outside .ai-tmp/test = 0
hard-rules||required|banned API hits, each registered in the allowed-diff table
acceptance-table||required|summary row count == body row count
allowed-diff||required|every exception row carries why / provenance / when-removed
screenshot-refs||required|every png cited by the acceptance table exists
evidence-freshness||required|cited artifact newer than the code it verifies (by cause, not global)
numeric-log-only||required|numeric rows resting on a log line only => HUMAN-ONLY, never PASS
verify-entry||required|tools/verify.ps1 exists and runs
reference-table||required|original value (provenance) / ours / delta for every element
no-handoff-docs|handoff-doc-found|required|no handoff / progress / NEXT documents
engine-credit||required|credit judged on RENDERED text, not on a source grep
baseline-images||required|reference-side baseline screenshots exist
spec-doc||required|the reference spec document exists
asset-research-doc||required|asset research log exists (gate 3)
no-sync-subagents||required|dispatch only through team members (the sync channel stalls: code=10003)
row-category||required|every verdict row carries numeric / visual / performance class
no-escaped-artifacts||required|no one-off artifact outside the project
sampler-selfcheck||required|every .ai-tmp ps1 parses and is ASCII-or-BOM
impl-by-executor||required|every changed impl file reconciles with a dispatch-log row
play-ledger|play-budget|required|every Play session logged with a non-empty reason
freeze-before-capture||required|no impl file changed after the batch evidence was captured
evidence-economy||required|contact-sheet index exists; loose png count within budget
graphics-device|render-device|required|renderer is not WARP / Basic software rasterization
coverage-rows||required|entity-list rows == verdict rows (and the list exists)
coverage-filled||required|zero verdict rows without a verdict
coverage-diff||required|zero rows marked mismatch
coverage-dimensions||required|all 12+3 dimensions present in the entity list
scale-tier||required|sampling tier S/M/L declared once
impact-radius||required|bug fix blast radius registered (dim / cause chain / rows)
evidence-anchor||planned|every verdict row anchors to a machine-produced artifact position
gate-sync||planned|project gate items superset of the template's required list
coverage-hit||planned|each verdict row hit by a probe output by row id, not by row count
no-assets-screenshots||required|no forensic screenshot dir under client/Assets
<!-- GATE-ITEMS-END -->

> **这个块是机器可读的**：`scripts/gate-sync.ps1` 拿它跟项目的 `tools/verify.ps1` 对账
> （项目的检查项名从 `Say '<STATUS>' '<name>'` 里提取）。**改模板时同步改这个块**，
> 否则"模板更新了、项目没跟上"这件事**谁也发现不了** —— 那正是 19~22 项至今没落地的成因。
> 第 4 列 `planned` = 已声明但暂不强制（只打印 INFO），成熟后改成 `required` 即开始拦截。

### 第 26 项的实现（可直接抄；已过两次自检）

```powershell
# 26) no forensic screenshots inside client/Assets (SKILL.md 1.8 item 6).
#     Scope is narrow ON PURPOSE: "any png under client/Assets" would be a FALSE RED -- all
#     three measured projects carry exactly 1 legitimate art png there. Only the capture
#     directory is a violation.
#     Self-tested (anti-gaming.md section 5): baseline PASS on 3 projects, FAIL after
#     injecting client/Assets/Screenshots/shot001.png.
$assetDir  = Join-Path $root 'client\Assets'
$shotInAsm = Join-Path $assetDir 'Screenshots'
if (Test-Path $shotInAsm) {
  $n = @(Get-ChildItem $shotInAsm -Recurse -Filter *.png -File -ErrorAction SilentlyContinue).Count
  $fail++; Say 'FAIL' 'no-assets-screenshots' ("client/Assets/Screenshots exists (" + $n + " png) -- captures belong in .ai-tmp/screenshots, delete before delivery (1.8)")
} else {
  Say 'PASS' 'no-assets-screenshots' 'no forensic screenshot dir under client/Assets'
}
```

### ⛔ 反面案例：一条"看起来机械可判"的规则，实现出来会摧毁另一条规则

曾打算加一条：**「`client/Assets/**/*.cs` 里出现 `原版资源` ⇒ FAIL」**（本意是 `reference/rules-full.md` 的「原版资源」目录 第 2 条"⛔ 不许让 Unity 工程直接引用 `原版资源/`"）。
**实测 51 处命中（三个项目 18 / 23 / 10），逐条看过之后：全部是注释里的出处标注**（`/// 出处 原版资源/参考工程/...`）。

⇒ 那条检查要是上了，会：
1. **51 个假红**；
2. 更糟 —— 它会逼执行者**删掉出处标注**才能变绿，**正好摧毁 `reference/rules-full.md` 的「复刻 = 解析 + 搬运」「写不出出处的量不许进工程」的核心机制**。**一条闸门把另一条更重要的规则打死了。**

**教训（写死，别再踩）**：

- **判"代码里的路径真的被使用"，⛔ 不判"这个词出现了"** —— `//` / `///` / `<para>` 必须先过滤（与第 2 项那条「`Select-String` 会连注释一起报命中」是同源警告）。
- **新检查上线前必须回答：它会跟哪条规则抢同一个位置？** 这里"引用路径"与"标注出处"用的是**同一个字符串形状**，只能靠"是不是注释行"区分 —— 判据必须建立在这个区分上。
- **实验脚本自己也会踩编码坑**：本次收集数据时用 `[string]::Concat([char]...)` 构造中文匹配串失败 ⇒ 变成空串 ⇒ `Contains("")` **恒真** ⇒ 得出"93/93 全命中"的假数据。**结论必须用第二种写法复核**（`([char[]]@(0x539F,...) -join '')`，先打印 `Length` 自检）。

> **判据一句话**：**能机械判 ≠ 能直接判。判据上线前必须两次自检，并且问一句「它会误伤哪条规则」。**

> **第 12 条的意义**：不标类别 ⇒「哪几项必须看图」就说不清 ⇒ 执行者只能二选一：
> **全截**（N 张图逐张读，贵一个量级）或**全不截**（退回"数字对画面错"）。
> **类别是"该不该截图"的唯一判据，所以必须落在表里**，不能靠执行者临场判断。
> 联络图的做法见 `reference/visual-loop.md` 第八节。

> **第 11 条的代价**（必须写死，否则会重犯）：曾把一条"不许有某某成员会话"的检查写成
> "**工作区里存在该目录就 FAIL**"，结果把**九天前另一个任务**留下的目录报成本次违规，
> 差点据此停掉正常流程去"修"一个不存在的问题。
> 判据一句话：**检查必须限定在本次任务的时间窗 / 作用域内** ——
> **会误报的检查比没有检查更糟**（它会让人去修不存在的问题，还会让人不再相信闸门）。

> **第 13 条补的是 `reference/rules-full.md` 的「临时测试文件规范」 的盲区（必须写死）**：原来的第 1 条只在**工程内**扫几个固定目录，
> 于是"**把一次性产物写到工程外**"这条路径**没有任何检查覆盖**。
> 一次性报告被写进**宿主会话产物目录**（既不在工程里、也不在工作区里），
> **闸门当时全绿**，是用户肉眼发现的。另外"结果展示 / 产物落盘"这类宿主自带的通道，
> 也会**主动把人往工程外引** —— 所以这一条不能只靠自觉。
>
> 三条设计约束（照抄，别改）：
>
> ① **标识取自运行时的工程目录名**（再补一个"去掉通用前缀的短名"），
>    ⛔ **不写死某个具体文件名的模式** —— 自造名是无穷的，写死只抓得到上一次，下次换个名字照样漏，
>    还会假阳性（与 `reference/rules-full.md` 的「收尾机械自检」 第 2 条"引擎自称"同一个道理）；
> ② **时间窗**（24h）+ **只认"新建"**（`CreationTime`，**不看** `LastWriteTime`）——
>    否则"别人改了工作区根/宿主目录里已有的文件"会天天误报（第 11 条的教训）；
> ③ **区域清单可扩展**：宿主目录名各宿主不同，**填不出来就留空** ——
>    **留空只让检查变窄，绝不会让"工作区根"那一半失效**。
>
> **局限写在明处**：这条只能覆盖**列进清单的区域**，不是"工程外全盘扫描"；
> 真正的兜底是 **`reference/rules-full.md` 的「必然性规则不许只写在 skill 里」 第 3 条**（把高风险动作做成**专用、类型化的入口**，让 harness 有钩子可拦）。

> **第 14 条治的是"每次都要白等满超时"**（驱动脚本的错误率接近 100%，**每一轮跑场景都是从等超时开始的**）。
> 病根不在"跑得慢"，而在**跑之前那一秒没查**：
>
> - **无 BOM 的 `.ps1` 里写中文当匹配串** ⇒ PS 5.1 按 **ANSI** 解析 ⇒ 脚本照跑、`-match` 永远不成立
>   ⇒ 完成标记读不到 ⇒ **只能等满超时**（"马里奥站着不动"）。匹配串**一律码点拼**，别赌编码；
> - **裸表达式喂给 `eval`**（如 `CloverEngine.Game.IsRunning`）**编译不过**，被当成"引擎没起来"
>   ⇒ 驱动会把**好好的 Play 会话杀掉**再重进（越修越慢）。入口形状要**先验一次**（`return X;`）；
> - **超时不是完成判据**：完成只认**被测程序自己写的标记**，并按"**新增次数**"判（旧标记会骗过它）。
>
> 判据一句话：**凡是要等分钟级的东西，先在秒级把它验一遍。**

## 骨架（复制后按项目改路径）

```powershell
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$fail = 0; $human = 0

function Say([string]$status, [string]$name, [string]$detail) {
  Write-Output ("{0,-11} {1}  {2}" -f $status, $name, $detail)
}

# non-ASCII paths / words built from code points -> this file stays ASCII-only (see hard pitfall 2)
$planDir  = Join-Path $root (([char[]]@(0x7B56,0x5212) -join ''))                             # ce hua
$spec     = Join-Path $planDir ((([char[]]@(0x9A8C,0x6536,0x8868)) -join '') + '.md')         # yan shou biao
$refTable = Join-Path $planDir ((([char[]]@(0x5BF9,0x7167,0x8868)) -join '') + '.md')         # dui zhao biao
$cNumeric = ([char[]]@(0x6570,0x503C,0x7C7B) -join '')                                        # "shu zhi lei"
$cVisual  = ([char[]]@(0x8868,0x73B0,0x7C7B) -join '')                                        # "biao xian lei"
$cProg    = ([char[]]@(0x8FDB,0x5EA6) -join '')                                               # "jin du"
$cHand    = ([char[]]@(0x4EA4,0x63A5) -join '')                                               # "jiao jie"

# ---- shared: what counts as an acceptance-table BODY row ---------------------
#     id forms in use: 12 | 12-15   (plain numbers -- a "segment" is a SECTION such as
#     "## G.", not a row-id prefix; see the "A-E 段的数字键行" note further down)
#     ⛔ Define it ONCE: four checks used to carry three different versions of this regex
#        ('[A-Z]?\d+' / '(\d+|\d+-\d+)' / an indented variant), so the SAME table produced
#        different row counts depending on which check asked (measured inconsistency).
#     ⛔ Do NOT add an optional letter prefix back. '[A-Z]?\d+' also matches the dimension
#        codes (D1..D12 / S1..S3) used by the dimension table, so those rows get counted as
#        verdict rows: row-category then reports them as "rows with no class" (a FALSE RED)
#        and the row totals inflate. Measured: '| D1 | ... |' matched that pattern.
$rowIdRe = '^\s*\|\s*\d+(?:\s*-\s*\d+)?\s*\|'

# 1) 散落临时 .cs
$n = @(Get-ChildItem $root -Recurse -Filter *.cs -ErrorAction SilentlyContinue |
       Where-Object { $_.FullName -match '\\(_dev|_assets_src|_assets_tmp)\\' }).Count
if ($n -eq 0) { Say 'PASS' 'stray-temp-files' '0 命中' } else { $fail++; Say 'FAIL' 'stray-temp-files' "$n 个" }

# 2) 硬规则命中（逐条列出，供人工核对是否已登记为例外）
$pat = 'Debug\.Log','Resources\.Load','PlayerPrefs','GameObject\.Find','FindObjectOfType','Instantiate\('
$hits = @(Get-ChildItem "$root\client\Assets\Scripts" -Recurse -Filter *.cs -ErrorAction SilentlyContinue |
          Select-String -Pattern $pat -Encoding UTF8)
Say ($(if($hits.Count -eq 0){'PASS'}else{'FAIL'})) 'hard-rules' "$($hits.Count) 处（须逐条能在验收表例外清单里找到）"
if ($hits.Count -gt 0) { $hits | ForEach-Object { Write-Output ("            " + ($_.Path -replace [regex]::Escape($root),'') + ':' + $_.LineNumber) }; $fail++ }

# 3) 验收表自洽 + 每行标「类别」（第 12 条）
if (Test-Path $spec) {
  $txt = [System.IO.File]::ReadAllText($spec,[Text.Encoding]::UTF8)
  # ⛔ 别把"数到了几行"当成"表是对的"：原先是**无条件** Say 'PASS' ⇒ **0 行也过**，
  #    还把"请人工核对"写成 PASS（那是 HUMAN-ONLY，不是 PASS）。
  #    三档：0 行 ⇒ FAIL；有行 ⇒ HUMAN-ONLY（摘要数 vs 本行数是给人核的，机器判不了格式）。
  $rows = ([regex]::Matches($txt, ('(?m)' + $rowIdRe))).Count
  if ($rows -eq 0) {
    $fail++; Say 'FAIL' 'acceptance-table' 'no body row matched "| N |" -- an empty acceptance table is not a pass'
  } else {
    $human++; Say 'HUMAN-ONLY' 'acceptance-table' ('' + $rows + ' body row(s); the summary number must equal this -- compare it, never trust this line')
  }
  $noCat = @(($txt -split "`n") | Where-Object {
              $_ -match $rowIdRe -and
              -not ($_.Contains($cNumeric) -or $_.Contains($cVisual)) }).Count
  if ($noCat -eq 0) { Say 'PASS' 'row-category' '每行都标了 数值类 / 表现类' }
  else { $fail++; Say 'FAIL' 'row-category' "$noCat 行没标类别（SKILL.md 第 2 节硬性判定第 3 条）" }
  $human++
} else { $fail++; Say 'FAIL' 'acceptance-table-missing' $spec }

# 6) 证据新鲜度 -- **按行判**（`reference/rules-full.md` 的「判定权与证据契约」 第 3 条 / `reference/rules-full.md` 的「改动回路：批次流水线」 T0）
#    ⛔ 绝不要用"全工程最后一次代码改动"当基准：那样改一个 .cs 就让**全部**截图作废、逼出全量重采
#       —— 那正是"把最贵的动作重复 N 次"（`reference/rules-full.md` 的「改动回路：批次流水线」 T0 的最大时间黑洞）。
#    口径：**每行引用的图，只需晚于"该行自己所述的那份代码/资产"**。
#          解析不到实现文件的行 ⇒ HUMAN-ONLY，⛔ 不许 FAIL（会误报的检查比没有更糟）。
#    实现要点（照这个形状写）：
#      ① 取行集合（与第 12 条同一套：A–E 段的数字键行）；
#      ② 每行解析出它引用的 *.png（反引号内）+ 它所述实现文件（反引号内 `文件:行` / 类名 / `*.cs`，
#         到 client/Assets/Scripts|Editor 里按文件名或类名定位）；
#      ③ 逐 (行,图) 比 mtime；违例**只作废那一行**并逐条列出。
#    配套的 area/panel → 文件 映射表（第 6b 条）同时是"重采哪些场景"的唯一数据源。
#    ⛔⛔ 本骨架**没有**实现上面 ①②③ 的解析 ⇒ `$perRow` 到这里是 $null。
#       所以这段必须**先判空**再比：否则 `foreach ($null)` 空转、`$stale.Count -eq 0` 成立
#       ⇒ **打印 PASS**（明明是"检查没生效"，却报"逐行比对通过"，是最危险的一类假绿）。
#       写项目实现时：把 ①②③ 补齐后删掉这个 guard；没补齐就让它停在 HUMAN-ONLY。
#   ⛔ 另外：本骨架里没有定义 `Sub`（旧版最后一行写 `$stale | ForEach-Object { Sub $_ }`，
#      一有 stale 就抛 "Sub is not recognized" —— 已改为 Write-Output）。
$stale = @(); $compared = 0; $noImpl = 0; $noShot = 0
if ($null -eq $perRow) {
  Say 'HUMAN-ONLY' 'evidence-freshness' 'skeleton: row parser not implemented yet (per-row freshness cannot be computed) -- implement 1-3 or review by hand'
  $human++
} else {
foreach ($row in $perRow) {
  if (@($row.Impl).Count -eq 0) { $noImpl++; continue }
  if (@($row.Shots).Count -eq 0) { $noShot++; continue }
  foreach ($s in $row.Shots) {
    $compared++
    if ($s.LastWriteTime -lt $row.ImplMtime) {
      $stale += ("row " + $row.Id + ": " + $s.Name + " 早于该行实现文件 " + $row.Impl)
    }
  }
}
#    ⛔ 0 个 (行,图) 对也不许 PASS —— 与上面 $null 同理：那是"没比到"，不是"都过"。
if ($compared -eq 0 -and $stale.Count -eq 0) {
  Say 'HUMAN-ONLY' 'evidence-freshness' 'no (row,shot) pair could be compared -- an empty result must never PASS'
  $human++
} elseif ($stale.Count -eq 0) {
  Say 'PASS' 'evidence-freshness' "$compared 个 (行,图) 对逐行比对通过；$noImpl 行解析不到实现文件 / $noShot 行无截图 ⇒ HUMAN-ONLY"
  $human++
} else {
  $fail++; Say 'FAIL' 'evidence-freshness' "$($stale.Count) 个 (行,图) 对过期 ⇒ **只作废那几行**，其余仍然有效"
  $stale | ForEach-Object { Write-Output ('            ' + $_) }
}
}

# 8) 原版对照表
if (Test-Path $refTable) { Say 'PASS' 'reference-table' $refTable }
else { $fail++; Say 'FAIL' 'reference-table-missing' 'section 2 requires it' }

# 9) 交接/进度类文档（用 glob 匹配，别只查固定名——`docs/进度-第二棒.md` 这类会漏）
$bad = @(Get-ChildItem $root -Recurse -Filter *.md -File -ErrorAction SilentlyContinue |
         Where-Object { $_.FullName -notmatch '\\Library\\' } |
         Where-Object { $_.Name -like 'NEXT*' -or $_.Name.Contains($cProg) -or $_.Name.Contains($cHand) } |
         ForEach-Object { $_.Name })
if ($bad.Count -eq 0) { Say 'PASS' 'no-handoff-docs' '' } else { $fail++; Say 'FAIL' 'handoff-doc-found' ($bad -join ', ') }

# 13) 工程外产物（`reference/rules-full.md` 的「临时测试文件规范」）：一次性产物只许 <项目根>/.ai-tmp/test/
$wsRoot = Split-Path $root -Parent
$rootName = Split-Path $root -Leaf
$projTokens = @($rootName)
if ($rootName.StartsWith('clover-project-')) { $projTokens += $rootName.Substring(15) }   # 短名（按你项目的命名改）
$brainZones = @()                                                                        # 宿主产物目录：填不出来就留空
if ($env:APPDATA) {
  $brainZones = @(Get-ChildItem (Join-Path $env:APPDATA '*\User\globalStorage\*\brain') -Directory -ErrorAction SilentlyContinue |
                  ForEach-Object { $_.FullName })
}
$escCut = (Get-Date).AddHours(-24)
$esc = @()
foreach ($t in $projTokens) {
  $esc += @(Get-ChildItem $wsRoot -File -Filter ("*" + $t + "*") -ErrorAction SilentlyContinue |
            Where-Object { $_.CreationTime -gt $escCut })
  foreach ($z in $brainZones) {
    $esc += @(Get-ChildItem $z -Recurse -File -Filter ("*" + $t + "*") -ErrorAction SilentlyContinue |
              Where-Object { $_.CreationTime -gt $escCut })
  }
}
$esc = @($esc | Sort-Object FullName -Unique)
if ($esc.Count -eq 0) { Say 'PASS' 'no-escaped-artifacts' "0 命中（工作区根 + $($brainZones.Count) 个宿主产物目录）" }
else {
  $fail++; Say 'FAIL' 'no-escaped-artifacts' "$($esc.Count) 个本工程文件落在工程外 ⇒ 挪进 .ai-tmp/test/（`reference/rules-full.md` 的「临时测试文件规范」）"
  $esc | ForEach-Object { Write-Output ('            ' + $_.FullName) }
}

# 14) 采样器自检（`reference/rules-full.md` 的「改动回路：批次流水线」 第 5 条）：.ai-tmp 下的驱动脚本 —— 语法 0 错，且"无 BOM 不许含非 ASCII"
$tmpRoot = Join-Path $root '.ai-tmp'
$badPs = @()
if (Test-Path $tmpRoot) {
  foreach ($f in @(Get-ChildItem $tmpRoot -Recurse -Filter *.ps1 -File -ErrorAction SilentlyContinue)) {
    $b = [System.IO.File]::ReadAllBytes($f.FullName)
    $bom = ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
    $nonAscii = @($b | Where-Object { $_ -gt 127 }).Count
    if ((-not $bom) -and $nonAscii -gt 0) { $badPs += ($f.Name + " (ANSI trap: non-ASCII without BOM)") }
    $enc = [System.Text.Encoding]::UTF8
    if (-not $bom) { $enc = [System.Text.Encoding]::Default }     # parse it the way PS 5.1 will
    $text = $enc.GetString($b)
    if ($bom) { $text = $text.TrimStart([char]0xFEFF) }
    $psk = $null; $per = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$psk, [ref]$per)
    if (@($per).Count -gt 0) { $badPs += ($f.Name + " (" + @($per).Count + " syntax error)") }
  }
}
if ($badPs.Count -eq 0) { Say 'PASS' 'sampler-selfcheck' 'scripts under .ai-tmp: syntax OK, no ANSI trap' }
else { $fail++; Say 'FAIL' 'sampler-selfcheck' ($badPs -join '; ') }

# 15) 实现必须由执行者产出（§5 开工闸门 / `reference/rules-full.md` 的「收尾机械自检」 第 8 条）：拿派活留痕对账。
#     为什么要这一条：主 agent 自己写实现 ⇒ 把宿主的"单任务模型请求上限"打满
#     （本机实测 500）⇒ 任务在做到一半时被强制暂停、手里只剩半成品。
#     规则层早就写了"主 agent 不做实现"，但没挂在动作入口上 ⇒ 违反它不留痕迹。
#     本条把"派活"变成必须留痕的产物，再和"近期被改动的实现文件"对账。
#     判据：每个实现文件都能对上一条派活行（文件在派活声明的范围内 && 派活行的时间窗覆盖该文件）。
#     ⛔ 别把这条做成"扫全部源码"：只扫本次任务时间窗内的改动，否则会把历史文件全报成违规（会误报的检查比没有更糟）。
#     两条必要的宽容（否则会误报，都踩过）：
#       · 一行派活**只在它自己的时间窗内有效** [本行时间, 下一行时间) —— 否则一条时间早、范围宽的行
#         会把之后所有改动都"追认"掉，检查形同虚设；
#       · 允许两种**具名留痕**：`# adjudicated: <路径>`（任务书漏授权的载体文件，主 agent 具名裁定）
#         与 `# direct-fix: <路径>`（§5 的"小改动"例外：单文件、≤20 行、不新增行为/不改格式，
#         用户明说的点状缺陷 —— 主 agent 直接做，写一行理由即可，**不要求派活行**）。
#         ⛔ 这两种都是"把写入变可见"，不是洗白通道：多文件 / 改数据格式 / 新增行为一律回去派活。
$logPath = Join-Path $root '.ai-tmp/test/dispatch-log.tsv'
# ⛔ **不要用 `**` 当递归**：PowerShell 的 -Path 只认 `*` / `?`（**单层**），
#    `'client/Assets/Scripts/**/*.cs'` 实际等价于 `'Scripts/*/*.cs'`
#    ⇒ **孙目录及更深的实现文件全部漏对账**（本项因此形同虚设）。
#    递归只有一条路：`-Recurse` + 扩展名白名单。
$implDirs = @('client/Assets/Scripts', 'client/Assets/Resources/Levels', '策划')
$implExt  = @('.cs', '.txt', '.csv', '.xlsx')
$implCut = (Get-Date).AddHours(-24)
$implFiles = @()
foreach ($r in $implDirs) {
  $p = Join-Path $root $r
  if (-not (Test-Path $p)) { continue }
  $implFiles += @(Get-ChildItem $p -Recurse -File -ErrorAction SilentlyContinue |
                  Where-Object { $_.LastWriteTime -gt $implCut -and $implExt -contains $_.Extension })
}
$implFiles = @($implFiles | Sort-Object FullName -Unique)
$dispatched = @(); $named = @()
if (Test-Path $logPath) {
  foreach ($line in @(Get-Content $logPath -ErrorAction SilentlyContinue)) {
    if ($line -match '^\s*#') {
      if ($line -match '^\s*#\s*(?:adjudicated|direct-fix):\s*([^\s]+)') { $named += $Matches[1].Replace('\', '/') }
      continue
    }
    if ($line.Trim().Length -eq 0) { continue }
    $c = $line -split "`t"
    if ($c.Count -ge 4) { $dispatched += [pscustomobject]@{ At = [datetime]$c[0]; By = $c[1]; Task = $c[2]; Scope = $c[3] } }
  }
}
$dispatched = @($dispatched | Sort-Object At)
for ($i = 0; $i -lt $dispatched.Count; $i++) {
  $until = if ($i + 1 -lt $dispatched.Count) { $dispatched[$i + 1].At } else { [datetime]'9999-01-01' }
  $dispatched[$i] | Add-Member -NotePropertyName Until -NotePropertyValue $until -Force
}
$orphan = @()
foreach ($f in $implFiles) {
  $rel = $f.FullName.Substring($root.Length).TrimStart('\', '/').Replace('\', '/')
  if ($named -contains $rel) { continue }
  $hit = @($dispatched | Where-Object {
      $scopes = @($_.Scope -split '[,;]') | ForEach-Object { $_.Trim().Replace('\', '/') } | Where-Object { $_.Length -gt 0 }
      $inScope = @($scopes | Where-Object { $rel -like ($_ + '*') }).Count -gt 0
      $inScope -and ($_.At -le $f.LastWriteTime) -and ($f.LastWriteTime -lt $_.Until)
    })
  if ($hit.Count -eq 0) { $orphan += $rel }
}
if ($implFiles.Count -eq 0) { Say 'HUMAN-ONLY' 'impl-by-executor' '本次时间窗内没有实现文件改动（无可对账）' }
elseif ($orphan.Count -eq 0) { Say 'PASS' 'impl-by-executor' "$($implFiles.Count) 个实现文件全部能对上派活留痕" }
else {
  $fail++; Say 'FAIL' 'impl-by-executor' "$($orphan.Count)/$($implFiles.Count) 个实现文件没有派活留痕 ⇒ 主 agent 自己动手了（§5 开工闸门）"
  $orphan | ForEach-Object { Write-Output ('            ' + $_) }
}

# 16) play-ledger -- SKILL 2 / 0.1: every editor_play must be on the ledger WITH A REASON.
#     NO count budget: a session cap was read as a licence to stop early (SKILL 0.1).
#     Keep going until the acceptance table is full; "count reached" is never a reason to stop.
$playLog    = Join-Path $root '.ai-tmp\test\play-log.tsv'
$playRows   = @()
if (Test-Path $playLog) {
  foreach ($line in @([System.IO.File]::ReadAllLines($playLog, [Text.Encoding]::UTF8))) {
    if ($line -match '^\s*#' -or $line.Trim().Length -eq 0) { continue }
    $c = $line -split "`t"
    $why = if ($c.Count -ge 4) { [string]$c[3] } else { '' }
    $playRows += [pscustomobject]@{ At = $c[0]; Task = $(if ($c.Count -ge 3) { [string]$c[2] } else { '' }); Why = $why }
  }
}
if (-not (Test-Path $playLog)) {
  Say 'HUMAN-ONLY' 'play-ledger' ('no ' + $playLog + ' -- keep one line per editor_play (time / who / slice / reason)')
} elseif (@($playRows | Where-Object { $_.Why.Trim().Length -lt 4 }).Count -gt 0) {
  $fail++; Say 'FAIL' 'play-ledger' 'some play-log row has no reason in column 4 -- write the reason, not another session'
} else {
  Say 'PASS' 'play-ledger' ('play sessions = ' + $playRows.Count + ', every row has a reason (no budget: keep going until the table is full)')
}

# 17) freeze-before-capture -- SKILL 1.13 beat 4: no impl file may change AFTER the first evidence capture
#    ⛔ 截图目录 = `<项目根>/.ai-tmp/screenshots/`（SKILL 1.8 / 8 / game-delivery 9.5 第 5 条：
#       取证截图是一次性产物，**不许进 `client/Assets/**`**）。
#       旧版本骨架把这里写成 `client\Assets\Screenshots` —— 与规则层**冲突**，抄模板的人会
#       把"违规目录"当标准证据目录用（某项目 197 张落进 Assets = 6.4 MB，交付前才清理）。
$shotsDir  = Join-Path $root '.ai-tmp\screenshots'
$winHours  = 6
$win       = (Get-Date).AddHours(-$winHours)
$newShots  = @(Get-ChildItem $shotsDir -Filter *.png -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt $win })
$implRoots = @('client\Assets\Scripts')
$engRoot   = Join-Path (Split-Path $root -Parent) 'clover-client-unity-engine\Runtime'   # '' when the project has no engine repo
if ($newShots.Count -eq 0) {
  Say 'HUMAN-ONLY' 'freeze-before-capture' ('no new evidence png within ' + $winHours + 'h')
} else {
  $t0    = ($newShots | Sort-Object LastWriteTime | Select-Object -First 1).LastWriteTime
  $after = @()
  foreach ($r in $implRoots) {
    $p = Join-Path $root $r
    if (Test-Path $p) { $after += @(Get-ChildItem $p -Recurse -Filter *.cs -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt $t0 }) }
  }
  if ($engRoot -ne '' -and (Test-Path $engRoot)) { $after += @(Get-ChildItem $engRoot -Recurse -Filter *.cs -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt $t0 }) }
  $after = @($after | Sort-Object FullName -Unique)
  if ($after.Count -eq 0) {
    Say 'PASS' 'freeze-before-capture' ('no impl file touched after capture start ' + $t0.ToString('MM-dd HH:mm:ss'))
  } else {
    $fail++; Say 'FAIL' 'freeze-before-capture' ('' + $after.Count + ' impl file(s) changed AFTER capture start ' + $t0.ToString('MM-dd HH:mm:ss') + ' => the captured evidence is stale')
    $after | Select-Object -First 5 | ForEach-Object { Write-Output ('            ' + $_.FullName.Substring($root.Length).TrimStart('\','/')) }
  }
}

# 18) evidence-economy -- SKILL 1.13 T0: visual rows live in ONE contact sheet; one png per row is a violation
$specTxt2 = if (Test-Path $spec) { [System.IO.File]::ReadAllText($spec, [Text.Encoding]::UTF8) } else { $null }
if ($specTxt2 -eq $null) {
  Say 'HUMAN-ONLY' 'evidence-economy' 'acceptance table not found'
} else {
  $visRows = @(($specTxt2 -split "`n") | Where-Object { $_ -match $rowIdRe -and $_.Contains($cVisual) })
  $cells   = 0
  foreach ($f in @(Get-ChildItem $shotsDir -Filter '*.index.tsv' -ErrorAction SilentlyContinue)) {
    $cells += @([System.IO.File]::ReadAllLines($f.FullName, [Text.Encoding]::UTF8) | Where-Object { $_.Trim().Length -gt 0 -and $_ -notmatch '^\s*#' }).Count
  }
  if ($visRows.Count -eq 0) {
    Say 'HUMAN-ONLY' 'evidence-economy' 'no visual-class row in the acceptance table'
  } elseif ($cells -eq 0) {
    $fail++; Say 'FAIL' 'evidence-economy' ('' + $visRows.Count + ' visual row(s) but no contact-sheet index (*.index.tsv)')
  } elseif ($newShots.Count -gt [Math]::Max(12, $visRows.Count * 2)) {
    $fail++; Say 'FAIL' 'evidence-economy' ('new png = ' + $newShots.Count + ' for ' + $visRows.Count + ' visual row(s) => per-row screenshotting (T0 forbids)')
  } else {
    Say 'PASS' 'evidence-economy' ('visual rows = ' + $visRows.Count + ', sheet cells = ' + $cells + ', new png = ' + $newShots.Count)
  }
}

# 19) graphics-device -- SKILL 6 gate 2: WARP software rendering voids every frame-time number
$editorLog = Join-Path $root 'client\Logs\Editor.log'
if (-not (Test-Path $editorLog)) {
  Say 'HUMAN-ONLY' 'graphics-device' 'no client/Logs/Editor.log -- run SystemInfo.graphicsDeviceName by hand'
} else {
  $devLine = @(Select-String -Path $editorLog -Pattern 'Device Name:\s*(.+)$' -ErrorAction SilentlyContinue | Select-Object -First 1)
  if ($devLine.Count -eq 0) {
    Say 'HUMAN-ONLY' 'graphics-device' 'no "D3D12 Device Filter" line in Editor.log'
  } else {
    $dev = $devLine[0].Matches[0].Groups[1].Value.Trim()
    if ($dev -match 'Basic Render Driver|Basic Display|WARP') {
      $fail++; Say 'FAIL' 'graphics-device' ('render device = "' + $dev + '" => software rendering; frame-time numbers are void (SKILL 6 gate 2)')
    } else {
      Say 'PASS' 'graphics-device' ('render device = ' + $dev)
    }
  }
}

# 20) coverage-matrix -- SKILL T0: "checked" must be a NUMBER.
#     entity-list rows == acceptance verdict rows; zero blank verdicts; zero "mismatch";
#     and every one of the 12+3 dimensions must appear at least once.
#     Why: symptom-driven work (fix only what the user reported) leaves the rest unjudged,
#     and an unjudged row has no cost. This item is what gives it a cost.
$cListName = ([char[]]@(0x5B9E,0x4F53,0x6E05,0x5355) -join '') + '.tsv'          # "shi ti qing dan" = entity list
$cList     = Join-Path $planDir $cListName
$cAgree    = ([char[]]@(0x4E00,0x81F4) -join '')                                 # "yi zhi"     = consistent
$cDiff     = ([char[]]@(0x4E0D,0x4E00,0x81F4) -join '')                          # "bu yi zhi"  = mismatch
#   ⛔ 别漏 0x4E00（yi）：少了它就是「不致」而不是「不一致」⇒ .Contains() 永远不成立
#      ⇒ coverage-diff 永远 PASS（**假绿**，比不检查更糟）。某项目照抄时中过这一枪。
#   ⛔ 判定行的取法：**只取覆盖矩阵那一段**（`## G.` / `<!-- COVERAGE-BEGIN..END -->` 标记区内），
#      ⛔ 不许拿"全文件所有数字键行"当判定行数 —— 那会把「允许的差异」表、自检汇总表一起算进来，
#      于是 coverage-rows 的等式（清单行数 == 判定行数）永远不成立或永远凑巧成立。
$dims      = @()
1..12 | ForEach-Object { $dims += ('D' + $_) }
1..3  | ForEach-Object { $dims += ('S' + $_) }
if (-not (Test-Path $cList)) {
  $fail++; Say 'FAIL' 'coverage-rows' 'missing entity list (plan/entity-list.tsv) -- enumerate it with tools/probes/enumerate-*.py, never by hand (T0)'
} else {
  $listRows = @([System.IO.File]::ReadAllLines($cList, [Text.Encoding]::UTF8) |
                Where-Object { $_.Trim().Length -gt 0 -and $_ -notmatch '^\s*#' }).Count
  $specRows = 0; $blank = 0; $diffN = 0
  if (Test-Path $spec) {
    # ⛔ Scope matters here (see the warning right above this check): the verdict rows live
    #    in ONE section. If the table carries COVERAGE-BEGIN/END markers, take only that
    #    slice -- a whole-file sweep also counts the allowed-diff and the summary tables,
    #    which is exactly how "rows == entity list" ends up impossible or accidentally true.
    $covTxt = [System.IO.File]::ReadAllText($spec, [Text.Encoding]::UTF8)
    $covSeg = [regex]::Match($covTxt, '(?s)<!--\s*COVERAGE-BEGIN\s*-->(.*?)<!--\s*COVERAGE-END\s*-->')
    if ($covSeg.Success) {
      $vt = @(($covSeg.Groups[1].Value -split "`n") | Where-Object { $_ -match $rowIdRe })
    } else {
      $vt = @([System.IO.File]::ReadAllLines($spec, [Text.Encoding]::UTF8) | Where-Object { $_ -match $rowIdRe })
      $human++
      Say 'HUMAN-ONLY' 'coverage-scope' 'no COVERAGE-BEGIN/END marker -- whole file scanned; the row count may include other tables'
    }
    $specRows = $vt.Count
    $blank    = @($vt | Where-Object { -not ($_.Contains($cAgree)) -and -not ($_.Contains($cDiff)) }).Count
    $diffN    = @($vt | Where-Object { $_.Contains($cDiff) }).Count
  }
  if ($specRows -eq 0) {
    $fail++; Say 'FAIL' 'coverage-rows' 'no verdict rows in the acceptance table'
  } elseif ($listRows -ne $specRows) {
    $fail++; Say 'FAIL' 'coverage-rows' ("entity rows = " + $listRows + " vs verdict rows = " + $specRows + " -> rows were skipped (T0)")
  } else {
    Say 'PASS' 'coverage-rows' ("entity rows == verdict rows (" + $listRows + ")")
  }
  if ($blank -gt 0) { $fail++; Say 'FAIL' 'coverage-filled' ("" + $blank + " verdict row(s) with no consistent/mismatch verdict") }
  elseif ($specRows -gt 0) { Say 'PASS' 'coverage-filled' 'every verdict row carries a verdict' }
  if ($diffN -gt 0) { $fail++; Say 'FAIL' 'coverage-diff' ("" + $diffN + " row(s) marked mismatch -> not deliverable (T0)") }
  elseif ($specRows -gt 0) { Say 'PASS' 'coverage-diff' 'zero mismatch' }
  $listTxt  = [System.IO.File]::ReadAllText($cList, [Text.Encoding]::UTF8)
  $missDim  = @($dims | Where-Object { $listTxt -notmatch ('\b' + $_ + '\b') })
  if ($missDim.Count -gt 0) { $fail++; Say 'FAIL' 'coverage-dimensions' ('missing dimension(s): ' + ($missDim -join ',')) }
  else { Say 'PASS' 'coverage-dimensions' 'all 12+3 dimensions present' }
}

# 21) scale-tier -- SKILL T0: sampling density is declared ONCE (S=1-way / M=2-way / L=3-way),
#     only ever upgraded, never downgraded to save time.
$cTier    = ([char[]]@(0x6863,0x4F4D) -join '')                                   # "dang wei"
$specDir  = Join-Path $planDir (([char[]]@(0x7B56,0x5212,0x6848) -join ''))       # "ce hua an"
$tierRx   = '\b(S|M|L)\s*(' + $cTier.Substring(0,1) + '|tier)'
$tierHit  = @()
if (Test-Path $specDir) {
  foreach ($f in @(Get-ChildItem $specDir -Filter *.md -File -ErrorAction SilentlyContinue)) {
    $tx = [System.IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
    if ($tx.Contains($cTier) -and ($tx -match $tierRx)) { $tierHit += $f.Name }
  }
}
if ($tierHit.Count -gt 0) { Say 'PASS' 'scale-tier' ('declared in ' + ($tierHit -join ',')) }
else { $fail++; Say 'FAIL' 'scale-tier' 'no tier (S/M/L) declared under plan/ce-hua-an/*.md -- declare once, never downgrade (T0)' }

# 22) impact-radius -- SKILL 1 / coverage-audit 9: a BUG FIX must enumerate its blast radius
#     (dimension / cause chain / affected rows). Fixing only the reported symptom = two steps
#     forward, one back (measured: patching a door mesh removed the door entirely).
$irPath = Join-Path $root '.ai-tmp/test/impact-radius.tsv'
if (-not (Test-Path $irPath)) {
  Say 'HUMAN-ONLY' 'impact-radius' 'no .ai-tmp/test/impact-radius.tsv -- for a bug fix, list the blast radius (dim / cause chain / affected rows)'
} else {
  $irBad = @([System.IO.File]::ReadAllLines($irPath, [Text.Encoding]::UTF8) |
             Where-Object { $_.Trim().Length -gt 0 -and $_ -notmatch '^\s*#' } |
             Where-Object { ($_ -split "`t").Count -lt 3 })
  if ($irBad.Count -eq 0) { Say 'PASS' 'impact-radius' 'every row lists dim / cause chain / affected rows' }
  else { $fail++; Say 'FAIL' 'impact-radius' ("" + $irBad.Count + " row(s) missing columns (dim / cause chain / affected rows)") }
}

Write-Output ''
Write-Output "===== 汇总：FAIL=$fail  HUMAN-ONLY=$human ====="
if ($fail -gt 0) { Write-Output 'FAIL 存在 ⇒ 不许说"完成 / 交付 / 实测通过"' }
exit $(if ($fail -gt 0) { 1 } else { 0 })
```

## 必须留在人手里的项（脚本永远代替不了）

脚本只覆盖"能算的"。下面这些**必须人（或真的能收到图像的执行者）过目**，脚本只能列成 `HUMAN-ONLY`：

- **外观是否 1:1**：同机位并排图逐元素比（`reference/rules-full.md` 的「判定权与证据契约」 第 7 条）
- **手感 / 动画连贯 / 节奏 / 音效时机**：时间序列，只能逐帧看或由人给基线
- **对照表里的"原版值"是否真的是原版值**（出处是否成立）—— 抽查即可，但不能不查
- **对照表的覆盖面是否够**（有没有整块元素根本没进表）
