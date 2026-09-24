# cited-evidence-whitelist.ps1 -- build the "do not delete at delivery" list from the plan docs.
#
# PROVENANCE (lifted into the skill 2026-09-24): written inside one project ("the source project"
# below) as the STRUCTURAL answer to its evidence-area debt, then parameterised -- plan area, asset
# area, cleanup zone, evidence zone, document set, product directory and judged assembly are all
# arguments now.  The comments that cite a measured incident are kept verbatim: each of them is the
# only thing stopping a later reader from "simplifying" a rule that was paid for, and this block
# itself is an INCIDENT PRODUCT -- see the "WRITE TRIGGERS" paragraph below.
#
# GLOSSARY for the case citations below: slice ids of the form <letters>-<alnum> (and the D-numbers)
# are the SOURCE PROJECT's own work-item ids, and "the team-lead" is that project's lead.  They are
# kept as provenance -- each marks WHERE a rule was paid for -- and are not meaningful outside it.
# COMPANION ARTEFACTS referred to below (an ambiguity-cleanup simulation probe, a read-back
# self-check, a parser-only syntax check) were project-local and are NOT shipped with the skill;
# they are named by their ROLE, not by a path that will not exist in your tree.
#
# WHY: the project's evidence area (.ai-tmp/screenshots for images, .ai-tmp/test for text audit
# files) is cited BY PATH from the documents under the plan dir. The delivery cleanup must not
# delete a cited file, otherwise every citing row becomes a dangling reference.
# SEMANTICS: "one-off area" DOES NOT MEAN "deletable" -- the delivery documents cite files that
# live in .ai-tmp/test, so those files must survive the cleanup. Only uncited files may be removed.
#
# SCOPE (team-lead ruling, from CR-R1's recount): the WHOLE plan dir by default, because the four
# ledger files hold only part of the references. `-Scope f2` reproduces the original 4-ledger
# subset. THE SCOPE IS PART OF THE OUTPUT FILE NAME (two scopes must never overwrite each other).
#
# FOUR EXTRACTION STEPS (a two-pass regex is NOT enough -- measured):
#   1) PATH form : `.ai-tmp/<...>` occurrences containing a slash
#   2) BARE form : `name.ext` inline-code tokens without a slash, resolved by basename
#   3) PATTERNS  : split by EXPANDABILITY (CR-U5R's A/B/C), never counted as MISSING:
#        A braces with explicit items (no ellipsis) -> expand NOW, existing members are whitelisted,
#          missing members are reported (not judged red)
#        B braces/globs containing an ellipsis        -> not mechanically expandable -> human
#        C `*` / `?` glob with a directory prefix     -> enumerate the directory, matches whitelisted
#      EXPANSION AND WHITELISTING ARE THE SAME STEP, and it runs before any cleanup: otherwise the
#      files behind `CR-T3-re-{00-baseline,...}.png` look unreferenced and get deleted.
#   A bare name resolving in >1 place is AMBIGUOUS: every candidate is listed and the HUMAN decides.
#   Only CANDIDATES INSIDE THE CLEANUP ZONE (.ai-tmp) are whitelisted -- sprite paths under
#   client/Assets are never deleted, and whitelisting them would only bloat the list. The full
#   candidate set is still printed for the reader.
#   Only a LITERAL path-form ref that (a) has no wildcard/brace/range/line suffix, (b) ends with a
#   file extension, (c) is absent from disk and (d) whose citing line does not say it was deleted,
#   is provably dangling -> that one IS a FAIL.
#
# FAILURE MODES (team-lead rule 2026-09-23: an automated step that touches disk must state how it breaks):
#   - severity: MEDIUM. Interrupting a land can leave a PARTIALLY written product (each file is one WriteAllLines call, not
#     atomic). Worst case = a short list; it is DETECTED by the read-back self-check, which compares the
#     header's declared entry count against the body line count. ⛔ It cannot corrupt other artifacts: this
#     tool writes only its own three files plus the append-only ledger/delta-log.
#   - severity: LOW. A failed .delta.log append loses ONE generation from the log (the whitelist and .delta.txt are already
#     written) => the ledger's counts still show the transition happened.
#   - severity: by design loud, not silent. The union FAILS LOUDLY (exit, no output) if the partner file is missing or suspiciously small, so a
#     halved union cannot be consumed silently.
#   - READING is the safe part ONLY IF you pass NONE of -Land / -Union / -BucketDump. (This line used to
#     claim "no -Land => nothing is written at all", which was FALSE and cost the team one wasted product
#     generation: -Union itself is a write trigger.)
#
# WRITE TRIGGERS (measured 2026-09-23 by grep of the write calls, then a minimal run, then a before/after
# fingerprint diff of every product -- the only method that was accepted):
#   -Land (or -OutFile)  -> writes cited-evidence-whitelist-<scope>.txt and its .delta.txt, and APPENDS
#                           cited-evidence-whitelist-transitions.tsv and the .delta.log;
#   -Union               -> ALSO writes cited-evidence-whitelist-UNION-<scope>.txt and APPENDS
#                           cited-evidence-whitelist-anchors.tsv. Without -Land it is REFUSED, exit 4, because
#                           the union header needs $asmSha, which only the -Land/-OutFile path computes;
#   -BucketDump <path>   -> writes exactly that path;
#   -Scope only (a pure read) -> writes NOTHING (measured: all 7 products byte-identical afterwards).
#
# READ-ONLY on every judged object. Absolute path resolution: a .NET file API uses the PROCESS working
# directory, which Set-Location does not reliably update.
#
# USAGE  (products default to <project>/tools/probes, NOT to this script's own directory: the script
#         now ships in the skill while the products belong to the project)
#   powershell -NoProfile -ExecutionPolicy Bypass -File <skill>/scripts/cited-evidence-whitelist.ps1 -ProjectRoot <project> -PlanDirRelative <plan-area>
#   ... -SelfTest
#   ... -Scope all -Land
#   ... -StateDirRelative tools/probes   # where the whitelist / delta / ledgers are written
#
# FIRST RUN ON A NEW PROJECT: -ProjectRoot is required in practice (it defaults to the CWD) and
# -PlanDirRelative must name the area that holds the citing documents; with neither, the run FAILS
# loudly ("no plan-dir document found") rather than producing an empty protection list.
#
# NOTE 1: ASCII-only on purpose -- PowerShell 5.1 parses a .ps1 without a BOM as ANSI/GBK, so a CJK
#         literal here would be corrupted. CJK names/characters are built from code points.
# NOTE 2: DELIMITER: every whitelist entry is written with FORWARD SLASHES, and the header says so.
#         Mixing '\' and '/' made two thirds of a consumer's matches silently miss (CR-R1 measured
#         43 duplicate rows before normalising).
# NOTE 3: name lookups use a PowerShell hashtable (CASE-INSENSITIVE); `-contains`/`-in` are also
#         case-insensitive, so the extension check uses `-cnotcontains`. Note that
#         `$array -cnotcontains ''` is TRUE, i.e. an empty extension can never be accepted.
param(
  # The project under judgement.  Defaults to the CURRENT DIRECTORY -- never to this script's own
  # location: the script now ships in the skill, while every object it reads lives in a project.
  [string]$ProjectRoot = '',
  # The area whose documents are the CITATION SOURCE.  A skill cannot know a project's plan-area
  # name, so it is an argument (the source project's own value is spelled with CJK code points
  # further down, as the technique example).  Empty => the run FAILS loudly.
  [string]$PlanDirRelative = '',
  # Optional second area that is indexed (a project's raw-original-asset area); empty = not indexed.
  [string]$AssetSrcRelative = '',
  # Where products + the append-only ledgers are written (project-relative, or absolute).
  [string]$StateDirRelative = 'tools/probes',
  # Zone definitions, as regexes (defaults = the skill's own convention in SKILL.md section 3.5).
  [string]$EvidenceRe = '^\.ai-tmp[\\/](test|screenshots)[\\/]',
  [string]$CleanupZone = '^\.ai-tmp[\\/]',
  # COMMA-SEPARATED STRING, not [string[]]: the documented invocation is -File, and the -File
  # argument parser passes each argument as ONE string without applying the comma operator, so a
  # [string[]] parameter cannot be filled that way at all (measured: the value bound as a single
  # bogus path, 4 index roots instead of 9, while every headline number still looked plausible).
  [string]$IndexRoots = '',
  # Subtree directories and file shapes that are never indexed (regex).
  [string]$SkipRe = '\\(Library|obj|bin|node_modules|\.git|__pycache__|Temp)\\|\.g\.cs$',
  # Judged assembly (project-relative).  EMPTY = the assembly stamp in the header reads 'n/a'.
  [string]$AsmRelative = '',
  # Prefix for the SELF-TEST probe names.  Parameterised only so a probe can never collide with a
  # real file name in a project that legitimately uses the default one.
  [string]$ProbePrefix = 'zzz-probe',
  [ValidateSet('all', 'f2')][string]$Scope = 'all',
  # Documents the 'f2' subset scope reads (comma-separated for the same -File reason as -IndexRoots).
  # Empty => 'f2' warns and falls back to the whole plan area instead of silently scanning nothing.
  [string]$ScopeDocs = '',
  [switch]$SelfTest,
  # NEGATIVE CONTROL for -SelfTest itself: skip creating the positive fixtures.  Every check that
  # depends on them must then go RED -- a self-test whose own criteria cannot fail proves nothing
  # (the skill's "confirm the criterion CAN fail, then confirm it fails for the right reason" rule).
  [switch]$SelfTestNoFixtures,
  [switch]$Land,
  [switch]$Union,
  [string]$BucketDump,
  [string]$UnionWith,
  [string]$Partner,
  [string]$OutFile,
  [switch]$Quiet,
  [int]$MaxList = 25
)

$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) {
    $ProjectRoot = (Get-Location).Path
    Write-Output ('INFO  -ProjectRoot not given: judging the current directory = ' + $ProjectRoot)
}
if (-not (Test-Path $ProjectRoot)) { Write-Output ('FAIL  project root not found: ' + $ProjectRoot); exit 1 }
$root = (Resolve-Path $ProjectRoot).Path
$here = if ([System.IO.Path]::IsPathRooted($StateDirRelative)) { $StateDirRelative } else { Join-Path $root $StateDirRelative }
if (-not (Test-Path $here)) { New-Item -ItemType Directory -Path $here -Force | Out-Null }
# The ONE-OFF area, as a full path.  Needed by -SelfTest, which writes its positive fixtures there:
# a self-test that depends on files a project happens to have proves nothing (they do not exist in
# the next project), so the fixtures are created and removed by the test itself.
$T = Join-Path $root '.ai-tmp\test'

