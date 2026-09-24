# 一键复检脚本模板（`tools/verify.ps1`）

> **为什么要有这个文件**：「收尾机械自检」8 条 + 证据契约如果只写成规则，执行者会忘、会解释着绕过去。**做成脚本，它每次都会跑，不依赖任何人的记性。能算出来的东西，不要写成规则 —— 写成脚本。**

## 怎么用

1. 新项目开工时把下面的骨架复制成 **`<项目根>/tools/verify.ps1`**。
2. 交付前跑一次：`powershell -NoProfile -ExecutionPolicy Bypass -File tools/verify.ps1`
3. **逐行读输出**，只允许三种结论：`PASS` / `FAIL` / `HUMAN-ONLY`。
   - 出现任何 `FAIL` ⇒ ⛔ 不许出现"完成 / 交付 / 实测通过"字样。
   - `HUMAN-ONLY` = "只能由人或多模态判"的项，**必须由人过目**，不许执行者代签。
4. 用户**只跑这一次**，不陪执行者逐点调参。

## ⛔ 写这个脚本时的四个硬坑（模板里已避开）

1. **`.ps1` 必须 ASCII-only，或者存成 UTF-8 带 BOM。** PS 5.1 在没有 BOM 时按 **ANSI/GBK** 解析 —— 中文被解成乱码 ⇒ **直接解析失败**（报 `Unexpected token` / `Missing closing ')'`，而报错行看起来完全是 ASCII，极难定位）。最省事：**脚本正文一律 ASCII**，输出也用英文短语。
2. **非 ASCII 的路径不要写字面量**（如 `策划/验收表.md`），用**码点拼**（见骨架里的 `([char[]]@(0x7B56,0x5212) -join '')`）。⛔ 坑中坑：用 `[string]::Concat([char]...)` 构造中文串曾失败 ⇒ 变成空串 ⇒ `Contains("")` **恒真** ⇒ 得出"93/93 全命中"的假数据。**结论必须用第二种写法复核**，并先打印 `Length` 自检。
3. **`Select-String` 会给注释行也报命中**：要过滤 `//` / `///` / `*` 开头的行，否则命中数虚高。
4. ⛔ **别用 `Get-Content` 不带 `-Encoding`**（会被宿主当作破坏性操作拦下）：读文本一律 `[System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)`。

## 必查项（对应「收尾机械自检」8 条 + 证据契约）

