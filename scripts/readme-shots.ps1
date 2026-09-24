# ============================================================================
#  readme-shots.ps1 -- publish the frames a README references OUT of the
#  throwaway capture batch and INTO a directory that ships with the repo.
#
#  Why this indirection exists (skill `clover-engine` 1.8): the capture batch
#  (typically under .ai-tmp/screenshots) is a ONE-OFF product and is deleted
#  after acceptance, so README must never point at it. This script is the
#  single, re-runnable way to publish those frames.
#
#  Two deliberate properties:
#    * ALL-OR-NOTHING: every source frame is checked BEFORE the first copy. A
#      half-published set would silently make README show fewer pictures than
#      the section promises, and only a human eye would notice.
#    * per-file sha256 is printed, so the published bytes are checkable.
#
#  The mapping table is a parameter (-MapFile), NOT baked into this script:
#  its columns are  from<TAB>to<TAB>what  with a header row whose first cell is
#  `from`; blank lines and lines starting with `#` are ignored. Paths in `from`
#  are relative to -Shots, paths in `to` are relative to -Dest.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File readme-shots.ps1 `
#        -Shots <project>/.ai-tmp/screenshots -Dest <project>/<docs image dir> `
#        -MapFile <project>/tools/readme-shots.map.tsv
#    # optional guard: refuse to publish into the Unity project
#    powershell ... -File readme-shots.ps1 -Shots ... -Dest ... -MapFile ... `
#        -ForbidPrefix <project>/client/Assets
#
#  Exit codes: 0 = published, 1 = a frame is missing / refused, 2 = bad arguments.
#
#  ASCII-only on purpose: Windows PowerShell 5.1 parses a BOM-less .ps1 as ANSI,
#  so CJK paths must come in as arguments, never as literals here.
# ============================================================================
param(
    [Parameter(Mandatory = $true)][string]$Shots,
    [Parameter(Mandatory = $true)][string]$Dest,
    [Parameter(Mandatory = $true)][string]$MapFile,
    [string]$ForbidPrefix = ''
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Shots)) {
    Write-Output ('FAIL readme-shots: capture dir not found -> ' + $Shots)
    exit 1
}
if (-not (Test-Path $MapFile)) {
    Write-Output ('FAIL readme-shots: mapping table not found -> ' + $MapFile)
    exit 2
}
$Dest = [System.IO.Path]::GetFullPath($Dest)
if (-not [string]::IsNullOrWhiteSpace($ForbidPrefix)) {
    $forbid = [System.IO.Path]::GetFullPath($ForbidPrefix)
    if ($Dest.StartsWith($forbid, [StringComparison]::OrdinalIgnoreCase)) {
        Write-Output ('FAIL readme-shots: -Dest must NOT be under ' + $forbid)
        exit 1
    }
}

# ---- read the mapping table ------------------------------------------------
$rows = @()
$sawData = $false
$n = 0
foreach ($line in [System.IO.File]::ReadAllLines($MapFile, [System.Text.Encoding]::UTF8)) {
    $n++
    if ($line.Trim().Length -eq 0 -or $line -match '^\s*#') { continue }
    $c = $line -split "`t"
    if (-not $sawData) {
        $sawData = $true
        if ($c[0].Trim().ToLower() -eq 'from') { continue }   # header row
    }
    if ($c.Count -lt 2 -or $c[0].Trim() -eq '' -or $c[1].Trim() -eq '') {
        Write-Output ('FAIL readme-shots: map line ' + $n + ' must have at least from<TAB>to')
        exit 2
    }
    $rows += [pscustomobject]@{
        From = $c[0].Trim()
        To   = $c[1].Trim()
        What = $(if ($c.Count -ge 3) { $c[2].Trim() } else { '' })
    }
}
if ($rows.Count -eq 0) {
    Write-Output ('FAIL readme-shots: mapping table has no data rows -> ' + $MapFile)
    exit 2
}

# ---- check EVERY source before copying ANYTHING ----------------------------
$missing = @()
foreach ($r in $rows) {
    if (-not (Test-Path -LiteralPath (Join-Path $Shots $r.From))) { $missing += $r.From }
}
if ($missing.Count -gt 0) {
    Write-Output ('FAIL readme-shots: ' + $missing.Count + '/' + $rows.Count + ' frame(s) missing in ' + $Shots + ' -> ' + ($missing -join ', '))
    Write-Output 'nothing was published (a half-published set would silently shorten the README).'
    exit 1
}

# ---- publish ---------------------------------------------------------------
if (-not (Test-Path -LiteralPath $Dest)) { [void](New-Item -ItemType Directory -Path $Dest) }
foreach ($r in $rows) {
    $src = Join-Path $Shots $r.From
    $dst = Join-Path $Dest $r.To
    $dstDir = Split-Path $dst -Parent
    if ($dstDir -and -not (Test-Path -LiteralPath $dstDir)) { [void](New-Item -ItemType Directory -Path $dstDir) }
    Copy-Item -LiteralPath $src -Destination $dst -Force
    $sha = (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash.ToLower()
    $len = (Get-Item -LiteralPath $dst).Length
    Write-Output ('{0,-34} <- {1,-32} {2,9} B  sha256 {3}  [{4}]' -f $r.To, $r.From, $len, $sha, $r.What)
}
Write-Output ('OK readme-shots: ' + $rows.Count + ' frame(s) published to ' + $Dest)
exit 0
