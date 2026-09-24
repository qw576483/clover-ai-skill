# 一键复检脚本模板（`tools/verify.ps1`）—— 极简版

> **用途 = 需要时自查**（`SKILL.md` §4）；⛔ **默认不建、不跑、不是交付的拦路虎** —— 只有"你自己不确定 / 用户反复报同一条"时才拿它出来跑一次。

> **为什么这份文件这么短**：**产出为主，验收为辅** —— 验收只有一个目的：证明产出不是假的（`SKILL.md` §4）。
> 曾经的版本有 47 项检查、每种证据都要五列表格 + 哈希 + 时间戳、每条判据都要配负控 —— 那是**验证仪式**，不是验证。
> **用户不会报一个没问题的 bug**；出问题直接去查就行。
> ⇒ 本模板只留 **3 条要求**（"光看会骗人、所以值得机械化"的那几件；下面 6 个名字只是常见实现名）；**其余检查一律可选自检**，红了只当提示，⛔ 不许拿它拦交付。
> ⛔ **这不是每个切片的仪式**：切片做完只交"产出物 + 一条自检命令的原始输出"；这脚本**需要时自查时跑一次**即可，⛔ 不做也不影响交付。

## 要查时的 3 条要求（其余都是可选自检）

| 要求 | 常见实现名（可选，⛔ 非要求） | 为什么必须机械化 |
|---|---|---|
| **① 编译 / 构建通过** | `build-compiles` | 编不过，别的都白说 |
| **② 交付卫生** | `stray-temp-files`、`tmp-budget` | 这条真失控过：单项目 3372 文件 / 990 MB |
| **③ 引用可达（含图新鲜度）** | `screenshot-refs`、`evidence-freshness` | 悬空引用 = 没证据；人眼看图**永远**看不出这是三天前的 |
| （脚本自己别崩 —— 是自检的前提，不是第 4 条要求） | `verify-script-crash` | 脚本自己崩 ⇒ **本次结论作废**，⛔ 不许假装绿 |

**已删除、不再检查**（写清"不检了，为什么"）：
覆盖矩阵 / 覆盖命中率 / 覆盖枚举 / 数值验收审计 / 被引证据白名单 / 证据自检 / 回读自检 / 基线图索引 /
清单自洽 / 汇总核对 / 派活台账列数 / 差异登记逐条核对 / 派活-实现对账 /
行数或文件大小的阈值判断（除 `.ai-tmp` 预算这一条真失控过的）/ **"每个判据必须配负控"这类仪式** /
每种证据都要五列表格 + 哈希 + 时间戳 / **"验收表每格填满"**。
理由：**这些抓到的都是人眼 / 逻辑一眼能看出来的东西**，或者它们上次红的时候抓的是**自己写错了** —— 却要花掉做东西的时间。

**写任何新判据之前，先过这两句反问**：
1. 「这条判据抓到的，是**人眼 / 逻辑一眼能看出来**的东西吗？**是 ⇒ 不写判据。**」
2. 「这条判据上次红的时候，抓的是**真缺陷**还是**它自己写错了**？**后者 ⇒ 删。**」

## 怎么用

1. **想查时**再把下面的骨架复制成 **`<项目根>/tools/verify.ps1`**（⛔ 不是开工必备步骤、⛔ 不是交付拦路虎）。
2. 要查时跑：`powershell -NoProfile -ExecutionPolicy Bypass -File tools/verify.ps1`。
3. **逐行读输出**：`PASS` / `FAIL` / `HUMAN-ONLY`。**既然跑了**，出现任何 `FAIL` ⇒ ⛔ 不许说"完成 / 交付 / 实测通过"。
   `HUMAN-ONLY` = **只能由人过目**的项（不许执行者代签），例如"这条线歪没歪"。
4. 真要跑时：用户**只跑这一次**，不陪执行者逐点调参。

## ⛔ 真写这个脚本时的五个硬坑（避开它们 = "脚本自己别崩"的一半）

