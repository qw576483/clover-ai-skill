# skill-health.ps1 -- self-check for the clover-engine skill package
#
# Why: "an instruction is a request, a gate is a guarantee". The rule layer stays small only if
#      something fails loudly when it grows back. Run this after ANY edit of this skill.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File <skill-dir>\scripts\skill-health.ps1 -RepoRoot <repo-copy-dir>
#
# Checks (each line prints PASS / FAIL / WARN / SKIP):
#   1 skill-size          SKILL.md must stay under a byte budget (progressive disclosure entry file)
#   2 router-reachable    every file referenced by SKILL.md must exist (no dangling pointers)
#   3 no-relaxed-phrasing the rule layer must never be relaxed by "project wins over global" wording
#   4 copies-synced       host install copy == repo source copy (name + size)
#                         + refuses to compare a copy against ITSELF (that always passes)
#   5 case-digest         the case/criteria digest must exist and be linked from the entry file
#
# ASCII-only on purpose (PowerShell 5.1 parses non-ASCII .ps1 without BOM as ANSI).

param([string]$RepoRoot = '')

$ErrorActionPreference = 'Continue'
$root = Split-Path $PSScriptRoot -Parent
$fail = 0

function Say([string]$status, [string]$name, [string]$detail) {
    Write-Output ("{0,-5} {1}  {2}" -f $status, $name, $detail)
}

# -- 1) size budget -------------------------------------------------------------------
$skill = Join-Path $root 'SKILL.md'
if (-not (Test-Path $skill)) {
    $fail++; Say 'FAIL' 'skill-size' ('missing ' + $skill)
} else {
    $bytes = (Get-Item $skill).Length
    $limit = 32768
    if ($bytes -le $limit) { Say 'PASS' 'skill-size' ('' + $bytes + ' bytes <= ' + $limit) }
    else { $fail++; Say 'FAIL' 'skill-size' ('' + $bytes + ' bytes > ' + $limit + ' -- move details to reference/** and link them from the router table') }
}

# -- 2) router reachability -----------------------------------------------------------
if (Test-Path $skill) {
    $txt = [System.IO.File]::ReadAllText($skill, [System.Text.Encoding]::UTF8)
    $miss = @()
    foreach ($m in [regex]::Matches($txt, '(reference|patterns|scaffold|experience|scripts)/[A-Za-z0-9_\-/]+\.(md|ps1|py)')) {
        $rel = $m.Value -replace '/', '\'
        if (-not (Test-Path (Join-Path $root $rel))) { $miss += $m.Value }
    }
    $miss = @($miss | Sort-Object -Unique)
    if ($miss.Count -eq 0) { Say 'PASS' 'router-reachable' 'all referenced files exist' }
    else { $fail++; Say 'FAIL' 'router-reachable' ($miss -join ', ') }
}

# -- 3) relaxed phrasing: a hit is only suspicious OUTSIDE forbid/check wording --------
#    (a check that cries wolf is worse than no check -- the same phrase legitimately
#     appears in "never let 'project wins' relax a hard rule" and in grep instructions)
$cProjectWins = ([char[]]@(0x4EE5, 0x672C, 0x9879, 0x76EE, 0x4E3A, 0x51C6) -join '')   # "yi ben xiang mu wei zhun"
$cGlobalFirst = ([char[]]@(0x4F18, 0x5148, 0x4E8E, 0x5168, 0x5C40) -join '')           # "you xian yu quan ju"
$ctxWords = @(
    ([char[]]@(0x4E0D, 0x8BB8) -join ''),        # bu xu      (must not)
    ([char[]]@(0x7981, 0x6B62) -join ''),        # jin zhi    (forbidden)
    ([char[]]@(0x653E, 0x5BBD) -join ''),        # fang kuan  (relax)
    ([char[]]@(0x52A0, 0x4E25) -join ''),        # jia yan    (tighten)
    ([char[]]@(0x68C0, 0x67E5) -join ''),        # jian cha   (check)
    ([char[]]@(0x81EA, 0x68C0) -join '')         # zi jian    (self-check)
)
$suspicious = @()
$ctxHits = 0
foreach ($f in @(Get-ChildItem $root -Recurse -File -Include *.md -ErrorAction SilentlyContinue)) {
    $arr = @([System.IO.File]::ReadAllLines($f.FullName, [System.Text.Encoding]::UTF8))
    for ($k = 0; $k -lt $arr.Count; $k++) {
        $line = $arr[$k]
        if (-not ($line.Contains($cProjectWins) -or $line.Contains($cGlobalFirst))) { continue }
        # context window = this line +/- 2 lines: the forbid/check wording often sits on a neighbour
        # (a quoted history sentence, or a grep pattern followed by "judge each hit" on the next line)
        $lo = [Math]::Max(0, $k - 2); $hi = [Math]::Min($arr.Count - 1, $k + 2)
        $win = ($arr[$lo..$hi] -join ' ')
        $isCtx = $false
        foreach ($w in $ctxWords) { if ($win.Contains($w)) { $isCtx = $true; break } }
        # quoting is not asserting: a hit wrapped in 「」 / "" / backticks is a quotation
        # (e.g. quoting a wrong historical wording) or a grep pattern, not a rule relaxation
        if (-not $isCtx) {
            $idx = $line.IndexOf($cProjectWins); if ($idx -lt 0) { $idx = $line.IndexOf($cGlobalFirst) }
            if ($idx -ge 0) {
                $before = $line.Substring(0, $idx)
                $bt = ([regex]::Matches($before, [string][char]0x60)).Count
                $oq = ([char]0x300C); $cq = ([char]0x300D)     # 「 」
                $du = ([char]0x201C); $dc = ([char]0x201D)     # “ ”
                $o = [Math]::Max($before.LastIndexOf($oq), $before.LastIndexOf($du))
                $c = [Math]::Max($before.LastIndexOf($cq), $before.LastIndexOf($dc))
                if ((($bt % 2) -eq 1) -or ($o -gt $c)) { $isCtx = $true }
            }
        }
        if ($isCtx) { $ctxHits++ } else { $suspicious += ($f.Name + ':' + ($k + 1) + '  ' + $line.Trim()) }
    }
}
if ($suspicious.Count -eq 0) { Say 'PASS' 'no-relaxed-phrasing' ('' + $ctxHits + ' keyword hit(s), all inside forbid/check wording') }
else {
    $fail++; Say 'FAIL' 'no-relaxed-phrasing' ('' + $suspicious.Count + ' line(s) actually relax the rule layer')
    $suspicious | Select-Object -First 5 | ForEach-Object { Write-Output ('            ' + $_) }
}

