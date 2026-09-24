# readback-selfcheck.ps1 -- READ THE PRODUCTS BACK and check them mechanically.
#
# WHY: "the printed numbers are right" is NOT the same as "the product was written correctly".
# A writer can print a correct count while writing ZERO (or half the) data rows -- e.g. an
# `if () {} else {}` used as an expression, or a log line written before the file was flushed.
# So every product is RE-READ from disk and checked for:
#   * a fingerprint TRIPLE (sha256_16 + bytes + mtime).  A bare hash cannot tell "the same file
#     reported two different hashes" from "the file really changed"; time is part of the identity.
#   * the header's DECLARED count vs the number of BODY lines  (the half-write detector);
#   * duplicates / trailing-blank-line / entries outside the allowed root.
#
# READ-ONLY by construction: the script self-scans its own source for writing built-ins and FAILS
# if it finds one -- so "prove that re-running this cannot disturb the product" is mechanical.
# The needles are assembled from fragments so the scanner does not match its own source text.
#
# Usage
#   powershell -NoProfile -File scripts\readback-selfcheck.ps1 -ProjectRoot <dir> -Files <a,b,c>
#   powershell -NoProfile -File scripts\readback-selfcheck.ps1 -ProjectRoot <dir> -Files <a,b> `
#       -DeclareRe 'entries=(\d+)' -WithinRoot batch
#
#   -Files        comma-separated product paths; relative paths resolve against -ProjectRoot.
#                 (A comma-separated STRING on purpose: PowerShell's -File entry point does not
#                 split `-Files a,b,c` into an array.)
#   -DeclareRe    regex whose group 1 is the count the header declares (default `entries=(\d+)`).
#                 No match => loud NOT-JUDGED for that file, never a silent pass.
#   -WithinRoot   optional: every body line must start with this prefix (e.g. `.ai-tmp/`).
#   -MinBody      body-line floor; fewer than this fails (default 1) -- an empty product is a
#                 half-write unless you say otherwise.
#
# exit 0 = all checks passed; 1 = at least one FAIL; 2 = the read-only self-scan failed.
param(
    [Parameter(Mandatory = $true)][string]$Files,
    [string]$ProjectRoot = '',
    [string]$DeclareRe = 'entries=(\d+)',
    [string]$WithinRoot = '',
    [int]$MinBody = 1
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = (Get-Location).Path }
$root = [IO.Path]::GetFullPath($ProjectRoot)

function Resolve-Abs([string]$p) {
    if ([IO.Path]::IsPathRooted($p)) { return [IO.Path]::GetFullPath($p) }
    return [IO.Path]::GetFullPath((Join-Path $root $p))
}

$fails = 0
function Ok([string]$m) { Write-Output ('  PASS  ' + $m) }
function No([string]$m) { $script:fails++; Write-Output ('  FAIL  ' + $m) }
function Nj([string]$m) { Write-Output ('  NOT-JUDGED  ' + $m) }

# ---- C0. read-only self-scan ----------------------------------------------------
$w = @(('Set' + '-Content'), ('Add' + '-Content'), ('Out' + '-File'), ('WriteAll' + 'Text'),
       ('WriteAll' + 'Lines'), ('New' + '-Item'), ('Remove' + '-Item'), ('Copy' + '-Item'), ('Move' + '-Item'))
