# skill-lint.ps1 -- reference-integrity + consistency lint for the skill package.
#
# Why this exists (measured 2026-09-21, all found by a HUMAN, not by any gate):
#   (a) SECTION-level dangling pointers: SKILL.md said "details -> rules-full.md section 0.1"
#       while rules-full.md had no such section. skill-health.ps1 said PASS -- it only checks
#       FILE-level reachability, never section-level.
#   (b) SELF-CONTRADICTING CONSTANT: maxTurns was written as 450 in one section and 250 in
#       another; the commit that changed it updated only one of the two places.
#   (c) A judgement rule that produced false reds on real data -- not caught at all.
# This script closes (a) and (b). (c) has no mechanical answer; it is covered by the
# two-sample rule in reference/anti-gaming.md section 5 and must be done by whoever writes
# the check.
#
# DESIGN RULE FOR THIS FILE: ZERO FALSE REDS. Two revisions of this script were themselves
# wrong before shipping, both times by over-reaching:
#   rev1 judged cross-file references against the current file  -> 9 false reds
#   rev2 required a digit-then-whitespace heading              -> 14 false reds
#     (real headings look like "## 9. title", i.e. a dot after the number)
# Both were caught by running it on real data, not by reading it. Any change here must be
# re-tested against a known-good tree and an injected defect.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/skill-lint.ps1
#   powershell ... -Root <skill-dir>
#
# ASCII-only on purpose (PowerShell 5.1 parses a BOM-less .ps1 as ANSI => CJK in source breaks it).

param([string]$Root = '')

$ErrorActionPreference = 'Continue'
if ($Root -eq '') { $Root = Split-Path $PSScriptRoot -Parent }
$fail = 0

function Say([string]$status, [string]$name, [string]$detail) {
    Write-Output ("{0,-5} {1}  {2}" -f $status, $name, $detail)
}
function Read-Utf8([string]$p) { [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8) }

$S = [char]0x00A7                                          # section sign
$IDEO = [char]0x3000                                       # ideographic space
$idPat = '([0-9]{1,2}(?:\.[0-9]{1,2})?)'
$files = @(Get-ChildItem $Root -Recurse -File -Include *.md -ErrorAction SilentlyContinue)

# -- 1) collect declared section ids, per file and globally ------------------------
#    Heading styles accepted: "## 9. title"  "## 9.5 title"  "## section 9 title"
$byFile = @{}
$all = @{}
foreach ($f in $files) {
    $rel = $f.FullName.Substring($Root.Length + 1) -replace '\\', '/'
    $ids = @{}
    foreach ($line in ([System.IO.File]::ReadAllLines($f.FullName, [System.Text.Encoding]::UTF8))) {
        if ($line -notmatch '^#{2,4}\s') { continue }
        $h = $line -replace '^#{2,4}\s*', ''
        $h = $h -replace ('^' + $S + '\s*'), ''
        if ($h -match ('^' + $idPat + '\s*\.?(?=\s|$|:|' + $IDEO + ')')) { $ids[$matches[1]] = $true }
    }
    $byFile[$rel] = $ids
    foreach ($k in $ids.Keys) { $all[$k] = $true }
}
Say 'INFO' 'sections' ('' + $all.Count + ' distinct section id(s) declared across ' + $files.Count + ' md file(s)')

# -- 2) section references must resolve --------------------------------------------
#    Two forms, judged differently. Whatever is NOT form A falls through to form B, so no
#    reference is ever silently skipped.
#      A) ADJACENT cross-file pointer:  `file.md` §N        (only whitespace between them)
#         -> the id must be declared IN THAT FILE.
#      B) everything else (bare §N, or a file named elsewhere on the line)
#         -> the id must be declared SOMEWHERE. This is the safe side: the entry file and the
#            full version are two views of one rule set, and a line may name an unrelated file.
#            Measured: judging form B as form A produced 7 false reds, including one where the
#            "file" was NEXT.md -- a FORBIDDEN name being quoted as a counter-example.
$refFiles = @('SKILL.md', 'reference\rules-full.md')
$adjacentRe = '`([A-Za-z0-9_\-/]+\.md)`[ \t]*' + $S + '\s*' + $idPat
$anyRe = $S + '\s*' + $idPat
$bad = @()
foreach ($rf in $refFiles) {
    $p = Join-Path $Root $rf
    if (-not (Test-Path $p)) { continue }
    foreach ($line in ([System.IO.File]::ReadAllLines($p, [System.Text.Encoding]::UTF8))) {
        if ($line.IndexOf($S) -lt 0) { continue }

        # form A
        $strict = @{}
        foreach ($m in [regex]::Matches($line, $adjacentRe)) {
            $target = $m.Groups[1].Value
            $id     = $m.Groups[2].Value
            $strict[$id] = $true
            $leaf = Split-Path $target -Leaf
            $hit = $false
            foreach ($k in $byFile.Keys) {
                if ((Split-Path $k -Leaf) -eq $leaf -and $byFile[$k].ContainsKey($id)) { $hit = $true; break }
            }
            if (-not $hit) { $bad += ($rf + '  ->  `' + $target + '` ' + $S + $id + '  (no such section in that file)') }
        }

        # form B (everything not already judged strictly)
        foreach ($m in [regex]::Matches($line, $anyRe)) {
            $id = $m.Groups[1].Value
            if ($strict.ContainsKey($id)) { continue }
            if (-not $all.ContainsKey($id)) { $bad += ($rf + '  ->  bare ' + $S + $id + '  (declared nowhere)') }
        }
    }
}
$bad = @($bad | Sort-Object -Unique)
if ($bad.Count -eq 0) {
    Say 'PASS' 'section-refs' 'every section reference resolves (single-target checked in-file, ambiguous checked globally)'
} else {
    $fail++
    Say 'FAIL' 'section-refs' ('' + $bad.Count + ' dangling section reference(s) -- the reader is sent nowhere:')
    $bad | Select-Object -First 25 | ForEach-Object { Write-Output ('            ' + $_) }
}

# -- 3) key constants must not contradict themselves -------------------------------
#    Add a row every time a constant gets duplicated. Only listed keys are judged, so this
#    check cannot produce a false red.
$consts = @(
    @{ n = 'maxTurns'; re = 'maxTurns\s*[:=]\s*([0-9]{2,4})' }
)
foreach ($c in $consts) {
    $vals = @{}
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($Root.Length + 1) -replace '\\', '/'
        foreach ($m in [regex]::Matches((Read-Utf8 $f.FullName), $c.re)) {
            $v = $m.Groups[1].Value
            if (-not $vals.ContainsKey($v)) { $vals[$v] = @() }
            if ($vals[$v] -notcontains $rel) { $vals[$v] += $rel }
        }
    }
    if ($vals.Count -eq 0) {
        Say 'SKIP' ('const-' + $c.n) 'not found anywhere'
    } elseif ($vals.Count -eq 1) {
        $only = @($vals.Keys)[0]
        Say 'PASS' ('const-' + $c.n) ('' + $c.n + ' = ' + $only + ' consistently (' + $vals[$only].Count + ' file(s))')
    } else {
        $fail++
        $desc = @()
        foreach ($k in $vals.Keys) { $desc += ($c.n + '=' + $k + ' in ' + ($vals[$k] -join ' + ')) }
        Say 'FAIL' ('const-' + $c.n) ('self-contradicting values: ' + ($desc -join ' | '))
    }
}

Write-Output ''
Write-Output ("===== skill-lint summary: FAIL=" + $fail + " =====")
exit $(if ($fail -gt 0) { 1 } else { 0 })
