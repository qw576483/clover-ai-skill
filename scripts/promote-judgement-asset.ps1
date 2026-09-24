# promote-judgement-asset.ps1 -- the ONE legitimate channel from "one-time artifact / workspace
# junk" to "judgement asset (kept, cited, version-controlled)", recorded in an APPEND-ONLY ledger.
#
# WHY A TOOL AT ALL: "I copied it and it looked fine" is not a record.  A judged asset that was
# promoted without a record cannot be told apart from one that was silently overwritten, and a
# ledger that some slice rewrites from scratch loses the earlier rows.  So:
#   * TARGET ALREADY EXISTS  => STOP (exit 3).  Never overwrite, never write a ledger row,
#                               never touch one byte of the existing target.
#   * the timestamp is generated HERE (there is deliberately NO parameter for it: a caller-supplied
#     time is a caller-supplied story);
#   * the verified hash is the byte-level sha256 of the TARGET *after* the copy, compared against
#     the source -- not "I remember it was the same file";
#   * whether the source was deleted is recorded from the OBSERVED result (a failed delete is
#     recorded as `no(delete-failed...)`, never as yes);
#   * after appending, the ledger's LAST LINE is read back and must equal the row just written.
#
# WRITE TRIGGERS OF THIS SCRIPT (declared on purpose -- a reader must not have to guess whether a
# tool writes anything): it writes ONLY when it is actually promoting.  It may (a) create the
# ledger directory + ledger file with a column header, (b) copy source->target, (c) create the
# target's parent directory, (d) append one row to the ledger, (e) delete the source IF
# -DeleteSource is given.  On exit 3 (target exists) it writes NOTHING.
#
# Usage
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\promote-judgement-asset.ps1 `
#       -Source <path> -Target <path> [-Actor <name>] [-DeleteSource] `
#       [-ProjectRoot <dir>] [-Ledger <path>] [-LedgerHeaderFile <path>]
#
#   -ProjectRoot         defaults to the CURRENT DIRECTORY; relative -Source/-Target/-Ledger are
#                        resolved against it (absolute paths are used as given).
#   -Ledger              defaults to <ProjectRoot>\.ai-tmp\promotions.tsv
#   -LedgerHeaderFile    optional text file; its lines are copied verbatim as '#' comments at the
#                        top of a freshly created ledger (put your project's rulings there)
#
# Exit codes: 0 ok / 2 source missing / 3 TARGET EXISTS (stopped, nothing written)
#             4 post-copy byte check failed (target copy removed) / 5 ledger read-back failed
#             6 ledger not creatable or not writable
param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Target,
    [string]$Actor = 'promote',
    [switch]$DeleteSource,
    [string]$ProjectRoot = '',
    [string]$Ledger = '',
    [string]$LedgerHeaderFile = ''
)
$ErrorActionPreference = 'Stop'
$encNoBom = New-Object Text.UTF8Encoding($false)

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = (Get-Location).Path }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
if ([string]::IsNullOrWhiteSpace($Ledger)) { $Ledger = Join-Path $ProjectRoot '.ai-tmp\promotions.tsv' }

function Get-Sha256Hex([string]$Path) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return (($sha.ComputeHash([IO.File]::ReadAllBytes($Path)) | ForEach-Object { $_.ToString('x2') }) -join '') }
    finally { $sha.Dispose() }
}
function Resolve-Abs([string]$p) {
    if ([IO.Path]::IsPathRooted($p)) { return [IO.Path]::GetFullPath($p) }
    return [IO.Path]::GetFullPath((Join-Path $ProjectRoot $p))
}

$srcFull = Resolve-Abs $Source
$dstFull = Resolve-Abs $Target

