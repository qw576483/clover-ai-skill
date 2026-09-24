# table-pipeline.ps1 -- one-click config-table pipeline (project-side thin wrapper).
#
#   txt source tables --[table -pack]--> xlsx (planner edits in Excel)
#                     --[table]---------> tsv + typed code (server + client)
#
# The actual generator lives in ANOTHER repository (a Go tool).  This wrapper is the project-side
# glue: it locates the tool, resolves the effective config, keeps the planner's xlsx authoritative,
# and verifies that the deliverables exist.  Point -TableSourceDir / -TableExe at that tool.
#
# THE FIVE HARD PITFALLS (each has a measured cause -- do not "simplify" them away):
#   1. pass -batch to the tool, or it BLOCKS waiting for Enter (looks like a hang);
#   2. a prebuilt <tool>.exe in the source dir is often an OLDER build that does not know
#      -pack / -pack-dir / -batch => if `go` is on PATH, run `go run <GoPackage>` from source;
#   3. to override client_dir, make a TEMP COPY of the config with that one line replaced --
#      never edit the config in place (the next run would inherit the override silently);
#   4. a planner-edited `<name>-pack.xlsx` is AUTHORITATIVE: only repack it with -Force;
#   5. TABLE NAMES MUST BE ASCII.  The generator derives Go type/field names from the sheet name,
#      and Go only treats a leading UPPERCASE ASCII letter as exported -- a CJK sheet name produces
#      `table.Tables{...}` whose fields are unreachable from any other package.  Pass -TableNames
#      as ASCII names; this wrapper does not enforce it beyond this note.
#
# NOTE: this file is intentionally ASCII-only.  Windows PowerShell 5.1 parses a .ps1 without a BOM
#       as ANSI/GBK, which corrupts every CJK literal and breaks parsing.  The two CJK directory
#       defaults are therefore built from code points; override them with real names if you like.
#
# Usage
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\table-pipeline.ps1 -Root <projectRoot>
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\table-pipeline.ps1 -Root <r> -Force
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\table-pipeline.ps1 -Root <r> -ClientDir <path>
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\table-pipeline.ps1 -Root <r> -NoPack
#
#   -Root           project root (default: current directory)
#   -Config         generator config (default: <Root>\tools\table.config.yaml)
#   -TableSourceDir the OTHER repo's generator source dir (default: <Root>\..\<tool>\table\core)
#   -GoPackage      package path to run from -TableSourceDir (default ./cmd/table)
#   -PlanDirName / -NumDocDirName / -ServerTableDir / -MappingName  layout knobs
#   -TableNames     comma-separated table names; used ONLY for the output verification below.
#                   Empty => the output check prints NOT-JUDGED instead of a silent pass.
#   -Force          repack even when a planner xlsx exists; also pass -force to the generator
#   -NoPack / -NoGen  skip step 1 / step 2
[CmdletBinding()]
param(
  [string]$Root = '',
  [string]$Config = '',
  [string]$ClientDir = '',
  [string]$TableSourceDir = '',
  [string]$TableExe = '',
  [string]$GoPackage = './cmd/table',
  [string]$PlanDirName = '',
  [string]$NumDocDirName = '',
  [string]$ServerTableDir = 'server/game/table',
  [string]$MappingName = '',
  [string]$TableNames = '',
  [switch]$Force,
  [switch]$NoPack,
  [switch]$NoGen
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) { $Root = (Get-Location).Path }
$Root = (Resolve-Path -LiteralPath $Root).Path

if ([string]::IsNullOrWhiteSpace($Config)) { $Config = Join-Path $Root 'tools/table.config.yaml' }
if (-not (Test-Path -LiteralPath $Config)) { Write-Error "config not found: $Config" }
$Config = (Resolve-Path -LiteralPath $Config).Path

# ---- non-ASCII defaults, built from code points (keeps this file ASCII-only) ----
# plan dir = two CJK chars; numeric-doc dir = four CJK chars; the mapping file name + ".tsv".
if ([string]::IsNullOrWhiteSpace($PlanDirName)) { $PlanDirName = ([char[]]@(0x7B56, 0x5212) -join '') }
if ([string]::IsNullOrWhiteSpace($NumDocDirName)) { $NumDocDirName = ([char[]]@(0x6570, 0x503C, 0x6587, 0x6863) -join '') }
if ([string]::IsNullOrWhiteSpace($MappingName)) {
  $MappingName = (([char[]]@(0x6253, 0x8868, 0x5BF9, 0x7167, 0x8868) -join '') + '.tsv')
}
$packSuffix = '-pack'

Write-Output ("root       = " + $Root)
Write-Output ("config     = " + $Config)

# ---- locate the generator ---------------------------------------------------
$toolExe = ''
if (-not [string]::IsNullOrWhiteSpace($TableExe)) {
  $toolExe = (Resolve-Path -LiteralPath $TableExe).Path
} else {
  if ([string]::IsNullOrWhiteSpace($TableSourceDir)) { $TableSourceDir = Join-Path $Root '..\clover-tools\table\core' }
  $src = (Resolve-Path -LiteralPath $TableSourceDir).Path
  $goCmd = Get-Command go -ErrorAction SilentlyContinue
  if ($null -ne $goCmd) {
    $toolExe = ''            # use: go run <GoPackage>   (cwd = $src)
  } else {
    $cand = Join-Path $src 'table.exe'
    if (Test-Path -LiteralPath $cand) {
      $toolExe = (Resolve-Path -LiteralPath $cand).Path
      Write-Warning "go not found: falling back to $toolExe (may be an older build without -pack)"
    } else {
      Write-Error "neither go nor a prebuilt .exe available (looked in $src)"
    }
  }
  $TableSourceDir = $src
}

