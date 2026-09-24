# play-log-format-census.ps1 -- RE-COMPUTABLE census of the shared play-log's record/format mixture.
#
# WHY IT EXISTS (team-lead ruling 2026-09-23, approving CR-F2's proposal): the format contract landed in
# play-log.tsv states "history contains N date-time shapes" and "N records". Those numbers must be
# RE-DERIVABLE, not remembered -- the project rule is "扫描要重跑、不要记结果". This script is the载体
# for that. It is NOT wired into any gate (lead: do not hook it up yet).
#
# HARD RULE IT EMBODIES (earned three times tonight): a RECORD is determined by LINE-START + COLUMN
# POSITION. Counting by "the line contains an ISO-shaped substring" is wrong -- measured: a 509-char row
# quotes `2026-09-23T01:21:32 CR-T2x ...` inside its <why> and a naive scan reports a SECOND record.
# Counting by "the line contains a slice name" is wrong too -- bodies carry file names such as
# CR-V2-hud-mine.png.
#
#   -- USAGE (the documented invocation is -File, and the project root is passed in)
#   powershell -NoProfile -ExecutionPolicy Bypass -File <skill>/scripts/play-log-format-census.ps1 -ProjectRoot <project>
#   ... -NegativeControl            # fixture under .ai-tmp only; refused elsewhere, deleted afterwards
#
# READ-ONLY on the real file. The only writes happen under -NegativeControl, only inside a fixture under
#
# PROVENANCE (lifted into the skill 2026-09-24): written inside one project ("the source project"
# below), then parameterised -- the project root is an argument now, and the tool path it prints about
# itself is derived from $PSCommandPath instead of a hard-coded location.  The case citations in the
# comments (<letters>-<alnum> ids, "team-lead") are that project's work items, kept as provenance.
param(
  # The project whose play-log is measured.  Defaults to the CURRENT DIRECTORY -- never to this file's
  # own location, because the script now ships in the skill while the ledger lives in a project.
  [string]$ProjectRoot = '',
  [string]$File = '.ai-tmp/test/play-log.tsv',
  [switch]$NegativeControl,
  [string]$Fixture = '.ai-tmp/test/play-log-format-census-fixture.tsv'
)
$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) {
  $ProjectRoot = (Get-Location).Path
  Write-Output ('# INFO -ProjectRoot not given: measuring the current directory = ' + $ProjectRoot)
}
$root = (Resolve-Path $ProjectRoot).Path
Set-Location $root

try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
$RE_RECORD  = '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}'   # line-start, second precision or finer
$RE_ISO     = '\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?([+-]\d{2}:\d{2}|Z)?'
$RE_ANY_TS  = '\d{4}-\d{2}-\d{2}T\d{2}:\d{2}'

# A GLUED record looks like: <body text><ISO><TAB><who><TAB>...  i.e. a timestamp that is NOT at the line
# start AND IS immediately followed by a TAB (the record's column separator). The FIRST version of this
# detector required "<TAB><ISO>" and therefore found 0 -- my own negative control caught it (measured),
# because the real glue shape has NO separator at all: the writer simply lost the trailing newline.
# NOTE it stays a CANDIDATE count: a tab-separated data column may also hold a timestamp-like value
# (measured: my own transitions ledger has a new_mtime column of exactly that shape).
function Count-Glued([string[]]$lines) {
  $n = 0
  foreach ($l in $lines) {
    foreach ($m in [regex]::Matches($l, $RE_ISO)) {
      if ($m.Index -eq 0) { continue }
      $end = $m.Index + $m.Length
      if ($end -lt $l.Length -and $l[$end] -eq [char]9) { $n++; break }
    }
  }
  return $n
}

