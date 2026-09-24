# gate-selftest.ps1 -- run the PROJECT's REAL tools/verify.ps1 against known-good and known-bad
# samples and check that each scenario produces the FAIL count / finding it must.
#
# Why this exists: reference/anti-gaming.md section 5 -- "a check that only ever reports red is
#   worse than no check". Every new or edited gate item has to survive the TWO-SAMPLE rule:
#   (1) a known-good tree stays green, (2) a known-bad tree goes red ON THAT ITEM, naming the thing
#   that was changed. Reading the check is not a self-test; running it twice is.
#   Measured cost of skipping it: a freshness check that reported PASS while it compared nothing
#   (its row parser was never written, so the loop ran over $null and "0 stale" looked like green).
#
# Method: this script never copies the gate -- it runs the real file, once per scenario, and every
#   scenario restores exactly what it touched in a `finally` block (mtimes and renames are put back,
#   even when the scenario throws). Each run's raw output is kept under
#   <Project>\.ai-tmp\test\selftest\ with an ISO timestamp on the first line, so "did it really run
#   just now" is answerable from disk.
#
# Fixtures are NEVER hard-coded here (screenshot names, item numbers and paths differ per project):
#   * default = auto-discovery from the project tree (see Auto-Scenarios below);
#   * or pass -Fixtures <file.tsv> with rows:
#         <scenario>  <op>  <target-relative-to-project>  <value>  <expect>  <regex-or->
#       op     : age-epoch | age-future | touch-now | rename
#       expect : fail-up  (FAIL must increase)      |  fail-same (FAIL must stay at the baseline)
#       value  : for rename = the new leaf name; otherwise ignored ('-' is fine)
#       regex  : a regex the gate output MUST match for this scenario to count as caught ('-' = none)
#     A scenario whose target does not exist is reported SKIP, never FAIL (a fixture that does not
#     apply to this project must not be able to red the run).
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate-selftest.ps1 -Project <project-root>
#   powershell ... -Project <root> -Fixtures <root>\.ai-tmp\test\gate-fixtures.tsv
#   powershell ... -Project <root> -ExpectBaselineFail 0
#
# ASCII-only on purpose (PowerShell 5.1 parses a BOM-less .ps1 as ANSI => CJK in source breaks it).

param(
    [Parameter(Mandatory = $true)][string]$Project,
    [string]$Gate = '',
    [string]$Fixtures = '',
    [int]$ExpectBaselineFail = 0,
    [string]$ShotsDir = '.ai-tmp\screenshots',
    [string]$ImplDir = 'client\Assets\Scripts',
    [string]$ReportDir = ''
)

$ErrorActionPreference = 'Stop'

# non-ASCII (CJK) fragments are built from code points so this file stays ASCII-only
$cVisual  = ([char[]]@(0x8868, 0x73B0, 0x7C7B) -join '')     # "biao xian lei" (visual class)
$cNumeric = ([char[]]@(0x6570, 0x503C, 0x7C7B) -join '')     # "shu zhi lei"  (numeric class)
$rowIdRe  = '^\s*\|\s*\d+(?:\s*-\s*\d+)?\s*\|'

if (-not (Test-Path $Project)) { Write-Output ('FAIL  project root not found: ' + $Project); exit 2 }
$Project = (Resolve-Path $Project).Path
if ($Gate -eq '') { $Gate = Join-Path $Project 'tools\verify.ps1' }
if (-not (Test-Path $Gate)) { Write-Output ('FAIL  no gate at ' + $Gate + ' -- pass -Gate <path to verify.ps1>'); exit 2 }
$shotRoot = Join-Path $Project $ShotsDir
if ($ReportDir -eq '') { $ReportDir = Join-Path $Project '.ai-tmp\test\selftest' }
if (-not (Test-Path $ReportDir)) { New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null }

# An ArrayList, NOT `$results = @()` + `+=`: with a scope-qualified `$script:results +=` the value is
# re-read on every call, and once it holds exactly one object PowerShell unwraps it to a PSObject ->
# the NEXT `+=` dies with "PSObject does not contain a method named op_Addition" (measured: scenarios
# B..E vanished from the report while the script still printed PASS -- a silent loss of checks).
$results = New-Object System.Collections.ArrayList

function Check([string]$name, [string]$expect, [bool]$ok, [string]$detail) {
    [void]$results.Add([pscustomobject]@{ Name = $name; Expect = $expect; Ok = $ok; Detail = $detail })
    Write-Output ("[{0}] {1}  expect={2}  {3}" -f $(if ($ok) { 'OK  ' } else { 'BAD ' }), $name, $expect, $detail)
}
function Skip([string]$name, [string]$why) {
    Write-Output ("[SKIP] " + $name + "  " + $why)
}

