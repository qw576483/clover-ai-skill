# cleanup-ambiguity-sim.ps1 -- SIMULATE the delivery cleanup and prove, with a negative control,
# that the "a same-named file in several places => keep EVERY candidate" rule is IMPLEMENTED.
#
# WHY: until it is measured, that rule is only a promise.  An ambiguous name is MORE dangerous than
# a unique one: a single deletion can hit several cited files at once, and the citation does not say
# which copy was meant, so the deletion is not recoverable.  Hence:
#   * report the ambiguous names, list their candidates, and require would-be deletions = 0;
#   * run a NEGATIVE CONTROL with the WRONG rule ("keep only the FIRST candidate") and require
#     deletions > 0 -- otherwise this check cannot tell a correct implementation from a broken one
#     (a rule with no discriminating measurement behind it is tonight's Nth "looks right").
#
# "AMBIGUOUS" IS NOT A VERDICT OF SAFETY.  It is an OPEN state whose safety depends on the
# implementation keeping all candidates.
#
# READ-ONLY: it reads files only; it never deletes or writes anything.  The script also self-checks
# that claim (see the C0 block) so that anyone may re-run it without disturbing a product.
#
# Usage
#   powershell -NoProfile -File scripts\cleanup-ambiguity-sim.ps1 -ProjectRoot <dir> -Whitelist <path>
#   powershell -NoProfile -File scripts\cleanup-ambiguity-sim.ps1 -ProjectRoot <dir> -Whitelist <path> -NegativeControl
#   powershell -NoProfile -File scripts\cleanup-ambiguity-sim.ps1 -ProjectRoot <dir> -Whitelist <path> -AmbigNames <path>
#
#   -Whitelist   TEXT file, one protected repo-relative path per line ('#' comments allowed)
#   -AmbigNames  TEXT file, one ambiguous basename per line ('#' comments allowed).  Feed this the
#                bucket dump of whatever tool decided "this name is cited and ambiguous" -- the
#                simulation must consume THAT tool's verdict, not re-guess which names count
#                (re-guessing once flagged 93 uncited runtime files as citations).
#                Without -AmbigNames every basename with >=2 candidates inside the zone is used.
#   -Zone        repo-relative deletable root (default .ai-tmp): the ONLY universe cleanup may delete
#   -ScanRoots   comma-separated repo-relative dirs used to count repo-wide candidates
#                (default: every top-level directory except -Zone)
#   -Samples     comma-separated basenames to report individually (optional)
#   -MaxList     how many paths to print per bucket (default 6)
#
# NOTE ON ARRAY PARAMETERS: PowerShell's `-File` entry point does NOT split `-ScanRoots a,b` into an
# array, so every list is taken as ONE comma-separated string and split inside the script.
#
# exit 0 = real rule deletes nothing (and, with -NegativeControl, the wrong rule does delete)
# exit 1 = the real rule would delete an ambiguous candidate (or -NegativeControl found no power)
param(
    [Parameter(Mandatory = $true)][string]$Whitelist,
    [string]$ProjectRoot = '',
    [string]$AmbigNames = '',
    [string]$Zone = '.ai-tmp',
    [string]$ScanRoots = '',
    [string]$Samples = '',
    [string]$SkipRe = '\\(Library|obj|bin|node_modules|\.git|__pycache__|Temp)\\',
    [switch]$NegativeControl,
    [int]$MaxList = 6
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = (Get-Location).Path }
$root = [IO.Path]::GetFullPath($ProjectRoot)