# SELF-ANCHORING (added 2026-09-23 after the team-lead's AS-OF line quoted a fingerprint of THIS file
# that was already stale before it landed): an append-only ledger cannot rewrite a hard-coded hash, so
# hard-coding one guarantees silent rot. Instead every run prints, at run time, the triple of BOTH the
# tool and the subject -- whoever records a result records what actually produced it.
function Show-Anchor([string]$subject) {
  $toolAbs = $PSCommandPath
  if (-not $toolAbs) { $toolAbs = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'play-log-format-census.ps1')) }
  if (Test-Path $toolAbs) {
    $ti = Get-Item $toolAbs
    Write-Output ('# tool    = ' + $toolAbs.Substring($root.Length).TrimStart('\') + '  sha256_16=' + (Get-FileHash $toolAbs -Algorithm SHA256).Hash.Substring(0,16) + '  bytes=' + $ti.Length + '  mtime=' + $ti.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))
  }
  if ($subject -and (Test-Path $subject)) {
    $si = Get-Item $subject
    Write-Output ('# subject = ' + $si.FullName.Substring($root.Length).TrimStart('\') + '  sha256_16=' + (Get-FileHash $subject -Algorithm SHA256).Hash.Substring(0,16) + '  bytes=' + $si.Length + '  mtime=' + $si.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))
  }
}

function Get-Census([string]$path) {
  $abs = [System.IO.Path]::GetFullPath($path)
  $text = [System.IO.File]::ReadAllText($abs, [System.Text.Encoding]::UTF8)
  $lines = @([System.IO.File]::ReadAllLines($abs, [System.Text.Encoding]::UTF8))
  # TWO PREDICATES, BOTH PRINTED (self-caught defect: my ad-hoc census used the lenient one and said 243,
  # this script used the strict one and said 241 -- the same file, two numbers, no error anywhere. A count
  # is meaningless without its predicate, so the census prints both and the difference.)
  $recStrict  = @($lines | Where-Object { $_ -match $RE_RECORD })
  $recLenient = @($lines | Where-Object { $_ -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}' })
  $rec = $recLenient   # the shape census must see EVERY shape, including minute-precision rows
  $shapes = @{}
  foreach ($r in $rec) {
    $sig = (($r -split "`t")[0] -replace '\d', '#')
    if ($shapes.ContainsKey($sig)) { $shapes[$sig]++ } else { $shapes[$sig] = 1 }
  }
  $cols = @{}
  foreach ($r in $rec) { $n = ($r -split "`t").Count; if ($cols.ContainsKey($n)) { $cols[$n]++ } else { $cols[$n] = 1 } }
  return [pscustomobject]@{
    Path       = $abs
    Lines      = $lines.Count
    Records    = $recStrict.Count
    RecordsLen = $recLenient.Count
    Comments   = @($lines | Where-Object { $_ -match '^\s*#' }).Count
    Blank      = @($lines | Where-Object { $_.Trim().Length -eq 0 }).Count
    Shapes     = $shapes
    Cols       = $cols
    GluedCands = (Count-Glued $lines)
    AnyTs      = @($lines | Where-Object { $_ -match $RE_ANY_TS }).Count
    # SUBSTRING occurrences, not lines: this is the quantity a naive "count the ISO-shaped texts" reader
    # would report, and the fixture requires it to EXCEED the record count while the record count stays put.
    AnyTsOcc   = @([regex]::Matches($text, $RE_ISO)).Count
    Crlf       = @([regex]::Matches($text, "`r`n")).Count
    BareLf     = @([regex]::Matches($text, "[^\r]\n")).Count
    EndsNl     = $text.EndsWith("`n")
    Utf8Bom    = ($text.Length -gt 0 -and [int][char]$text[0] -eq 0xFEFF)
  }
}

function Show-Census($c) {
  Write-Output ('file        = ' + $c.Path)
  Write-Output ('physicalLines=' + $c.Lines + '   #comments=' + $c.Comments + '   blank=' + $c.Blank)
  Write-Output ('records STRICT  (line-start, \d{2}:\d{2}:\d{2} or finer) = ' + $c.Records)
  Write-Output ('records LENIENT (line-start, \d{2}:\d{2} or finer)          = ' + $c.RecordsLen + '   (+' + ($c.RecordsLen - $c.Records) + ' minute-precision rows the strict predicate ignores)')
  Write-Output '   <== a record count is MEANINGLESS without its predicate: quote which one.'
  Write-Output ('line breaks = CRLF ' + $c.Crlf + ' + bareLF ' + $c.BareLf + '   endsWithNewline=' + $c.EndsNl + '   utf8Bom=' + $c.Utf8Bom)
  Write-Output ('ISO-shaped SUBSTRING occurrences (what a naive counter reports) = ' + $c.AnyTsOcc + '   on ' + $c.AnyTs + ' line(s)')
  Write-Output '   <== NOT the record count: records are the line-start number above; in-body timestamps are quoted history.'
  Write-Output ('structural glued-candidates (TAB+ISO inside a line) = ' + $c.GluedCands + '   <== candidate only; a data column can look like this')
  Write-Output ('field-count distribution: ' + (($c.Cols.GetEnumerator() | Sort-Object Name | ForEach-Object { 'cols=' + $_.Name + ' rows=' + $_.Value }) -join '  |  '))
  Write-Output 'date-time shapes of the RECORD column (digits -> #):'
  $c.Shapes.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { Write-Output ('    ' + $_.Name.PadRight(38) + ' rows=' + $_.Value) }
}

if ($NegativeControl) {
  # The fixture contains the three shapes that fool naive counters. The detector must return 3 records,
  # 1 structural glued-candidate, and must NOT be swayed by the in-body timestamp / slice name.
  $fxAbs = [System.IO.Path]::GetFullPath((Join-Path $root $Fixture))
  $oneTime = [System.IO.Path]::GetFullPath((Join-Path $root '.ai-tmp')) + [System.IO.Path]::DirectorySeparatorChar
  if (-not $fxAbs.StartsWith($oneTime, [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Output 'NEGCTL FAIL: fixture must live under .ai-tmp (refusing to write elsewhere)'; exit 1
  }
  $d = Split-Path $fxAbs -Parent
  if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
  $L = New-Object System.Collections.Generic.List[string]
  $L.Add('# fixture: a header comment line, then the three hostile shapes')
  $L.Add('2026-01-01T00:00:01.0000000+08:00' + "`t" + 'CR-XX' + "`t" + 'chain-a' + "`t" + 'plain record')
  $L.Add('2026-01-01T00:00:02.0000000+08:00' + "`t" + 'CR-XX' + "`t" + 'chain-b' + "`t" + 'body QUOTES an older row: 2026-09-23T01:21:32 CR-T2x "attempt 1 fell into Boot-stuck"')
  $L.Add('2026-01-01T00:00:03.0000000+08:00' + "`t" + 'CR-XX' + "`t" + 'chain-c' + "`t" + 'body NAMES a file: CR-V2-hud-mine.png and CR-V2-measure-after.txt')
  $L.Add('2026-01-01T00:00:04.0000000+08:00' + "`t" + 'CR-YY' + "`t" + 'chain-d' + "`t" + 'first of a GLUED pair' + '2026-01-01T00:00:05.0000000+08:00' + "`t" + 'CR-YY' + "`t" + 'chain-e' + "`t" + 'second of a GLUED pair')
  [System.IO.File]::WriteAllLines($fxAbs, $L, (New-Object System.Text.UTF8Encoding($false)))
  $c = Get-Census $fxAbs
  Show-Census $c
  Write-Output ''
  Write-Output ('expect: records=4 (line-start)  glued-candidates=1  comments=1  shapes=1')
  Write-Output ('measured: records=' + $c.Records + '  glued-candidates=' + $c.GluedCands + '  comments=' + $c.Comments + '  shapes=' + $c.Shapes.Count)
  Remove-Item -LiteralPath $fxAbs -Force
  Write-Output ('fixture deleted = ' + (-not (Test-Path -LiteralPath $fxAbs)))
  # The discrimination proof: the fixture holds 6 ISO-shaped SUBSTRINGS but only 4 line-start records
  # (one record quotes an older timestamp in its body, one carries a slice-name-like file name, and one
  # line hides a second record). A naive counter would report 6 -- the line-start count must stay 4.
  # (First version asserted `AnyTs > Records` where AnyTs counts LINES, not occurrences => it failed on a
  # correct file. My own negative control caught the wrong expectation -- again.)
  $pass = ($c.Records -eq 4) -and ($c.RecordsLen -eq 4) -and ($c.GluedCands -eq 1) -and ($c.Comments -eq 1) -and ($c.Shapes.Count -eq 1) -and ($c.AnyTsOcc -eq 6)
  Write-Output ''
  Write-Output ('NEGCTL ' + $(if ($pass) { 'PASS' } else { 'FAIL' }) + '  (line-start counting is immune to in-body timestamps / slice names, and the glued pair IS surfaced as a structural candidate)')
  if (-not $pass) { exit 1 }
  exit 0
}

Show-Anchor $File
$c = Get-Census $File
Show-Census $c
Write-Output ''
Write-Output '# re-derive anytime: powershell -NoProfile -File tools/probes/play-log-format-census.ps1'
Write-Output '# FORBIDDEN: do NOT quote a record count without saying "line-start semantics" (the contract block says so).'
exit 0