| # | 查什么 | 判据 |
|---|---|---|
| 1 | 散落临时文件（`_dev` / `_assets_src` / `_assets_tmp` 下的 `*.cs`） | 计数 = 0 |
| 2 | 硬规则命中（`Debug\.Log` / `Resources\.Load` / `PlayerPrefs` / `(?<!Game\.)Input\.` / `GameObject\.Find` / `FindObjectOfType` / `Instantiate\(`） | 每条命中都能在验收表「允许的差异」里找到对应行 |
| 3 | 验收表自洽（汇总数字 vs 表体行数）+ 每行标类别 | 表体行数 > 0，且每行含 `数值类` / `表现类` |
| 4 | 「允许的差异」每行含"是什么 / 为什么 / 出处 / 何时消除" | 缺任一 ⇒ FAIL |
| 5 | 路径可达（验收表里的 `路径:行`、截图路径） | 全部存在 |
| 6 | **证据新鲜度** —— **按因果作废，不许一改就全废** | 每条"已实测"引用的产物 **mtime 晚于**被验证代码 / 资产；**作废范围 = 这次改动真能影响到的那几行**（同模块 / 同功能链 / 同屏），⛔ 不是"任何文件一变就全量作废"。**实现见下方「第 6 项的实现」** |
| 6b | **范围表必须被两处共用** | 下方骨架的 `$areaRoots` / `$panelOf` 既是新鲜度判据的输入，**也是"重采哪些场景"的唯一数据源** —— ⛔ 不许"闸门按因果判、重采却全量跑" |
| 6c | **mtime 类红项的「具名裁决」登记处** | 允许一条具名裁决：在 `.ai-tmp/test/ledger.tsv` 写一行 `kind=adjudicated`（详情 = `<检查名> -- <理由（≥12 字）>`；旧项目 `dispatch-log.tsv` 里的 `# adjudicated:` 行也算）⇒ 该检查降为 `HUMAN-ONLY` 并打印理由。⛔ 理由为空 / 短于 12 字 ⇒ 忽略、仍然 FAIL；⛔ 不许当"消红手段"（它只登记**人已判过的假阳性**，便于复查） |
| 7 | 一键复检入口存在（本脚本自身） | 存在且能跑 |
| 8 | **原版对照表存在**（`策划/对照表.md`） | 存在，且每行有"原版值(出处) / 我们的值 / 差值" |
| 9 | 无交接 / 进度类文档 | `docs/交接-*.md` / `NEXT.md` / `docs/进度*.md` 均不存在 |
| 10 | **引擎自称 —— 判据是"渲染出来的"，不是"源码里有没有"** | ① 源码 / 文档里**逐字**是 `clover-engine`；② **首页画面上**那一行是 `by clover-engine`，判据取**运行时 UI 节点树里那个标签的实际文本 + 实际字体**（或对截图做字形比对），⛔ 不是 grep 源码 —— **源码里有 ≠ 画面上有 ≠ 大小写对**；③ **大小写也算**：只有大写的像素字体会渲染成 `BY CLOVER-ENGINE`，**不合规**。**实现见下方「第 10 项的实现」** |
| 11 | **检查项的作用域 / 时间窗**（防假阳性） | 只判"**本次任务**产生的痕迹"；历史残留**不计 FAIL** |
| 12 | **验收表是否标了类别** | 每行都有 `数值类` / `表现类`；`表现类` 的行**能在联络图索引表里查到格号** |
| 13 | **工程外产物** | **工作区根 + 宿主会话产物目录**里，"24h 内新建且名字带本工程标识"的文件数 = 0。**三条设计约束**：① 标识取自**运行时的工程目录名**（再补一个去前缀短名），⛔ 不写死具体文件名模式（自造名无穷，写死只抓上一次还会假阳性）；② **时间窗（24h）+ 只认 `CreationTime`**（⛔ 不看 `LastWriteTime`，否则"别人改了已有文件"会天天误报）；③ 区域清单**可扩展、填不出就留空**（留空只让检查变窄，不会让"工作区根"那一半失效）。**局限**：只覆盖列进清单的区域，不是"工程外全盘扫描" |
| 14 | **采样器自检**（跑场景**前**一秒就能查完的东西） | `.ai-tmp/**/*.ps1` 每个文件：**语法 0 错**，且 **非 ASCII 字节 = 0 或带 BOM**（无 BOM + CJK ⇒ PS 5.1 按 ANSI 解析 ⇒ `-match` 静默失效 ⇒ 白等满超时）；**裸表达式喂 `eval` 编译不过** ⇒ 会被当成"引擎没起来"而杀掉好好的 Play 会话 ⇒ 入口形状先验一次（`return X;`）；**超时不是完成判据** —— 完成只认**被测程序自己写的标记**，且按"**新增次数**"判 |
| 15 | **实现由执行者产出** | 本次时间窗内改动的实现文件**逐个**能在 `.ai-tmp/test/ledger.tsv`（kind=`dispatch`；旧项目仍是 `dispatch-log.tsv` 也算）里找到派活行（文件落在该行声明的范围内 **且** 派活时间 ≤ 文件 mtime）；对不上 ⇒ 主 agent 自己动手了。**例外**：小改动用一行 `# direct-fix: <路径> -- <理由>` 留痕即算通过（⛔ 不许拿它给多文件 / 改数据格式 / 新增行为的改动洗白） |
| 16 | **进 Play 必须记账（⛔ 不设次数上限）** | `.ai-tmp/test/ledger.tsv` 里 kind=`play` 的行（旧项目 `play-log.tsv` 也算）：**每进一次 Play 一行**（`ISO 时间 / kind / 执行者 / 详情=为什么必须进这条链`）。判据：① **详情列非空**；② 有实机证据但**没有账本** ⇒ FAIL。⛔ **本项不判"行数多不多"** —— 曾经的"行数 ≤ 预算（默认 5）"被读成了**停工的许可证**（验到第 5 次就收手），**已废除** |
| 17 | **采集后冻结** | **本批次证据里最早那张的 mtime = T0**；"本批次证据" = **最新那张联络图索引 `*.index.tsv` 引用到的 png**（无索引才退回"窗口内新增的 `Screenshots/*.png`"）。**T0 之后不许再有实现文件**（`client/Assets/Scripts/**`、引擎 `Runtime/**`）被改动。⛔ 不许直接用"6h 窗口内最旧的新 png"当 T0（会把历史批次的图算进来 ⇒ 必然误报 FAIL）。违反 ⇒ FAIL 并列文件 |
| 18 | **证据经济性**（⛔ 不许逐行截图、不许逐项进出 Play） | 验收表 `表现类` 行数 ≥ 1 时：① **必须存在联络图索引**（`Screenshots/*.index.tsv`，格号 ↔ 行号）；② **没进任何联络图**的独立 `png` 数 ≤ `max(12, 表现类行数 × 2)`。超出 ⇒ FAIL。⛔ **被 `*.index.tsv` 引用过的 png = 联络图的组成部分**，必须从计数里排除（否则瓦片被重复计数 ⇒ 误报） |
| 19 | **渲染设备不是软件渲染**（配方 `experience/perf-triage.md`） | 读 `client/Logs/Editor.log` 里 Unity 启动时写的 `[D3D12 Device Filter] Device Name:`（或 `Renderer:`）。**命中 `Microsoft Basic Render Driver` / `Basic Display` / `WARP` ⇒ FAIL** —— 那是纯 CPU 软件光栅化，**此时任何"帧率 / 卡顿"结论都无效**。日志里没有这一行 ⇒ `HUMAN-ONLY`（改用手工 `SystemInfo.graphicsDeviceName`） |
| 20 | **T0 覆盖矩阵**（口径 `patterns/full-coverage-audit.md`） | 四 / 五条子判据：① `coverage-rows` = **覆盖关系**（⛔ 不是行数相等）：清单里**每个实体**在判定行里 ≥1 行、判定行**每一行**都能对上清单里某个实体（**缺清单 ⇒ FAIL**；⛔ 写成"行数相等"会被凑成假绿）；② `coverage-filled` = 每行都有 `一致`/`不一致`（**零空行**）；③ `coverage-diff` = `不一致` 计数 **= 0**；④ `coverage-dimensions` = **12+3 个维度代号（D1..D12 / S1..S3）在清单里各出现 ≥1 次** |
| 21 | **规模档位已声明**（档位表 `patterns/full-coverage-audit.md` §9.5） | 规格文档顶部写明档位 `S`（1-way）/ `M`（2-way pairwise）/ `L`（3-way + 全状态全边界）；**判一次，只许上调**（不声明 = 默认全量 = 会被读成"做不完"从而整体规避） |
| 22 | **修 bug 的影响域已登记**（口径 `patterns/full-coverage-audit.md` §9） | `.ai-tmp/test/impact-radius.tsv` 每行 ≥3 列：`维度 / 因果链 / 受影响行`；文件不存在 ⇒ `HUMAN-ONLY`（回报里写清是"本次无 bug 修复"还是"没登记"） |
| 23 | **证据锚点可解析** | 每条判定行带 `anchor:` 指向**机器产物**：① 该文件存在；② 该位置内容**匹配该行期望值**（不是"有内容"就算过）；③ ⛔ 指向 `md` / 回报 / 代码注释 ⇒ FAIL。**口径（⛔ 勿按字面追溯）**：只判**本次任务新增 / 改动的判定行**（增量口径）；**合法锚点两类** —— ① 机器产物位置（`文件:行` 或字段名）② **原版载体引用**（原版 `.res` / `.cfg` / `.cpp` / `hud.txt` 等**仓外载体**的 `文件:行`）。⛔ 指向 `md` / 回报 / 注释**不算** |
| 24 | **闸门版本同步**（脚本 `scripts/gate-sync.ps1`） | 本项目实现的检查项 **⊇** 模板 `GATE-ITEMS` 要求的清单（项目检查项名从 `Say '<STATUS>' '<name>'` 里提取） |
| 25 | **判据防凑数** | 覆盖矩阵的每一行必须能在某个探针输出里**按行 id 命中**；⛔ 只比行数 ⇒ 可被"把两边凑相等"通过（指标一旦成为目标，就不再是好指标） |
| 26 | **取证截图不许进 `client/Assets/`** | `client/Assets/Screenshots` **目录存在 ⇒ FAIL**。⛔ 不许按"`client/Assets/**` 下有 png 就 FAIL"判 —— 实测每个项目都有 1 个**正式美术** png，那样判是**假红**。实现见下方「第 26 项的实现」（已过两次自检：真实项目基线 PASS + 注入 `Screenshots/` 后 FAIL） |