function Resolve-Abs([string]$p) {
    if ([IO.Path]::IsPathRooted($p)) { return [IO.Path]::GetFullPath($p) }
    return [IO.Path]::GetFullPath((Join-Path $root $p))
}
function Read-List([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    return @(Get-Content -LiteralPath $path -Encoding UTF8 |
             Where-Object { $_.Trim().Length -gt 0 -and $_ -notmatch '^\s*#' } |
             ForEach-Object { $_.Trim().Replace('\', '/') })
}
function Rel([string]$full) { return ($full.Substring($root.Length).TrimStart('\', '/').Replace('\', '/')) }

# ---- C0. re-run safety: this script must contain no writing built-in -------------
# The needle strings are assembled from fragments so that this very regex does not match its own
# source text (a self-scan that always trips on itself would be useless).
$w = @(('Set' + '-Content'), ('Add' + '-Content'), ('Out' + '-File'), ('WriteAll' + 'Text'),
       ('WriteAll' + 'Lines'), ('New' + '-Item'), ('Remove' + '-Item'), ('Copy' + '-Item'), ('Move' + '-Item'))
$selfText = [IO.File]::ReadAllText($PSCommandPath)
$hits = @($w | Where-Object { $selfText.Contains($_) })
Write-Output ('C0 re-run safety: writing built-ins appearing in this file = ' + $hits.Count + ' ' + ($hits -join ','))
if ($hits.Count -gt 0) {
    Write-Output 'C0 FAIL: this script claims to be read-only but contains a writer -- fix the claim or the script'
    exit 2
}

# ---- inputs ---------------------------------------------------------------------
$wlPath = Resolve-Abs $Whitelist
if (-not (Test-Path -LiteralPath $wlPath)) { Write-Output ('FAIL whitelist not found: ' + $wlPath); exit 1 }
$wlLines = Read-List $wlPath
if ($wlLines.Count -lt 10) { Write-Output ('FAIL whitelist suspiciously small (' + $wlLines.Count + ' entries)'); exit 1 }
$wlSet = @{}
foreach ($l in $wlLines) { $wlSet[$l] = 1 }
$wlHash = (Get-FileHash -LiteralPath $wlPath -Algorithm SHA256).Hash.Substring(0, 16)

# ---- the deletable universe -----------------------------------------------------
$zonePath = Resolve-Abs $Zone
if (-not (Test-Path -LiteralPath $zonePath)) { Write-Output ('FAIL zone not found: ' + $zonePath); exit 1 }
$zone = @(Get-ChildItem -LiteralPath $zonePath -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { Rel $_.FullName })
$byNameZone = @{}
foreach ($z in $zone) {
    $n = Split-Path $z -Leaf
    if (-not $byNameZone.ContainsKey($n)) { $byNameZone[$n] = New-Object System.Collections.Generic.List[string] }
    $byNameZone[$n].Add($z)
}

# ---- repo-wide basename counts (to know which names are ambiguous) ---------------
if ([string]::IsNullOrWhiteSpace($ScanRoots)) {
    $roots = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
               Where-Object { (Rel $_.FullName) -ne $Zone.Replace('\', '/') } | ForEach-Object { Rel $_.FullName })
} else {
    $roots = @($ScanRoots.Split(',') | Where-Object { $_.Trim().Length -gt 0 } | ForEach-Object { $_.Trim() })
}
$repoBy = @{}
foreach ($r in $roots) {
    $rp = Resolve-Abs $r
    if (-not (Test-Path -LiteralPath $rp)) { continue }
    Get-ChildItem -LiteralPath $rp -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.FullName -match $SkipRe) { return }
        if (-not $repoBy.ContainsKey($_.Name)) { $repoBy[$_.Name] = 0 }
        $repoBy[$_.Name]++
    }
}

# ---- the ambiguous name set -----------------------------------------------------
$ambSource = 'ALL in-zone names with >=2 candidates (no -AmbigNames given)'
if (-not [string]::IsNullOrWhiteSpace($AmbigNames)) {
    $ap = Resolve-Abs $AmbigNames
    if (-not (Test-Path -LiteralPath $ap)) { Write-Output ('FAIL ambiguous-name file not found: ' + $ap); exit 1 }
    $amb = @(Get-Content -LiteralPath $ap -Encoding UTF8 |
             Where-Object { $_.Trim().Length -gt 0 -and $_ -notmatch '^\s*#' } |
             ForEach-Object { $_.Trim() } | Sort-Object -Unique)
    $ambSource = $ap + '  sha256_16=' + (Get-FileHash -LiteralPath $ap -Algorithm SHA256).Hash.Substring(0, 16)
} else {
    $amb = @($byNameZone.Keys | Where-Object { @($byNameZone[$_]).Count -ge 2 } | Sort-Object)
}

$ambInZone = New-Object System.Collections.Generic.List[string]
$ambDeletable = New-Object System.Collections.Generic.List[string]
foreach ($n in $amb) {
    if (-not $byNameZone.ContainsKey($n)) { continue }
    foreach ($z in $byNameZone[$n]) {
        $ambInZone.Add($z)
        if (-not $wlSet.ContainsKey($z)) { $ambDeletable.Add($z) }
    }
}

# ---- would-be deletions under the REAL rule -------------------------------------
$deletableZone = New-Object System.Collections.Generic.List[string]
foreach ($z in $zone) { if (-not $wlSet.ContainsKey($z)) { $deletableZone.Add($z) } }

Write-Output ('root       = ' + $root)
Write-Output ('zone       = ' + $Zone + '   (' + $zone.Count + ' file(s): the only deletable universe)')
Write-Output ('whitelist  = ' + $wlPath + '  sha256_16=' + $wlHash + '  entries=' + $wlLines.Count)
Write-Output ('amb sources= ' + $ambSource)
Write-Output ('amb names  = ' + $amb.Count + '   candidates inside the zone = ' + $ambInZone.Count)
Write-Output ''
Write-Output '--- REAL RULE (all candidates kept): would-be deletions ---'
Write-Output ('  ambiguous candidates that would be deleted = ' + $ambDeletable.Count + '   <== must be 0')
if ($ambDeletable.Count -gt 0) { $ambDeletable | Select-Object -First $MaxList | ForEach-Object { Write-Output ('    WOULD DELETE: ' + $_) } }
Write-Output ('  total would-be deletions in the zone       = ' + $deletableZone.Count + '  (not a defect by itself: uncited files are supposed to go)')

# ---- named samples --------------------------------------------------------------
foreach ($sample in @($Samples.Split(',') | Where-Object { $_.Trim().Length -gt 0 } | ForEach-Object { $_.Trim() })) {
    $tw = if ($repoBy.ContainsKey($sample)) { $repoBy[$sample] } else { 0 }
    $tz = if ($byNameZone.ContainsKey($sample)) { @($byNameZone[$sample]) } else { @() }
    $kept = 0; $del = 0
    foreach ($z in $tz) { if ($wlSet.ContainsKey($z)) { $kept++ } else { $del++ } }
    Write-Output ''
    # A sample with 0 candidates inside the zone cannot be deleted by ANY implementation => it
    # cannot distinguish a correct one from a broken one => it is NOT a probe.  Say so; do not
    # silently keep it in the sample list as if it proved something.
    $verdict = if ($tz.Count -eq 0) { 'NOT A PROBE (0 in-zone candidates: cannot fail, proves nothing)' } else { 'PROBE (can fail: a wrong rule deletes it)' }
    Write-Output ('SAMPLE ' + $sample + ' : repo-wide candidates=' + $tw + ' | inside zone=' + $tz.Count + ' | whitelisted=' + $kept + ' | would-be deleted=' + $del + '  ==> ' + $verdict)
    $tz | Select-Object -First $MaxList | ForEach-Object { Write-Output ('    zone: ' + $_ + '  whitelisted=' + $wlSet.ContainsKey($_)) }
}

# ---- cross-zone: TWO definitions, TWO numbers ------------------------------------
# The SAME fact yields 1 or 2 depending on the granularity chosen, and neither number is wrong --
# so print both WITH their definitions and never quote a bare "cross-zone = N".
$ztTop = New-Object System.Collections.Generic.List[string]
$ztSub = New-Object System.Collections.Generic.List[string]
$badTop = New-Object System.Collections.Generic.List[string]
$badSub = New-Object System.Collections.Generic.List[string]
foreach ($n in $amb) {
    if (-not $byNameZone.ContainsKey($n)) { continue }
    $cands = @($byNameZone[$n])
    $tops = @($cands | ForEach-Object { ($_ -split '/')[1] } | Sort-Object -Unique)
    $dirs = @($cands | ForEach-Object { $p = $_ -split '/'; ($p[0..($p.Count - 2)] -join '/') } | Sort-Object -Unique)
    $del = @($cands | Where-Object { -not $wlSet.ContainsKey($_) })
    if ($tops.Count -ge 2) { $ztTop.Add($n); foreach ($d in $del) { $badTop.Add($d) } }
    if ($dirs.Count -ge 2) { $ztSub.Add($n); foreach ($d in $del) { $badSub.Add($d) } }
}
Write-Output ''
Write-Output ('CROSS-ZONE (A = TOP-LEVEL component under -Zone differs; see the script header for the definition)')
Write-Output ('  names=' + $ztTop.Count + '   candidates that would be deleted=' + $badTop.Count + '   <== must be 0')
Write-Output ('CROSS-ZONE (B = containing DIRECTORY differs; SUPERSET of A)')
Write-Output ('  names=' + $ztSub.Count + '   candidates that would be deleted=' + $badSub.Count + '   <== must be 0')
Write-Output '  => A and B do not contradict: B is a superset count of A.'

# ---- negative control -----------------------------------------------------------
$rc = 0
if ($NegativeControl) {
    Write-Output ''
    Write-Output '=== NEGATIVE CONTROL (the WRONG rule: keep only the FIRST candidate) ==='
    $wrongKept = @{}
    foreach ($n in $amb) { if ($byNameZone.ContainsKey($n)) { $wrongKept[$byNameZone[$n][0]] = 1 } }
    $wrongDel = New-Object System.Collections.Generic.List[string]
    foreach ($n in $amb) {
        if ($byNameZone.ContainsKey($n)) {
            foreach ($z in $byNameZone[$n]) { if (-not $wrongKept.ContainsKey($z)) { $wrongDel.Add($z) } }
        }
    }
    Write-Output ('  under the wrong rule, ambiguous candidates deleted = ' + $wrongDel.Count + '   <== must be > 0 for this check to have discriminating power')
    $wrongDel | Select-Object -First $MaxList | ForEach-Object { Write-Output ('    WOULD DELETE (wrong rule): ' + $_) }
    if ($wrongDel.Count -le 0) {
        Write-Output '  NEGATIVE CONTROL FAILED: the check cannot distinguish the two rules'
        $rc = 1
    }
}

if ($ambDeletable.Count -gt 0) { exit 1 }
exit $rc