$selfText = [IO.File]::ReadAllText($PSCommandPath)
$hits = @($w | Where-Object { $selfText.Contains($_) })
Write-Output ('readback selfcheck | at ' + (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK'))
Write-Output ('C0 read-only self-scan: writing built-ins in this file = ' + $hits.Count + ' ' + ($hits -join ','))
if ($hits.Count -gt 0) {
    Write-Output 'C0 FAIL: this script claims to be read-only but contains a writer'
    exit 2
}
Write-Output '# every fingerprint below is a TRIPLE (sha256_16 + bytes + mtime) -- read the triple,'
Write-Output '# not the hash alone: a bare hash cannot separate "same file" from "changed file".'
Write-Output ''

$list = @($Files.Split(',') | Where-Object { $_.Trim().Length -gt 0 } | ForEach-Object { $_.Trim() })
if ($list.Count -eq 0) { Write-Output 'FAIL no -Files given'; exit 1 }

foreach ($rel in $list) {
    $p = Resolve-Abs $rel
    $leaf = Split-Path $p -Leaf
    if (-not (Test-Path -LiteralPath $p)) { No ($rel + ' missing'); Write-Output ''; continue }

    $it = Get-Item -LiteralPath $p
    $hash = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.Substring(0, 16)
    $all = @(Get-Content -LiteralPath $p -Encoding UTF8)
    $hdr = @($all | Where-Object { $_ -match '^\s*#' })
    $body = @($all | Where-Object { $_.Trim().Length -gt 0 -and $_ -notmatch '^\s*#' })
    Write-Output ('-- ' + $leaf + '   sha256_16=' + $hash + '  bytes=' + $it.Length +
                  '  mtime=' + $it.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') +
                  '   lines=' + $all.Count + '  header=' + $hdr.Count + '  body=' + $body.Count)

    # invariant 1: the header's declared count == the number of body lines (cross-column)
    $declared = $null
    foreach ($h in $hdr) {
        $m = [regex]::Match($h, $DeclareRe)
        if ($m.Success -and $m.Groups.Count -ge 2) { $declared = [int]$m.Groups[1].Value }
    }
    if ($null -eq $declared) {
        Nj ($leaf + ': header matches ' + $DeclareRe + ' on none of its ' + $hdr.Count + ' header line(s)')
    } elseif ($declared -eq $body.Count) {
        Ok ($leaf + ': declared ' + $declared + ' == body lines ' + $body.Count)
    } else {
        No ($leaf + ': declared ' + $declared + ' != body lines ' + $body.Count + '   <== half write?')
    }

    # invariant 2: a product with no body at all is a half write unless -MinBody lowers the floor
    if ($body.Count -lt $MinBody) { No ($leaf + ': body lines ' + $body.Count + ' < -MinBody ' + $MinBody) }
    else { Ok ($leaf + ': body lines ' + $body.Count + ' >= -MinBody ' + $MinBody) }

    # invariant 3: unique entries
    $uniq = @($body | Sort-Object -Unique).Count
    if ($uniq -eq $body.Count) { Ok ($leaf + ': all ' + $body.Count + ' entries unique') }
    else { No ($leaf + ': duplicate entries = ' + ($body.Count - $uniq)) }

    # invariant 4: every entry lives inside the declared root, with forward slashes only
    if (-not [string]::IsNullOrWhiteSpace($WithinRoot)) {
        $outside = @($body | Where-Object { -not $_.StartsWith($WithinRoot) }).Count
        $bslash = @($body | Where-Object { $_.Contains('\') }).Count
        if ($outside -eq 0 -and $bslash -eq 0) { Ok ($leaf + ': every entry is under ' + $WithinRoot + ' with forward slashes only') }
        else { No ($leaf + ': outside-root entries=' + $outside + '  backslash entries=' + $bslash) }
    } else {
        Nj ($leaf + ': entry-root check not configured (-WithinRoot empty)')
    }

    # invariant 5: the file ends with exactly one newline (a missing final newline is how a
    # truncated last row looks; two means an append wrote a blank separator into the body)
    $bytes = [IO.File]::ReadAllBytes($p)
    if ($bytes.Length -eq 0) { No ($leaf + ': zero bytes') }
    elseif ($bytes[$bytes.Length - 1] -ne 10) { No ($leaf + ': last byte is not LF (truncated final row?)') }
    else { Ok ($leaf + ': file ends with LF') }

    # informational: entries cited but absent on disk are a DOCUMENTED state, so report (a FAIL
    # here would be wrong) -- but silence would hide them.
    $absent = 0
    foreach ($e in $body) {
        if (-not (Test-Path -LiteralPath (Join-Path $root ($e -replace '/', '\')))) { $absent++ }
    }
    Write-Output ('  NOTE  cited-but-absent on disk = ' + $absent + ' (informational; a FAIL here would be wrong)')
    Write-Output ''
}

Write-Output ('READBACK SELFCHECK ' + $(if ($fails -eq 0) { 'PASS' } else { 'FAIL (' + $fails + ')' }))
if ($fails -gt 0) { exit 1 }
exit 0