| 27 | **`.ai-tmp` 预算**（治"临时文件只增不减"） | `.ai-tmp/**` ① **文件数 ≤ 300**、② **体积 ≤ 200 MB**；③ ⛔ 目录里不许出现**构建缓存 / 依赖目录**（`gocache` / `gopath` / `gotmp` / `node_modules` / `bin` / `obj`）与**目录级备份**（`*-bak-*`）。任一超限 ⇒ FAIL（报最快的修法：删截图 / 删逐帧 TSV / 把缓存指回系统默认位置） |
| 28 | **引擎与 skill 未被改**（口径 `patterns/engine-fix.md`） | ① 引擎仓（`clover-client-unity-engine` / `clover-server-engine`，若在本机）`git status --porcelain` **为空**；② 本 skill 的仓库源与宿主副本**未被本次任务修改**（比交付前基线）。有改动 **且** `引擎问题.md` 里没有对应行 ⇒ FAIL |
| 29 | **引擎问题已登记**（口径 `patterns/engine-fix.md` §2） | `<项目根>/引擎问题.md` **存在**且含三段 `## 引擎缺口` / `## 引擎 bug` / `## skill 问题`（**没遇到问题也要建**，三段各写"本轮无"）。缺文件或缺段 ⇒ FAIL |

### ⛔ 新检查上线前的三条纪律

- **能机械判 ≠ 能直接判**：判据上线前必须**两次自检**（已知正确样本 PASS + 已知错误样本 FAIL），并问一句「**它会误伤哪条规则**」。
  **反例**：曾打算加"`client/Assets/**/*.cs` 里出现 `原版资源` ⇒ FAIL" —— 实测 51 处命中**全部是注释里的出处标注** ⇒ 会制造 51 个假红，还会逼执行者**删掉出处标注**才能变绿，**正好打死「写不出出处的量不许进工程」这条更重要的规则**。⇒ 判"代码里的路径真的被使用"，⛔ 不判"这个词出现了"（`//` / `///` / `<para>` 必须先过滤）。
- **作用域纪律**：曾把"不许有某某会话目录"写成"工作区里存在该目录就 FAIL"，把**九天前另一个任务**留下的目录报成本次违规。⇒ **检查必须限定在本次任务的时间窗 / 作用域内** —— **会误报的检查比没有检查更糟**。
- **第 12 条的意义**：不标类别 ⇒「哪几项必须看图」就说不清 ⇒ 只能二选一：**全截**（N 张图逐张读，贵一个量级）或**全不截**（退回"数字对画面错"）。**类别是"该不该截图"的唯一判据，必须落在表里。**

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
tmp-budget||required|.ai-tmp file count and size within budget, no build caches or dir backups inside
no-engine-edits||required|engine repo and skill copies untouched (or recorded in engine issues file)
engine-issues||required|engine gaps / bugs / skill issues recorded in the engine issues file
<!-- GATE-ITEMS-END -->

> **这个块是机器可读的**：`scripts/gate-sync.ps1` 拿它跟项目的 `tools/verify.ps1` 对账
> （项目的检查项名从 `Say '<STATUS>' '<name>'` 里提取）。**改模板时同步改这个块**，
> 否则"模板更新了、项目没跟上"这件事**谁也发现不了** —— 那正是 19~22 项至今没落地的成因。
> 第 4 列 `planned` = 已声明但暂不强制（只打印 INFO），成熟后改成 `required` 即开始拦截。

### 第 26 项的实现（可直接抄；已过两次自检）