# -- 4) the two copies must be identical ----------------------------------------------
#    Guard first: this check is $root vs $RepoRoot, and $root is derived from this script's own
#    location -- so running it FROM the repo with -RepoRoot <same repo> compares a copy with
#    itself and passes no matter how stale the install copy is (the host
#    copy was 44 files behind and it still said PASS). Refuse that usage instead of green-on-nothing.
#    Normalize BOTH paths first: a trailing separator (or any spelling variance) used to make
#    every relative name lose its first character, so one trailing "\" printed a wall of bogus
#    ONLY-HOST / ONLY-REPO lines. Normalize, then compare, then slice with the normalized lengths.
$rootFull = ([System.IO.Path]::GetFullPath($root)).TrimEnd('\')
$repoFull = ''
if ($RepoRoot -ne '') { if (Test-Path $RepoRoot) { $repoFull = ([System.IO.Path]::GetFullPath($RepoRoot)).TrimEnd('\') } }
if ($RepoRoot -ne '' -and $repoFull -ne '' -and $repoFull -eq $rootFull) {
    $fail++; Say 'FAIL' 'copies-synced' ('-RepoRoot is THIS copy (' + $rootFull + ') -- run it from the OTHER copy: -File <host>\scripts\skill-health.ps1 -RepoRoot <repo>')
} elseif ($RepoRoot -ne '' -and $repoFull -ne '') {
    # ⛔ 排除"不该比"的东西，否则这条检查**永远红**、等于没有：
    #    `-Recurse -File` 会把 VCS 元数据一并列出来。两份副本**各自**都是 git 工作树，
    #    但对象库/索引/日志天然不同 ⇒ 只报 `ONLY-HOST .git\objects\..` 这种 490 条噪音，
    #    真实的漂移被淹没。而 `_user_meta.json` 是**安装侧**才有的元数据（仓库里没有也不该有）。
    #    背景同 §「闸门自身也要被闸」：一条**不可能通过**的检查 = 会被无视 = 真漂移照样漏。
    #    ⛔ 不要顺手把所有点开头的目录都排掉 —— 只排这两个已知的。
    $skipRe = '^(\.git\\|_user_meta\.json$)'
    $a = @(Get-ChildItem $rootFull -Recurse -File | ForEach-Object { $_.FullName.Substring($rootFull.Length + 1) } | Where-Object { $_ -notmatch $skipRe })
    $b = @(Get-ChildItem $repoFull -Recurse -File | ForEach-Object { $_.FullName.Substring($repoFull.Length + 1) } | Where-Object { $_ -notmatch $skipRe })
    $d = @()
    foreach ($f in $a) {
        if ($b -notcontains $f) { $d += ('ONLY-HOST ' + $f) }
        elseif ((Get-Item (Join-Path $rootFull $f)).Length -ne (Get-Item (Join-Path $repoFull $f)).Length) { $d += ('SIZE ' + $f) }
    }
    foreach ($f in $b) { if ($a -notcontains $f) { $d += ('ONLY-REPO ' + $f) } }
    if ($d.Count -eq 0) { Say 'PASS' 'copies-synced' ('host == repo (' + $a.Count + ' files)') }
    else { $fail++; Say 'FAIL' 'copies-synced' ($d -join ' | ') }
} else {
    Say 'SKIP' 'copies-synced' 'pass -RepoRoot <repo-copy> to compare the two copies'
}

# -- 5) the case/criteria digest must exist and be linked from the entry file ---------
#    Layering is the point: the entry file is a SHORT summary; the digest keeps the
#    criteria, the minimal cases and the cost notes. Losing the digest = losing semantics
#    (that is a FAIL, not a warning).
$full = Join-Path $root 'reference\rules-full.md'
if (-not (Test-Path $full)) {
    $fail++; Say 'FAIL' 'case-digest' 'reference/rules-full.md missing -- keep the case/criteria digest; the entry file is the summary only'
} elseif (-not ([System.IO.File]::ReadAllText($skill, [System.Text.Encoding]::UTF8)).Contains('reference/rules-full.md')) {
    $fail++; Say 'FAIL' 'case-digest' 'reference/rules-full.md exists but SKILL.md does not link it (dangling knowledge)'
} else {
    $fLines = @([System.IO.File]::ReadAllLines($full, [System.Text.Encoding]::UTF8)).Count
    Say 'PASS' 'case-digest' ('digest kept: ' + $fLines + ' lines, linked from SKILL.md')
}

Write-Output ''
Write-Output ("===== summary: FAIL=" + $fail + " =====")
exit $(if ($fail -gt 0) { 1 } else { 0 })