function Invoke-Table([string[]]$ToolArgs) {
  if ([string]::IsNullOrWhiteSpace($toolExe)) {
    Push-Location -LiteralPath $TableSourceDir
    try { & go run $GoPackage @ToolArgs } finally { Pop-Location }
  } else {
    & $toolExe @ToolArgs
  }
}

# ---- resolve the effective config (client_dir override -> temp copy) --------
$cfgTmpDir = Join-Path $Root '.ai-tmp/test'
$packDir   = Join-Path (Join-Path $Root $PlanDirName) $NumDocDirName
$effConfig = $Config
if (-not [string]::IsNullOrWhiteSpace($ClientDir)) {
  if (-not (Test-Path -LiteralPath $cfgTmpDir)) { New-Item -ItemType Directory -Path $cfgTmpDir -Force | Out-Null }
  $effConfig = Join-Path $cfgTmpDir 'table-config.effective.yaml'
  $lines = [System.IO.File]::ReadAllLines($Config, [System.Text.Encoding]::UTF8)
  $out = New-Object System.Collections.Generic.List[string]
  $hit = $false
  foreach ($ln in $lines) {
    if ($ln -match '^\s*client_dir\s*:') {
      $out.Add('client_dir: "' + ($ClientDir -replace '\\', '/') + '"')
      $hit = $true
    } else {
      $out.Add($ln)
    }
  }
  if (-not $hit) { Write-Error "config has no client_dir line: $Config" }
  [System.IO.File]::WriteAllLines($effConfig, $out.ToArray(), (New-Object System.Text.UTF8Encoding($false)))
  Write-Output ("client_dir = " + $ClientDir + "   (via " + $effConfig + ")")
}

# ---- step 1: pack source txt -> xlsx (planner-facing) -----------------------
if (-not $NoPack) {
  if (-not (Test-Path -LiteralPath $packDir)) { Write-Error "planning dir not found: $packDir" }
  $txts = @(Get-ChildItem -LiteralPath $packDir -Filter *.txt -File)
  if ($txts.Count -eq 0) { Write-Error "no *.txt source tables in $packDir" }

  # a planner-edited <name>-pack.xlsx is authoritative: only repack it with -Force
  $todo = @()
  foreach ($t in $txts) {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($t.Name)
    $target = Join-Path $packDir ($base + $packSuffix + '.xlsx')
    if ((Test-Path -LiteralPath $target) -and (-not $Force)) {
      Write-Output ("  skip   " + $t.Name + "  (planner copy exists: " + [System.IO.Path]::GetFileName($target) + "; use -Force to repack)")
    } else {
      $todo += $t
    }
  }

  if ($todo.Count -gt 0) {
    Write-Output ''
    Write-Output '--- step 1/2 : pack source tables (txt -> xlsx) ---'
    $packArgs = @('-pack', '-pack-dir', $packDir, '-batch')
    Invoke-Table $packArgs | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Error "table -pack failed (exit $LASTEXITCODE)" }
    foreach ($t in $todo) {
      $base = [System.IO.Path]::GetFileNameWithoutExtension($t.Name)
      $plain = Join-Path $packDir ($base + '.xlsx')
      $target = Join-Path $packDir ($base + $packSuffix + '.xlsx')
      if (-not (Test-Path -LiteralPath $plain)) { Write-Error "pack produced no xlsx for $($t.Name)" }
      Move-Item -LiteralPath $plain -Destination $target -Force
      Write-Output ("  pack   " + $t.Name + " -> " + [System.IO.Path]::GetFileName($target))
    }
  }
}

# ---- step 2: xlsx -> tsv + typed code --------------------------------------
if (-not $NoGen) {
  Write-Output ''
  Write-Output '--- step 2/2 : generate tsv + typed code ---'
  $genArgs = @('-config', $effConfig, '-batch')
  if ($Force) { $genArgs += '-force' }
  Invoke-Table $genArgs
  if ($LASTEXITCODE -ne 0) { Write-Error "table generation failed (exit $LASTEXITCODE)" }
}

# ---- verify the deliverables -------------------------------------------------
Write-Output ''
Write-Output '--- outputs ---'
$names = @($TableNames.Split(',') | Where-Object { $_.Trim().Length -gt 0 } | ForEach-Object { $_.Trim() })
if ($names.Count -eq 0) {
  # NOT-JUDGED, loudly: an unverified pipeline must not look like a verified one
  Write-Output '  NOT-JUDGED no -TableNames given => generated tsv files were NOT verified (pass -TableNames a,b,c)'
} else {
  $srvDir = Join-Path $Root $ServerTableDir
  foreach ($n in $names) {
    $logical = if ($n.EndsWith('_cs')) { $n.Substring(0, $n.Length - 3) } else { $n }
    $tsv = Join-Path (Join-Path $srvDir 'tsv') ($logical + '.tsv')
    if (Test-Path -LiteralPath $tsv) {
      $n_rows = ([System.IO.File]::ReadAllLines($tsv, [System.Text.Encoding]::UTF8)).Count - 1
      Write-Output ("  " + $n + " : " + $n_rows + " data row(s)  " + $tsv)
    } else {
      Write-Error ("missing generated tsv: " + $tsv)
    }
  }
}
$map = Join-Path $packDir $MappingName
if (Test-Path -LiteralPath $map) { Write-Output ("  mapping : " + $map) }
Write-Output 'table pipeline OK'