> 块首注释里带 `[SHIPPED-VERBATIM]` 标记 ⇒ `scripts/gate-sync.ps1` 的 `skeleton-equals-shipped`
> 会**去注释、屏蔽字符串后逐行比对**模板这一块与项目 `tools/verify.ps1` 里的同名块。**改这一块
> 必须同步改标签**（标记写在注释里，不参与比对）；没有这个标记的块一律不比对（⛔ 不许把
> 「所有块都要求逐字相同」写进闸门 —— 项目合法会改路径，那是**假红机器**）。
>
> ⚠️ 你要粘的地方（`tools/verify.ps1`）含中文注释：粘进 `.ps1` **必须存成 UTF-8 with BOM**（否则 PS 5.1 按 ANSI 解码 ⇒ 引号被吞、**一行都不执行**，而上一次的日志还在 ⇒ 你会以为跑过了）。复制后先 `Test` 一下 `Tokenize` 的 `errs.Count -eq 0`。

```powershell
# 26) no forensic screenshots inside client/Assets (SKILL.md 1.8 item 6).  [SHIPPED-VERBATIM]
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


### 第 6 项的实现（可直接抄；替换骨架里的 `$null` guard 版本）

> 骨架里那个 `if ($null -eq $perRow)` 的 guard 只是**防假绿的临时闸**（`$perRow` 从来没被填过 ⇒
> 一旦有人删掉 guard，`foreach ($null)` 空转、`stale.Count -eq 0` 成立 ⇒ **打印 PASS**，那是最危险
> 的一类假绿）。下面这块是**已跑通的完整实现**，整块替换骨架的 6) 段即可。
> 唯一需要按项目填的是 `$areas` 映射表；块里每个"比不了"的分支都走 `HUMAN-ONLY`，⛔ 没有一条
> "空结果 ⇒ PASS" 的路。
> 它输出两个 label：`FAIL evidence-freshness`（某几行的图比自己 area 的依赖旧 ⇒ **只作废那几行**）
> 与 `FAIL evidence-freshness-map`（有 cited 截图匹配不上任何 area ⇒ 新截图不许悄悄逃过）。
> **行口径**：只取**判定行**（带 `一致` / `未验` / `未做` / `不适用` 之一）—— 验收表里还挂着「历史 /
> 已修问题」表，那些行的图**不该重采**（它们记录的是旧 bug），混进来就是假红。本块**只看新鲜度、不看
> 结论格写了什么**；"表里有没有结论 / 只判结论列" 是另一件事（项目侧的交付文档检查器管），两边别互相
> 替对方下判。
>
> ⚠️ 注意 `不一致` 行：`Contains("一致")` 会**把它一并纳入**（`不一致` 含子串 `一致`）—— 这是**有意**的：它同样是被判过的行，其引用图也不许旧。已登记、**不需要重采**的差异走「允许的差异」段（见 §6 交付清单），⛔ 不要写成判定表里的 `不一致` 行 —— 否则与 freshness 判据互相打架、必然假红。
>
> ⚠️ 你要粘的地方（`tools/verify.ps1`）含中文注释：粘进 `.ps1` **必须存成 UTF-8 with BOM**（否则 PS 5.1 按 ANSI 解码 ⇒ 引号被吞、**一行都不执行**，而上一次的日志还在 ⇒ 你会以为跑过了）。复制后先 `Test` 一下 `Tokenize` 的 `errs.Count -eq 0`。

```powershell
# 6) evidence freshness -- judged BY CAUSE, from ONE explicit area map
#    (SKILL.md mechanical self-check item 6 + this file's items 6 / 6b).
#    * invalidation scope = the ROWS the change can really influence (same module / same feature
#      chain / same screen) -- NOT "any file in the project changed => throw the whole batch away";
#    * the map is ALSO the only data source for the RE-SHOOT scope (item 6b): the `s` field is what
#      `verify.ps1 -Reshoot` prints and what the re-shoot driver accepts. If the gate judged by cause
#      while the re-shoot ran everything, one edit would still cost a whole re-shoot batch.
#    Why (measured): using the newest .cs / level file of the WHOLE project as the baseline of every
#    shot turned a single level-data edit into "re-shoot ALL cited shots", including rows no level
#    file can touch. One edit cost a whole batch.
#
#    --- PARAMETERS: the ONLY project-specific part is the $areas map below ---
#      n = area name (printed with every finding; the name the report refers to)
#      d = files or DIRECTORIES this area's screens depend on, RELATIVE TO $root (a directory = its
#          whole tree). The baseline of a shot = newest file among its OWN area's `d`.
#      p = regex over the CITED screenshot FILE NAMES. A cited shot must match EXACTLY ONE area;
#          an unmapped cited shot is a FAIL, so a brand-new screenshot can never silently escape.
#      s = probe scene(s) that produce those shots, comma-separated => the re-shoot scope.
#    One area per screen / per contact sheet. An aggregate sheet that draws frames from several areas
#    belongs to an area whose `d` is the UNION of their `d` and whose `s` is the UNION of their
#    scenes: a sheet is only as fresh as the biggest input it draws.
#    ACCEPTANCE TEST (two-sample rule, reference/anti-gaming.md section 5): run this on a known-good
#    tree (must PASS) AND on a tree where ONE visual row's cited png is aged past its own area's
#    newest dependency (must FAIL, naming that png + its area). scripts/gate-selftest.ps1 performs
#    both runs; never ship this block on a single green run.
#
#    Self-contained on purpose (so it can replace the skeleton's guard block anywhere): the four
#    shared names below are re-derived here -- delete these four lines if the skeleton already
#    defines them (skeleton order: $shotDir is defined later, inside item 17).
$shotDir  = Join-Path $root '.ai-tmp\screenshots'
$rowIdRe  = '^\s*\|\s*\d+(?:\s*-\s*\d+)?\s*\|'
$cNumeric = ([char[]]@(0x6570,0x503C,0x7C7B) -join '')
$cVisual  = ([char[]]@(0x8868,0x73B0,0x7C7B) -join '')

