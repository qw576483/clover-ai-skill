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

# Template discovery order. Why it is not a single candidate: this script gets COPIED into
# <project>/tools/, so $PSScriptRoot-1 = the PROJECT root there -- one candidate then resolves
# to <project>/reference/verify-template.md, which no project has => "template not found" on
# every project-level run unless -Template is passed by hand. 
if ($Template -eq '') {
    $cands = @(
        (Join-Path $root 'reference\verify-template.md'),
        (Join-Path $root 'tools\verify-template.md'),
        (Join-Path (Split-Path $PSScriptRoot -Parent) 'reference\verify-template.md'),
        (Join-Path $env:USERPROFILE '.codebuddy\skills\ai-skill\reference\verify-template.md')
    )
    foreach ($c in $cands) { if (Test-Path $c) { $Template = $c; break } }
    if ($Template -eq '') { $Template = $cands[0] }
}
if (-not (Test-Path $Template)) {
    $fail++; Say 'FAIL' 'gate-sync' ('template not found: ' + $Template + ' -- pass -Template <path to verify-template.md>')
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

# -- 3b) skeleton-equals-shipped: "template skeleton code == shipped gate code" -------
#    Why this exists: the template ships paste-ready blocks; a project copies one and then edits it
#    "just a little" -- a renamed label, or a hidden dependency on a variable some OTHER check
#    happens to define. Both kept every check green while the two copies drifted apart, and the
#    drift only surfaced when the other check was touched. (Measured: exactly that happened to the
#    no-assets-screenshots block.)
#    Scope, and why it is not "compare every block" (ZERO FALSE REDS):
#      * ONLY a template block whose header comment carries the token [SHIPPED-VERBATIM] is compared;
#      * a project legitimately rewrites paths/labels in the other blocks, so demanding byte
#        equality everywhere would be a false-red machine -- that is how a gate gets ignored.
#    Matching: a template block is looked up in the shipped gate by its LABEL SET first (the label is
#    the stable identity -- item NUMBERS shift as soon as a project inserts one check), then by item
#    number. Not found at all => FAIL (it is marked as shipped verbatim, so it must exist).
#    Comparison: strip comments, then blank out string literals -> wording may differ, CODE may not.
function Normalize-GateCode([string]$text) {
    $out = @()
    foreach ($ln in ($text -split "`r?`n")) {
        $s = $ln.Trim()
        if ($s -eq '' -or $s.StartsWith('#')) { continue }
        $sb = New-Object System.Text.StringBuilder
        $q = [char]0
        foreach ($ch in $s.ToCharArray()) {
            if ($q -eq [char]0 -and ($ch -eq "'" -or $ch -eq '"')) { $q = $ch }
            elseif ($q -ne [char]0 -and $ch -eq $q) { $q = [char]0 }
            elseif ($q -eq [char]0 -and $ch -eq '#') { break }
            [void]$sb.Append($ch)
        }
        $code = $sb.ToString().Trim()
        $code = [regex]::Replace($code, "'[^']*'", "'str'")
        $code = [regex]::Replace($code, '"[^"]*"', '"str"')
        if ($code -ne '') { $out += $code }
    }
    return ($out -join "`n")
}
function Split-GateBlocks([string]$text) {
    # a block starts at a line matching "# <n>)" and runs to just before the next one (or EOF)
    $lines = $text -split "`r?`n"
    $idx = @()
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^#\s*(\d+[a-z]?)\)') { $idx += $i } }
    $res = @()
    for ($k = 0; $k -lt $idx.Count; $k++) {
        $end = if ($k + 1 -lt $idx.Count) { $idx[$k + 1] - 1 } else { $lines.Count - 1 }
        $num = [regex]::Match($lines[$idx[$k]], '^#\s*(\d+[a-z]?)\)').Groups[1].Value
        $res += [pscustomobject]@{ Num = $num; Text = (($lines[$idx[$k]..$end]) -join "`n") }
    }
    return $res
}
function Get-GateLabels([string]$text) {
    $r = @()
    foreach ($mm in [regex]::Matches($text, "Say\s+'[A-Za-z\-]+'\s+'([^']+)'")) { $r += $mm.Groups[1].Value }
    return @($r | Sort-Object -Unique)
}
$tplBlocks = @()
foreach ($fm in [regex]::Matches($tplTxt, '(?s)```powershell(.*?)```')) {
    foreach ($b in (Split-GateBlocks $fm.Groups[1].Value)) {
        if ($b.Text.Contains('[SHIPPED-VERBATIM]')) { $tplBlocks += $b }
    }
}
if ($tplBlocks.Count -eq 0) {
    Say 'INFO' 'skeleton-equals-shipped' 'no template block carries [SHIPPED-VERBATIM] -- nothing to compare (tag a block whose code must stay identical in every project)'
} else {
    $shipBlocks = @(Split-GateBlocks $gTxt)
    $drift = @()
    $notes = @()
    foreach ($tb in $tplBlocks) {
        $tl = Get-GateLabels $tb.Text
        $match = @($shipBlocks | Where-Object { (($tl.Count -gt 0) -and ((Get-GateLabels $_.Text) -join ',') -eq ($tl -join ',')) })
        if ($match.Count -eq 0) { $match = @($shipBlocks | Where-Object { $_.Num -eq $tb.Num }) }
        if ($match.Count -eq 0) {
            $drift += ('block #' + $tb.Num + ' is marked [SHIPPED-VERBATIM] but the shipped gate has no block with the same label(s) [' + ($tl -join ',') + ']')
            continue
        }
        $na = Normalize-GateCode $tb.Text
        $nb = Normalize-GateCode $match[0].Text
        # A shipped block may legitimately carry EXTRA TRAILING lines: a template block ends at the next
        # "# <n>)" marker, while the project's LAST block runs to EOF and therefore swallows the gate
        # footer (summary + exit). Treating that as drift was a FALSE RED (measured on the first real
        # run), so the rule is: the template block must be a PREFIX of the shipped block. Only trailing
        # extras are tolerated, and they are reported as a note -- anything changed or inserted is not.
        $tLines = @($na -split "`n")
        $sLines = @($nb -split "`n")
        $prefix = ($sLines.Count -ge $tLines.Count)
        if ($prefix) {
            for ($i = 0; $i -lt $tLines.Count; $i++) { if ($sLines[$i] -ne $tLines[$i]) { $prefix = $false; break } }
        }
        if ($prefix) {
            $extra = $sLines.Count - $tLines.Count
            if ($extra -gt 0) { $notes += ('block #' + $tb.Num + ': ' + $extra + ' extra trailing code line(s) in the shipped copy (gate footer / local additions) -- not drift') }
        } else {
            $drift += ('block #' + $tb.Num + ' (labels ' + ($tl -join ',') + '): CODE differs (comments/strings ignored) -- template ' + $tLines.Count + ' code line(s) vs shipped ' + $sLines.Count)
            foreach ($d in @(Compare-Object $tLines $sLines)) {
                $drift += ('    ' + $d.SideIndicator + ' ' + $d.InputObject)
            }
        }
    }
    if ($drift.Count -eq 0) {
        Say 'PASS' 'skeleton-equals-shipped' ('' + $tplBlocks.Count + ' [SHIPPED-VERBATIM] block(s) identical to the shipped gate (comments/strings ignored)')
        $notes | ForEach-Object { Write-Output ('            note: ' + $_) }
    } else {
        $fail++
        Say 'FAIL' 'skeleton-equals-shipped' ('' + $drift.Count + ' line(s) of drift between the template and the shipped gate')
        $drift | Select-Object -First 30 | ForEach-Object { Write-Output ('            ' + $_) }
    }
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
