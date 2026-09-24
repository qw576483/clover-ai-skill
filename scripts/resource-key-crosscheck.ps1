# resource-key-crosscheck.ps1 -- FOUR-WAY consistency check between a resource KEY registry, the
# files on disk, the pipeline that lands them, and the references built inside source code.
#
# PROVENANCE (lifted into the skill 2026-09-24): grown in one project ("the source project" below)
# from a two-way check into a four-way one, each direction added because a REAL incident had slipped
# through the directions that existed at the time.  Parameterised on the way in: the registry file,
# every path family (root / template / regexes / generator) and the reference-scan roots are
# arguments.  The incident comments are kept verbatim -- they are the only reason a later reader does
# not delete the check they look redundant next to.
#
# WHY FOUR DIRECTIONS (each one cost the source project a real incident):
#   A) key -> file      : the obvious one.  A key pointing at a file that was never landed renders
#                         nothing, silently (no error, no log -- just a missing sprite).
#   B) file -> key      : "landed but never referenced".  This is the direction that catches a
#                         renamed/abandoned asset set and a half-finished copy run.
#   C) registry <-> generator : the copy pipeline and the registry DRIFTED APART (measured: 99 copy
#                         entries vs 100 registry keys, one key short).  Nothing failed; the sprite
#                         was simply absent at runtime.  ==> THIS SCRIPT IS CURRENTLY RED ON THE
#                         SOURCE PROJECT BY DESIGN, and that is its value proof: it caught a live
#                         defect that no gate was calling.  Do not "fix" the number by relaxing the
#                         check.
#   D) reference -> file : A/B/C all read ONLY the registry file, so a path built OUTSIDE it was
#                         INVISIBLE.  Measured: a style helper builds its frames through the same
#                         helper, so the probe called those frames "unreferenced" and a later slice
#                         DELETED two of them while code still pointed at them.  D resolves every
#                         helper call and every path literal found in any source file.
#
# THE 1-OF-7 LESSON (why the path families are DATA, not code): the source project has ELEVEN path
# constructors spread over SIX path families (unit / building / tower / level / card-art / effect
# directories, ...), and the original version of this script understood exactly ONE of them.  So it
# reported a clean bill of health for the six families it could not see -- the failure mode is not
# "a check that is missing", it is "a check that looks like it covers everything".  A family this
# script cannot describe is therefore NEVER silently skipped: -Config must list every family, and
# D) prints each family it read, so the coverage is visible in the output rather than implied.
#
# USAGE
#   powershell -NoProfile -ExecutionPolicy Bypass -File <skill>/scripts/resource-key-crosscheck.ps1 -ProjectRoot <project> -Config <families.json>
#   ... -Corrupt        # NEGATIVE CONTROL: inject a synthetic key whose file cannot exist => A must FAIL
# Exit 0 = every configured check holds; 1 = at least one does not.
# A .ps1 must be ASCII-only or carry a BOM: Windows PowerShell 5.1 reads a BOM-less .ps1 as ANSI, so
# a CJK literal in the source is silently corrupted.  This file is ASCII-only.
param(
    [string]$ProjectRoot = '',
    # JSON file describing the path families (see -SampleConfig for the schema).  REQUIRED: without
    # it there is no way to know which families exist, and guessing one is exactly the 1-of-7 bug.
    [string]$Config = '',
    [switch]$SampleConfig,
    [switch]$Corrupt,
    [switch]$Quiet
)
$ErrorActionPreference = 'Stop'