# (a) cited-shot universe = pngs cited by a VERDICT row that carries the VISUAL class.
#     "verdict row" is used here in the same sense as everywhere else in this file: the row carries a
#     verdict word. NOTE that scope filter is NOT cosmetic -- an acceptance table also carries historical
#     / "problems already fixed" tables, and their rows cite pngs that must NOT be re-shot (they record
#     an old bug). Let them into the universe and the freshness check goes red on pictures nobody is
#     allowed to re-shoot (measured in the project this shape came from).
#     A NUMERIC row's illustrative png is NOT judged either: its evidence is a runtime log line /
#     assertion (SKILL.md evidence-class rule, item 3) and failing it would be a false positive --
#     measured: 39/63 rows went red that way while nothing was stale. A row carrying BOTH classes is
#     treated as VISUAL (the stricter side). Scope note for whoever reconciles this with a separate
#     deliverable-doc checker: this block judges FRESHNESS only -- it never looks at what the verdict
#     cell says, and "not yet verified / not done / not applicable" rows are deliberately included
#     (badged rows still carry evidence that can go stale).
$cVerdict = @(
  ([char[]]@(0x4E00,0x81F4) -join ''),          # "yi zhi"      = consistent
  ([char[]]@(0x672A,0x9A8C) -join ''),          # "wei yan"     = not yet verified
  ([char[]]@(0x672A,0x505A) -join ''),          # "wei zuo"     = not done
  ([char[]]@(0x4E0D,0x9002,0x7528) -join '')    # "bu shi yong" = registered not-applicable
)
$specTxt = if (Test-Path $spec) { [System.IO.File]::ReadAllText($spec, [System.Text.Encoding]::UTF8) } else { '' }
$visPngs = @{}; $numPngs = @{}; $visRows = 0
foreach ($ln in ($specTxt -split "`n")) {
  if ($ln -notmatch $rowIdRe) { continue }
  $isVerdict = $false
  foreach ($v in $cVerdict) { if ($ln.Contains($v)) { $isVerdict = $true; break } }
  if (-not $isVerdict) { continue }
  $isVis = $ln.Contains($cVisual)
  if ($isVis) { $visRows++ }
  $dst = if ($isVis) { $visPngs } else { $numPngs }
  foreach ($m in [regex]::Matches($ln, '([A-Za-z0-9_\-]+\.png)')) { $dst[$m.Groups[1].Value] = 1 }
}