function Run-Gate([string]$tag) {
    $out = Join-Path $ReportDir ('gate-' + $tag + '.out.txt')
    if (Test-Path $out) { Remove-Item $out -Force }        # never let a stale log stand in for a run
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $txt = (& powershell -NoProfile -ExecutionPolicy Bypass -File $Gate 2>&1 | Out-String)
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    $stamp = (Get-Date).ToString('s')
    [System.IO.File]::WriteAllText($out, ('# gate-selftest | ' + $tag + ' | ran at ' + $stamp + ' | exit=' + $code + "`r`n" + $txt), [System.Text.Encoding]::UTF8)
    $f = [regex]::Matches($txt, 'FAIL\s*=\s*(\d+)')
    $h = [regex]::Matches($txt, 'HUMAN-ONLY\s*=\s*(\d+)')
    $failN = if ($f.Count -gt 0) { [int]$f[$f.Count - 1].Groups[1].Value } else { -1 }
    $humanN = if ($h.Count -gt 0) { [int]$h[$h.Count - 1].Groups[1].Value } else { -1 }
    return [pscustomobject]@{ Tag = $tag; Fail = $failN; Human = $humanN; Exit = $code; Text = $txt; Out = $out }
}

Write-Output '----- gate self-test (runs the REAL gate; every scenario restores what it touched) -----'
Write-Output ('gate   = ' + $Gate)
Write-Output ('reports= ' + $ReportDir)

# ---------------------------------------------------------------- baseline (known-good sample)
$base = Run-Gate 'A-baseline'
if ($base.Fail -lt 0) {
    Check 'A baseline' ('FAIL=' + $ExpectBaselineFail) $false 'the gate printed no summary line carrying FAIL=<n> -- cannot compare anything, fix the gate first'
    Write-Output ''
    Write-Output '----- gate self-test: FAIL (no usable baseline) -----'
    exit 1
}
Check 'A baseline (known-good)' ('FAIL=' + $ExpectBaselineFail) ($base.Fail -eq $ExpectBaselineFail) ('FAIL=' + $base.Fail + ' HUMAN-ONLY=' + $base.Human + ' exit=' + $base.Exit + ' -> ' + $base.Out)
if ($base.Fail -ne $ExpectBaselineFail) {
    Write-Output '      a known-good sample must be green BEFORE any injection: fix the tree (or pass'
    Write-Output '      -ExpectBaselineFail <n> for a tree that is knowingly red), then run this again.'
}

# ------------------------------------------- what this project's gate actually implements
# A scenario is only meaningful when the gate implements the item it exercises; the item's label
# must therefore appear in the baseline output. Absent => SKIP (never FAIL): an item this project
# does not ship must not be able to red the self-test.
function Has-Item([string]$label) { return $base.Text.Contains($label) }

# ------------------------------------------------------------------ auto-discovered scenarios
# The project's own acceptance table says which rows are visual / numeric and which png they cite:
# the target files come from THERE, never from a hard-coded list (see the header).
$spec = $null
$planDir = Join-Path $Project (([char[]]@(0x7B56, 0x5212) -join ''))
if (Test-Path $planDir) {
    foreach ($c in @(Get-ChildItem $planDir -Filter *.md -File -ErrorAction SilentlyContinue)) {
        $tx = [System.IO.File]::ReadAllText($c.FullName, [System.Text.Encoding]::UTF8)
        if ($tx -match '(?m)^\|\s*\d+(-\d+)?\s*\|' -and $tx.Contains($cVisual)) { $spec = $c.FullName; break }
    }
}
$visCite = @(); $numCite = @()
if ($spec) {
    foreach ($ln in ([System.IO.File]::ReadAllLines($spec, [System.Text.Encoding]::UTF8))) {
        if ($ln -notmatch $rowIdRe) { continue }
        $isVis = $ln.Contains($cVisual)
        $png = @([regex]::Matches($ln, '([A-Za-z0-9_\-]+\.png)') | ForEach-Object { $_.Groups[1].Value })
        if ($isVis) { $visCite += $png } else { $numCite += $png }
    }
    $numCite = @($numCite | Where-Object { $visCite -notcontains $_ })
}
function Shots-Of([string[]]$names) {
    $r = @()
    foreach ($n in $names) {
        $p = Join-Path $shotRoot $n
        if (Test-Path $p) { $r += $p }
    }
    return @($r)
}
$visFiles = @(Shots-Of $visCite)
$numFiles = @(Shots-Of $numCite)

