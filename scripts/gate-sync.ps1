# gate-sync.ps1 -- keep a project's tools/verify.ps1 in sync with the template's item list
#
# Why this exists: "who maintains the gate" is the question deterministic-gates.md never answers.
#   Measured: the template declares 22 check items; several projects landed only 18/19 of them,
#   each with a DIFFERENT subset -- and the same item carries a DIFFERENT name in the template
#   vs the project (play-ledger vs play-budget, handoff-doc-found vs no-handoff-docs), so any
#   ad-hoc comparison silently misses the drift. The rule was written; the gate was never wired.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate-sync.ps1 -Project <project-root>
#   powershell ... -Project <root> -Template <path-to-verify-template.md>
#
# ASCII-only on purpose (PowerShell 5.1 parses a BOM-less .ps1 as ANSI => CJK in source breaks it).

param(
  [string]$Project = '',
  [string]$Template = ''
)

$ErrorActionPreference = 'Continue'
$root = Split-Path $PSScriptRoot -Parent
$fail = 0

function Say([string]$status, [string]$name, [string]$detail) {
    Write-Output ("{0,-5} {1}  {2}" -f $status, $name, $detail)
}

if ($Template -eq '') { $Template = Join-Path $root 'reference\verify-template.md' }
if (-not (Test-Path $Template)) {
    $fail++; Say 'FAIL' 'gate-sync' ('template not found: ' + $Template)
    exit 1
}
if ($Project -eq '') {
    $fail++; Say 'FAIL' 'gate-sync' 'pass -Project <project-root>'
    exit 1
}
$gate = Join-Path $Project 'tools\verify.ps1'
if (-not (Test-Path $gate)) {
    $fail++; Say 'FAIL' 'gate-sync' ('no tools\verify.ps1 under ' + $Project + ' -- copy it from the template (SKILL.md 0.7 item 1)')
    exit 1
}

# -- 1) declared items: the machine-readable block in the template --------------------
#    Format: <name>|<alias-or-empty>|<required-or-planned>|<one-line what>
#    alias    : accept an older name a project still uses (name drift is itself a finding).
#    planned  : declared but not yet enforced -- printed as INFO, never counted as missing.
$tplTxt = [System.IO.File]::ReadAllText($Template, [System.Text.Encoding]::UTF8)
$m = [regex]::Match($tplTxt, '(?s)<!--\s*GATE-ITEMS-BEGIN\s*-->(.*?)<!--\s*GATE-ITEMS-END\s*-->')
if (-not $m.Success) {
    $fail++; Say 'FAIL' 'gate-items' 'template carries no GATE-ITEMS block -- add one so this comparison is possible'
    exit 1
}
$declared = @()
$planned  = @()
$aliasOf  = @{}
foreach ($ln in ($m.Groups[1].Value -split "`n")) {
    $t = $ln.Trim()
    if ($t.Length -eq 0 -or $t.StartsWith('#')) { continue }
    $parts = $t -split '\|'
    $n = $parts[0].Trim()
    if ($n.Length -eq 0) { continue }
    $st = if ($parts.Count -ge 3) { $parts[2].Trim() } else { 'required' }
    if ($st -eq 'planned') { if ($planned -notcontains $n) { $planned += $n }; continue }
    if ($declared -notcontains $n) { $declared += $n }
    if ($parts.Count -ge 2 -and $parts[1].Trim().Length -gt 0) { $aliasOf[$parts[1].Trim()] = $n }
}
Say 'INFO' 'gate-items' ('template requires ' + $declared.Count + ' item(s)')
if ($planned.Count -gt 0) { Say 'INFO' 'gate-planned' ('declared but not enforced yet: ' + ($planned -join ', ')) }

# -- 2) implemented items: every Say('<STATUS>','<name>',...) call in the project gate --
$gTxt = [System.IO.File]::ReadAllText($gate, [System.Text.Encoding]::UTF8)
$impl = @()
foreach ($mm in [regex]::Matches($gTxt, "Say\s+'[A-Za-z\-]+'\s+'([a-z0-9\-]+)'")) {
    $impl += $mm.Groups[1].Value
}
$impl = @($impl | Sort-Object -Unique)
Say 'INFO' 'gate-impl' ('project implements ' + $impl.Count + ' named check(s)')

# -- 3) compare: a declared item counts as done under its name OR its alias ------------
$missing = @()
$viaAlias = @()
foreach ($d in $declared) {
    if ($impl -contains $d) { continue }
    $alias = ''
    foreach ($k in $aliasOf.Keys) { if ($aliasOf[$k] -eq $d) { $alias = $k } }
    if ($alias -ne '' -and ($impl -contains $alias)) { $viaAlias += ($d + '(as ' + $alias + ')') }
    else { $missing += $d }
}
if ($viaAlias.Count -gt 0) {
    Say 'WARN' 'gate-alias' ('matched only under an older name: ' + ($viaAlias -join ', ') + ' -- rename to the template name')
}
if ($missing.Count -eq 0) {
    Say 'PASS' 'gate-sync' ('all ' + $declared.Count + ' template item(s) present')
} else {
    $fail++; Say 'FAIL' 'gate-sync' ('' + $missing.Count + ' template item(s) missing: ' + ($missing -join ', '))
    $missing | ForEach-Object { Write-Output ('            missing: ' + $_) }
    Write-Output '            copy the implementation from reference/verify-template.md (it ships ready to paste)'
}

# -- 4) gate self-test: a check that cries wolf is worse than no check ----------------
#    The two-sample rule from reference/anti-gaming.md section 5: a new/changed check must
#    (a) PASS on a known-good sample and (b) FAIL on a known-bad sample. This cannot be run
#    mechanically from here, so it is reported as HUMAN-ONLY with the exact acceptance test.
Write-Output ''
Say 'HUMAN-ONLY' 'gate-selftest' 'for every item added/edited since last delivery, prove BOTH: (1) a known-good sample PASSES, (2) an injected defect FAILS. A check that only reports red must not ship (anti-gaming.md section 5)'

Write-Output ''
Write-Output ("===== summary: FAIL=" + $fail + " =====")
exit $(if ($fail -gt 0) { 1 } else { 0 })