# (b) the area map -- replace this PLACEHOLDER map with the project's own rows.
#     (placeholders that match nothing are deliberate: until they are filled in, every cited shot is
#      reported as unmapped, which is loud and correct -- it can never look green.)
$areas = @(
  @{ n = 'ui-<panel>';   d = @('client\Assets\Scripts\UI\<Panel>.cs', 'client\Assets\Scripts\UI\UIBuilder.cs', 'client\Assets\Resources\Fonts'); p = '^<panel>-[a-z0-9\-]*\.png$'; s = '<scene>' },
  @{ n = 'level-<name>'; d = @('client\Assets\Resources\Levels\<Level>.txt', 'client\Assets\Scripts\Module\Gameplay\GameplayModule.cs');                p = '^<name>-[a-z0-9\-]+\.png$';  s = '<scene>,<scene2>' }
)
function Newest-AreaFile([string[]]$paths) {
  $files = @()
  foreach ($p in $paths) {
    $full = Join-Path $root $p
    if (-not (Test-Path $full)) { continue }
    $item = Get-Item $full
    if ($item.PSIsContainer) { $files += @(Get-ChildItem $full -Recurse -File -ErrorAction SilentlyContinue) }
    else { $files += $item }
  }
  $files = @($files | Where-Object { $_.Name -notlike '*.meta' -and $_.Name -notlike '*.import' })
  return ($files | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
}
function Get-AreaOf([string]$name) { foreach ($a in $areas) { if ($name -match $a.p) { return $a } } return $null }

$stale = @(); $unmapped = @(); $sceneSet = @{}
$cited = @()
if (Test-Path $shotDir) {
  $cited = @(Get-ChildItem $shotDir -Filter *.png -File -ErrorAction SilentlyContinue |
             Where-Object { $visPngs.ContainsKey($_.Name) })
}
# every branch that cannot compare MUST NOT print PASS -- an empty result is not a pass:
if ($visRows -eq 0) {
  $human++; Say 'HUMAN-ONLY' 'evidence-freshness' 'no visual-class row in the acceptance table -- nothing to compare (add the class; do not read this line as green)'
} elseif ($cited.Count -eq 0) {
  $human++; Say 'HUMAN-ONLY' 'evidence-freshness' ('no cited visual shot found on disk (' + @($visPngs.Keys).Count + ' cited) -- see screenshot-refs; an empty comparison must never PASS')
} elseif ($areas.Count -eq 0) {
  $human++; Say 'HUMAN-ONLY' 'evidence-freshness' 'the area map ($areas) is empty -- per-row freshness cannot be computed at all; fill it in'
} else {
  foreach ($f in $cited) {
    $a = Get-AreaOf $f.Name
    if ($null -eq $a) { $unmapped += $f.Name; continue }
    $base = Newest-AreaFile $a.d
    if (-not $base) { $unmapped += ($f.Name + ' (area ' + $a.n + ': none of its dependencies exists)'); continue }
    if ($f.LastWriteTime -lt $base.LastWriteTime) {
      $stale += ('{0} < {1} (area={2} scene={3})' -f $f.Name, $base.Name, $a.n, $a.s)
      foreach ($sc in ($a.s -split ',')) { if ($sc.Trim().Length -gt 0) { $sceneSet[$sc.Trim()] = 1 } }
    }
  }
  $sceneList = (@($sceneSet.Keys) | Sort-Object) -join ','
  # optional: the re-shoot driver reads its scene list from HERE and nowhere else (item 6b).
  # to enable, add  param([switch]$Reshoot)  to the top of this gate.
  if ($Reshoot) {
    Write-Output ('stale cited shots: ' + $stale.Count + '; areas to re-shoot (scene=...):')
    $stale | ForEach-Object { Write-Output ('            ' + $_) }
    Write-Output ('RESHOOT_SCENES=' + $sceneList)
    exit 0
  }
  if ($unmapped.Count -gt 0) {
    $fail++; Say 'FAIL' 'evidence-freshness-map' ('' + $unmapped.Count + ' cited screenshot(s) match no area in the map -> add one row per screen/sheet (an unmapped shot must never silently escape)')
    $unmapped | ForEach-Object { Write-Output ('            ' + $_) }
  }
  if ($stale.Count -eq 0 -and $unmapped.Count -eq 0) {
    $msg = 'visual rows = ' + $visRows + ', ' + $cited.Count + ' cited png all newer than their OWN area newest dependency'
    $msg = $msg + '; ' + @($numPngs.Keys).Count + ' numeric-row png NOT judged (their evidence is a log line / assertion)'
    Say 'PASS' 'evidence-freshness' $msg
  } elseif ($stale.Count -gt 0) {
    $fail++; Say 'FAIL' 'evidence-freshness' ('' + $stale.Count + '/' + $cited.Count + ' cited screenshots of VISUAL rows are older than a file in their OWN area -> re-shoot exactly these (scene=...): ' + $sceneList)
    $stale | Select-Object -First 40 | ForEach-Object { Write-Output ('            ' + $_) }
  }
}
```

### 第 10 项的实现（可直接抄；判据是"渲染出来的"）

> `GATE-ITEMS` 把 `engine-credit` 标成 **required**，但正文长期只有一句判据、**没有实现**（骨架里到
> `# 22)` 就结束了）。下面这块补上。
> 关键：**判据取运行时 UI 节点树 + 活屏像素**，⛔ 不 grep 源码 —— 源码里有 ≠ 画面上有 ≠ 大小写对。
> 报告由**探针场景测量产出**（人不能手写），本块逐字段、大小写敏感地断言，并要求 **每一屏各自成立**
> （"某个面板上有这行字"不算满足规则）；`tamper != none` 直接判红 ⇒ 反向自检跑的那份报告不能冒充交付证据。
> 它输出两个 label：`FAIL engine-credit`（渲染出来的那行字不满足规则）与
> `FAIL engine-credit-freshness`（报告比该 area 的依赖旧 ⇒ 得重跑探针场景）。
>
> ⚠️ 你要粘的地方（`tools/verify.ps1`）含中文注释：粘进 `.ps1` **必须存成 UTF-8 with BOM**（否则 PS 5.1 按 ANSI 解码 ⇒ 引号被吞、**一行都不执行**，而上一次的日志还在 ⇒ 你会以为跑过了）。复制后先 `Test` 一下 `Tokenize` 的 `errs.Count -eq 0`。

```powershell
# 10) engine self-name credit -- the judge is what was RENDERED, never the source text (SKILL.md 1.6).
#     Why this shape: the naive check grepped the SOURCE for 'by clover-engine' and stayed green
#     through BOTH defects a user reported -- (a) the title screen (the screen the player lands on)
#     had no credit line at all; (b) the source text was right, but the pixel font maps a-z onto the
#     UPPERCASE glyph shapes, so the screen showed 'BY CLOVER-ENGINE'.
#     How: a probe scene writes ONE machine-produced report describing the RUNNING game -- the runtime
#     UI node tree (label text / font / active / visible / anchors), the font's real glyph boxes, and
#     the INK PROFILE of the live screen's bottom strip. This block asserts every field for EVERY
#     scope: "a line that is merely present somewhere" does not count, and neither does a label that
#     sits on an inactive/other panel.
#     REQUIRED REPORT SCHEMA (the probe writes these lines; one block per scope):
#       credit|<scope>|panel=<PanelClass>|label=<LabelObjectName>|found=true|open=true|active=true|visible=true|exact=true|text="<the line>"
#       credit|<scope>|font=<FontAssetName>
#       credit|<scope>|fontMetrics lowercaseShaped=true|...
#       credit|<scope>|anchor min=(x,y) max=(x,y)
#       credit|<scope>|pixels ink=<n> topRatio=<r> shortRuns=<n> hMax=<n> bandBottomGapPx=<n> screenCenterOffsetPx=<n> crop=<file.png>
#       (header line) tamper=none|<tag>
#     --- PARAMETERS (project-specific) ---
#       $credit          : the required string, EXACTLY, case-sensitive (name the ENGINE)
#       $creditFont      : the font actually used for that line (the lowercase-capable one)
#       $creditScopes    : scope -> the panel class that OWNS that screen + the label object name
#       $creditArea      : the item-6 area-map row whose `d` is what can change this line
#       $creditMinShortRuns : how many of the line's glyph runs must be >= 3px shorter than the
#                          tallest run. DERIVE IT FROM THE FONT FILE, not from our own render: walk
#                          the candidate fonts at the project's pixel size and compare per-glyph run
#                          heights -- the 8x8 pixel font really in use gave 10/15 short runs, the
#                          all-uppercase NES font gave 1/15, so 6 separates the two BY CONSTRUCTION.
#     Reverse self-check (do not skip): the probe must ALSO ship two tamper entries (text forced
#     uppercase / line hidden) that each write a report whose header says tamper=<tag>; this block
#     rejects tamper != none, so "make the probe say PASS" is itself caught.
#     Freshness: the report is runtime evidence -- it must be newer than $creditArea's newest
#     dependency, and it must NOT be compared against the project-wide newest file (a level-data or
#     gameplay edit cannot change the credit line; doing exactly that produced a false FAIL).
#     Requires the item-6 block above ($areas + Newest-AreaFile). Without item 6, drop the last part.
$credit        = 'by clover-engine'
$creditFont    = '<FontAssetName>'
$creditArea    = 'ui-<panel>'
$creditMinShortRuns = 6
$creditScopes  = @(
  @{ scope = 'home'; panel = '<HomePanel>'; label = '<LabelObjectName>' },   # the screen the player lands on
  @{ scope = 'boot'; panel = '<BootPanel>'; label = '<LabelObjectName>' }
)
$repPath = Join-Path $shotDir 'credit-render.txt'
$report  = if (Test-Path $repPath) { [System.IO.File]::ReadAllText($repPath, [System.Text.Encoding]::UTF8) } else { '' }

function Credit-Line([string]$txt, [string]$scope, [string]$key) {
  foreach ($ln in ($txt -split "`n")) {
    if ($ln.TrimEnd("`r").StartsWith("credit|$scope|") -and $ln.Contains($key)) { return $ln.TrimEnd("`r") }
  }
  return ''
}
function Credit-Grab([string]$line, [string]$pattern) { $m = [regex]::Match($line, $pattern); if ($m.Success) { return $m.Groups[1].Value } return '' }
function Credit-Num([string]$line, [string]$pattern, [double]$default) { $m = [regex]::Match($line, $pattern); if ($m.Success) { return [double]$m.Groups[1].Value } return $default }

