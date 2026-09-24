# evidence-selfcheck.ps1 -- evidence-discipline self-check for a Clover project.
# PROVENANCE (lifted into the skill 2026-09-24): written inside one project ("the source project"
# below) after that project's lead ruled that a "promise" must become "one runnable command", then
# parameterised -- every object name, ledger name and judged-assembly path is now an argument.  The
# measured incidents in the comments are kept verbatim: they are the only thing that stops a later
# reader from "simplifying" a rule that was paid for.
# Follows the skill's own conventions: ASCII-only file (PowerShell 5.1 parses a no-BOM .ps1 as ANSI,
# so a CJK literal is silently mangled).
#
# WHY THIS EXISTS -- two failure modes measured in this project, both of which make a WRONG result
# look like a PASSING one:
#   1) a no-BOM .ps1 containing CJK literals is read as ANSI => lookups silently MISS (measured: a
#      row that had already been re-captured was still reported as "needs capture", which would have
#      made the next slice burn a live Play window for nothing);
#   2) a mis-named helper silently calls something else (measured: a function named R lost to the
#      built-in alias r = Invoke-History, so a table-writer wrote garbage; a second variant wrote
#      the wrong column index and reported 34 rows as failing).
#   => A script that did not run correctly and a script that ran look IDENTICAL in the artefacts.
#      Therefore: CHECK ENCODING BEFORE TRUSTING OUTPUT, and RECONCILE THE OUTPUT AGAINST INDEPENDENT
#      ARTEFACTS AFTERWARDS.  This file is both halves of that loop, as a command.
#
# PROJECT RULE FOR DESTRUCTIVE WRITES -- an index / a list / a ledger may only be written by a tool
# that implements ALL FOUR, and the tool must first be proven to REFUSE in a sentinel state:
#   1) BACK UP FIRST.  Not optional, no exceptions, no "it is a small edit" -- the cost of a backup
#      is one file copy; the cost of skipping it is a corrupted audit artefact that NOBODY NOTICES,
#      because the corrupt version can still look updated and can still pass the gate.
#      (Measured, CR-R1: a table writer corrupted the contact-sheet index 172 -> 239 lines with
#      67 garbage rows.  It was recovered ONLY because a backup had been taken seconds earlier.
#      Had it not, the index would have read as "updated" and stayed wrong forever.)
#   2) AFTER WRITING, COMPARE every pre-existing line against the backup (byte-exact) and require
#      that the file grew by EXACTLY the number of lines intended; restore automatically on mismatch.
#   3) RECONCILE the result against independent artefacts afterwards (see (B) below).
#   4) To close a slice out, the misses that belong to OTHER slices must be skip-able EXPLICITLY
#      (a named switch, printed as WARN) -- never silently downgraded.
#
# PROJECT RULE FOR CONCLUSION-LEVEL CLAIMS (in force 2026-09-23, adopted after a self-correction by
# slice CR-R1): every conclusion -- not just a reading -- must carry (a) an AS-OF instant and (b) the
# sha256 of the assembly it was reached on.  A conclusion that lives only in a message, with no
# artefact behind it, is treated as UNREGISTERED and possibly already stale: do not dispatch work on
# it, do not write it into a ledger, do not use it for cross-checking.
#   WHY: "no positive card-play reading exists on the current assembly" was said at ~09:2x and was
#   falsified at 09:33:48 -- 90 minutes.  It lived in ONE message and in NO artefact, so no
#   reconciliation could ever catch it.  That is the hardest of this project's measured "it looks
#   right" families: the previous ones at least left something on disk to check.
#   The check below is the MECHANISABLE HALF of the rule: a table this tool judges must timestamp
#   itself and name the assembly.  The message half cannot be mechanised here; only discipline and,
#   where it matters, the pattern above ("AS-OF = ... ; ASSEMBLY sha256 = ...").
# TWO POWERSHELL TRAPS, both measured on this project, both belonging to the "it did not run right"
# family (they do not throw; they produce a WRONG RESULT):
#   a) @( @('a','b'), @('c','d') ) FLATTENS the nested arrays -- a two-dimensional table can never be
#      written with an array literal; use [pscustomobject] per row (or a List of them).
#   b) A function name CAN COLLIDE WITH A BUILT-IN ALIAS, and aliases win over functions:
#      a helper named `R` silently called `r` = Invoke-History.  Use long, unambiguous names.
#      Same family: `%`, `?`, `sc`, `ft`, `ls`, `gc`, `sleep`.
#   c) `... | Select-Object -First N` ON A NATIVE COMMAND'S PIPELINE TRUNCATES THE CHILD PROCESS:
#      PowerShell raises StopUpstreamCommands, and a child started with `powershell -File x.ps1`
#      gets cut off mid-run.  Measured, CR-R1: a generator that writes its report last had that
#      report silently missing, because the caller only wanted the first 2 lines of stdout -- the
#      script "looked like it ran" and printed exactly what the caller expected.
#      => capture the whole thing into a variable first (`$o = ... 2>&1 | Out-String`) and slice the
#         STRING, never the live pipeline, whenever the child does more than print.
#
# LIFTED 2026-09-24: this file is the generic form of a probe written inside one project (the
# "source project" from here on).  Its rules were never project-specific -- evidence discipline is
# the same everywhere -- so the object names, the ledger paths and the judged-assembly path are all
# parameters now and the script lives in the skill.  Everything below that cites a measured incident
# is kept verbatim on purpose: a rule with no incident behind it gets "simplified" away by the next
# reader, and each of these cost the source project a wasted generation or a false green.
#
# USAGE (the project root is passed in; it is NOT derived from this file's location any more, because
# the script now lives in the skill while the artefacts live in a project):
#   powershell -NoProfile -ExecutionPolicy Bypass -File <skill>/scripts/evidence-selfcheck.ps1 -ProjectRoot <project>
#   ... -ProjectRoot D:\other\clover-project-x        # REQUIRED in practice: defaults to the CWD
#   ... -DllRelative client\Library\ScriptAssemblies\Game.dll   # judged assembly (empty = skip freshness)
#   ... -AssemblyShaColumn <name>                     # evidence-table column carrying the assembly sha16
#   ... -EvidenceTable .ai-tmp/test/<slice>-oldnew.tsv   # comma-separated for several; auto-detected when omitted
#   ... -HeartbeatWindowHours 24
#   ... -SkipHeartbeatCoverage                        # explicit, printed downgrade (see (C))
#   ... -GapLedgerMarker <marker> -GapLedgerRelative '<area>\<ledger>.md'   # registration source
#   ... -SimulateSlice <slice>                        # SELF-TEST hook, see below
# FIRST RUN ON A NEW PROJECT is expected to go RED on (C) alone: heartbeat coverage is a
# PROJECT-level rule (it judges other slices' work), so a project that has never run a slice has no
# heartbeat files yet.  Close the first run out with -SkipHeartbeatCoverage (an explicit, PRINTED
# downgrade) and register the misses; do NOT "fix" it by editing the window.
#
# REGISTERED HISTORICAL GAPS (why the default can now be green without hiding anything):
#   a gap that is already recorded in the ledger is EXCLUDED from the verdict but ALWAYS PRINTED, so a
#   permanent known gap stops drowning out a new one.  Admission is deliberately narrow (team-lead
#   constraint 1): the name must appear verbatim between backticks on the row carrying the marker
#   token, and be matched EXACTLY after case normalisation -- no prefix, no substring, no fuzzy.
#   Constraint 3: this exclusion must be proven NOT to swallow genuine new gaps, so the tool carries
#   a self-test hook.  The proof, run every time the mechanism changes, is in both directions:
#     -SimulateSlice ZZ9-NEWGAP     -> must go RED and name it        (unregistered)
#     -SimulateSlice CR-T1b         -> must be excluded and printed    (registered)
#     -SimulateSlice CR-U           -> must go RED  (CR-U is a PREFIX of the registered CR-U5)
#     -SimulateSlice CR-T1b-NEW     -> must go RED  (CONTAINS the registered CR-T1b)
#   A test that cannot fail proves nothing: an earlier near-miss case used CR-T1, which legitimately
#   HAS a heartbeat, so it could never have been a gap and the case was worthless.
#
# WHAT IT CHECKS
#   (A) encoding + syntax of every *.ps1 under <root>/.ai-tmp  -> "ASCII-only OR has BOM", parseErr = 0
#   (B) artifact reconciliation: for every evidence table with a cr-dll-sha256-16 column, each row's
#       file must EXIST, be NEWER than the judged assembly, and carry the right sha256 prefix
#   (C) ledger accounting: no dangling START in .ai-tmp/test/play-log.tsv, and every slice that
#       STARTed inside the window has its heartbeat-<slice>.tsv
# Exit code 0 = every check PASS; 1 = at least one FAIL (printed with the offending row).
param(
    # The project under judgement.  Defaults to the CURRENT DIRECTORY (never to this script's own
    # location: the script ships in the skill, so deriving from $PSScriptRoot would judge the skill).
    [string]$ProjectRoot = '',
    # Judged assembly, project-relative.  EMPTY = no judged assembly => the freshness/hash half of (B)
    # is skipped with a WARN.  There is deliberately NO default file name: a default would be a
    # project-specific guess ("Game.dll") that silently judges the wrong object on the next project.
    [string]$DllRelative = '',
    # Name of the evidence-table column that carries the assembly sha256 prefix.  Parameterised
    # because a column name is a project's vocabulary, not the rule's.  Used BOTH for auto-detection
    # (the marker must sit on a comment line) and for the per-row comparison.
    [string]$AssemblyShaColumn = 'dll-sha256-16',
    # COMMA-SEPARATED STRING, not [string[]], on purpose: the documented invocation is
    #   powershell -File <script> -EvidenceTable a.tsv,b.tsv
    # and the -File argument parser passes every argument as ONE string -- it does NOT apply the
    # comma operator to a [string[]] parameter, so an array parameter is simply UNREACHABLE that way
    # (measured: -IndexRoots bound as one bogus path, silently indexing 4 roots instead of 9, while
    # every headline number still looked plausible).  So the split is done here, in the script.
    [string]$EvidenceTable = '',
    # Where the durable judging-asset tables live (second place an evidence table may legally sit).
    [string]$ProbesRootRelative = 'tools/probes',
    [int]$HeartbeatWindowHours = 24,
    # Heartbeat coverage is judged over OTHER slices' work too, so it reports project-level debt that
    # no single slice can fix.  Keep it ON by default (it is the rule), and let a slice close itself
    # out with this switch when the misses are demonstrably not its own -- explicitly, never silently.
    [switch]$SkipHeartbeatCoverage,
    # Registered historical gaps are EXCLUDED from the heartbeat verdict but always PRINTED.
    # Source of registration is nailed down (team-lead constraint 1): the marker token has to appear
    # literally on the row, in this one file, and a name is only excluded by EXACT match after
    # case-normalisation -- no prefix match, no fuzzy match.  ("X-T1" must never be swallowed by
    # "X-T1b"; both are distinct registrations or neither is.)
    # BOTH defaults are EMPTY on purpose: with an empty marker every line would "contain" it, every
    # backticked token would register, and the exclusion would swallow EVERY gap -- a green that looks
    # like a pass and hides everything.  No marker configured => nothing is excluded (printed as INFO).
    [string]$GapLedgerMarker = '',
    [string]$GapLedgerRelative = '',
    # SELF-TEST HOOK (team-lead constraint 3).  Adds synthetic slice names to the coverage candidate
    # pool so the exclusion mechanism can be proven IN BOTH DIRECTIONS without touching any real
    # ledger: an unregistered name must still go RED, a registered name must be excluded and printed.
    # This is the mirror of rule 4 above -- an exclusion mechanism must be shown to NOT swallow
    # genuine new problems, or it is just a nicer way of turning the check green.
    # comma-separated for the same -File reason as $EvidenceTable above
    [string]$SimulateSlice = ''
)