# CJK names are built from code points: this file must stay readable by PowerShell 5.1 even without a
# BOM, so it must not carry a CJK literal.  The source project's plan area is used as the DEFAULT so
# the technique has a worked example in place; pass -PlanDirRelative to override it.
if (-not $PlanDirRelative) {
    $PlanDirRelative = (([char[]]@(0x7B56,0x5212) -join ''))          # ce hua  <-- EXAMPLE ONLY
    Write-Output ('INFO  -PlanDirRelative not given: falling back to the source project default "' + $PlanDirRelative + '"')
}
$planDir = if ([System.IO.Path]::IsPathRooted($PlanDirRelative)) { $PlanDirRelative } else { Join-Path $root $PlanDirRelative }
$assetSrc = if ($AssetSrcRelative) { (Split-Path $AssetSrcRelative -Leaf) } else { '' }
$idxRootList = @($IndexRoots -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$scopeDocList = @($ScopeDocs -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
# The script still Set-Location's to the project root because the INDEX ROOTS below are written as
# project-relative names and are walked with PS cmdlets (which DO follow Set-Location).  Note the
# asymmetry the source project measured: .NET/IO APIs do NOT follow Set-Location -- every path handed
# to them in this file is built from $root, never from a relative literal.
Set-Location $root

$ellipsis = ([char]0x2026).ToString()

function Doc([int[]]$cp, [string]$ext) { return (Join-Path $planDir ((([char[]]$cp) -join '') + $ext)) }
# ^ kept only as the worked example of the ASCII-file technique (build CJK names from code points);
#   nothing calls it any more -- the 'f2' subset is a parameter now.
if ($Scope -eq 'f2') {
  # The 'f2' subset scope was the source project's ORIGINAL 4-document subset (its lead later widened
  # the scope to the whole plan area, ruling "the four ledger files hold only part of the references").
  # The 4 document names were CJK and are now a PARAMETER (-ScopeDocs) -- a skill must not hard-code
  # one project's document names.  Empty => fall back to the whole plan area, LOUDLY: silently
  # scanning nothing would look exactly like "this project has no citations".
  if ($scopeDocList.Count -eq 0) {
    Write-Output 'WARN  -Scope f2 without -ScopeDocs: falling back to the WHOLE plan area (no document subset configured)'
    $docs = @(Get-ChildItem $planDir -Recurse -File -Include '*.md', '*.tsv' -ErrorAction SilentlyContinue)
  } else {
    # NOTE: Get-Item, not the raw path strings -- the rest of the script reads $_.FullName, and a
    # string array made every path empty in the first version ("Empty path name is not legal").
    $docs = @($scopeDocList | ForEach-Object {
              if ([System.IO.Path]::IsPathRooted($_)) { $_ } else { Join-Path $planDir $_ } }) |
            Where-Object { Test-Path $_ } | ForEach-Object { Get-Item $_ }
  }
} else {
  $docs = @(Get-ChildItem $planDir -Recurse -File -Include '*.md', '*.tsv' -ErrorAction SilentlyContinue)
}
if ($docs.Count -eq 0) { Write-Output 'FAIL  no plan-dir document found'; exit 1 }

$pathRe  = [regex]'\.ai-tmp/[^\s`|<>"'']+'
$codeRe  = [regex]'`([^`\r\n]{1,160})`'
$lineRef = [regex]':\d+(-\d+)?$|#L\d+$'
$placeRe = [regex]'[*?{}]|\.\.'
# $extOk gates TWO different branches, which is why the omission of py/ps1 was a real defect, not a style
# choice: the PATH branch (\\.ai-tmp/...) accepts any extension, while the BARE-NAME branch (L272 + $plainRe
# at L286) only recognises extensions listed here. Same class of file, two shapes => only half was seen.
# Measured by CR-V1 (2026-09-23), with a positive control: 48 bare-name .py/.ps1 tokens in 策划/**, of which
# 16 resolve to in-zone entities that were ALL absent from the list (they would have been deleted at cleanup,
# i.e. "under-inclusion = an unrecoverable dangling reference"), while 50 PATH-shaped .ai-tmp/**.py refs were
# all already protected => the gap was specific to the bare-name shape, NOT "py is unprotected".
# Only measured extensions are added; speculative ones are not (each addition widens the protection list).
$extOk   = @('txt','png','jpg','jpeg','json','tsv','log','out','cs','md','ogg','asset','unity','meta','ini','xml','py','ps1')

$cutAscii = [char[]]@(0x3B,0x3A,0x2C,0x29,0x28,0x5D,0x5B,0x7D,0x7B,0x60,0x27,0x22,0x3E,0x3C,0x21,0x7C)
$cutCjk   = [char[]]@(0xFF08,0xFF09,0xFF0C,0xFF1A,0xFF1B,0xFF01,0xFF1F,0x3001,0x3002,0x300A,0x300B,0x201C,0x201D,0x2018,0x2019,0x2014,0x2026)
$cutSet   = ($cutAscii + $cutCjk)
$tailSet  = ($cutSet + [char[]]@(0x2E))

function Trim-Bits([string]$s) {
  $t = $s.Trim()
  for ($i = 1; $i -lt $t.Length; $i++) {
    if ($cutSet -contains $t[$i]) { $t = $t.Substring(0, $i); break }
  }
  while ($t.Length -gt 0 -and $tailSet -contains $t[$t.Length - 1]) { $t = $t.Substring(0, $t.Length - 1) }
  return $t
}

function Get-BraceExpansions([string]$tok) {
  $m = [regex]::Match($tok, '\{([^{}]+)\}')
  if (-not $m.Success) { return @($tok) }
  $pre = $tok.Substring(0, $m.Index); $post = $tok.Substring($m.Index + $m.Length)
  $out = @()
  foreach ($part in ($m.Groups[1].Value -split ',')) { $out += Get-BraceExpansions ($pre + $part.Trim() + $post) }
  return $out
}
# RANGE form: `prefix<N>..<M>suffix` denotes the CONSECUTIVE members N..M (e.g. AP2-probe-0..4.txt).
# NOTE the asymmetry CR-U5R measured: a range can only express CONSECUTIVE numbering, so a
# non-contiguous family MUST be written as a brace list (`{0,7,14,21,28,35}`) -- with a range the
# other members look unreferenced and get deleted. Both buckets are therefore required.
# Returns the member names, or $null when the token is not a range form.
function Expand-RangeMembers([string]$tok) {
  $m = [regex]::Match($tok, '^(?<pre>.*?)(?<a>\d+)\.\.(?<b>\d+)(?<post>\.[A-Za-z0-9]{1,6})$')
  if (-not $m.Success) { return $null }
  $a = [int]$m.Groups['a'].Value; $b = [int]$m.Groups['b'].Value
  if ($b -lt $a) { return $null }
  if (($b - $a) -gt 200) { return $null }        # refuse absurd spans instead of generating noise
  $out = @()
  for ($i = $a; $i -le $b; $i++) { $out += ($m.Groups['pre'].Value + $i + $m.Groups['post'].Value) }
  return $out
}

function Normalize([string]$p) { return ($p -replace '\\', '/') }

# Index roots: the areas whose FILE NAMES are looked up when a bare name is resolved.  Only '.ai-tmp'
# (the cleanup zone) is universal; everything else is a project's own layout, so it comes in through
# -IndexRoots (comma-separated).  The plan area is always added (it holds the citing documents).
# NOTE 1: the source project's list named its asset pack explicitly in the skip regex below; a pack
#   name is project vocabulary and is NOT baked in -- put it in -SkipRe if the pack is huge.
# NOTE 2: the roots are turned ABSOLUTE here.  They used to be project-relative names resolved against
#   the process CWD after a Set-Location -- and a relative root that fails Test-Path silently drops
#   every file under it from the index, which moves ONLY the bare-name sub-counts and looks like a
#   project that simply has fewer files.  Measured in the lift: a caller whose CWD was not the project
#   root produced "0 distinct file name(s) across 1 root(s)" and nothing else looked wrong.
$indexRoots = @((Join-Path $root '.ai-tmp'))
foreach ($r in $idxRootList) {
    $indexRoots += $(if ([System.IO.Path]::IsPathRooted($r)) { $r } else { Join-Path $root $r })
}
$indexRoots += $planDir
if ($assetSrc) { $indexRoots += (Join-Path $root $assetSrc) }
$skipRe = $SkipRe
# DIAGNOSTIC: print the roots actually used AND whether each exists.  A root that silently fails
# Test-Path removes every file under it from the name index, which is invisible in every downstream
# number except the bare-name bucket (measured: 4 of 9 roots indexed, and only STEP2's sub-counts
# moved).  Printing it here means the coverage of the index is READABLE, not implied.
$idxRootInfo = @($indexRoots | ForEach-Object { ($_ -replace [regex]::Escape($root), '.') + '=' + (Test-Path $_) })

function Build-Index() {
  $idx = @{}
  foreach ($r in $indexRoots) {
    if (-not (Test-Path $r)) { continue }
    Get-ChildItem $r -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
      if ($_.FullName -match $skipRe) { return }
      if (-not $idx.ContainsKey($_.Name)) { $idx[$_.Name] = New-Object System.Collections.Generic.List[string] }
      $idx[$_.Name].Add((Normalize $_.FullName.Substring($root.Length).TrimStart('\', '/')))
    }
  }
  return $idx
}

function Invoke-Extract([string]$Text, $Index) {
  $pathRefs = @{}; $bareRefs = @{}; $patterns = @{}; $pathLine = @{}; $hadLineSuffix = @{}
  $whitelist = New-Object System.Collections.Generic.List[string]
  $missing   = New-Object System.Collections.Generic.List[string]
  $deleted   = New-Object System.Collections.Generic.List[string]
  $unresolved= New-Object System.Collections.Generic.List[string]
  $ambiguous = New-Object System.Collections.Generic.List[string]
  $outside   = New-Object System.Collections.Generic.List[string]
  $patA = New-Object System.Collections.Generic.List[string]
  $patB = New-Object System.Collections.Generic.List[string]
  $patC = New-Object System.Collections.Generic.List[string]
  $expMissing = New-Object System.Collections.Generic.List[string]

  $braceTokens = 0; $braceExpanded = @{}; $rangeTokens = 0; $rangeNames = @{}
  foreach ($m in ($pathRe.Matches($Text))) {
    $ls = $Text.LastIndexOf("`n", [Math]::Max(0, $m.Index - 1)); $le = $Text.IndexOf("`n", $m.Index)
    if ($le -lt 0) { $le = $Text.Length }
    $line = $Text.Substring([Math]::Max(0, $ls + 1), [Math]::Max(0, $le - $ls - 1))
    # ORDER MATTERS: expand braces on the RAW token first (Trim-Bits cuts at '{'), then trim.
    $hadLine = $lineRef.IsMatch($m.Value.Trim()) -or ($m.Value -match ':\d')
    if ($m.Value.Contains('{')) { $braceTokens++ }
    # ellipsis is checked on the RAW token: Trim-Bits cuts at U+2026, so after trimming the marker
    # is already gone (measured -- the first version lost all ellipsis patterns that way).
    if ($m.Value.Contains($ellipsis) -or $m.Value.Contains('...')) {
      # only a FILE pattern belongs in bucket B: without this gate the bucket filled up with prose
      # and code snippets that merely contain an ellipsis (measured: `Emit(..., 1f)`,
      # `CreateBoxRect(..., style.TrackColor)`, `Hint '...' size=24`), which inflated the count.
      # The shape is judged AFTER masking the ellipsis, so a real `…png` tail is still recognised.
      $shape = Trim-Bits ((($m.Value -replace [regex]::Escape($ellipsis), 'X') -replace '\.\.\.', 'X'))
      if ($shape.Length -gt 9 -and ($shape -match '\.[A-Za-z0-9]{1,6}$' -or $shape.Contains('{')) -and $shape -notmatch '["'':]') {
        if (-not $patB.Contains($m.Value.Trim())) { $patB.Add($m.Value.Trim()) }
      }
      continue
    }
    $fromBrace = $m.Value.Contains('{')
    foreach ($x in (Get-BraceExpansions $m.Value.Trim())) {
      $raw = Trim-Bits $x
      if ($raw.Length -le 9) { continue }
      if ($fromBrace) {
        # a brace-form PATH ref is resolved RIGHT HERE: existing members go into the whitelist
        # (ruling: expansion and whitelisting are the same step, before any cleanup) and missing
        # members are REPORTED -- never MISSING, because the pattern itself was never a literal.
        $braceExpanded[$raw] = 1
        if (Test-Path (Join-Path $root ($raw -replace '/', '\')) -PathType Leaf) { $whitelist.Add((Normalize $raw)) }
        else { $expMissing.Add(("{0}  (from brace pattern {1})" -f (Normalize $raw), $m.Value.Trim())) }
        continue
      }
      # RANGE bucket: expand `N..M` NOW, resolve each member, existing -> whitelist, missing ->
      # reported only. Before this existed, `..` was merely EXCLUDED (so the false MISSING went away
      # but no protection was built either) -- that is the "fixed the alarm, not the fire" shape.
      if ($raw.Contains('..')) {
        $rngMembers = Expand-RangeMembers $raw
        if ($rngMembers) {
          $rangeTokens++
          foreach ($mm in $rngMembers) {
            $rangeNames[$mm] = 1
            if (Test-Path (Join-Path $root ($mm -replace '/', '\')) -PathType Leaf) { $whitelist.Add((Normalize $mm)) }
            else { $expMissing.Add(("{0}  (from range pattern {1})" -f (Normalize $mm), $raw)) }
          }
          continue
        }
      }
      if ($placeRe.IsMatch($raw)) {
        if ($raw.Contains($ellipsis) -or $raw.Contains('...')) { if (-not $patB.Contains($raw)) { $patB.Add($raw) }; continue }
        if ($raw.Contains('{')) { if (-not $patA.Contains($raw)) { $patA.Add($raw) }; continue }
        if ($raw.Contains('*') -or $raw.Contains('?')) { if (-not $patC.Contains($raw)) { $patC.Add($raw) }; continue }
        if (-not $patterns.ContainsKey($raw)) { $patterns[$raw] = 0 }
        $patterns[$raw]++; continue
      }
      if (-not $pathRefs.ContainsKey($raw)) { $pathRefs[$raw] = 0; $pathLine[$raw] = $line; $hadLineSuffix[$raw] = $hadLine }
      $pathRefs[$raw]++
    }
  }
  foreach ($m in $codeRe.Matches($Text)) {
    $tok = $m.Groups[1].Value.Trim()
    if ($tok.Length -eq 0) { continue }
    if ($tok -match '[/\\]') { continue }
    if ($tok.Contains($ellipsis) -or $tok.Contains('...')) {
      # same file-shape gate as the path branch: prose snippets with an ellipsis are not citations
      $shape = ($tok -replace [regex]::Escape($ellipsis), 'X') -replace '\.\.\.', 'X'
      if (($shape -match '\.[A-Za-z0-9]{1,6}$' -or $shape.Contains('{')) -and $shape -notmatch '["'':]') {
        if (-not $patB.Contains($tok)) { $patB.Add($tok) }
      }
      continue
    }
    # a brace form only counts as a file pattern when it really looks like `name{a,b}.ext` -- prose
    # snippets such as `recompile_status {"failed":false}` are not patterns (measured noise).
    if ($tok.Contains('{')) {
      if ($tok -match '^[A-Za-z0-9_\-\.]+\{[^{}]+\}\.[A-Za-z0-9]{1,6}$') { if (-not $patA.Contains($tok)) { $patA.Add($tok) } }
      elseif ($tok -match '["'':]') { continue }   # prose / JSON snippet, not a citation at all
      else { if (-not $patB.Contains($tok)) { $patB.Add($tok) } }
      continue
    }
    if ($tok.Contains('*') -or $tok.Contains('?')) { if (-not $patC.Contains($tok)) { $patC.Add($tok) }; continue }
    $tok = $lineRef.Replace($tok, '')
    foreach ($n in (Get-BraceExpansions $tok)) {
      if ($n -match '[^\x20-\x7E\{\}]') { continue }
      if ($n -match '\.\.') { continue }
      if ($n -match '^[^A-Za-z0-9_]') { continue }
      $mm = [regex]::Match($n, '^([A-Za-z0-9_\-\.]+)\.([A-Za-z0-9]{1,6})$')
      if (-not $mm.Success) { continue }
      # extension must already be lowercase (`Debug.Log` is code, not a file); -cnotcontains is
      # CASE-SENSITIVE and an empty extension is never accepted.
      if ($extOk -cnotcontains $mm.Groups[2].Value) { continue }
      if ($mm.Groups[1].Value.Length -eq 0) { continue }
      if (-not $bareRefs.ContainsKey($n)) { $bareRefs[$n] = 0 }
      $bareRefs[$n]++
    }
  }

  # ---- PLAIN-TEXT bare names (CR-R1 found 6 files that ONLY their tool protected) ----
  # The table cells cite file names WITHOUT backticks (e.g. `panelStep5;AI2-04-roomlist.png`), so a
  # backtick-only extractor misses them and the cleanup would delete them. The scan is
  # RESOLUTION-GATED: a plain token is accepted only when it resolves to an existing file under the
  # cleanup zone, which keeps the false-positive rate at zero (source names like battle.go or asset
  # names like frame_015.png resolve elsewhere and are ignored).
  $plainNames = @{}
  $plainRe = [regex]('(?<![A-Za-z0-9_\-\./\\])([A-Za-z0-9_][A-Za-z0-9_\-\.]*\.(' + ($extOk -join '|') + '))')
  foreach ($m in $plainRe.Matches($Text)) {
    $n = $m.Groups[1].Value
    if ($n -match '\.\.') {
      # RANGE bucket for plain-text tokens too (same rule as the path branch)
      $rngBare = Expand-RangeMembers $n
      if ($rngBare) {
        $rangeTokens++
        foreach ($mm in $rngBare) {
          $rangeNames[$mm] = 1
          if ($Index.ContainsKey($mm)) {
            $evR = @($Index[$mm] | Where-Object { $_ -match $cleanupZone })
            if ($evR.Count -ge 1) { foreach ($k in $evR) { $whitelist.Add((Normalize $k)) } }
            else { $expMissing.Add(("{0}  (from range pattern {1})" -f $mm, $n)) }
          } else { $expMissing.Add(("{0}  (from range pattern {1})" -f $mm, $n)) }
        }
      }
      continue
    }
    if (-not $Index.ContainsKey($n)) { continue }
    $ev = @($Index[$n] | Where-Object { $_ -match $cleanupZone })
    if ($ev.Count -eq 0) { continue }
    $plainNames[$n] = 1
    if (-not $bareRefs.ContainsKey($n)) { $bareRefs[$n] = 0 }
    $bareRefs[$n]++
  }

  $dirs = New-Object System.Collections.Generic.List[string]
  foreach ($p in ($pathRefs.Keys | Sort-Object)) {
    $full = Join-Path $root ($p -replace '/', '\')
    if (Test-Path $full -PathType Leaf) { $whitelist.Add((Normalize $p)); continue }
    if (Test-Path $full -PathType Container) { $dirs.Add(("{0}  (cited {1}x)" -f $p, $pathRefs[$p])); continue }
    if ($hadLineSuffix[$p]) { $patterns[$p] = $pathRefs[$p]; continue }   # ':line' -> pattern, not missing
    if ($p -notmatch '\.[A-Za-z0-9]{1,6}$') { $patterns[$p] = $pathRefs[$p]; continue }  # truncated -> pattern
    $ln = [string]$pathLine[$p]
    $mDel = ([char]0x5220).ToString() + ([char]0x9664).ToString()                              # shan chu
    $mOne = ([char]0x4E00).ToString() + ([char]0x6B21).ToString() + ([char]0x6027).ToString()  # yi ci xing
    if ($ln.Contains($mDel) -or $ln.Contains($mOne)) {
      $deleted.Add(("{0}  (cited {1}x)  [citing line says deleted/one-off]" -f $p, $pathRefs[$p]))
    } else {
      $missing.Add(("{0}  (cited {1}x)" -f $p, $pathRefs[$p]))
    }
  }

  $inEvidence = 0
  $ambFull = @{}
  foreach ($n in ($bareRefs.Keys | Sort-Object)) {
    $hits = @(); if ($Index.ContainsKey($n)) { $hits = @($Index[$n]) }
    $ev = @($hits | Where-Object { $_ -match $evidenceRe })
    # only candidates inside the CLEANUP ZONE are whitelisted (CR-R1: the rest bloated the list by
    # 715 rows); every candidate is still printed for the reader.
    $keep = @($hits | Where-Object { $_ -match $cleanupZone })
    foreach ($k in $keep) { $whitelist.Add((Normalize $k)) }
    if ($ev.Count -ge 1) { $inEvidence++ }
    if ($hits.Count -ge 2) {
      # list up to 20 candidates inline (a 12-candidate name is a team-chosen sample and must be
      # readable without truncation); the machine-readable full list is in the -BucketDump file,
      # which keeps EVERY candidate so "count == number of listed candidates" stays an invariant.
      $ambFull[$n] = @($hits)
      $show = @($hits | Select-Object -First 20) -join ' | '
      if ($hits.Count -gt 20) { $show += ('  ... (+' + ($hits.Count - 20) + ' more; the -BucketDump file lists all)') }
      $ambiguous.Add(("{0}  ({1} candidates)  -> {2}" -f $n, $hits.Count, $show))
    } elseif ($hits.Count -eq 1) {
      if ($ev.Count -eq 0) { $outside.Add(("{0}  -> {1}" -f $n, $hits[0])) }
    } else {
      $unresolved.Add(("{0}  (cited {1}x)" -f $n, $bareRefs[$n]))
    }
  }

  # ---- patterns A / C expand INTO the whitelist; B is human-only ----
  foreach ($k in ($patA | Sort-Object)) {
    $exp = @(Get-BraceExpansions $k) | Where-Object { $_ -match '^[A-Za-z0-9_\-\./\\]+$' }
    $okN = 0; $gone = @()
    foreach ($e in $exp) {
      if (Test-Path (Join-Path $root ($e -replace '/', '\')) -PathType Leaf) { $whitelist.Add((Normalize $e)); $okN++ }
      else { $gone += $e }
    }
    foreach ($g in $gone) { $expMissing.Add(("{0}  (from pattern {1})" -f (Normalize $g), $k)) }
  }
  # NOTE: a `{}` inside a PATH citation is expanded BEFORE bucketing, so those files enter STEP1 /
  # the whitelist as the real names they denote; $braceTokens/$braceExpanded keep that visible so
  # two implementations can compare "how many refs were brace-form" on the same footing.
  $expandedA = New-Object System.Collections.Generic.List[string]
  foreach ($k in ($patA | Sort-Object)) {
    $exp = @(Get-BraceExpansions $k) | Where-Object { $_ -match '^[A-Za-z0-9_\-\./\\]+$' }
    $okN = @($exp | Where-Object { Test-Path (Join-Path $root ($_ -replace '/', '\')) -PathType Leaf }).Count
    $bad = $exp.Count - $okN
    $expandedA.Add(("{0}  [{1} member(s) expanded, {2} whitelisted{3}]" -f $k, $exp.Count, $okN, $(if ($bad -gt 0) { ', ' + $bad + ' not on disk' } else { '' })))
  }
  foreach ($k in ($patC | Sort-Object)) {
    $dir = Split-Path ($k -replace '/', '\') -Parent
    $leaf = Split-Path ($k -replace '/', '\') -Leaf
    $hits = @()
    if ($dir -and (Test-Path (Join-Path $root $dir))) {
      $hits = @(Get-ChildItem (Join-Path $root $dir) -Filter $leaf -File -ErrorAction SilentlyContinue |
                ForEach-Object { Normalize $_.FullName.Substring($root.Length).TrimStart('\', '/') } |
                Where-Object { $_ -match $cleanupZone })
    }
    foreach ($h in $hits) { $whitelist.Add($h) }
    $expandedA.Add(("{0}  [{1} file(s) matched on disk and whitelisted]" -f $k, $hits.Count))
  }

  # ── UNCONDITIONAL KEEP (team-lead's rule 2026-09-23, from CR-U5R's "the protection itself must be
  # protected"): NOT derived from citation reachability. Index files are EVIDENCE SURFACES -- an index
  # of a screenshot/evidence set. If the set survives but its index is deleted, the evidence becomes
  # unreadable ("orphaned"), even though no 策划/ document happens to name the index today.
  # Declared here so that "what must never be deleted" is MACHINE-GENERATED instead of remembered.
  # NOTE: the generator's own products (whitelist / delta / buckets) live in tools/probes, i.e. OUTSIDE
  # the cleanup zone => the "whitelist-related files" half of that rule needs no entry here.
  $keepHits = New-Object System.Collections.Generic.List[string]
  $keepZone = Join-Path $root '.ai-tmp'
  if (Test-Path $keepZone) {
    foreach ($h in @(Get-ChildItem $keepZone -Recurse -File -Filter '*index*.tsv' -ErrorAction SilentlyContinue)) {
      $rel = Normalize $h.FullName.Substring($root.Length).TrimStart('\', '/')
      if (-not $whitelist.Contains($rel)) { $whitelist.Add($rel) }
      $keepHits.Add($rel)
    }
  }

  return [pscustomobject]@{
    PathRefs = $pathRefs; BareRefs = $bareRefs
    UncondKeep = @($keepHits | Sort-Object -Unique)
    BraceTokens = $braceTokens; BraceExpanded = $braceExpanded.Count; PlainNames = $plainNames.Count
    RangeTokens = $rangeTokens; RangeNames = $rangeNames.Count
    InEvidence = $inEvidence; DirRefs = $dirs; Deleted = $deleted; PatA = $expandedA; PatB = @($patB | Sort-Object)
    Truncated = @($patterns.Keys | Sort-Object)
    Whitelist = @($whitelist | Sort-Object -Unique); Missing = $missing
    Unresolved = $unresolved; Ambiguous = $ambiguous; AmbFull = $ambFull; Outside = $outside; ExpMissing = $expMissing
  }
}

# ---------------------------------------------------------------- self-test fixtures
# WHY THE FIXTURES ARE CREATED HERE (before the index) AND REMOVED LATER: the source project's
# self-test vectors pointed at files that happened to exist in that project, so -SelfTest PASSED
# there and would FAIL on every other project -- i.e. it tested the PROJECT, not the script.  The
# fixtures are therefore written by the test itself, into the one-off area (that is what the one-off
# area is for) and deleted at the end of the self-test block.
# They must exist BEFORE the name index is built, because the ambiguity vector is resolved through
# the index, not through the file system.
# Each vector has its OWN name prefix: an earlier version shared one prefix, and then the "no bad
# member was whitelisted" assertion counted the GOOD fixtures as bad (measured: whitelisted=8
# reported=11) -- two vectors interfering is exactly the kind of false red that gets a check deleted.
# If this script dies mid-way the fixtures remain under .ai-tmp/test; the stray-temp-files gate then
# reports them, which is the correct outcome rather than a silent leak.
$fxDir = $null
$fxNames = @()
$fxDup = ''
if ($SelfTest -and -not $SelfTestNoFixtures) {
    $fxDir = Join-Path $T 'probe-fixtures'
    if (-not (Test-Path $fxDir)) { New-Item -ItemType Directory -Path $fxDir -Force | Out-Null }
    foreach ($i in 0..4) { $fxNames += ('{0}-rng-{1}.txt' -f $ProbePrefix, $i) }                     # RANGE positive: all members exist
    foreach ($i in 0..2) { $fxNames += ('{0}-prt-{1}.txt' -f $ProbePrefix, $i) }                     # RANGE partial: 3 of 6 exist
    foreach ($i in @(0, 7, 14, 21, 28, 35)) { $fxNames += ('{0}-brc-{1}.txt' -f $ProbePrefix, $i) }  # brace A: all members exist
    foreach ($n in $fxNames) { Set-Content -Path (Join-Path $fxDir $n) -Value 'fixture' -Encoding ASCII }
    # ambiguity vector: the same bare name in two places, at least one inside the evidence zone
    $fxDup = ('{0}-dup.md' -f $ProbePrefix)
    Set-Content -Path (Join-Path $fxDir $fxDup) -Value 'fixture' -Encoding ASCII
    Set-Content -Path (Join-Path $T $fxDup) -Value 'fixture' -Encoding ASCII
}

$index = Build-Index
$text  = ($docs | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8) }) -join "`n"
$withRefs = @($docs | Where-Object { [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8).Contains('.ai-tmp') }).Count
$r     = Invoke-Extract $text $index
$bsEntries = @($r.Whitelist | Where-Object { $_.Contains('\') }).Count
$outEntries = @($r.Whitelist | Where-Object { $_ -notmatch $cleanupZone }).Count

if (-not $Quiet) {
  Write-Output ('root      = ' + $root)
  Write-Output ('scope     = ' + $Scope + ' : ' + $docs.Count + ' file(s) scanned, ' + $withRefs + ' of them cite .ai-tmp')
  Write-Output ('index     = ' + $index.Count + ' distinct file name(s) across ' + $indexRoots.Count + ' root(s)')
  Write-Output ('index roots= ' + ($idxRootInfo -join '  '))
  Write-Output ('delimiter = forward slash  (entries containing a backslash: ' + $bsEntries + ' ; entries outside the cleanup zone: ' + $outEntries + ')')
  Write-Output ''
  Write-Output ('STEP1 literal path refs    = ' + $r.PathRefs.Count + '  (exist ' + ($r.PathRefs.Count - $r.Missing.Count - $r.Deleted.Count) + ', absent-but-documented ' + $r.Deleted.Count + ', MISSING ' + $r.Missing.Count + ')')
  Write-Output ('STEP2 bare-name refs       = ' + $r.BareRefs.Count + '  (hit the evidence area ' + $r.InEvidence + ', single hit elsewhere ' + $r.Outside.Count + ', unresolved ' + $r.Unresolved.Count + ')')
  Write-Output ('STEP2b AMBIGUOUS bare      = ' + $r.Ambiguous.Count)
  Write-Output ('STEP2c plain-text bare     = ' + $r.PlainNames + '  (table cells cite names without backticks; accepted only when they resolve inside the cleanup zone)')
  Write-Output ('STEP3 pattern refs         = ' + ($r.PatA.Count + $r.PatB.Count) + '  (A expandable ' + $r.PatA.Count + ', B ellipsis/human ' + $r.PatB.Count + ') -- none counted as MISSING')
  Write-Output ('STEP3a brace-form PATH refs= ' + $r.BraceTokens + ' token(s) -> ' + $r.BraceExpanded + ' expanded name(s) (expanded BEFORE bucketing, so they enter STEP1 and the whitelist as real names)')
  Write-Output ('STEP3b RANGE-form refs     = ' + $r.RangeTokens + ' token(s) -> ' + $r.RangeNames + ' member name(s) (N..M expanded; existing members whitelisted, missing ones reported only)')
  Write-Output ('WHITELIST entries (uniq)   = ' + $r.Whitelist.Count + '  (files inside the cleanup zone only)')
  Write-Output ('INFO dir-form path refs    = ' + $r.DirRefs.Count)
  Write-Output ''
  Write-Output '--- FAIL: literal path citation absent from disk, no pattern, citing line does not say deleted ---'
  if ($r.Missing.Count -eq 0) { Write-Output '  (none)' } else { $r.Missing | Select-Object -First $MaxList | ForEach-Object { Write-Output ('  ' + $_) } }
  Write-Output ''
  Write-Output '--- INFO: absent from disk but the citing line explicitly says deleted / one-off (NOT a defect) ---'
  if ($r.Deleted.Count -eq 0) { Write-Output '  (none)' } else { $r.Deleted | ForEach-Object { Write-Output ('  ' + $_) } }
  Write-Output ''
  Write-Output '--- HUMAN: pattern refs A (brace list, expandable -- members already whitelisted) ---'
  if ($r.PatA.Count -eq 0) { Write-Output '  (none)' } else { $r.PatA | Select-Object -First $MaxList | ForEach-Object { Write-Output ('  ' + $_) } }
  Write-Output ''
  Write-Output '--- INFO: expanded members that are NOT on disk (reported, never judged red) ---'
  if ($r.ExpMissing.Count -eq 0) { Write-Output '  (none)' } else { $r.ExpMissing | Select-Object -First $MaxList | ForEach-Object { Write-Output ('  ' + $_) } }
  Write-Output ''
  Write-Output '--- HUMAN: truncated path refs (no file extension after trimming -- prose cut, not a file) ---'
  if ($r.Truncated.Count -eq 0) { Write-Output '  (none)' } else { $r.Truncated | Select-Object -First $MaxList | ForEach-Object { Write-Output ('  ' + $_) } }
  Write-Output ''
  Write-Output '--- HUMAN: pattern refs B (ellipsis -> not mechanically expandable) ---'
  if ($r.PatB.Count -eq 0) { Write-Output '  (none)' } else { $r.PatB | Select-Object -First $MaxList | ForEach-Object { Write-Output ('  ' + $_) } }
  Write-Output ''
  Write-Output '--- HUMAN: unresolved bare names (NOT a verdict -- source / asset / pattern / truly dangling) ---'
  if ($r.Unresolved.Count -eq 0) { Write-Output '  (none)' } else { $r.Unresolved | ForEach-Object { Write-Output ('  ' + $_) } }
  Write-Output ''
  Write-Output '--- HUMAN: ambiguous bare names (every candidate listed; cleanup-zone candidates whitelisted) ---'
  if ($r.Ambiguous.Count -eq 0) { Write-Output '  (none)' } else { $r.Ambiguous | Select-Object -First $MaxList | ForEach-Object { Write-Output ('  ' + $_) } }
  Write-Output ''
  Write-Output '--- INFO: bare names with a single hit outside the cleanup zone (source / asset names) ---'
  if ($r.Outside.Count -eq 0) { Write-Output '  (none)' } else { $r.Outside | Select-Object -First $MaxList | ForEach-Object { Write-Output ('  ' + $_) } }
  Write-Output ''
  Write-Output ('WHITELIST (first 12 of ' + $r.Whitelist.Count + '):')
  $r.Whitelist | Select-Object -First 12 | ForEach-Object { Write-Output ('  ' + $_) }
}

# MACHINE-READABLE BUCKET DUMP: the cleanup simulation must be able to ask "which names did the
# extractor actually FIND (i.e. which are citations)?" -- without this the simulation would treat
# every same-name file in the tree as "ambiguous citation", including Mono runtime files under
# .ai-tmp/test/build that nobody cites (measured: 93 such false candidates). Citation-ness is the
# extractor's output, so it has to be exported instead of re-guessed.
if ($BucketDump) {
  $bAbs = if ([System.IO.Path]::IsPathRooted($BucketDump)) { $BucketDump } else { [System.IO.Path]::GetFullPath((Join-Path $root $BucketDump)) }
  $bl = New-Object System.Collections.Generic.List[string]
  $bl.Add('# machine-readable buckets | scope=' + $Scope + ' | at ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + ' | generator scripts/cited-evidence-whitelist.ps1 -BucketDump')
  # $tab as a char avoids nested-quote escaping in the line below (a splice attempt broke the file).
  $tab = [char]9
  $bl.Add('# AMBIG<tab>name<tab>candidateCount<tab>candidate1|candidate2|...   EVERY candidate, uncapped,')
  $bl.Add('# so "candidateCount == number of |-separated candidates" is a checkable cross-column invariant.')
  $bl.Add('# ZONE-SPREAD: candidates may live in different zones (e.g. ui-index-manifest.tsv exists in')
  $bl.Add('#   both .ai-tmp/test/zoom and .ai-tmp/screenshots) -- keeping only some of them still dangles.')
  foreach ($n in ($r.AmbFull.Keys | Sort-Object)) {
    $paths = @($r.AmbFull[$n])
    $bl.Add('AMBIG' + $tab + $n + $tab + $paths.Count + $tab + ($paths -join '|'))
  }
  [System.IO.File]::WriteAllLines($bAbs, $bl, (New-Object System.Text.UTF8Encoding($false)))
  Write-Output ('BUCKET DUMP written: ' + $bAbs + '  (' + $r.AmbFull.Keys.Count + ' ambiguous name(s), full candidate lists)')
}

if ($Land -and -not $OutFile) { $OutFile = Join-Path $here ('cited-evidence-whitelist-' + $Scope + '.txt') }
if ($OutFile) {
  $abs = if ([System.IO.Path]::IsPathRooted($OutFile)) { $OutFile } else { [System.IO.Path]::GetFullPath((Join-Path $root $OutFile)) }
  $asm = if ($AsmRelative) { Join-Path $root $AsmRelative } else { '' }
  $asmSha = if ($asm -and (Test-Path $asm)) { (Get-FileHash $asm -Algorithm SHA256).Hash.Substring(0, 16) } else { 'n/a' }
  # ONE header line on purpose: PowerShell flattens a string[] argument into one space-joined line
  # for some .NET overloads (measured: three '# ...' elements arrived as a single line).
  # SELF-DESCRIBING CONSUMPTION CONTRACT (team-lead ruling). Tonight's third "one thing, two shapes,
  # consumer sees one" trap -- delimiters, path-form vs bare-name, scope vs shape -- so the header
  # tells the future cleanup author EXACTLY how to consume this file.
  $cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File scripts/cited-evidence-whitelist.ps1 -Scope ' + $Scope + ' -Land'
  $hdr = New-Object System.Collections.Generic.List[string]
  $hdr.Add('# cited-evidence-whitelist  scope=' + $Scope + '  entries=' + $r.Whitelist.Count +
           '  --  MACHINE-GENERATED DERIVATIVE, NOT evidence, do NOT hand-edit; regenerate with: ' + $cmd)
  # KINDS was WRONG until 2026-09-23 (CR-D1 caught it): (b) used to claim bare names resolve only under
  # `.ai-tmp/test or .ai-tmp/screenshots`, but the implementation resolves under EVERY `.ai-tmp/` subtree --
  # measured in this very file: .ai-tmp/hosts 3 entries, .ai-tmp/web 11, .ai-tmp/drivers 2. That false
  # sentence made readers believe bare names were confined to two directories (it also removed the basis for
  # a "third gap" hypothesis). NOTE: the regex KEEP for ambiguity classification ($evidenceRe =
  # ^.ai-tmp/(test|screenshots)/) is a DIFFERENT surface -- protection is not restricted by it.
  $hdr.Add('# KINDS: (a) path-form citations taken verbatim from the ledger docs; (b) bare-name citations resolved to their real path under ANY .ai-tmp/ subtree' +
           ' (test, screenshots, hosts, web, drivers, ...); (c) files reached by expanding brace, glob or numeric-range patterns (pattern expansion happens BEFORE any cleanup);' +
           ' (d) *.ai-tmp/**/*index*.tsv kept unconditionally (an index is a judgement surface; deleting it orphans the set it indexes).' +
           ' For an AMBIGUOUS bare name (same name in >1 place) EVERY cleanup-zone candidate is listed in this file.')
  $hdr.Add('# DELIMITER: forward slash only (0 entries contain a backslash).  CONSUMER CONTRACT: match these lines as FILE-NAME LITERALS -- do NOT re-derive citations with your own regex,' +
           ' because path-form and bare-name references are two different shapes and each implementation then silently misses half of them (measured: 40 bare-name cites + 43 duplicate rows).')
  # DEFINITIONS pinned in the header (CR-R1's suggestion): without them two implementations spend
  # rounds explaining number differences instead of comparing facts.
  $hdr.Add('# DEFINITIONS (pinned so two implementations never argue about numbers again): ' +
           'MISSING = a LITERAL path-form ref that ends with a file extension, contains no brace/glob/' +
           'range/:line form, is ABSENT from disk AND whose citing line does not say deleted/one-off. ' +
           'PATTERN BUCKETS (A/B) count pattern tokens found ANYWHERE in the documents (path-form AND ' +
           'bare-name), not only inside the .ai-tmp path tails. BARE NAMES = backticked inline-code tokens PLUS ' +
           'plain-text tokens (table cells cite names without backticks) that RESOLVE to an existing file ' +
           'inside the cleanup zone; the extension must be lowercase and in a fixed set, so code ' +
           'identifiers such as Debug.Log are excluded.')
  # CONSUMER-SIDE SEMANTICS (team-lead SPEC, from CR-F1's wording): this list is a PROTECTION list,
  # NOT a red-line list. Both possible errors point the same (safe) way: over-inclusion merely keeps
  # an extra file (zero cost), under-inclusion produces an unrecoverable dangling reference. So the
  # extractor is deliberately generous and nobody may use this file to judge anyone red.
  $hdr.Add('# AMBIGUITY = an OPEN STATE, NOT "SAFE": a name with several candidates is safe ONLY because this' +
           ' extractor keeps EVERY candidate inside the cleanup zone. That implementation is measured by' +
           ' the project''s ambiguity-cleanup simulation probe (0 would-be deletions; its -NegativeControl deletes 2,' +
           ' i.e. the check can fail). Never quote "ambiguous names are safe" as a proven conclusion.' +
           ' A name all of whose candidates live OUTSIDE the cleanup zone (e.g. frame_418.png, 12 copies under' +
           ' client/Assets) cannot be deleted by construction and therefore cannot distinguish a correct' +
           ' implementation from a broken one -- it is not a usable probe for this rule.')
  $hdr.Add('# ROLE: PROTECTION LIST, not a red-line list. Over-inclusion = an extra kept file (zero cost);' +
           ' under-inclusion = an unrecoverable dangling reference. Use it to decide what NOT to delete;' +
           ' never use it to mark a row as failed.')
  $hdr.Add('# UNCONDITIONAL KEEP: index files under the cleanup zone are kept REGARDLESS of citation' +
           ' reachability -- rule = .ai-tmp/**/*index*.tsv (EVIDENCE SURFACE: an index of a screenshot/' +
           ' evidence set; deleting it orphans the set even if no doc names it today).' +
           ' kept-index-files=' + $r.UncondKeep.Count + ' <== re-globbed and cross-checked against this file' +
           ' by the read-back self-check (that check can fail: -NegativeControl)')
  # TWO ORTHOGONAL AXES, TWO NUMBERS (team-lead ruling 2026-09-23): never report one word "ambiguous".
  #   multi-candidate = an IMPLEMENTATION fact (how many same-name candidates sit inside the zone)
  #   not-in-union    = a COVERAGE fact     (how many candidates are absent from the protection set)
  # CANDIDATE DEFINITION (self-caught error, measured): the first version of this line counted EVERY
  # repo-wide copy, including ones OUTSIDE the cleanup zone (e.g. the 12 client/Assets copies of
  # frame_418.png) => it printed not-in-union=11, which is meaningless: an out-of-zone copy cannot be
  # deleted by the cleanup, so its absence from a protection list protects nothing. The axis is about
  # IN-ZONE candidates only -- same definition as the sim and as CR-R1's cross-check.
  $mcNames = @($r.AmbFull.Keys | Sort-Object)
  $niuNames = @($mcNames | Where-Object {
      @(@($r.AmbFull[$_]) | Where-Object { $_ -match $cleanupZone -and $r.Whitelist -notcontains $_ }).Count -gt 0 })
  # multi_candidate SPLIT INTO TWO NUMBERS (team-lead ruling 2026-09-23; the third "same fact, two
  # numbers" of the night -- CR-F2's generator says 13, CR-F1/CR-R1 say 2):
  #   _all   = every name this GENEROUS extractor resolves ambiguously (it also accepts plain-text bare
  #            tokens, brace/range expansions) => e.g. frame_008..206.png appear in prose
  #   _cited = the subset that ALSO appears as an explicit PATH citation => the only ones whose deletion
  #            can break a judgement. SAFETY DEPENDS ON THIS ONE.
  $citedAmbig = @($mcNames | Where-Object {
      $nn = $_
      @(@($r.PathRefs.Keys) | Where-Object { (Split-Path ($_ -replace '\\', '/') -Leaf) -eq $nn }).Count -gt 0 })
  $hdr.Add('# AMBIGUITY COUNTS (both axes; candidate = IN-ZONE candidate, i.e. one the cleanup could delete)' +
           ' | multi_candidate_all = ' + $mcNames.Count + ' (every doc-mentioned name with >1 in-zone candidate; this GENEROUS extractor)' +
           ' | multi_candidate_cited = ' + $citedAmbig.Count + ' (of those, ALSO cited as an explicit PATH reference -- DIRECTORY-QUALIFIED, i.e. the citation' +
           ' pins one directory, unlike the bare-name prose mentions counted in _all => SAFETY DEPENDS ONLY ON THESE;' +
           ' an unreferenced same-name file can go without breaking any judgement' +
           ' | measured for the all-scope: _all=13 names (frame_008..206.png etc. appear only as bare prose names), _cited=2' +
           ' (e.g. a full-page screenshot and its index manifest) -- both numbers come from the SAME extraction, so the gap is the definition, not a disagreement)' +
           ' | not-in-union = ' + $niuNames.Count + ' name(s) with at least one IN-ZONE candidate ABSENT from this file' +
           ' | TWO DEPENDENCIES, kept apart (team-lead ruling D115, wording pinned because the loose version' +
           ' silently excused the base contract):' +
           ' (i) IN AMBIGUOUS CASES TOO, no whitelist member may be deleted -- nobody may delete a W member on' +
           ' the grounds that "a same-name file was picked" => BASE CONTRACT, ALWAYS required => this list NEEDS it.' +
           ' (ii) "keep EVERY candidate" (the extra ambiguity rule) is required ONLY IF some candidate is not in W' +
           ' => for this list: not-in-union=' + $niuNames.Count + ' => ' + $(if ($niuNames.Count -eq 0) { 'NOT required' } else { 'REQUIRED' }) + '.' +
           ' CRITERION = whether a candidate outside W exists.' +
           ' MEASURED (negative control of the project''s ambiguity-cleanup simulation probe): under the wrong rule' +
           ' ("keep only the first candidate") the two whitelisted copies ARE deleted => "all candidates are in W"' +
           ' does NOT by itself mean "(i) is not needed"; never quote "ambiguous names are safe" as a conclusion.')
  $hdr.Add('# AUDIT CHAIN: the sidecar .delta.txt describes only the MOST RECENT transition (a later land' +
           ' overwrites it). The append-only ledger cited-evidence-whitelist-transitions.tsv keeps one row' +
           ' per land (prev_sha16 -> new_sha16, changed, added, removed, entries) so "what changed when"' +
           ' survives. NOTE: prev!=new every time because THIS header line "cleanup at <ts>" changes;' +
           ' the load-bearing numbers are added/removed (body entries), which stay 0/0 for header-only lands.' +
           ' FINGERPRINTS CARRY TIME (team-lead ruling 2026-09-23): every ledger row records new_bytes +' +
           ' new_mtime next to the hashes, because a bare sha16 cannot distinguish "same file, two hashes"' +
           ' from "file really changed". Rows after the SCHEMA v2 marker have 11 fields, earlier rows 9.')
  # CORPUS AS-OF (CR-R1's request): the union is only as fresh as the documents it read. State what the
  # corpus looked like when this file was produced, so a reader can judge staleness without hashing it.
  # NOTE: deliberately NOT a corpus manifest hash -- that would be the dir_content_hash recipe, which has
  # exactly one implementation and must not be re-implemented here.
  $newest = ($docs | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
  $newestTxt = if ($newest) { (Split-Path $newest.FullName -Leaf) + ' @ ' + $newest.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') } else { '(none)' }
  $hdr.Add('# CORPUS AS-OF ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + ' | docs scanned = ' + $docs.Count +
           ' (.md + .tsv only; .txt excluded) | newest doc = ' + $newestTxt +
           ' -- if the corpus has moved on since this instant, this list may be stale: re-run to refresh.' +
           ' EXCLUDED .txt: measured 2026-09-23 by CR-R1 (parsed, not recounted) -- the two numeric docs' +
           ' (numeric_docs .txt) contain NO resolvable cleanup-zone reference => a COUNTING difference, not a protection gap.')
  # CITATION SOURCES -- the truth. The old wording ("every EXISTING citation is protected") over-promised
  # and misled two team members into "X cites Y => Y is protected" reasoning that does not hold:
  # citations are collected ONLY from 策划/**.md|*.tsv. The index surface also covers .ai-tmp / client/...
  # -- that is WHO IS LOOKED UP, not WHO CITES. A citation written INSIDE a .ai-tmp file protects NOTHING.
  $hdr.Add('# CITATION SOURCES: 策划/**.md|*.tsv ONLY. A citation written inside a .ai-tmp file protects' +
           ' NOTHING (measured 2026-09-23: an in-.ai-tmp file citing .ai-tmp/test/CR-U5-evidence.txt with a' +
           ' line range protected nothing). To protect a file, put its path in a 策划/ document. The TARGET' +
           ' index surface is wider than the CITATION source surface -- never conflate the two.')
  $hdr.Add('# cleanup at ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + ' | assembly sha256_16=' + $asmSha +
           ' | CLEANUP RULE: citations found in 策划/ are protected, INCLUDING refs pointing into .ai-tmp/drivers (keep them)' +
           ' | WRITING RULE: a NEW row must NOT cite .ai-tmp/drivers' +
           ' | one-off area DOES NOT mean deletable: the delivery docs cite files under .ai-tmp/test')
  # AUDIT DELTA (CR-R1's finding): overwriting a whitelist in place destroys the audit chain -- two
  # versions exist and nobody can tell WHAT the +2 entries were. So the previous hash and the
  # added/removed sets are written to a sidecar before the overwrite.
  if (Test-Path $abs) {
    $prev = @(Get-Content $abs -Encoding UTF8 | Where-Object { $_.Trim().Length -gt 0 -and $_ -notmatch '^#' } | ForEach-Object { Normalize $_.Trim() })
    $prevHash = (Get-FileHash $abs -Algorithm SHA256).Hash.Substring(0, 16)
    $addedSet = @($r.Whitelist | Where-Object { $prev -notcontains $_ })
    $removedSet = @($prev | Where-Object { $r.Whitelist -notcontains $_ })
    $dLines = New-Object System.Collections.Generic.List[string]
    $dLines.Add('# DELTA for ' + (Split-Path $abs -Leaf) + ' | previous sha256_16=' + $prevHash + ' (' + $prev.Count + ' entries) -> new ' + $r.Whitelist.Count + ' entries | at ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + ' | Machine-generated, do NOT hand-edit')
    # NOTE: no inline `if` expression -- that is PowerShell 7 syntax and this project runs WinPS 5.1.
    $addNote = if ($addedSet.Count -eq 0) { ' (none)' } else { '' }
    $remNote = if ($removedSet.Count -eq 0) { ' (none)' } else { '' }
    $dLines.Add('# added ' + $addedSet.Count + $addNote)
    foreach ($a in $addedSet) { $dLines.Add('+ ' + $a) }
    $dLines.Add('# removed ' + $removedSet.Count + $remNote)
    foreach ($rm in $removedSet) { $dLines.Add('- ' + $rm) }
    $dAbs = ($abs -replace '\.txt$', '.delta.txt')
    [System.IO.File]::WriteAllLines($dAbs, $dLines, (New-Object System.Text.UTF8Encoding($false)))
    # GENERATIONAL DELTA LOG (CR-R1's residual finding, adopted 2026-09-23): the sidecar .delta.txt only
    # ever describes ONE transition, so two lands later the previous one is unrecoverable (measured: the
    # 322->327 "+5 RANGE fix" entry list is gone). Append the SAME block to an append-only .delta.log so
    # "what changed in each generation" accumulates instead of being replaced.
    $logAbs = ($abs -replace '\.txt$', '.delta.log')
    $logSep = '# ===== transition at ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + ' | previous sha256_16=' + $prevHash +
              ' (' + $prev.Count + ' entries) -> new ' + $r.Whitelist.Count + ' entries ====='
    [System.IO.File]::AppendAllText($logAbs, ($logSep + "`r`n" + (($dLines | ForEach-Object { $_ }) -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
    Write-Output ('DELTA LOG appended: ' + (Split-Path $logAbs -Leaf))
    # The append-only transition ledger is written AFTER the whitelist overwrite, below (see the NOTE there).
    Write-Output ('DELTA written: ' + $dAbs + '  (+' + $addedSet.Count + ' / -' + $removedSet.Count + ' vs ' + $prevHash + ')')
  }
  $allLines = New-Object System.Collections.Generic.List[string]
  foreach ($h in $hdr) { $allLines.Add($h) }
  foreach ($e in $r.Whitelist) { $allLines.Add($e) }
  [System.IO.File]::WriteAllLines($abs, $allLines, (New-Object System.Text.UTF8Encoding($false)))
  Write-Output ('WHITELIST written: ' + $abs + '  (' + $r.Whitelist.Count + ' entries, ' + $hdr.Count + ' contract lines)')

  # APPEND-ONLY TRANSITION LEDGER (CR-R1's finding: the sidecar delta describes only the MOST RECENT
  # transition, so the next land destroys "what changed" -- measured: the +4 transition at 11:27 was
  # overwritten by a header-only land minutes later).
  # DEFECT SELF-CAUGHT (measured): the first version sat INSIDE the block above and computed $newHash
  # BEFORE the overwrite => every row read `prev == new` and the ledger proved nothing. It must run
  # AFTER the write, which is why it lives here.
  $tAbs = Join-Path $here 'cited-evidence-whitelist-transitions.tsv'
  $tEnc = New-Object System.Text.UTF8Encoding($false)
  if (-not (Test-Path $tAbs)) {
    [System.IO.File]::AppendAllText($tAbs, ("# SCHEMA v2 -- at`tscope`tprev_sha256_16`tnew_sha256_16`tchanged`tadded`tremoved`tentries`tnew_bytes`tnew_mtime`tnote" + "`r`n"), $tEnc)
  }
  elseif (@(Get-Content $tAbs -Encoding UTF8 | Where-Object { $_ -match 'SCHEMA v2' }).Count -eq 0) {
    # APPEND-ONLY schema change: a fingerprint must carry TIME (team-lead ruling 2026-09-23, from CR-V2)
    # -- a bare sha16 cannot tell "same file, two hashes" from "file really changed". Rows ABOVE this
    # marker keep v1's 9 columns; rows BELOW add new_bytes + new_mtime. Old rows are NEVER rewritten
    # (rewriting is exactly the "overwrite destroys the audit chain" failure this ledger exists for).
    [System.IO.File]::AppendAllText($tAbs, ("# SCHEMA v2 (added columns: new_bytes, new_mtime) -- rows ABOVE this line are v1 (9 cols)." + "`r`n"), $tEnc)
  }
  $newHash = (Get-FileHash $abs -Algorithm SHA256).Hash.Substring(0, 16)
  $newItem = Get-Item $abs
  $prevFor = if ($prevHash) { $prevHash } else { '(absent)' }
  $changedTxt = if ($prevHash -and ($prevHash -ne $newHash)) { 'yes' } else { 'no' }
  $addC = if ($addedSet) { @($addedSet).Count } else { 0 }
  $remC = if ($removedSet) { @($removedSet).Count } else { 0 }
  $tLine = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + "`t" + $Scope + "`t" + $prevFor + "`t" + $newHash + "`t" +
           $changedTxt + "`t" + $addC + "`t" + $remC + "`t" + $r.Whitelist.Count + "`t" + $newItem.Length + "`t" +
           $newItem.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') + "`tland-v2`r`n"
  [System.IO.File]::AppendAllText($tAbs, $tLine, $tEnc)
  Write-Output ('TRANSITION appended: ' + (Split-Path $tAbs -Leaf) + '  ' + $prevFor + ' -> ' + $newHash + '  changed=' + $changedTxt + '  (+' + $addC + '/-' + $remC + ')')
}

# ---------------------------------------------------------------------------
# UNION with a second, independently written implementation (CR-R1's).
# Rationale: the two tools are each conservative in DIFFERENT places (measured: 19 entries only
# here, 6 only there), and at cleanup time "keeping a file costs nothing, deleting a cited one
# dangles a reference" -- the cost is asymmetric, so the cleanup consumes the UNION.
# The union fails LOUDLY when the partner file is missing or suspiciously small: a silently
# halved union would be worse than none.
# ---------------------------------------------------------------------------
if ($Union) {
  # FAIL-CLOSED (team-lead ruling 2026-09-23; root cause located in this file): -Union ALONE writes two
  # objects -- cited-evidence-whitelist-UNION-<scope>.txt (below) and an append to ...-anchors.tsv -- while
  # $asmSha and the transitions/delta ledgers are computed only on the -Land / -OutFile path. A -Union-only
  # run therefore emitted a union whose header read "assembly sha256_16= | ..." (no assembly stamp) and left
  # transitions.tsv unappended; that is exactly the state one reviewer flagged as an inconsistent product.
  # The union header NEEDS $asmSha, so this combination is refused instead of producing an unstamped product.
  if (-not $Land) {
    Write-Output 'UNION FAIL: -Union without -Land would write cited-evidence-whitelist-UNION-<scope>.txt with an EMPTY assembly summary (measured 2026-09-23) and append nothing to the transitions ledger. Pass -Land -Union together, or pass -OutFile.'
    exit 4
  }
  # -UnionWith <path> is the documented switch; -Partner is kept as a legacy alias.
  $otherPath = if ($UnionWith) { $UnionWith } elseif ($Partner) { $Partner } else { Join-Path $here ('evidence-whitelist-crosscheck-whitelist-' + $Scope + '.txt') }
  $partnerPath = $otherPath   # NOTE: do NOT name this local `$unionWith` -- it would BE the param
  if (-not (Test-Path $partnerPath)) { Write-Output ('UNION FAIL: partner whitelist not found: ' + $partnerPath); exit 3 }
  # NOTE: the local is $partnerEntries, NOT $partner -- `$partner` would BE the [string] parameter
  # `$Partner` (PowerShell variables are case-insensitive), so the array would be coerced to a
  # single string and the union would silently contain one entry. Same family as CR-R1's $p/$P.
  $partnerEntries = @(Get-Content $partnerPath -Encoding UTF8 -ErrorAction SilentlyContinue |
               Where-Object { $_.Trim().Length -gt 0 -and $_ -notmatch '^#' } |
               ForEach-Object { Normalize $_.Trim() })
  if ($partnerEntries.Count -lt 10) { Write-Output ('UNION FAIL: partner whitelist suspiciously small (' + $partnerEntries.Count + ' entries)'); exit 3 }
  $partnerHash = (Get-FileHash $partnerPath -Algorithm SHA256).Hash
  $onlyAList = @($r.Whitelist | Where-Object { $partnerEntries -notcontains $_ })
  $onlyBList = @($partnerEntries | Where-Object { $r.Whitelist -notcontains $_ })
  $onlyA = $onlyAList.Count
  $onlyB = $onlyBList.Count
  # per-class residual breakdown (team-lead ruling): the residuals are not errors, they are the two
  # implementations being conservative in DIFFERENT places, so they must be named, not just counted.
  $clsDrivers = @($onlyAList | Where-Object { $_ -match '^\.ai-tmp/drivers/' }).Count
  $clsSubdir  = @($onlyAList | Where-Object { $_ -match '^\.ai-tmp/(test|screenshots)/.+/' }).Count
  $clsOther   = $onlyA - $clsDrivers - $clsSubdir
  $partitionNote = 'A-only ' + $onlyA + ', B-only ' + $onlyB + ', shared ' + ($r.Whitelist.Count - $onlyA)
  $otherItem = Get-Item $partnerPath
  $otherAsof = $otherItem.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
  # explicit loop instead of array+array: concatenating two arrays inside @() with a pipeline threw
  # "MetadataError / ParentContainsErrorRecordException" (measured), and a silent union failure is
  # exactly the failure mode this file is supposed to prevent.
  # NAMING RULE LEARNED THE HARD WAY: do NOT name a local `$union` / `$partner` -- those ARE the
  # [switch]$Union / [string]$Partner parameters (PowerShell variables are case-insensitive), so the
  # assignment is coerced and dies with
  #   "Cannot convert value "System.Object[]" to type "System.Management.Automation.SwitchParameter""
  # reported at this very line. Twice in one file tonight; hence $unionEntries / $partnerEntries.
  $uSet = @{}
  foreach ($e in @($r.Whitelist)) { if ($e -match $cleanupZone) { $uSet[[string]$e] = 1 } }
  foreach ($e in @($partnerEntries)) { if ($e -match $cleanupZone) { $uSet[[string]$e] = 1 } }
  $unionEntries = @($uSet.Keys | Sort-Object)
  $uAbs = Join-Path $here ('cited-evidence-whitelist-UNION-' + $Scope + '.txt')
  $uCmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File scripts/cited-evidence-whitelist.ps1 -Scope ' + $Scope + ' -Land -Union'
  # ── ANCHOR AUDITABILITY (CR-R1's three suggestions, adopted by team-lead 2026-09-23) ────────────────
  # (i) DIGEST SCOPE: the sha256 in this header is over the file's RAW BYTES -- not LF-normalized text and
  #     not the AST-subset hash. Measured tonight: one implementation is 5FF43837D1D09B00 as bytes but
  #     D28C730316AF7708 normalized, and both readings are legitimate => the scope must be stated or a
  #     reader reports a phantom difference.
  # (ii) mtime is a CONVENIENCE coordinate only: "restore the mtime" is a REGISTERED BLIND SPOT of this
  #     project's snapshots, so a backdated mtime is undetectable => mtime is NEVER a verification
  #     primitive, only a time hint.
  # (iii) An anchor CHANGE must be an auditable EVENT, not a silent replacement: each land appends a row
  #     to an append-only ANCHORS log (same fix as the delta-generation problem).
  $aPath = Join-Path $here ('cited-evidence-whitelist-' + $Scope + '.txt')
  $aHashU = (Get-FileHash $aPath -Algorithm SHA256).Hash.Substring(0, 16)
  $bHashU = $partnerHash.Substring(0, 16)
  $anchorsLog = Join-Path $here 'cited-evidence-whitelist-anchors.tsv'
  $prevA = ''; $prevB = ''
  if (Test-Path $anchorsLog) {
    $prevRows = @(Get-Content $anchorsLog -Encoding UTF8 | Where-Object { $_.Trim().Length -gt 0 -and $_ -notmatch '^\s*#' })
    $prevRows = @($prevRows | Where-Object { (($_ -split "`t")[1]) -eq $Scope })
    if ($prevRows.Count -gt 0) { $pf = $prevRows[-1] -split "`t"; $prevA = $pf[2]; $prevB = $pf[3] }
  }
  $chList = New-Object System.Collections.Generic.List[string]
  # COLUMN VALUE `SELF`, not `A` (CR-R1's suggestion, team-lead ruling 2026-09-23): side A rewrites its own
  # header on EVERY land, so the old value `A` fired on every row -- a consumer that alerts on "changed is
  # non-empty" would alert forever. `SELF` says what actually happened (this side rewrote itself) and leaves
  # `B` as the only value that means "something external moved". Combined states fall through to the generic
  # note below. Both the value and the note use the same key so a reader cannot see two words for one fact.
  if ($prevA -and ($prevA -ne $aHashU)) { $chList.Add('SELF') }
  if ($prevB -and ($prevB -ne $bHashU)) { $chList.Add('B') }
  $chTxt = if ($chList.Count -eq 0) { $(if ($prevA) { 'none' } else { 'first' }) } else { ($chList -join '+') }
  if (-not (Test-Path $anchorsLog)) {
    [System.IO.File]::AppendAllText($anchorsLog, ("# at`tscope`tA_sha256_16`tB_sha256_16`tA_mtime`tB_mtime`tchanged`tnote" + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
  }
  $aMtime = (Get-Item $aPath).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
  $aNote = if ($chTxt -eq 'none') { 'anchors unchanged' }
           elseif ($chTxt -eq 'first') { 'first record for this scope' }
           elseif ($chTxt -eq 'B') { 'ANCHOR CHANGED (partner file moved -- external event)' }
           elseif ($chTxt -eq 'SELF') { 'ANCHOR CHANGED (this side rewrote itself: its header carries this land timestamp) -- expected on EVERY land; the load-bearing signal is the ENTRY delta in the transitions ledger, and only `B` means an external event' }
           else { 'ANCHOR CHANGED (auditable event)' }
  [System.IO.File]::AppendAllText($anchorsLog, ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + "`t" + $Scope + "`t" + $aHashU + "`t" + $bHashU + "`t" + $aMtime + "`t" + $otherAsof + "`t" + $chTxt + "`t" + $aNote + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
  Write-Output ('ANCHORS appended: ' + (Split-Path $anchorsLog -Leaf) + '  scope=' + $Scope + '  changed=' + $chTxt + '  A=' + $aHashU + ' B=' + $bHashU)

  $uh = New-Object System.Collections.Generic.List[string]
  $uh.Add('# cited-evidence-whitelist UNION  scope=' + $Scope + '  entries=' + $unionEntries.Count + '  -- MACHINE-GENERATED, do NOT hand-edit; regenerate: ' + $uCmd)
  $uh.Add('# ANCHOR DIGESTS above are sha256 over RAW FILE BYTES (not LF-normalized, not the AST-subset hash);' +
          ' mtimes are CONVENIENCE ONLY -- "restore mtime" is a registered blind spot, so mtime is never a verification primitive.' +
          ' Anchor changes are audited in cited-evidence-whitelist-anchors.tsv (this land: changed=' + $chTxt + ').')
  $uh.Add('# SOURCES: (A) cited-evidence-whitelist-' + $Scope + '.txt  as-of ' + (Get-Item (Join-Path $here ('cited-evidence-whitelist-' + $Scope + '.txt'))).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') +
           '  sha256_16=' + (Get-FileHash (Join-Path $here ('cited-evidence-whitelist-' + $Scope + '.txt')) -Algorithm SHA256).Hash.Substring(0, 16) +
           '  [entries ' + $r.Whitelist.Count + ']' +
           ' || (B) independent implementation ' + (Split-Path $partnerPath -Leaf) + '  as-of ' + $otherAsof +
           '  sha256_16=' + $partnerHash.Substring(0, 16) + '  [entries ' + $partnerEntries.Count + ']')
  # CONTINUATION RULE (measured): a line break only continues a statement when the operator sits at
  # the END of the previous line. The first version ended this string WITHOUT a trailing '+' and
  # produced a 4-error cascade that pointed at lines 469 / 423 / 474 / 486 -- i.e. every line except
  # the cause. Reusable check: a parser-only syntax check on the file (no execution).
#   (path fixed 2026-09-23 by CR-F2: it used to point at .ai-tmp/test/, which is the ONE-TIME area and is
#    cleared before delivery -- a durable comment must not cite a path that will not exist.)
    $uh.Add('# WHY THE UNION: at cleanup time keeping a file costs NOTHING while deleting a cited one creates a dangling reference -- the cost is asymmetric, so the conservative direction is the union; it is also necessary because the two implementations are conservative in DIFFERENT places (measured: ' + $onlyA + ' only in A, ' + $onlyB + ' only in B). Evidence that this is not hypothetical: the independent implementation missed 15 real cited files whose citations sit in a SUBDIRECTORY of the evidence area (its tokenizer split at the path separator) and it could not have found that with its own implementation alone. One correction per side: a side that only fixes the criticised tool and not the critic lets the rule rot.')
  $uh.Add('# RESIDUAL CLASSES (A-only ' + $onlyA + '): refs into .ai-tmp/drivers ' + $clsDrivers + ' | files inside a subdirectory of the evidence area ' + $clsSubdir + ' | other ' + $clsOther +
           ' || (B-only ' + $onlyB + '): bare names the other extractor resolved into the evidence area')
  $uh.Add('# KINDS / DELIMITER / DEFINITIONS: identical to the single-source file (see cited-evidence-whitelist-' + $Scope + '.txt).')
  $uMc = @($r.AmbFull.Keys | Sort-Object)
  $uNiu = @($uMc | Where-Object {
      @(@($r.AmbFull[$_]) | Where-Object { $_ -match $cleanupZone -and $unionEntries -notcontains $_ }).Count -gt 0 })
  $uCited = @($uMc | Where-Object {
      $nn = $_
      @(@($r.PathRefs.Keys) | Where-Object { (Split-Path ($_ -replace '\\', '/') -Leaf) -eq $nn }).Count -gt 0 })
  $uh.Add('# AMBIGUITY COUNTS (both axes, measured on THIS union file; candidate = IN-ZONE candidate) | multi_candidate_all = ' + $uMc.Count +
           ' (every doc-mentioned name with >1 in-zone candidate) | multi_candidate_cited = ' + $uCited.Count +
           ' (also cited as an explicit PATH reference => safety depends only on these)' +
           ' | not-in-union = ' + $uNiu.Count +
           ' name(s) with at least one IN-ZONE candidate ABSENT from this union. not-in-union=0 while multi-candidate>0 is' +
           ' exactly CR-R1''s "narrow-definition zero": safety then depends on the keep-every-candidate' +
           ' implementation, not on the union alone.')
  $uh.Add('# UNCONDITIONAL KEEP (part of A, inherited by the union): index files under the cleanup zone' +
           ' survive regardless of citation reachability -- rule = .ai-tmp/**/*index*.tsv (EVIDENCE SURFACE:' +
           ' deleting an index orphans the set it indexes). kept-index-files=' + $r.UncondKeep.Count +
           ' <== re-globbed and cross-checked against THIS file by the read-back self-check' +
           ' (the check can fail: run it with -NegativeControl)')
  $uh.Add('# ROLE: PROTECTION LIST, not a red-line list (over-inclusion keeps an extra file at zero cost; under-inclusion dangles a reference). The union exists because the two implementations are conservative in different places; never use it to mark a row as failed.')
  $uh.Add('# CONSUMER CONTRACT: match these lines as FILE-NAME LITERALS, forward slashes only -- do NOT re-derive citations with your own regex; two shapes (path-form vs bare-name) make each implementation silently miss half of them, and each extractor is conservative in a different place.')
  $uh.Add('# union at ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + ' | assembly sha256_16=' + $asmSha +
           ' | CLEANUP RULE: citations found in 策划/ are protected -- the SOURCE surface is the 策划/ docs' +
           ' ONLY; a citation written inside a .ai-tmp file protects NOTHING (see the single-source file for' +
           ' the full statement) | WRITING RULE: a NEW row must NOT cite .ai-tmp/drivers')
  $uAll = New-Object System.Collections.Generic.List[string]
  foreach ($h in $uh) { $uAll.Add($h) }
  foreach ($e in $unionEntries) { $uAll.Add($e) }
  [System.IO.File]::WriteAllLines($uAbs, $uAll, (New-Object System.Text.UTF8Encoding($false)))
  Write-Output ('UNION written: ' + $uAbs + '  (' + $unionEntries.Count + ' entries = A ' + $r.Whitelist.Count + ' + B ' + $partnerEntries.Count + ')')
}

# ---------------------------------------------------------------------------
# self-test: probes injected into the TEXT ONLY, then the very same pipeline is re-run.
# ---------------------------------------------------------------------------
if ($SelfTest) {
  Write-Output ''
  Write-Output '=== SELF-TEST (probes injected in memory only; the same pipeline is re-run) ==='
  $probeBare = $ProbePrefix + '-nb-no-such-file-probe.txt'
  $probePath = '.ai-tmp/test/probe-fixtures/' + $ProbePrefix + '-np-no-such-path-probe.txt'
  $extAlt = ($extOk -join '|')
  $ambName = @($index.Keys | Where-Object {
      if (-not ($_ -cmatch ('^[A-Za-z0-9_][A-Za-z0-9_\-\.]*\.(' + $extAlt + ')$'))) { return $false }
      $h = @($index[$_]); if ($h.Count -lt 2) { return $false }
      @($h | Where-Object { $_ -match $evidenceRe }).Count -ge 1
    } | Sort-Object)[0]
  if (-not $ambName -and $fxDup) { $ambName = $fxDup }
  $probeAmb = if ($ambName) { $ambName } else { $ProbePrefix + '-no-duplicate-found.md' }
  # A/C expansion probes: one brace pattern whose members DO exist (known-good) and one whose
  # members do NOT (known-bad) -- a test that cannot fail proves nothing.
  # RANGE vectors (lead ruling + CR-U5R's measurement). A POSITIVE sample only proves "it expands";
  # the PARTIAL sample proves "a missing member is reported, not judged red" -- the second is the
  # one that matters ("positive samples can only show expansion; partial ones show no false red").
  if ($fxDir) { Write-Output ('  -- fixtures created by the test: ' + $fxNames.Count + ' file(s) under ' + $fxDir) }
  else { Write-Output '  -- NEGATIVE CONTROL: fixtures deliberately NOT created (every fixture-dependent check must go RED)' }

  $fxRel = '.ai-tmp/test/probe-fixtures/'
  $probeRangeGood = $fxRel + $ProbePrefix + '-rng-0..4.txt'
  $probeRangePart = $fxRel + $ProbePrefix + '-prt-0..5.txt'
  $probeGoodPat = $ProbePrefix + '-brc-{0,7,14,21,28,35}.txt'
  $goodPatFiles = @((Get-BraceExpansions ($fxRel + $probeGoodPat))) |
                  Where-Object { Test-Path (Join-Path $root ($_ -replace '/', '\')) }
  $probeBadPat = $ProbePrefix + '-bad-{1,2}.txt'

  $r2 = Invoke-Extract ($text + "`n``$probeBare`` ``$probePath`` ``$probeAmb`` ``$fxRel$probeGoodPat`` ``$fxRel$probeBadPat`` ``$probeRangeGood`` ``$probeRangePart``") $index
  $ok = $true

  # --- RANGE bucket vectors: raw Test-Path table first (the lead asked for raw output) ---
  $vecGood = @(Expand-RangeMembers $probeRangeGood)
  $vecPart = @(Expand-RangeMembers $probeRangePart)
  Write-Output ('  -- RANGE vector 1 (positive): ' + $probeRangeGood + ' -> ' + $vecGood.Count + ' member(s)')
  foreach ($v in $vecGood) { Write-Output ('       ' + $v + '  Test-Path=' + (Test-Path (Join-Path $root ($v -replace '/', '\')) -PathType Leaf)) }
  Write-Output ('  -- RANGE vector 2 (partial): ' + $probeRangePart + ' -> ' + $vecPart.Count + ' member(s)')
  foreach ($v in $vecPart) { Write-Output ('       ' + $v + '  Test-Path=' + (Test-Path (Join-Path $root ($v -replace '/', '\')) -PathType Leaf)) }

  if (@($r2.Unresolved | Where-Object { $_ -like ($probeBare + '*') }).Count -ge 1) {
    Write-Output ('  PASS  nonexistent BARE name is reported as unresolved: ' + $probeBare)
  } else { Write-Output ('  FAIL  nonexistent bare name was silently dropped: ' + $probeBare); $ok = $false }
  if (@($r2.Missing | Where-Object { $_ -like ($probePath + '*') }).Count -ge 1) {
    Write-Output ('  PASS  nonexistent literal PATH citation is reported as missing: ' + $probePath)
  } else { Write-Output ('  FAIL  nonexistent path citation was silently dropped: ' + $probePath); $ok = $false }

  $ambHit = @($r2.Ambiguous | Where-Object { $_ -like ($probeAmb + '  (*') })
  if ($ambHit.Count -ge 1) { Write-Output ('  PASS  AMBIGUOUS bare name lists candidates and picks none: ' + $probeAmb) }
  else { Write-Output ('  FAIL  ambiguity probe did not trigger: ' + $probeAmb); $ok = $false }

  # pattern A: known-good members must land IN THE WHITELIST (not merely "not missing")
  $inWl = @($r2.Whitelist | Where-Object { $_ -like ('*' + $probeGoodPat.Substring(0, 12) + '*') }).Count
  if ($goodPatFiles.Count -ge 1 -and $inWl -ge $goodPatFiles.Count) {
    Write-Output ('  PASS  brace pattern A expansion IS whitelisted: ' + $probeGoodPat + ' -> ' + $inWl + ' entr(ies)')
  } else { Write-Output ('  FAIL  brace pattern A expansion missing from the whitelist: ' + $probeGoodPat + ' (files=' + $goodPatFiles.Count + ' wl=' + $inWl + ')'); $ok = $false }

  # pattern A: known-bad members must be REPORTED and must NOT be whitelisted
  $badInWl = @($r2.Whitelist | Where-Object { $_ -like ('*' + $ProbePrefix + '-bad-*') }).Count
  $badReported = @($r2.ExpMissing | Where-Object { $_ -like ('*' + $ProbePrefix + '-bad-*') }).Count
  if ($badInWl -eq 0 -and $badReported -ge 2) {
    Write-Output ('  PASS  nonexistent brace members are reported (' + $badReported + ') and NOT whitelisted')
  } else { Write-Output ('  FAIL  brace bad-member handling: whitelisted=' + $badInWl + ' reported=' + $badReported); $ok = $false }

  # pattern B: ellipsis must be human-only -- never missing, never expanded
  $bProbe = $ProbePrefix + '-ep-' + ([char]0x2026).ToString() + 'x.png'
  $r3 = Invoke-Extract ($text + "`n``.ai-tmp/test/$bProbe``") $index
  $bHit = @($r3.PatB | Where-Object { $_ -like ('*' + $ProbePrefix + '-ep-*') }).Count
  $bMissing = @($r3.Missing | Where-Object { $_ -like ('*' + $ProbePrefix + '-ep-*') }).Count
  if ($bHit -ge 1 -and $bMissing -eq 0) { Write-Output ('  PASS  ellipsis pattern goes to bucket B and never to MISSING: ' + $bProbe) }
  else { Write-Output ('  FAIL  ellipsis handling: B=' + $bHit + ' missing=' + $bMissing); $ok = $false }

  # RANGE positive: every member on disk must reach the whitelist
  $wlGood = @($vecGood | Where-Object { $r2.Whitelist -contains (Normalize $_) }).Count
  if ($vecGood.Count -ge 5 -and $wlGood -eq $vecGood.Count) {
    Write-Output ('  PASS  RANGE positive sample fully expands INTO the whitelist: ' + $wlGood + '/' + $vecGood.Count + ' members')
  } else { Write-Output ('  FAIL  RANGE positive sample not whitelisted: ' + $wlGood + '/' + $vecGood.Count); $ok = $false }

  # RANGE partial: whitelisted == number on disk, reported == number missing, nothing judged red
  $partOnDisk = @($vecPart | Where-Object { Test-Path (Join-Path $root ($_ -replace '/', '\')) -PathType Leaf })
  $partWl = @($vecPart | Where-Object { $r2.Whitelist -contains (Normalize $_) }).Count
  $partRep = 0
  foreach ($mm in $vecPart) { if (@($r2.ExpMissing | Where-Object { $_ -like ((Normalize $mm) + '*') }).Count -ge 1) { $partRep++ } }
  # explicit loop: a nested Where-Object that reuses $_ for a different pipeline is a trap (the first
  # version compared each MISSING line against ITSELF and reported 6 false reds).
  $partRed = 0
  foreach ($mm in $vecPart) {
    $mn = Normalize $mm
    if (@($r2.Missing | Where-Object { $_ -like ($mn + '*') }).Count -ge 1) { $partRed++ }
  }
  if ($partWl -eq $partOnDisk.Count -and $partRep -eq ($vecPart.Count - $partOnDisk.Count) -and $partRed -eq 0) {
    Write-Output ('  PASS  RANGE partial sample: ' + $partWl + ' whitelisted (== ' + $partOnDisk.Count + ' on disk), ' + $partRep + ' reported, 0 judged red')
  } else {
    Write-Output ('  FAIL  RANGE partial sample: whitelisted=' + $partWl + ' onDisk=' + $partOnDisk.Count + ' reported=' + $partRep + ' red=' + $partRed)
    $ok = $false
  }

  if (@($r2.Whitelist | Where-Object { $_ -like ('*' + $ProbePrefix + '-nb-*') -or $_ -like ('*' + $ProbePrefix + '-np-*') }).Count -eq 0) {
    Write-Output '  PASS  no probe leaked a nonexistent file into the whitelist'
  } else { Write-Output '  FAIL  a nonexistent probe leaked into the whitelist'; $ok = $false }

  # fixture cleanup (see the self-test fixture block above): the test must not leave anything behind,
  # otherwise IT becomes the stray temp file it exists to prevent.
  foreach ($n in $fxNames) { $fp = Join-Path $fxDir $n; if (Test-Path $fp) { Remove-Item $fp -Force } }
  if ($fxDup) { $dp = Join-Path $T $fxDup; if (Test-Path $dp) { Remove-Item $dp -Force } }
  if ($fxDir -and (Test-Path $fxDir)) { Remove-Item $fxDir -Force -Recurse }
  Write-Output ('  INFO  self-test fixtures removed (' + $fxNames.Count + ' + 1 duplicate copy)')

  Write-Output ('SELF-TEST ' + $(if ($ok) { 'PASS' } else { 'FAIL' }))
  Write-Output ('CORPUS   : ' + $r.Missing.Count + ' literal citation(s) absent without a deleted-note (the exit code reflects THIS, not the self-test)')
  if (-not $ok) { exit 2 }
}

if ($r.Missing.Count -gt 0) { exit 1 }
exit 0