if ($SampleConfig) {
    @'
{
  "families": [
    {
      "name": "ui-frame",
      "registryFile": "client/Assets/Scripts/Core/ResPaths.cs",
      "resourceRoot": "client/Assets/Resources/Sprites/Ui",
      "relPrefix": "Sprites/Ui/",
      "relTemplate": "{d}/{s}/frame_{n:D3}",
      "extension": ".png",
      "keyCallRegex": "public static string (\\w+) \\{ get \\{ return UiFrame\\((\\w+), (\\w+), (\\d+)\\); \\} \\}",
      "dirConstRegex": "public const string (\\w+Dir) = \"([^\"]+)\";",
      "srcConstRegex": "public const string (UiSrc\\w+) = \"([^\"]+)\";",
      "literalRegex": "\"(Sprites/Ui/[A-Za-z0-9_/\\-]+)\"",
      "callRegex": "\\.UiFrame\\(\\s*([\\w.]+)\\s*,\\s*([\\w.]+)\\s*,\\s*(\\d+)\\s*\\)",
      "referenceRoots": ["client/Assets/Scripts"],
      "generatorFile": "tools/probes/copy-ui-assets.py",
      "generatorEntryRegex": "\\(\"(\\w+)\",\\s*(\\d+),\\s*\"(\\w+)\"\\)",
      "excludeFiles": [],
      "landedSubdirRegex": ""
    }
  ]
}
'@ | Write-Output
    exit 0
}

if (-not $ProjectRoot) {
    $ProjectRoot = (Get-Location).Path
    Write-Output ('INFO  -ProjectRoot not given: judging the current directory = ' + $ProjectRoot)
}
if (-not (Test-Path $ProjectRoot)) { Write-Output ('FAIL  project root not found: ' + $ProjectRoot); exit 1 }
$root = (Resolve-Path $ProjectRoot).Path
if (-not $Config) {
    Write-Output 'FAIL  -Config <families.json> is required.'
    Write-Output '      WHY: this check is four-way against ONE path family; a project with several families'
    Write-Output '      needs all of them listed, otherwise the families it does not know about read as clean.'
    Write-Output '      Run with -SampleConfig to print the schema.'
    exit 1
}
if (-not (Test-Path $Config)) { Write-Output ('FAIL  config not found: ' + $Config); exit 1 }
$cfg = (Get-Content -Raw -Encoding UTF8 $Config) | ConvertFrom-Json
$families = @($cfg.families)
if ($families.Count -eq 0) { Write-Output 'FAIL  config lists no family'; exit 1 }