1. **`.ps1` 编码 —— 唯一口径：只看一个事实「文件里有没有非 ASCII 字节」。**
   - **没有**非 ASCII 字节（纯 ASCII）⇒ 随便存，**不需要 BOM**。
   - **有任何**非 ASCII 字节 —— **不管它在代码行、注释还是输出文案里** ⇒ **整个文件必须存成 UTF-8 with BOM**。PS 5.1 在没有 BOM 时按 **ANSI/GBK** 解析 ⇒ 中文变乱码 / 引号被吞 ⇒ **直接解析失败**。
   - 推荐写法：**脚本正文一律 ASCII**、输出用英文短语；注释要写中文就**带 BOM**。
   ⛔ **不许再有第二套口径**（例如"代码行必须 ASCII、注释可以不带 BOM"）：两套并存时，**连"备份一个含中文的 `.ps1`"这个动作本身都会把自检刷红**（实测：一份 138 个非 ASCII 字节、无 BOM 的 `.ps1`，只能存成 `.txt` 才敢备份）。
2. **非 ASCII 的路径不要写字面量**（如 `策划/验收表.md`），用**码点拼**（见骨架里的 `([char[]]@(0x7B56,0x5212) -join '')`）。
   ⛔ 坑中坑：`[string]::Concat([char]...)` 构造中文串曾失败 ⇒ 变成空串 ⇒ `Contains("")` **恒真** ⇒ 得"全命中"的假数据。**结论必须用第二种写法复核**，并先打印 `Length` 自检。
3. **`Select-String` 会给注释行也报命中**：要过滤 `//` / `///` / `*` 开头的行。
4. ⛔ **别用 `Get-Content` 不带 `-Encoding`**（会被宿主当破坏性操作拦下）：读文本一律 `[System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)`。
5. **数组字面量里用 `+` 拼出来的每个元素都必须各自加括号**：PS 的**逗号优先级高于 `+`**，`@('a'+'b','c'+'d')` 会塌成**一个**元素 ⇒ `foreach` 只跑一次、后面的断言**静默漏判**，看起来"全绿"。正确写法：`@( ($p+'.tsv'), ($q+'.txt') )`。

## 骨架（复制后按项目改路径）

> ⚠️ 粘进 `tools/verify.ps1` 若含中文注释 ⇒ **必须存成 UTF-8 with BOM**（否则引号被吞、**一行都不执行**，而上一次的日志还在 ⇒ 你会以为跑过了）。复制后先 `Test` 一下 `Tokenize` 的 `errs.Count -eq 0`。