# --- scenario B: one VISUAL row's cited png aged past its own area's newest dependency => red
$B = 'B visual-row png aged'
if ($visFiles.Count -eq 0) {
    Skip $B 'no visual-class row citing a png that exists on disk (no acceptance table or no shots)'
} elseif (-not (Has-Item 'evidence-freshness')) {
    Skip $B 'the gate implements no evidence-freshness item'
} else {
    $p = $visFiles[0]; $o = (Get-Item $p).LastWriteTime
    try {
        (Get-Item $p).LastWriteTime = [datetime]'2001-01-01T00:00:00'
        $r = Run-Gate 'B-visual-aged'
        $named = $r.Text.Contains((Split-Path $p -Leaf))
        Check $B 'FAIL >= baseline+1 and the aged png is named' (($r.Fail -ge $base.Fail + 1) -and $named) ('FAIL=' + $r.Fail + ' (baseline ' + $base.Fail + '), named=' + $named + ' -> ' + $r.Out)
    } finally { (Get-Item $p).LastWriteTime = $o }
}

# --- scenario C: a NUMERIC row's png aged the same way must NOT be judged (its evidence is a log)
$C = 'C numeric-row png aged'
if ($numFiles.Count -eq 0) {
    Skip $C 'no numeric-only row citing a png that exists on disk'
} elseif (-not (Has-Item 'evidence-freshness')) {
    Skip $C 'the gate implements no evidence-freshness item'
} else {
    $p = $numFiles[0]; $o = (Get-Item $p).LastWriteTime
    try {
        (Get-Item $p).LastWriteTime = [datetime]'2001-01-01T00:00:00'
        $r = Run-Gate 'C-numeric-aged'
        $named = $r.Text.Contains((Split-Path $p -Leaf))
        Check $C ('FAIL stays ' + $base.Fail + ' (a numeric png is not evidence)') (($r.Fail -eq $base.Fail) -and (-not $named)) ('FAIL=' + $r.Fail + ', named=' + $named + ' -> ' + $r.Out)
    } finally { (Get-Item $p).LastWriteTime = $o }
}

# --- scenario D: the contact-sheet index disappears => the visual row has no queryable cell
$D = 'D contact-sheet index removed'
if (-not (Test-Path $shotRoot)) {
    Skip $D 'no screenshot dir'
} elseif (-not (Has-Item 'evidence-economy')) {
    Skip $D 'the gate implements no evidence-economy item'
} else {
    $idx = @(Get-ChildItem $shotRoot -Filter *.index.tsv -File -ErrorAction SilentlyContinue)
    if ($idx.Count -eq 0) { Skip $D 'no *.index.tsv in the screenshot dir (nothing to hide)' }
    else {
        $f = $idx[0].FullName; $bak = $f + '.selftest-bak'
        try {
            Move-Item -LiteralPath $f -Destination $bak -Force
            $r = Run-Gate 'D-no-index'
            Check $D 'FAIL >= baseline+1 naming evidence-economy' (($r.Fail -ge $base.Fail + 1) -and ($r.Text.Contains('evidence-economy'))) ('FAIL=' + $r.Fail + ' -> ' + $r.Out)
        } finally { if (Test-Path $bak) { Move-Item -LiteralPath $bak -Destination $f -Force } }
    }
}

# --- scenario E: an impl file touched AFTER the capture => the captured evidence is stale
$E = 'E impl touched after capture'
if (-not (Test-Path $shotRoot)) {
    Skip $E 'no screenshot dir'
} elseif (-not (Has-Item 'freeze-before-capture')) {
    Skip $E 'the gate implements no freeze-before-capture item'
} else {
    $shots = @(Get-ChildItem $shotRoot -Filter *.png -File -ErrorAction SilentlyContinue)
    $impl = @()
    $idir = Join-Path $Project $ImplDir
    if (Test-Path $idir) { $impl = @(Get-ChildItem $idir -Recurse -Filter *.cs -File -ErrorAction SilentlyContinue) }
    if ($shots.Count -eq 0 -or $impl.Count -eq 0) { Skip $E 'needs at least one screenshot and one impl .cs' }
    else {
        $sp = $shots[0].FullName; $so = (Get-Item $sp).LastWriteTime
        $ip = $impl[0].FullName;  $io = (Get-Item $ip).LastWriteTime
        try {
            (Get-Item $sp).LastWriteTime = (Get-Date)                       # a capture "just now" => T0 now
            (Get-Item $ip).LastWriteTime = (Get-Date).AddMinutes(5)         # impl touched after that capture
            $r = Run-Gate 'E-impl-after-capture'
            Check $E 'FAIL >= baseline+1 naming freeze-before-capture' (($r.Fail -ge $base.Fail + 1) -and ($r.Text.Contains('freeze-before-capture'))) ('FAIL=' + $r.Fail + ' -> ' + $r.Out)
        } finally {
            (Get-Item $sp).LastWriteTime = $so
            (Get-Item $ip).LastWriteTime = $io
        }
    }
}