function Read-Utf8([string]$p) { return [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8) }
function Join-Rel([string]$rel) { return (Join-Path $root ($rel -replace '/', '\')) }

$fail = 0
foreach ($fam in $families) {
    $name = $fam.name
    Write-Output ''
    Write-Output ('=== family: ' + $name + ' ===')

    $regPath  = Join-Rel $fam.registryFile
    $resRoot  = Join-Rel $fam.resourceRoot
    $ext      = if ($fam.extension) { [string]$fam.extension } else { '.png' }
    $relPfx   = [string]$fam.relPrefix
    $tmpl     = [string]$fam.relTemplate

    if (-not (Test-Path $regPath)) { $fail++; Write-Output ('  FAIL  registry file not found: ' + $fam.registryFile); continue }
    if (-not (Test-Path $resRoot)) { $fail++; Write-Output ('  FAIL  resource root not found: ' + $fam.resourceRoot); continue }
    if (-not $tmpl) { $fail++; Write-Output '  FAIL  family declares no relTemplate'; continue }

    $src = Read-Utf8 $regPath
    $dirMap = @{}; $srcMap = @{}
    foreach ($m in [regex]::Matches($src, [string]$fam.dirConstRegex)) { $dirMap[$m.Groups[1].Value] = $m.Groups[2].Value }
    foreach ($m in [regex]::Matches($src, [string]$fam.srcConstRegex)) { $srcMap[$m.Groups[1].Value] = $m.Groups[2].Value }

    # ---- A) key -> file -------------------------------------------------------------------------
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($m in [regex]::Matches($src, [string]$fam.keyCallRegex)) {
        $key = $m.Groups[1].Value
        $d = $dirMap[$m.Groups[2].Value]; $s = $srcMap[$m.Groups[3].Value]
        if (-not $d -or -not $s) {
            $fail++
            Write-Output ('  FAIL  cannot resolve constant for key ' + $key + ' (' + $m.Groups[2].Value + ' / ' + $m.Groups[3].Value + ') -- declare it or the key is unjudgeable')
            continue
        }
        $n = [int]$m.Groups[4].Value
        $relBody = $tmpl.Replace('{d}', $d).Replace('{s}', $s).Replace('{n:D3}', ('{0:D3}' -f $n)).Replace('{n}', [string]$n)
        $rel = $relPfx + $relBody
        $abs = Join-Path $resRoot ($relBody -replace '/', '\')
        [void]$rows.Add([pscustomobject]@{ Key = $key; Rel = $rel + $ext; Abs = $abs + $ext; Exists = (Test-Path ($abs + $ext)) })
    }
    if ($Corrupt) {
        # NEGATIVE CONTROL: a key whose file by construction cannot exist.  Check A must go RED and
        # name THIS key -- "rc=1" alone would not prove the criterion that fired is the intended one.
        [void]$rows.Add([pscustomobject]@{ Key = 'ZZ-CORRUPT-PROBE'; Rel = ($relPfx + 'zz/corrupt/probe' + $ext); Abs = (Join-Path $resRoot ('zz\corrupt\probe' + $ext)); Exists = $false })
        Write-Output '  -- NEGATIVE CONTROL active: synthetic key ZZ-CORRUPT-PROBE injected; check A must FAIL on it'
    }
    if ($rows.Count -eq 0) { $fail++; Write-Output ('  FAIL  no key matching keyCallRegex found in ' + $fam.registryFile); continue }

    if (-not $Quiet) {
        Write-Output '  key' + "`t" + 'path' + "`t" + 'exists'
        foreach ($r in $rows) { Write-Output ('  {0}`t{1}`t{2}' -f $r.Key, $r.Rel, $r.Exists) }
    }
    $missing = @($rows | Where-Object { -not $_.Exists })
    Write-Output ('  A) keys = {0} ; files present = {1} ; files MISSING = {2}' -f $rows.Count, ($rows.Count - $missing.Count), $missing.Count)

    # ---- D) reference -> file (and it feeds B) --------------------------------------------------
    $constMap = @{}
    $csFiles = @()
    foreach ($rr in @($fam.referenceRoots)) {
        $rp = Join-Rel ([string]$rr)
        if (Test-Path $rp) { $csFiles += @(Get-ChildItem $rp -Recurse -File -Filter *.cs) }
    }
    foreach ($f in $csFiles) {
        foreach ($m in [regex]::Matches((Read-Utf8 $f.FullName), 'const string (\w+)\s*=\s*"([^"]+)"')) {
            $constMap[$m.Groups[1].Value] = $m.Groups[2].Value
        }
    }
    $csRefs = New-Object System.Collections.Generic.HashSet[string]
    foreach ($f in $csFiles) {
        $ct = Read-Utf8 $f.FullName
        foreach ($m in [regex]::Matches($ct, [string]$fam.callRegex)) {
            $dTok = $m.Groups[1].Value.Split('.')[-1]; $sTok = $m.Groups[2].Value.Split('.')[-1]
            $fr = [int]$m.Groups[3].Value
            $d = $dirMap[$dTok]; if (-not $d) { $d = $constMap[$dTok] }
            $s = $srcMap[$sTok]; if (-not $s) { $s = $constMap[$sTok] }
            if ($d -and $s) {
                $body = $tmpl.Replace('{d}', $d).Replace('{s}', $s).Replace('{n:D3}', ('{0:D3}' -f $fr)).Replace('{n}', [string]$fr)
                [void]$csRefs.Add($relPfx + $body)
            }
        }
        $litRe = [string]$fam.literalRegex
        if ($litRe) {
            foreach ($m in [regex]::Matches($ct, $litRe)) {
                $lit = $m.Groups[1].Value -replace ([regex]::Escape($ext) + '$'), ''
                if ($lit.StartsWith($relPfx)) { [void]$csRefs.Add($lit) }
            }
        }
    }
    $csRefList = @($csRefs | Sort-Object)
    $csMissing = @($csRefList | Where-Object { -not (Test-Path (Join-Path $resRoot (($_.Substring($relPfx.Length) + $ext) -replace '/', '\'))) })
    Write-Output ('  D) in-source references to this family = {0} ; missing on disk = {1}' -f $csRefList.Count, $csMissing.Count)

    # ---- B) file -> key ------------------------------------------------------------------------
    $excl = @($fam.excludeFiles)
    $onDisk = @(Get-ChildItem $resRoot -Recurse -File -Filter ('*' + $ext) |
                Where-Object { $excl -notcontains $_.Name } |
                ForEach-Object { $_.FullName.Substring($resRoot.Length).TrimStart('\') -replace '\\', '/' })
    if ($fam.landedSubdirRegex) { $onDisk = @($onDisk | Where-Object { $_ -match $fam.landedSubdirRegex }) }
    $keyed = @($rows | ForEach-Object { $_.Rel.Substring($relPfx.Length) })
    # a path referenced from source counts as a reference too (direction D); this is NOT a relaxation
    # of B -- the original B simply could not see such a reference, which is what let a slice delete
    # a still-referenced frame.
    $keyed = @(@($keyed) + @($csRefList | ForEach-Object { $_.Substring($relPfx.Length) + $ext }) | Sort-Object -Unique)
    $orphan = @($onDisk | Where-Object { $keyed -notcontains $_ })
    $unbacked = @($keyed | Where-Object { $onDisk -notcontains $_ })
    Write-Output ('  B) landed files reachable by a key = {0} ; landed but unreferenced = {1}' -f ($onDisk.Count - $orphan.Count), $orphan.Count)
    if ($orphan.Count)   { Write-Output ('     unreferenced: ' + (($orphan | Select-Object -First 10) -join ', ')) }
    if ($unbacked.Count) { Write-Output ('     key without file on disk: ' + (($unbacked | Select-Object -First 10) -join ', ')) }

    # ---- C) registry <-> generator -------------------------------------------------------------
    $genDelta = 0
    if (-not $fam.generatorFile) {
        Write-Output '  C) NOT JUDGED: this family declares no generatorFile (printed, never silently skipped)'
    } else {
        $genPath = Join-Rel ([string]$fam.generatorFile)
        if (-not (Test-Path $genPath)) {
            Write-Output ('  C) NOT JUDGED: generator not found: ' + $fam.generatorFile + ' (printed, never silently skipped)')
        } else {
            $genKeys = @()
            foreach ($m in [regex]::Matches((Read-Utf8 $genPath), [string]$fam.generatorEntryRegex)) { $genKeys += $m.Groups[$m.Groups.Count - 1].Value }
            $genKeys = @($genKeys | Sort-Object)
            $regKeys = @($rows | Where-Object { $_.Key -ne 'ZZ-CORRUPT-PROBE' } | ForEach-Object { $_.Key } | Sort-Object)
            $diff = @(Compare-Object $genKeys $regKeys)
            $genDelta = $diff.Count
            Write-Output ('  C) generator entries = {0} ; registry keys = {1} ; difference = {2}' -f $genKeys.Count, $regKeys.Count, $diff.Count)
            if ($diff.Count) { $diff | ForEach-Object { Write-Output ('     ' + $_.SideIndicator + ' ' + $_.InputObject) } }
        }
    }

    if ($missing.Count)  { $fail++; Write-Output ('  FAIL A: ' + $missing.Count + ' key(s) point at a file that does not exist -> ' + (($missing | Select-Object -First 5 | ForEach-Object { $_.Key }) -join ', ')) }
    if ($orphan.Count)   { $fail++; Write-Output ('  FAIL B: ' + $orphan.Count + ' landed file(s) are not referenced by any key or source reference') }
    if ($unbacked.Count) { $fail++; Write-Output ('  FAIL B: ' + $unbacked.Count + ' key(s) have no file on disk') }
    if ($genDelta)       { $fail++; Write-Output ('  FAIL C: the copy pipeline and the registry disagree on ' + $genDelta + ' name(s)') }
    if ($csMissing.Count){ $fail++; Write-Output ('  FAIL D: a source file references a path of this family that does not exist') }
}
Write-Output ''
Write-Output ('===== SUMMARY: FAIL={0}  families={1}  config={2} =====' -f $fail, $families.Count, $Config)
exit $(if ($fail -gt 0) { 1 } else { 0 })