if ($report -eq '') {
  $fail++; Say 'FAIL' 'engine-credit' ('no runtime render report at ' + $repPath + ' -- it must be WRITTEN BY MEASUREMENT from the running game, never by hand')
} else {
  $bad = @()
  $tamper = Credit-Grab $report 'tamper=([a-z]+)'
  if ($tamper -ne 'none') { $bad += ("report header says tamper='" + $tamper + "' -- that is a reverse-self-check run, not a delivery measurement") }
  foreach ($sc in $creditScopes) {
    $scope = $sc.scope
    $head = Credit-Line $report $scope 'panel='
    $txtL = Credit-Line $report $scope 'text='
    $fntL = Credit-Line $report $scope 'font='
    $metL = Credit-Line $report $scope 'fontMetrics'
    $pxL  = Credit-Line $report $scope 'pixels'
    $ancL = Credit-Line $report $scope 'anchor'
    if ($head -eq '' -or $txtL -eq '' -or $fntL -eq '' -or $metL -eq '' -or $pxL -eq '') {
      $bad += ($scope + ': report has no complete measurement block (see the schema in the block header)'); continue
    }
    foreach ($k in 'open=true', 'found=true', 'active=true', 'visible=true', 'exact=true') {
      if (-not $head.Contains($k)) { $bad += ($scope + ": '" + $k + "' not satisfied -> " + $head) }
    }
    # the measured label must be the one ON THE PANEL THAT OWNS THAT SCREEN:
    if (-not $head.Contains('panel=' + $sc.panel)) { $bad += ($scope + ': the measured label is not on panel=' + $sc.panel + ' -> ' + $head) }
    if (-not $head.Contains('label=' + $sc.label)) { $bad += ($scope + ': the measured label is not ' + $sc.label + ' -> ' + $head) }
    # the text must be the required string EXACTLY (case-sensitive: 'BY clover-engine' must fail)
    $got = Credit-Grab $txtL 'text="([^"]*)"'
    if (-not ($got -ceq $credit)) { $bad += ($scope + ": rendered text is '" + $got + "', required exactly '" + $credit + "' (case-sensitive)") }
    # the font must be the one that HAS lowercase glyph shapes
    $fname = Credit-Grab $fntL 'font=([^ ]+)'
    if (-not ($fname -ceq $creditFont)) { $bad += ($scope + ": label font is '" + $fname + "', required '" + $creditFont + "'") }
    $lower = Credit-Grab $metL 'lowercaseShaped=([a-z]+)'
    if ($lower -ne 'true') { $bad += ($scope + ": font glyph boxes say lowercaseShaped=" + $lower + " (a-z must differ from A-Z and 'y' must descend) -> " + $metL) }
    # pixels of the live screen's strip: a real lowercase line has x-height glyphs, so the top rows of
    # the ink band carry far less ink than the middle rows; all-uppercase shapes make every row
    # equally dense (ratio ~0.9), true lowercase is ~0.2 -- require < 0.5.
    $ink   = [int](Credit-Num $pxL 'ink=(\d+)' -1)
    $ratio = Credit-Num $pxL 'topRatio=([-\d.]+)' -1
    $gap   = [int](Credit-Num $pxL 'bandBottomGapPx=(-?\d+)' -1)
    $short = [int](Credit-Num $pxL 'shortRuns=(\d+)' -1)
    $hmax  = [int](Credit-Num $pxL 'hMax=(\d+)' -1)
    $off   = [int](Credit-Num $pxL 'screenCenterOffsetPx=(-?\d+)' 9999)
    if ($ink -lt 20) { $bad += ($scope + ': no/negligible ink on the line own rect (ink=' + $ink + ') => nothing was rendered there -> ' + $pxL) }
    if ($short -lt $creditMinShortRuns) { $bad += ($scope + ': only ' + $short + ' glyph run(s) are shorter than hMax-3 (hMax=' + $hmax + ', need >= ' + $creditMinShortRuns + ') => the shapes on screen are NOT lowercase -> ' + $pxL) }
    if ($ratio -lt 0 -or $ratio -ge 0.5) { $bad += ($scope + ': ink band is uniformly dense (topRatio=' + $ratio + ' >= 0.5) => the glyphs are NOT lowercase -> ' + $pxL) }
    if ($gap -lt 0 -or $gap -gt 64) { $bad += ($scope + ': credit line sits ' + $gap + ' px above the bottom edge (must be at the bottom, <= 64) -> ' + $pxL) }
    if ($off -eq 9999) { $bad += ($scope + ': no screen-centre offset was measured -> ' + $pxL) }
    elseif ([Math]::Abs($off) -gt 4) { $bad += ($scope + ': credit line is off-centre by ' + $off + ' px (must be bottom-CENTRE) -> ' + $pxL) }
    $crop = Credit-Grab $pxL 'crop=([^ ]+)'
    if ($crop -eq '' -or $crop -eq 'none') { $bad += ($scope + ': the measured strip was not saved as an image -> ' + $pxL) }
    elseif (-not (Test-Path (Join-Path $shotDir $crop))) { $bad += ($scope + ": evidence crop '" + $crop + "' is missing from the screenshot dir -> " + $pxL) }
  }
  if ($bad.Count -eq 0) {
    Say 'PASS' 'engine-credit' ('rendered on EVERY scope (' + ((@($creditScopes | ForEach-Object { $_.scope })) -join '+') + '): text ' + $credit + ' exact (case-sensitive), font ' + $creditFont + ', lowercase glyphs in the pixels, bottom-centre')
  } else {
    $fail++; Say 'FAIL' 'engine-credit' ('' + $bad.Count + ' assertion(s) failed on the RENDERED credit line')
    $bad | ForEach-Object { Write-Output ('            ' + $_) }
  }
  # freshness: the report is runtime evidence -- judge it against the credit AREA (item 6), not the project
  if ((Test-Path $repPath) -and $areas.Count -gt 0) {
    $ca = $null; foreach ($a in $areas) { if ($a.n -eq $creditArea) { $ca = $a } }
    if ($null -eq $ca) {
      $fail++; Say 'FAIL' 'engine-credit-freshness' ('the area map has no row named ' + $creditArea + ' -> the report cannot be judged for freshness')
    } else {
      $newest = Newest-AreaFile $ca.d
      $rep = Get-Item $repPath
      if ($newest -and ($rep.LastWriteTime -lt $newest.LastWriteTime)) {
        $fail++; Say 'FAIL' 'engine-credit-freshness' ('report ' + $rep.LastWriteTime + ' is OLDER than ' + $newest.Name + ' ' + $newest.LastWriteTime + ' -> re-run the credit probe scene (area ' + $creditArea + ')')
      } else {
        Say 'PASS' 'engine-credit-freshness' 'the render report is newer than the credit area newest dependency'
      }
    }
  }
}
```

## 骨架（复制后按项目改路径）

> ⚠️ 你要粘的地方（`tools/verify.ps1`）含中文注释：粘进 `.ps1` **必须存成 UTF-8 with BOM**（否则 PS 5.1 按 ANSI 解码 ⇒ 引号被吞、**一行都不执行**，而上一次的日志还在 ⇒ 你会以为跑过了）。复制后先 `Test` 一下 `Tokenize` 的 `errs.Count -eq 0`。

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
#   ✅ 可直接抄的完整实现（含 area 映射表的形状 + `evidence-freshness-map` + 重采场景唯一数据源）
#      见本文件「第 6 项的实现（可直接抄；替换本 guard 块）」一节 —— 整块替换下面这段 guard 即可。
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
$logPath  = Join-Path $root '.ai-tmp/test/ledger.tsv'       # 新名：5 列 = 时间 / kind / 主体 / 对象 / 详情
$isLedger = Test-Path $logPath
if (-not $isLedger) { $logPath = Join-Path $root '.ai-tmp/test/dispatch-log.tsv' }   # 旧名兼容（4 列，无 kind）
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
$playLog    = Join-Path $root '.ai-tmp\test\ledger.tsv'      # kind=play 的行
$isLedger2  = Test-Path $playLog
if (-not $isLedger2) { $playLog = Join-Path $root '.ai-tmp\test\play-log.tsv' }   # 旧名兼容
$playRows   = @()
if (Test-Path $playLog) {
  foreach ($line in @([System.IO.File]::ReadAllLines($playLog, [Text.Encoding]::UTF8))) {
    if ($line -match '^\s*#' -or $line.Trim().Length -eq 0) { continue }
    $c = $line -split "`t"
    if ($isLedger2) {
      if ($c.Count -lt 5 -or $c[1] -ne 'play') { continue }
      $playRows += [pscustomobject]@{ At = $c[0]; Task = [string]$c[3]; Why = [string]$c[4] }
      continue
    }
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