function Split-List([string]$s) {
    if (-not $s) { return @() }
    return @($s -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
$evTables = Split-List $EvidenceTable
$simSlices = Split-List $SimulateSlice

$fail = 0
if (-not $ProjectRoot) {
    $ProjectRoot = (Get-Location).Path
    Write-Output ('INFO  -ProjectRoot not given: judging the current directory = ' + $ProjectRoot)
}
if (-not (Test-Path $ProjectRoot)) { Write-Output ('FAIL  project root not found: ' + $ProjectRoot); exit 1 }
$root = (Resolve-Path $ProjectRoot).Path
$T = Join-Path $root '.ai-tmp\test'
$probesRoot = Join-Path $root $ProbesRootRelative
$shotsRoot = Join-Path $root '.ai-tmp\screenshots'
$dllPath = if ($DllRelative) { Join-Path $root $DllRelative } else { '' }

# An evidence table may name an artefact three ways: an absolute path, a project-relative path
# (".ai-tmp/screenshots/x.png"), or a bare file name ("x.png" -- the older tables do this, and the
# bare name means "in the screenshot area").  Resolve all three, never assume one.
function Resolve-Artifact([string]$rel) {
    if ([string]::IsNullOrWhiteSpace($rel)) { return $null }
    if ([System.IO.Path]::IsPathRooted($rel)) { if (Test-Path $rel) { return $rel } else { return $null } }
    $c = Join-Path $root $rel
    if (Test-Path $c) { return $c }
    $c = Join-Path $shotsRoot $rel
    if (Test-Path $c) { return $c }
    return $null
}

Write-Output ('evidence-selfcheck -- project root = ' + $root)

# ---------------------------------------------------------------- judged object
$dll = $null
if (-not $dllPath) {
    Write-Output 'WARN  no judged assembly configured (-DllRelative empty) (freshness checks will be skipped)'
    $dllH = ''
} elseif (Test-Path $dllPath) {
    $dll = Get-Item $dllPath
    $dllH = (Get-FileHash $dll.FullName -Algorithm SHA256).Hash
    Write-Output ('judged assembly = ' + $DllRelative)
    Write-Output ('  mtime  = ' + $dll.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))
    Write-Output ('  size   = ' + $dll.Length)
    Write-Output ('  sha256 = ' + $dllH)
} else {
    Write-Output ('WARN  judged assembly not found: ' + $dllPath + ' (freshness checks will be skipped)')
    $dllH = ''
}

# ---------------------------------------------------------------- (A) encoding + syntax
Write-Output ''
Write-Output '=== (A) encoding + syntax of every .ai-tmp *.ps1 ==='
$files = @(Get-ChildItem $root -Recurse -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
           Where-Object { $_.FullName -match '\\\.ai-tmp\\' } | Sort-Object FullName)
$badPs = @()
foreach ($p in $files) {
    $b = [System.IO.File]::ReadAllBytes($p.FullName)
    $non = 0; for ($i = 0; $i -lt $b.Length; $i++) { if ($b[$i] -gt 127) { $non++ } }
    $bom = ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
    $errs = $null; $toks = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($p.FullName, [ref]$toks, [ref]$errs)
    $nErr = if ($errs) { @($errs).Count } else { 0 }
    if (-not (($non -eq 0 -or $bom) -and ($nErr -eq 0))) {
        $badPs += ($p.Name + ' (nonascii=' + $non + ' bom=' + $bom + ' parseErr=' + $nErr + ')')
    }
}
if ($files.Count -eq 0) { Write-Output '  INFO  no .ps1 under .ai-tmp' }
elseif ($badPs.Count -eq 0) { Write-Output ('  PASS  ' + $files.Count + ' script(s): ASCII-only or BOM, zero parse errors') }
else {
    $fail++
    Write-Output ('  FAIL  ' + $badPs.Count + ' of ' + $files.Count + ' script(s) would be misread as ANSI or do not parse:')
    $badPs | ForEach-Object { Write-Output ('        ' + $_) }
}

# ---------------------------------------------------------------- (B) artifact reconciliation
Write-Output ''
Write-Output '=== (B) reconcile every evidence table against the files on disk ==='
if (-not $evTables -or $evTables.Count -eq 0) {
    $evTables = @()
    # both places an evidence table may legitimately live: the slice's one-off area, and the DURABLE
    # judging-asset area (tools/probes) -- carrier tables must live in the durable one, but older
    # tables may still be in .ai-tmp/test while a slice is in flight.
    foreach ($f in @(@(Get-ChildItem $T -Filter '*.tsv' -File -ErrorAction SilentlyContinue) +
                     @(Get-ChildItem $probesRoot -Filter '*.tsv' -File -ErrorAction SilentlyContinue))) {
        # The marker must appear on a COMMENT line -- i.e. in the table's own column header.  Matching
        # the bare token anywhere in the file is too loose: a heartbeat or a log that merely MENTIONS
        # the column name ("... the sole tsv with a <column> header ...") was picked up as an
        # evidence table and then reported 53 bogus problem rows.  Measured; hence the ^# requirement.
        $head = @([System.IO.File]::ReadAllLines($f.FullName, [System.Text.Encoding]::UTF8)) |
                Where-Object { $_ -match '^\s*#' -and $_.Contains($AssemblyShaColumn) }
        if ($head.Count -gt 0) { $evTables += $f.FullName.Substring($root.Length).TrimStart('\') }
    }
}
if ($evTables.Count -eq 0) { Write-Output ('  INFO  no evidence table carrying a ' + $AssemblyShaColumn + ' column found') }
foreach ($rel in $evTables) {
    $tp = Join-Path $root $rel
    if (-not (Test-Path $tp)) { $fail++; Write-Output ('  FAIL  table missing: ' + $rel); continue }
    $lines = @([System.IO.File]::ReadAllLines($tp, [System.Text.Encoding]::UTF8))
    $header = $lines | Where-Object { $_ -match '^#\s*cols:' } | Select-Object -First 1
    $delim = [char]9
    $ci = @{}                       # column-name -> index, read from the table's own header
    if ($header) {
        $names = ($header -replace '^#\s*cols:\s*', '') -split $delim
        if ($names.Count -le 1) { $names = ($header -replace '^#\s*cols:\s*', '') -split '\s{2,}' }
        for ($i = 0; $i -lt $names.Count; $i++) { $ci[$names[$i].Trim()] = $i }
    }
    $iFile = if ($ci.ContainsKey('artifact')) { $ci['artifact'] } else { 0 }
    $iShot = if ($ci.ContainsKey('new-mtime')) { $ci['new-mtime'] } else { 2 }
    $iHash = $ci[$AssemblyShaColumn]
    $n = 0; $bad = @()
    foreach ($ln in $lines) {
        if ($ln -match '^\s*#' -or -not $ln.Contains($delim)) { continue }
        $c = $ln -split $delim
        if ($c.Count -le $iShot) { continue }
        if ($c[$iFile] -eq 'artifact' -or $c[$iShot] -eq 'new-mtime') { continue }
        $p = Resolve-Artifact $c[$iFile]
        if ($null -eq $p) { $bad += ('MISSING  ' + $c[$iFile]); continue }
        $n++
        if ($dll -and (Get-Item $p).LastWriteTime -le $dll.LastWriteTime) { $bad += ('TOO OLD  ' + $c[$iFile]) }
        if ($dllH -and $iHash -ne $null -and $c[$iHash] -ne $dllH.Substring(0, 16)) { $bad += ('HASH COL ' + $c[$iFile]) }
    }
    # conclusion-level claims must carry their own reach: an as-of instant + the assembly sha256
    $hdr = @($lines | Where-Object { $_ -match '^\s*#' })
    $hasHash = @($hdr | Where-Object { $_ -match 'sha256' }).Count -gt 0
    $hasStamp = @($hdr | Where-Object { $_ -match '\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}' }).Count -gt 0
    if ($hasHash -and $hasStamp) { Write-Output ('  PASS  ' + $rel + ': header carries an as-of instant and the assembly sha256') }
    else {
        $fail++
        Write-Output ('  FAIL  ' + $rel + ': header lacks ' + $(if ($hasStamp) { '' } else { 'an as-of instant ' }) + $(if ($hasHash) { '' } else { 'the assembly sha256 ' }) + '(conclusion-level claims must carry both)')
    }
    if ($bad.Count -eq 0) { Write-Output ('  PASS  ' + $rel + ': ' + $n + ' row(s) exist, are newer than the judged assembly, sha256 column agrees') }
    else {
        $fail++
        Write-Output ('  FAIL  ' + $rel + ': ' + $bad.Count + ' problem row(s) of ' + $n + ' checked')
        $bad | Select-Object -First 10 | ForEach-Object { Write-Output ('        ' + $_) }
    }
}

# ---------------------------------------------------------------- (C) ledger accounting
Write-Output ''
Write-Output '=== (C) ledger accounting: play-log START/END pairing and heartbeat coverage ==='
$plog = Join-Path $T 'play-log.tsv'
if (-not (Test-Path $plog)) { Write-Output '  INFO  no play-log.tsv' }
else {
    $rows = @([System.IO.File]::ReadAllLines($plog, [System.Text.Encoding]::UTF8) |
              Where-Object { $_ -notmatch '^\s*#' -and $_ -match "`t" })
    $open = @{}
    $recent = @{}
    $cut = (Get-Date).AddHours(-$HeartbeatWindowHours)
    # a slice field is not always a bare name: historical rows carry "AD1 (executor)" / "BC1 (executor)"
    # / a runner name, so take the FIRST whitespace-delimited token and match heartbeat files
    # case-insensitively.  Without this the check reports false misses (measured).
    $hbHave = @{}
    foreach ($h in @(Get-ChildItem $T -Filter 'heartbeat-*.tsv' -File -ErrorAction SilentlyContinue)) {
        $n = $h.Name.Substring('heartbeat-'.Length); $n = $n.Substring(0, $n.Length - '.tsv'.Length)
        $hbHave[$n.ToLowerInvariant()] = $true
    }
    foreach ($r in $rows) {
        $c = $r -split "`t"
        if ($c.Count -lt 4) { continue }
        $slice = ($c[1] -split '\s+')[0].Trim(); $kind = $c[3]
        if ($kind -match '^START') { $open[$slice] = $true } elseif ($kind -match '^END') { $open.Remove($slice) }
        # NOTE: $when must be a typed [datetime] BEFORE the [ref] call -- with $null the overload
        # resolution fails at runtime with "cannot find an overload for TryParse and argument count 2".
        $when = [datetime]::MinValue
        if ([datetime]::TryParse($c[0], [ref]$when)) { if ($when -gt $cut) { $recent[$slice] = $true } }
    }
    if ($open.Count -eq 0) { Write-Output '  PASS  play-log: no dangling START (every START has an END)' }
    else {
        $fail++
        Write-Output ('  FAIL  play-log: dangling START for ' + (($open.Keys | Sort-Object) -join ', '))
        # This is a TRUE statement either way, but the CAUSE differs and only a human can tell them
        # apart: (i) a chain is in flight right now (the Editor is in play mode), or (ii) a slice
        # finished without writing END.  The tool refuses to guess -- it prints the discriminator.
        Write-Output '        NOTE  if the Editor is currently in play mode this is an IN-FLIGHT chain, not a missing END.'
        Write-Output '        NOTE  check with: unity command editor_status   (playMode == playing => in flight)'
    }
    # self-test hook: synthetic names enter the candidate pool exactly like real ones
    foreach ($s in $simSlices) {
        if (-not [string]::IsNullOrWhiteSpace($s)) { $recent[$s.Trim()] = $true }
    }
    $noHb = @()
    foreach ($s in $recent.Keys) {
        if (-not $hbHave.ContainsKey($s.ToLowerInvariant())) { $noHb += $s }
    }

    # ---- registered historical gaps (team-lead constraint 1: exact match only) ----------------
    # A gap is excluded ONLY if its name appears verbatim in the registration row; the row is found
    # by a literal marker token in one named file.  Prefix / fuzzy / substring matching would let a
    # registration for "X-T1b" silence a future "X-T1" -- so they are all forbidden here.
    $zhRegistered = ([char[]]@(0x5DF2, 0x767B, 0x8BB0) -join '')   # yi deng ji
    $zhRows       = ([char[]]@(0x6761) -join '')                    # tiao
    $zhExcluded   = ([char[]]@(0x88AB, 0x6392, 0x9664) -join '')    # bei pai chu
    # The source project's default ledger was '<plan-area>/<acceptance-table>.md', spelled with CJK
    # code points so this ASCII-only file stays parseable.  That default is NOT reproduced here (a
    # skill cannot know a project's ledger path and an empty-path Join-Path would then hand a
    # DIRECTORY to ReadAllLines).  The technique is kept in the three lines above: an ASCII-only
    # .ps1 must build CJK output labels from code points, or PowerShell 5.1 decodes them as ANSI.
    $registered = @{}
    $gapRowsFound = 0
    if ([string]::IsNullOrWhiteSpace($GapLedgerMarker) -or [string]::IsNullOrWhiteSpace($GapLedgerRelative)) {
        Write-Output '  INFO  no registration source configured (-GapLedgerMarker / -GapLedgerRelative) -- nothing may be excluded'
    } else {
    $gapLedger = Join-Path $root $GapLedgerRelative
    if (Test-Path $gapLedger) {
        foreach ($ln in [System.IO.File]::ReadAllLines($gapLedger, [System.Text.Encoding]::UTF8)) {
            if (-not $ln.Contains($GapLedgerMarker)) { continue }
            $gapRowsFound++
            foreach ($m in [regex]::Matches($ln, '`([A-Za-z0-9_\-\.]+)`')) {
                $name = $m.Groups[1].Value
                if ($name.Length -lt 2) { continue }
                # skip tokens that are obviously file references, not slice names
                if ($name -match '\.(md|tsv|ps1|cs|png|jpg|dll|exe|log|txt|json|py|asset|unity)$') { continue }
                $registered[$name.ToLowerInvariant()] = $true
            }
        }
    }
    }
    $excluded = @(); $live = @()
    foreach ($s in $noHb) {
        if ($registered.ContainsKey($s.ToLowerInvariant())) { $excluded += $s } else { $live += $s }
    }
    if ([string]::IsNullOrWhiteSpace($GapLedgerMarker) -or [string]::IsNullOrWhiteSpace($GapLedgerRelative)) {
        # already printed above; keep the branch so the else-form never renders an empty path
    } elseif ($gapRowsFound -gt 0) {
        Write-Output ('  INFO  registration source: ' + $GapLedgerRelative + ' marker "' + $GapLedgerMarker + '" (rows matched: ' + $gapRowsFound + '; names registered: ' + $registered.Count + ')')
    } else {
        Write-Output ('  INFO  no registration row with marker "' + $GapLedgerMarker + '" found in ' + $GapLedgerRelative + ' -- nothing may be excluded')
    }
    if ($excluded.Count -gt 0) {
        Write-Output ('  INFO  ' + $zhRegistered + ' ' + $excluded.Count + ' ' + $zhRows + $zhExcluded + ' (they stay visible here, they are NOT silently dropped):')
        Write-Output ('        ' + (($excluded | Sort-Object) -join ', '))
    }
    $noHb = $live     # the verdict now runs on the UNREGISTERED remainder only
    if ($recent.Count -eq 0) { Write-Output ('  INFO  no slice started within ' + $HeartbeatWindowHours + 'h') }
    elseif ($noHb.Count -eq 0) {
        Write-Output ('  PASS  heartbeat: ' + $recent.Count + ' slice(s) active within ' + $HeartbeatWindowHours + 'h; ' + $excluded.Count + ' gap(s) excluded as registered, 0 UNREGISTERED gap(s)')
    }
    elseif ($SkipHeartbeatCoverage) { Write-Output ('  WARN  heartbeat missing (coverage check explicitly skipped by the caller) for: ' + (($noHb | Sort-Object) -join ', ')) }
    else { $fail++; Write-Output ('  FAIL  UNREGISTERED heartbeat gap(s) -- a slice with activity but no heartbeat file, and NOT registered: ' + (($noHb | Sort-Object) -join ', ')) }
}

Write-Output ''
Write-Output ('===== evidence-selfcheck: FAIL=' + $fail + ' =====')
if ($fail -gt 0) { exit 1 }