# ---- pre-gate ---------------------------------------------------------------
if (-not (Test-Path -LiteralPath $srcFull)) {
    Write-Output ('STOP source does not exist, nothing was done: ' + $srcFull)
    exit 2
}
if (Test-Path -LiteralPath $dstFull) {
    $shaExist = Get-Sha256Hex $dstFull
    Write-Output ('STOP target already exists => stopped, NOT overwritten: ' + $dstFull)
    Write-Output ('     current target (untouched) sha256=' + $shaExist + ' bytes=' + (Get-Item -LiteralPath $dstFull).Length)
    Write-Output '     no ledger row was added.'
    exit 3
}
if (-not (Test-Path -LiteralPath $Ledger)) {
    try {
        $null = New-Item -ItemType Directory -Force -Path (Split-Path $Ledger)
        $header = New-Object System.Collections.Generic.List[string]
        if (-not [string]::IsNullOrWhiteSpace($LedgerHeaderFile) -and (Test-Path -LiteralPath $LedgerHeaderFile)) {
            foreach ($ln in [IO.File]::ReadAllLines([IO.Path]::GetFullPath($LedgerHeaderFile))) {
                if ($ln.Trim().Length -eq 0) { continue }
                $header.Add($(if ($ln.StartsWith('#')) { $ln } else { '# ' + $ln }))
            }
        }
        # the column line is itself a '#' line with exactly 6 TAB-separated fields, so a machine
        # can split it exactly like a data row
        $header.Add("#stamp`tactor`tsource`ttarget`tsha256`tsource_deleted")
        [IO.File]::WriteAllText($Ledger, (($header -join "`n") + "`n"), $encNoBom)
        Write-Output ('ledger did not exist => created (header lines=' + $header.Count + '): ' + $Ledger)
    } catch {
        Write-Output ('STOP ledger not creatable / not writable: ' + $Ledger + ' :: ' + $_.Exception.Message)
        exit 6
    }
}

# ---- promote: copy + BYTE-LEVEL verify --------------------------------------
$null = New-Item -ItemType Directory -Force -Path (Split-Path $dstFull)
[IO.File]::Copy($srcFull, $dstFull, $false)
$shaSrc = Get-Sha256Hex $srcFull
$shaDst = Get-Sha256Hex $dstFull
if ($shaSrc -cne $shaDst) {
    Remove-Item -LiteralPath $dstFull -Force -ErrorAction SilentlyContinue
    Write-Output ('STOP post-copy byte check failed (target copy withdrawn): src=' + $shaSrc + ' dst=' + $shaDst)
    exit 4
}

# ---- delete-source flag is recorded from the OBSERVED result ----------------
$delFlag = 'no'
if ($DeleteSource) {
    Remove-Item -LiteralPath $srcFull -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $srcFull) { $delFlag = 'no(delete-failed)' } else { $delFlag = 'yes' }
}

# ---- append one row (timestamp generated here) ------------------------------
$stamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
$row = $stamp + "`t" + $Actor + "`t" + $srcFull + "`t" + $dstFull + "`t" + $shaDst + "`t" + $delFlag
$b = [IO.File]::ReadAllBytes($Ledger)
if ($b.Length -gt 0 -and $b[$b.Length - 1] -ne 10) { [IO.File]::AppendAllText($Ledger, "`n", $encNoBom) }
[IO.File]::AppendAllText($Ledger, $row + "`n", $encNoBom)

# ---- read back: the ledger's last line must equal the row just written -------
$all = [IO.File]::ReadAllLines($Ledger)
$last = $all[$all.Count - 1]
if ((@($all | Where-Object { $_.Trim().Length -eq 0 }).Count -gt 0)) {
    Write-Output 'NOTE the ledger contains blank line(s) not produced by this write -- please look.'
}
if ($last -cne $row.TrimEnd()) {
    Write-Output ('STOP ledger read-back failed (last line != the row just written): last=' + $last)
    exit 5
}
Write-Output 'OK promoted'
Write-Output ('  row    = ' + $row)
Write-Output ('  sha256(src)=' + $shaSrc)
Write-Output ('  sha256(dst)=' + $shaDst + '  (byte-identical)')
Write-Output ('  source_deleted = ' + $delFlag + '  (source ' + $(if ($delFlag -eq 'yes') { 'deleted' } else { 'kept' }) + ')')
Write-Output ('  ledger = ' + $Ledger + '  data rows=' + (@($all | Where-Object { $_.Trim().Length -gt 0 -and -not $_.StartsWith('#') }).Count))
exit 0
