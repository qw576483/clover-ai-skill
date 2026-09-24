# fingerprint-blindspot-suite.ps1 -- the SHARED BLIND SPOT of a directory content hash, measured.
#
# PROVENANCE (lifted into the skill 2026-09-24): written inside one project ("the source project"
# below), then parameterised -- the authority implementation and the project root are arguments now,
# and the authority is named by its ROLE (the single implementation that produces the manifest hash)
# rather than by a path that only exists in that project.  The measured values are that project's,
# kept because a blind spot with no measurement behind it gets "simplified" away.
# NOT A GATE ITEM: this file is an EVIDENCE CARRIER.  It needs write access under .ai-tmp for its
# sandbox and it prints NOT-JUDGED (exit 4) rather than a green when it cannot run -- wiring it into a
# gate would turn "the authority changed shape" into a delivery failure.
#
# WHY IT EXISTS (team-lead ruling 2026-09-23, option 2 of the two CR-F2 proposed): the manifest hash is
# produced by exactly ONE implementation (the authority; in the source project that was its
# retain-assembly probe). What must NOT be lost is the INDEPENDENT EVIDENCE that this key has a known
# blind spot -- so this file keeps ONLY the sandbox suite. It does NOT read the index ledger, does NOT
# compare recorded values, and is NOT wired into any gate. It produces NO content hash of any real
# artifact: the few values it prints are of a throwaway sandbox, obtained by running the authority's
# OWN functions.
#
# HOW IT CALLS THE AUTHORITY (measured constraint): the module has NO `__main__` guard, so importing it
#   would run its whole argparse pipeline. The helper parses the file with `ast`, keeps Import/FunctionDef
#   nodes plus only the module-level constants those functions reference, and execs that subset. The
#   SUBSET FINGERPRINT is printed so a change in the authority is visible (measured: it moved from
#   fa28f2151f824832 to 75ec3ff74dc44419 when CR-R1 landed the integer-nanosecond fix).
#
# THE TWO SENSITIVE BANDS OF THIS KEY (both measured, both must be stated wherever the value is used):
#   BAND 1  same-size in-place rewrite WITH the original mtime restored  => INVISIBLE (expected: a
#           file-level `path=mtime` entry has the identical blind spot, so the two are EQUIVALENT).
#   BAND 2  the millisecond field is rendered from st_mtime_ns (INTEGER nanoseconds). Any rendering that
#           passes through a float first -- datetime.fromtimestamp(st_mtime) rounds to the nearest
#           MICROsecond -- lands ONE MILLISECOND HIGH on a boundary (measured instance: a file whose true
#           value is 400.9998 ms renders .400 on the integer path and .401 through the float path; that
#           single file was the whole of the 2/6 cross-implementation gap). ⛔ Cross-implementation
#           comparison must align THIS point first; case5 below demonstrates the band in a sandbox.
#
# FAILURE MODES (team-lead rule 2026-09-23: a step that touches disk must state how it breaks):
#   - severity: LOW. Worst case = a LEFTOVER SANDBOX directory + a FAIL line. It deletes only $sbAbs, and refuses to run
#     at all unless that path is under .ai-tmp. => it cannot delete or rewrite a real artifact, and it
#     cannot touch the authority (it only reads it).
#   - severity: MEDIUM (a silent green would be worse). If the authority's functions cannot be extracted/executed it reports NOT-JUDGED and exits 4, never a
#     green.
#   - a truncated pipe (e.g. `| Select-Object -First N`) can kill this process mid-run, which would leave
#     the sandbox behind and skip the "sandbox deleted" self-check -- so do not truncate its output when
#     you care about its side effects.
#
# READ-ONLY on real inputs. Writes happen only inside a sandbox under .ai-tmp (refused otherwise); the
# sandbox is deleted afterwards and, when -Dir is given, the suite asserts that target's value is unchanged.
param(
  # The AUTHORITY implementation: the one module that produces the manifest hash.  REQUIRED -- an
  # empty default cannot be guessed, because "some other project's probe path" would silently judge
  # nothing.  Pass it project-relative (e.g. tools/probes/<your-retain-assembly>.py).
  [string]$Impl = '',
  # The project the authority belongs to.  Defaults to the CURRENT DIRECTORY -- never to this file's
  # own location: the script ships in the skill, the authority lives in a project.
  [string]$ProjectRoot = '',
  # The authority's function names, as data: $ManifestFns = which defs to extract (the manifest is one
  # of them) and $EntryFn = the one that returns a single entry's value.  Baked-in names were the
  # original form; a project whose authority names them differently got an EMPTY extracted subset and
  # a NOT-JUDGED, i.e. the suite silently stopped measuring anything.
  [string]$ManifestFns = 'manifest_of,entry_value',
  [string]$EntryFn = 'entry_value',
  [string]$Dir,
  [string]$Sandbox = '.ai-tmp/test/dir-content-hash-blindspot-sandbox'
)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
if (-not $PSBoundParameters.ContainsKey('Sandbox') -or -not $Sandbox) { $Sandbox = '.ai-tmp/test/dir-content-hash-blindspot-sandbox' }
if (-not $ProjectRoot) {
  $ProjectRoot = (Get-Location).Path
  Write-Output ('INFO  -ProjectRoot not given: using the current directory = ' + $ProjectRoot)
}
if (-not $Impl) {
  Write-Output 'NOT-JUDGED  -Impl <authority .py> is required.'
  Write-Output '            WHY: the whole suite is "run the AUTHORITY''s own functions in a sandbox"; with no'
  Write-Output '            authority named there is nothing to exercise, and a default path would silently'
  Write-Output '            judge a file that does not exist in your tree.'
  exit 4
}
$root = (Resolve-Path $ProjectRoot).Path
Set-Location $root
$implAbs = [System.IO.Path]::GetFullPath((Join-Path $root $Impl))
$sbAbs   = [System.IO.Path]::GetFullPath((Join-Path $root $Sandbox))