# ------------------------------------------------------------ fixture-driven scenarios (-Fixtures)
if ($Fixtures -eq '') {
    Skip 'F fixtures' 'no -Fixtures file (the four auto scenarios above need no fixture)'
} elseif (-not (Test-Path $Fixtures)) {
    Check 'F fixtures' 'file exists' $false ('fixture file not found: ' + $Fixtures)
} else {
    $n = 0
    foreach ($line in ([System.IO.File]::ReadAllLines($Fixtures, [System.Text.Encoding]::UTF8))) {
        if ($line -match '^\s*#' -or $line.Trim().Length -eq 0) { continue }
        $c = $line -split "`t"
        if ($c.Count -lt 6) { Check ('F row ' + ($n + 1)) '6 columns' $false ('bad fixture row: ' + $line); continue }
        $n++
        $sc = $c[0].Trim(); $op = $c[1].Trim(); $rel = $c[2].Trim().Replace('/', '\')
        $val = $c[3].Trim(); $exp = $c[4].Trim(); $rx = $c[5].Trim()
        $tgt = Join-Path $Project $rel
        $name = 'F ' + $sc
        if (-not (Test-Path $tgt)) { Skip $name ('target not present: ' + $rel); continue }
        $saved = $null; $moved = ''
        try {
            switch ($op) {
                'age-epoch'  { $saved = (Get-Item $tgt).LastWriteTime; (Get-Item $tgt).LastWriteTime = [datetime]'2001-01-01T00:00:00' }
                'age-future' { $saved = (Get-Item $tgt).LastWriteTime; (Get-Item $tgt).LastWriteTime = (Get-Date).AddMinutes(10) }
                'touch-now'  { $saved = (Get-Item $tgt).LastWriteTime; (Get-Item $tgt).LastWriteTime = (Get-Date) }
                'rename'     {
                    if ($val -eq '' -or $val -eq '-') { Check $name 'a new leaf name in column 4' $false 'op=rename needs the new leaf name'; continue }
                    $moved = Join-Path (Split-Path $tgt -Parent) $val
                    Move-Item -LiteralPath $tgt -Destination $moved -Force
                }
                default { Check $name 'a known op' $false ('unknown op: ' + $op); continue }
            }
            $r = Run-Gate ('F-' + ($sc -replace '[^A-Za-z0-9\-]', '_'))
            $ok = if ($exp -eq 'fail-up') { $r.Fail -ge $base.Fail + 1 } elseif ($exp -eq 'fail-same') { $r.Fail -eq $base.Fail } else { $false }
            if ($rx -ne '' -and $rx -ne '-') { $ok = $ok -and ($r.Text -match $rx) }
            Check $name ($exp + $(if ($rx -ne '' -and $rx -ne '-') { ' + /' + $rx + '/' } else { '' })) $ok ('FAIL=' + $r.Fail + ' (baseline ' + $base.Fail + ') -> ' + $r.Out)
        } finally {
            if ($moved -ne '' -and (Test-Path $moved)) { Move-Item -LiteralPath $moved -Destination $tgt -Force }
            elseif ($null -ne $saved) { (Get-Item $tgt).LastWriteTime = $saved }
        }
    }
    if ($n -eq 0) { Skip 'F fixtures' 'the fixture file has no data rows' }
}

# --------------------------------------------------------------- restoration (must be green again)
$after = Run-Gate 'Z-restored'
Check 'Z after restore' ('FAIL=' + $ExpectBaselineFail) ($after.Fail -eq $ExpectBaselineFail) ('FAIL=' + $after.Fail + ' HUMAN-ONLY=' + $after.Human + ' -> ' + $after.Out)

Write-Output ''
$bad = @($results | Where-Object { -not $_.Ok })
if ($bad.Count -eq 0) {
    Write-Output ('----- gate self-test: PASS (' + $results.Count + ' scenario(s): good stays green, every injected defect is caught) -----')
    exit 0
} else {
    Write-Output ('----- gate self-test: FAIL (' + $bad.Count + '/' + $results.Count + ' scenario(s) behaved wrong) -----')
    $bad | ForEach-Object { Write-Output ('        ' + $_.Name + '  expect=' + $_.Expect + '  got: ' + $_.Detail) }
    exit 1
}