```powershell
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$fail = 0; $human = 0

function Say([string]$status, [string]$name, [string]$detail) {
  Write-Output ("{0,-11} {1}  {2}" -f $status, $name, $detail)
}

# non-ASCII paths / words built from code points -> this file stays ASCII-only (hard pitfall 2)
$planDir  = Join-Path $root (([char[]]@(0x7B56,0x5212) -join ''))                       # ce hua
$spec     = Join-Path $planDir ((([char[]]@(0x9A8C,0x6536,0x8868)) -join '') + '.md')   # yan shou biao
$cNumeric = ([char[]]@(0x6570,0x503C,0x7C7B) -join '')                                  # shu zhi lei
$cVisual  = ([char[]]@(0x8868,0x73B0,0x7C7B) -join '')                                  # biao xian lei
$shotDir  = Join-Path $root '.ai-tmp\screenshots'
$rowIdRe  = '^\s*\|\s*\d+(?:\s*-\s*\d+)?\s*\|'

# 0) verify-script-crash -- a gate that throws must NEVER look green (item 5).
#    Without this, an uncaught exception aborts BEFORE the summary line: no FAIL, no PASS,
#    last line is half an error message -- it reads like "ran fine", while nothing was judged.
trap {
  $fail++
  Say 'FAIL' 'verify-script-crash' ($_.Exception.Message + ' -- the gate threw; treat this run as VOID, never as a pass')
  continue
}

# 1) build-compiles -- nothing else counts until this is green.
#    Replace the body with the project's real build entry (csc / dotnet / go build / unity batch).
$buildLog = Join-Path $root '.ai-tmp\test\build.log'
if (Test-Path $buildLog) {
  $bTxt = [System.IO.File]::ReadAllText($buildLog, [System.Text.Encoding]::UTF8)
  $bErr = @([regex]::Matches($bTxt, ': error [A-Z]{2}\d+')).Count
  if ($bErr -eq 0) { Say 'PASS' 'build-compiles' 'build log carries 0 error(s)' }
  else { $fail++; Say 'FAIL' 'build-compiles' ('' + $bErr + ' compile error(s) -- fix them before anything else') }
} else {
  $human++; Say 'HUMAN-ONLY' 'build-compiles' ('no ' + $buildLog + ' -- build once and tee the output there')
}

# 2) evidence-freshness -- the ONE anti-self-deception gate: a picture must be newer than the
#    code / asset it verifies. A human can NEVER tell by looking that a shot is three days old.
#    Scope is BY CAUSE: only the rows the change can really influence are void, never the batch.
#    An empty comparison must NEVER print PASS.
$cited = @()
if (Test-Path $shotDir) { $cited = @(Get-ChildItem $shotDir -Filter *.png -File -ErrorAction SilentlyContinue) }
$implNewest = $null
foreach ($r in @('client\Assets\Scripts')) {
  $p = Join-Path $root $r
  if (-not (Test-Path $p)) { continue }
  $f = @(Get-ChildItem $p -Recurse -Filter *.cs -File -ErrorAction SilentlyContinue |
         Sort-Object LastWriteTime -Descending | Select-Object -First 1)
  if ($f.Count -gt 0 -and ($null -eq $implNewest -or $f[0].LastWriteTime -gt $implNewest.LastWriteTime)) { $implNewest = $f[0] }
}
if ($cited.Count -eq 0) {
  $human++; Say 'HUMAN-ONLY' 'evidence-freshness' 'no screenshot on disk -- nothing to compare (do NOT read this as green)'
} elseif ($null -eq $implNewest) {
  $human++; Say 'HUMAN-ONLY' 'evidence-freshness' 'no implementation file found -- compile scope unknown'
} else {
  $stale = @($cited | Where-Object { $_.LastWriteTime -lt $implNewest.LastWriteTime })
  if ($stale.Count -eq 0) {
    Say 'PASS' 'evidence-freshness' ('' + $cited.Count + ' shot(s) all newer than ' + $implNewest.Name)
  } else {
    $fail++; Say 'FAIL' 'evidence-freshness' ('' + $stale.Count + '/' + $cited.Count + ' shot(s) older than ' + $implNewest.Name + ' -- re-shoot exactly these')
    $stale | Select-Object -First 20 | ForEach-Object { Write-Output ('            ' + $_.Name) }
  }
}

# 3) screenshot-refs -- every path cited by the acceptance table must exist on disk.
#    A dangling ref = no evidence at all.
$missing = @()
if (Test-Path $spec) {
  $st = [System.IO.File]::ReadAllText($spec, [System.Text.Encoding]::UTF8)
  foreach ($m in [regex]::Matches($st, '([A-Za-z0-9_\-\\/\.]+\.(?:png|tsv|txt|md|log))')) {
    $rel = $m.Groups[1].Value
    if ($rel -match '^(reference|patterns|scaffold|scripts)/') { continue }
    $full = Join-Path $root $rel
    if (-not (Test-Path $full)) { $missing += $rel }
  }
  $missing = @($missing | Sort-Object -Unique)
  if ($missing.Count -eq 0) { Say 'PASS' 'screenshot-refs' 'every cited path resolves' }
  else {
    $fail++; Say 'FAIL' 'screenshot-refs' ('' + $missing.Count + ' cited path(s) do not resolve => a dangling ref is not evidence')
    $missing | Select-Object -First 20 | ForEach-Object { Write-Output ('            ' + $_) }
  }
} else { $human++; Say 'HUMAN-ONLY' 'screenshot-refs' ('no ' + $spec + ' -- nothing to resolve against') }

# 4) delivery hygiene -- the one threshold that really got out of hand (3372 files / 990 MB).
$tmpRoot = Join-Path $root '.ai-tmp'
$n = @(Get-ChildItem $root -Recurse -Filter *.cs -File -ErrorAction SilentlyContinue |
       Where-Object { $_.FullName -match '\\(_dev|_assets_src|_assets_tmp)\\' }).Count
if ($n -eq 0) { Say 'PASS' 'stray-temp-files' '0 stray .cs outside .ai-tmp' }
else { $fail++; Say 'FAIL' 'stray-temp-files' ('' + $n + ' stray .cs under _dev/_assets_src/_assets_tmp') }

if (-not (Test-Path $tmpRoot)) { Say 'PASS' 'tmp-budget' '.ai-tmp does not exist (nothing temporary)' }
else {
  $files = @(Get-ChildItem $tmpRoot -Recurse -File -ErrorAction SilentlyContinue)
  $mb    = [Math]::Round((($files | Measure-Object Length -Sum).Sum) / 1MB, 1)
  $cache = @($files | Where-Object { $_.FullName -match '\\(gocache|gopath|gotmp|node_modules|bin|obj)\\' -or $_.Name -like '*-bak-*' })
  if ($files.Count -gt 300 -or $mb -gt 200 -or $cache.Count -gt 0) {
    $fail++; Say 'FAIL' 'tmp-budget' ('' + $files.Count + ' file(s) / ' + $mb + ' MB / ' + $cache.Count + ' cache-or-backup item(s) -- delete shots, frame TSVs and caches')
  } else { Say 'PASS' 'tmp-budget' ('' + $files.Count + ' file(s) / ' + $mb + ' MB') }
}

Write-Output ''
Write-Output "===== summary: FAIL=$fail  HUMAN-ONLY=$human ====="
if ($fail -gt 0) { Write-Output 'FAIL present => never say done / delivered / verified' }
exit $(if ($fail -gt 0) { 1 } else { 0 })
```