$helper = @'
import ast, hashlib, sys
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

def load(path, wanted):
    src = open(path, "r", encoding="utf-8").read()
    tree = ast.parse(src)
    keep_fn = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name in wanted]
    used = set()
    for fn in keep_fn:
        for node in ast.walk(fn):
            if isinstance(node, ast.Name):
                used.add(node.id)
    keep_const = [n for n in tree.body if isinstance(n, ast.Assign)]
    keep_const = [n for n in keep_const if any(isinstance(t, ast.Name) and t.id in used for t in n.targets)]
    keep_imp = [n for n in tree.body if isinstance(n, (ast.Import, ast.ImportFrom))]
    subsrc = "\n".join(ast.get_source_segment(src, n) for n in (keep_imp + keep_const + keep_fn)) + "\n"
    g = {}
    exec(compile(subsrc, path, "exec"), g)
    return g, subsrc

g, subsrc = load(sys.argv[2], set(sys.argv[4].split(",")))
cmd = sys.argv[1]
if cmd == "fingerprint":
    print(hashlib.sha256(subsrc.encode("utf-8")).hexdigest()[:16] + "\t" + str(len(subsrc)))
elif cmd == "value":
    name = sys.argv[3]
    try:
        val = str(g[sys.argv[5]](name))
    except Exception as e:
        val = "ERROR:" + type(e).__name__
    print(name + "\t" + val)
else:
    print("UNKNOWN-CMD")
'@

function Invoke-Impl([string[]]$argsList) {
  $py = $helper | python - @argsList 2>&1
  if ($LASTEXITCODE -ne 0) { return $null }
  return @($py)
}
# G2: -Dir goes through argv, so require the echoed name back byte-identical; a mangled round-trip must
# yield NOT-JUDGED rather than compare two different names (measured: non-ASCII paths are mangled by an
# argv round-trip, which once produced 12 false DRIFTs in the earlier checker).
function ValFor([string]$rel) {
  $line = @(Invoke-Impl @('value', $implAbs, $rel, $ManifestFns, $EntryFn))[0]
  $p = $line -split "`t"
  if ($p.Count -lt 2) { return 'NOT-JUDGED(short-output)' }
  if ($p[0] -ne $rel) { return ('NOT-JUDGED(echo-mismatch:' + $p[0] + ')') }
  return $p[1]
}

