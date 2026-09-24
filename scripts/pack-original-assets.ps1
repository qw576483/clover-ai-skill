# ============================================================================
#  pack-original-assets.ps1 -- REPRODUCIBLE zip of an original-assets folder,
#  for shipping the original material next to the delivery over git-lfs.
#
#  Rule source: skill `clover-engine` -> reference/asset-sources.md 8.2:
#    the original-assets folder stays OUT of git by default; only when the user
#    explicitly asks to ship the original material do we pack it into a zip and
#    commit that zip through git-lfs. The zip stays at the repo root -- it must
#    NEVER end up inside the Unity project (client/Assets/**), where Unity would
#    import every packed byte.
#
#  Reproducibility (this is the point of the script): entries are written in
#  ORDINAL sorted order with a FIXED LastWriteTime, so packing the same folder
#  twice yields byte-identical output and therefore the same sha256 -- which is
#  what makes the manifest line checkable by whoever receives the zip.
#    * never hand-zip from the file manager (every archive differs)
#    * record the printed sha256 in the original-assets manifest
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File pack-original-assets.ps1 `
#        -Src <project>/<original-assets dir>
#    powershell -NoProfile -ExecutionPolicy Bypass -File pack-original-assets.ps1 `
#        -Src <project>/<original-assets dir> -Out "$env:TEMP\refs.zip"
#
#  Exit codes: 0 = packed, 1 = refused / nothing to pack, 2 = bad arguments.
#
#  ASCII-only on purpose: Windows PowerShell 5.1 parses a BOM-less .ps1 as ANSI,
#  so a CJK folder name must be passed on the command line, not written here.
# ============================================================================
param(
    [Parameter(Mandatory = $true)][string]$Src,
    [string]$Out = '',
    [string]$AssetsDir = '',
    [string[]]$SkipDirs = @('.git', 'Library', 'Temp', 'obj', 'Logs', 'Build', 'Builds', 'UserSettings', '.vs', 'node_modules'),
    [string]$FixedTime = '2020-01-01T00:00:00Z'
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Src)) {
    Write-Output ('FAIL pack-original-assets: source not found -> ' + $Src)
    exit 1
}
$Src = (Resolve-Path $Src).Path
$srcLeaf = Split-Path $Src -Leaf
if ([string]::IsNullOrWhiteSpace($Out)) { $Out = Join-Path (Split-Path $Src -Parent) ($srcLeaf + '.zip') }
if ([string]::IsNullOrWhiteSpace($AssetsDir)) { $AssetsDir = Join-Path (Split-Path $Src -Parent) 'client\Assets' }
$Out = [System.IO.Path]::GetFullPath($Out)

# --- hard rule: the archive must never land inside the Unity project --------
$assetsFull = [System.IO.Path]::GetFullPath($AssetsDir)
if ($Out.StartsWith($assetsFull, [StringComparison]::OrdinalIgnoreCase)) {
    Write-Output ('FAIL pack-original-assets: the zip must NOT be placed under ' + $assetsFull)
    exit 1
}
if ($Out -eq $Src -or $Out.StartsWith($Src + [System.IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    Write-Output 'FAIL pack-original-assets: -Out must not sit inside -Src (the archive would pack itself)'
    exit 1
}

# --- collect + ordinal sort -------------------------------------------------
# Reference trees are source trees; skip machine-generated caches if any slipped
# in, and sort by ORDINAL order (culture-aware sort can differ between hosts,
# which would break the "same sha256" property).
$rels = New-Object System.Collections.Generic.List[string]
$fullOf = @{}
foreach ($f in (Get-ChildItem $Src -Recurse -File -Force)) {
    $rel = $f.FullName.Substring($Src.Length + 1)
    $top = ($rel -split '\\')[0]
    if ($SkipDirs -contains $top) { continue }
    $rel = $rel.Replace('\', '/')
    $rels.Add($rel)
    $fullOf[$rel] = $f.FullName
}
if ($rels.Count -eq 0) {
    Write-Output ('FAIL pack-original-assets: nothing to pack under ' + $Src)
    exit 1
}
# Ordinal (not culture-aware) sort: a locale-dependent order would break the
# "same sha256" property between two hosts.
# NOTE: `[Array]::Sort[string](...)` does NOT parse under Windows PowerShell 5.1
# (generic method syntax) -- use the non-generic overload.
$relArr = [string[]]$rels.ToArray()
[System.Array]::Sort($relArr, [System.StringComparer]::Ordinal)


$totalBytes = 0
foreach ($r in $relArr) { $totalBytes += (Get-Item -LiteralPath $fullOf[$r]).Length }
Write-Output ('pack-original-assets: {0} files, {1:N1} MB -> {2}' -f $relArr.Count, ($totalBytes / 1MB), $Out)

if (Test-Path -LiteralPath $Out) { Remove-Item -LiteralPath $Out -Force }

# PowerShell 5.1: ZipFile lives in ...FileSystem, but the ZipArchiveMode enum
# lives in System.IO.Compression -- load BOTH (loading only the first fails with
# "Unable to find type [System.IO.Compression.ZipArchiveMode]").
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$fixed = [System.DateTimeOffset]::Parse($FixedTime, [System.Globalization.CultureInfo]::InvariantCulture)
$zip = [System.IO.Compression.ZipFile]::Open($Out, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($rel in $relArr) {
        $e = $zip.CreateEntry($rel, [System.IO.Compression.CompressionLevel]::Optimal)
        $e.LastWriteTime = $fixed
        $os = $e.Open()
        $is = [System.IO.File]::OpenRead($fullOf[$rel])
        try { $is.CopyTo($os) } finally { $is.Close(); $os.Close() }
    }
} finally {
    $zip.Dispose()
}

$info = Get-Item -LiteralPath $Out
$sha = (Get-FileHash -LiteralPath $Out -Algorithm SHA256).Hash.ToLower()
Write-Output ('packed: {0} bytes ({1:N1} MB), {2} entries' -f $info.Length, ($info.Length / 1MB), $relArr.Count)
Write-Output ('sha256: ' + $sha)
Write-Output 'reproducibility: run this script twice -- the sha256 above must not change.'
Write-Output 'next steps (skill reference/asset-sources.md 8.2):'
Write-Output '  git lfs install'
Write-Output "  '*.zip filter=lfs diff=lfs merge=lfs -text' | Add-Content .gitattributes"
Write-Output ('  git add .gitattributes "' + [System.IO.Path]::GetFileName($Out) + '"')
Write-Output '  # then record the sha256 above + this script version in the original-assets manifest.'
exit 0