## 必须留在人手里的项（脚本永远代替不了）

- **外观是否 1:1**：同机位并排图逐元素比（`SKILL.md` §6 第 3 条）。
- **手感 / 动画连贯 / 节奏 / 音效时机**：时间序列，只能逐帧看或由人给基线。
- **"这条线歪没歪 / 这个按钮小没小"**：看一眼就知道，⛔ 不写脚本判。

<!-- GATE-ITEMS-BEGIN -->
# REFERENCE LIST ONLY -- NOT a required name set (required count = 0).
# status "ref" = an optional name you MAY reuse; the project picks its own names.
# name | alias | status | one-line what
build-compiles||ref|compiles / builds with 0 error
evidence-freshness||ref|every cited shot newer than the code / asset it verifies
screenshot-refs||ref|every path cited by the acceptance table resolves on disk
stray-temp-files||ref|zero stray .cs outside .ai-tmp (delivery hygiene)
tmp-budget||ref|.ai-tmp file count / size within budget, no caches or dir backups inside
verify-script-crash||ref|a gate that throws is VOID, never green
<!-- GATE-ITEMS-END -->

> **这是一个"参考清单"，不是要求**（`required` 计数 = **0**）：上面那 **3 条要求**（编译 / 交付卫生 / 引用可达）是要求；下面 6 个名字只是**常见实现名**，供项目抄用。
> - **判据怎么实现、叫什么名字，由项目自己定** ⇒ **不对齐、不报缺名、也不报多余**。项目少写一条原则才是问题，名字对不上模板**不是**问题。
> - ⛔ **本 skill 不再提供自动对账脚本**（原先那个已随本轮精简删除）。需要"模板 ↔ 项目"对账的项目，请把对账**内联进自己的 `tools/verify.ps1`**，或者干脆不建 —— **对账本身也是仪式**。
> - 想**自动解析**这个块的项目，才需要沿用 `name | alias | status | what` 的分列格式；只是人读的话格式随意。
> ⛔ **不再有 `planned` 列**：一标"计划中"，就会有人把它当需求去实现，最后又长回 47 项。