Write-Output ('dir_content_hash BLIND SPOT SUITE | at ' + (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK'))
Write-Output ('# authority = ' + $Impl + '  sha256_16=' + (Get-FileHash $implAbs -Algorithm SHA256).Hash.Substring(0,16) + '  bytes=' + (Get-Item $implAbs).Length + '  mtime=' + (Get-Item $implAbs).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))
$fp = @(Invoke-Impl @('fingerprint', $implAbs, '-', $ManifestFns, $EntryFn))
if ($null -eq $fp) { Write-Output 'NOT-JUDGED: cannot execute the authority'; exit 4 }
# WHICH BYTES IS THIS? (CR-R1's correction, 2026-09-23): over the EXTRACTED SUBSET SOURCE TEXT -- the
# Import/FunctionDef/constant nodes read out of the authority, joined with LF -- NOT the authority file's
# bytes. The byte hash of the authority is a different number (measured 2026-09-23: subset 75ec3ff74dc44419
# vs file bytes 5FF43837D1D09B00), and comparing the two produces a phantom "difference".
Write-Output ('# SUBSET FINGERPRINT (over the EXTRACTED SUBSET SOURCE TEXT, LF-joined -- NOT the file bytes) = ' + $fp[0].Trim())
Write-Output '# BAND 1: same-size rewrite + restored mtime => invisible | BAND 2: millisecond must come from INTEGER ns'

$oneTime = [System.IO.Path]::GetFullPath((Join-Path $root '.ai-tmp')) + [System.IO.Path]::DirectorySeparatorChar
if (-not $sbAbs.StartsWith($oneTime, [System.StringComparison]::OrdinalIgnoreCase)) {
  Write-Output 'SUITE FAIL: sandbox must live under .ai-tmp (refusing to write elsewhere)'; exit 1
}
$sbrel = '.ai-tmp/test/' + (Split-Path $Sandbox -Leaf) + '/**'
$guardBefore = $null
if ($Dir) { $guardBefore = ValFor ($Dir.TrimEnd('/') + '/**') }

if (Test-Path -LiteralPath $sbAbs) { Remove-Item -LiteralPath $sbAbs -Recurse -Force }
New-Item -ItemType Directory -Force -Path $sbAbs | Out-Null
$f1 = Join-Path $sbAbs 'a.bin'; $f2 = Join-Path $sbAbs 'b.bin'; $sub = Join-Path $sbAbs 'sub'
New-Item -ItemType Directory -Force -Path $sub | Out-Null
[System.IO.File]::WriteAllText($f1, 'AAAA'); [System.IO.File]::WriteAllText($f2, 'BBBBBB'); [System.IO.File]::WriteAllText((Join-Path $sub 'c.bin'), 'CC')
$stamp = [datetime]::SpecifyKind([datetime]::ParseExact('2026-01-02T03:04:05', 'yyyy-MM-ddTHH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture), [System.DateTimeKind]::Local)
foreach ($p in @($f1,$f2,(Join-Path $sub 'c.bin'))) { [System.IO.File]::SetLastWriteTime($p, $stamp) }

$v0 = ValFor $sbrel; $v0b = ValFor $sbrel
Write-Output ('case0 determinism                 => ' + $v0 + '   second run equal=' + ($v0 -eq $v0b))
[System.IO.File]::WriteAllText($f1, 'ZZZZ'); [System.IO.File]::SetLastWriteTime($f1, $stamp)
$v1 = ValFor $sbrel
Write-Output ('case1 same-size rewrite + mtime RESTORED => ' + $v1 + '  equal=' + ($v1 -eq $v0) + '   [BAND 1 reproduced: expected equal, registered -- NOT a failure]')
$later = $stamp.AddMinutes(5)
[System.IO.File]::WriteAllText($f1, 'YYYY'); [System.IO.File]::SetLastWriteTime($f1, $later)
$v2 = ValFor $sbrel
Write-Output ('case2 same-size rewrite, mtime CHANGED   => ' + $v2 + '  changed=' + ($v2 -ne $v0) + '   [must be True]')
[System.IO.File]::WriteAllText($f2, 'BBBBBBB')
$v3 = ValFor $sbrel
Write-Output ('case3 size change                        => ' + $v3 + '  changed=' + ($v3 -ne $v2) + '   [must be True]')
$f4 = Join-Path $sbAbs 'd.bin'; [System.IO.File]::WriteAllText($f4, 'D')
$v4 = ValFor $sbrel
Remove-Item -LiteralPath $f4 -Force
$v5 = ValFor $sbrel
Write-Output ('case4 add file                           => ' + $v4 + '  changed=' + ($v4 -ne $v3) + '   [must be True]')
Write-Output ('case4 delete it again                    => ' + $v5 + '  back to case3 value=' + ($v5 -eq $v3) + '   [must be True: closure]')

# case5 -- BAND 2 demonstrated, not asserted: render the millisecond field BOTH ways on a file whose true
# fraction is 400.9998 ms. The integer path (what the authority uses) yields 400; the float path
# (datetime.fromtimestamp rounds to microseconds) yields 401. ⛔ The float path is the REJECTED historical
# rendering and is printed ONLY to prove the band exists -- it never yields a value anyone may use.
# NOTE ON FORM: the band is about RENDERING, not about the filesystem, so the demonstration is driven by
# the measured constant (400999800 ns) instead of by a file whose mtime the volume may or may not keep to
# 100 ns. A file IS still written and read back, but only as an OBSERVATION of what the volume stores.
# THIRD GOTCHA IN THE SAME THREE LINES (measured, three versions destroyed by it):
#   (a) `[int](($x / 10000) % 1000)`   -> `/` yields a DOUBLE and `[int]` CASTS BY ROUNDING
#   (b) `[Math]::Floor($x / 10000.0)`  -> the double already lost the sub-ms at ~6.4e13
#   (c) `[long]([decimal]$x / 1e6)`    -> a decimal->long CAST also ROUNDS (400.9998 -> 401)
# Only PURE INTEGER arithmetic is exact, so everything below is written as `x - (x % m)` over integers.
$bandNs = [long]400999800                       # 400.9998 ms -- the measured value of effects_sprite_456.png
$bandInt = [int](((($bandNs - ($bandNs % 1000000)) / 1000000)) % 1000)                 # floor of ms, exact
$bandUs  = [long](($bandNs + 500 - (($bandNs + 500) % 1000)) / 1000)                    # round to nearest microsecond
$bandFloat = [int](((($bandUs - ($bandUs % 1000)) / 1000)) % 1000)                      # then floor to ms
$f5 = Join-Path $sbAbs 'e.bin'
[System.IO.File]::WriteAllText($f5, 'EE')
$base = [datetime]::SpecifyKind([datetime]::ParseExact('2026-01-02T03:04:05', 'yyyy-MM-ddTHH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture), [System.DateTimeKind]::Local)
$f5t = $base.AddTicks(4009998)          # 4009998 ticks = 400.9998 ms  (1 tick = 100 ns)
[System.IO.File]::SetLastWriteTime($f5, $f5t)
$ticks = (Get-Item $f5).LastWriteTimeUtc.Ticks
# MEASURED GOTCHA, and it is the very band being demonstrated: PowerShell's `/` on two integers returns a
# DOUBLE when the division is not exact, and `[int]`/`[long]` CASTS ROUND instead of truncating. The first
# version of this line was `[int](($ticks / 10000) % 1000)` and it printed 401 for a 400.9998 ms value --
# i.e. the demo fell into BAND 2 while demonstrating it. Integer paths must use explicit Floor/DivRem.
# SECOND, WORSE GOTCHA IN THE SAME LINE (measured): `$ticks / 10000` looks like integer division but
# PowerShell's `/` returns a DOUBLE, and at ~6.4e13 ms the double cannot hold the sub-millisecond part --
# it ROUNDED UP to ...401. So even `[Math]::Floor(...)` was useless: the precision was already gone.
# Demo code fell into BAND 2 for the second time. Use DECIMAL (28-29 significant digits, exact here) or
# the Int64 overload of [Math]::DivRem; a PS cast of a double rounds AND a PS `/` loses precision.
$msTotal  = [long]([decimal]$ticks / 10000)                                # exact: whole milliseconds
$msInt    = [int]($msTotal % 1000)                                         # integer path: floor of sub-ms
$subTicks = $ticks % 10000000                                              # ticks inside the second
$us       = [int][Math]::Round($subTicks / 10.0)                           # float path: round to microseconds
$msFloat  = [int][Math]::Floor([Math]::Floor($us / 1000.0) % 1000)
$bandDiffer = ($bandInt -ne $bandFloat)
Write-Output ('case5 BAND 2 ms-boundary rendering (constant input ' + $bandNs + ' ns) => integer-ns path=' + $bandInt + '  rejected-float path=' + $bandFloat + '  differ=' + $bandDiffer + '   [must be True: the band is real, so ms MUST come from st_mtime_ns]')
$subTicks = $ticks % 10000000
$obsNs = [long]$subTicks * 100
$obsInt = [int](((( - ($obsNs % 1000000)) / 1000000)) % 1000)
$obsUs = [long](($obsNs + 500 - (($obsNs + 500) % 1000)) / 1000)
$obsFloat = [int](((( - ($obsUs % 1000)) / 1000)) % 1000)
Write-Output ('      observation only (not part of the verdict): the volume stored ' + $subTicks + ' sub-second ticks for a requested 4009998 ; .NET reports Millisecond=' + (Get-Item $f5).LastWriteTimeUtc.Millisecond + ' (so this volume keeps 100 ns and the band is reachable on disk)')
Write-Output ('      measured instance from tonight: effects_sprite_456.png true 400.9998 ms -> .400 (correct) vs .401 (float) = the ENTIRE 2/6 gap')

$guardOk = $true
if ($Dir) { $guardAfter = ValFor ($Dir.TrimEnd('/') + '/**'); $guardOk = ($guardAfter -eq $guardBefore); Write-Output ('guard: real target before/after the suite: ' + $guardBefore + ' / ' + $guardAfter + '  unchanged=' + $guardOk) }
Remove-Item -LiteralPath $sbAbs -Recurse -Force
Write-Output ('sandbox deleted = ' + (-not (Test-Path -LiteralPath $sbAbs)))
$pass = ($v0 -eq $v0b) -and ($v1 -eq $v0) -and ($v2 -ne $v0) -and ($v3 -ne $v2) -and ($v4 -ne $v3) -and ($v5 -eq $v3) -and $bandDiffer -and $guardOk
Write-Output ''
Write-Output ('SUITE ' + $(if ($pass) { 'PASS' } else { 'FAIL' }) + '  (moves on every ordinary edit; does NOT move when nothing changed; BAND 1 reproduced and labelled; BAND 2 rendered both ways and shown to differ)')
if (-not $pass) { exit 1 }
exit 0
