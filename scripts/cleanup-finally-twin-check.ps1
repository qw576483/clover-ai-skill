# cleanup-finally-twin-check.ps1 -- prove that a script's CLEANUP really is run by its `finally`,
# using a TWIN BODY as the negative control.
#
# WHY A TWIN: "the sandbox was gone afterwards" can come from causes other than the finally block
# (the injection never fired, the sandbox was never created, an earlier exit cleaned it).  A single
# positive reading is therefore a potentially TAUTOLOGICAL assertion.  So three readings must hold
# TOGETHER:
#   P2 (negative control) an identical TWIN with the cleanup ACTIONS disabled must LEAVE the sandbox
#                         behind under the same injection -- if it does not, P1 proves nothing;
#   P1 (positive)         the real script, SAME injection, must have its sandbox gone, and the exit
#                         code must be != 0 (the injection really fired);
#   P3 (no regression)    the real script on the normal path must still succeed.
# The sandbox is checked ON DISK, never from stdout alone.
#
# TWIN CONSTRUCTION (walked into this once -- recorded so nobody repeats it): replacing `} finally {`
# with `} if ($false) {` does NOT work, because PowerShell requires try to be followed by catch or
# finally => the twin itself fails to PARSE, exits != 0, and P2 can look "passed" while proving
# nothing (a false green).  The twin is therefore built by COMMENTING OUT the cleanup lines
# line-by-line, and the build must prove that stripping the marker restores the source EXACTLY.
#
# The twin is built in the ONE-TIME area (<ProjectRoot>/.ai-tmp/test/) and deleted again -- it must
# never become a permanent "broken sample" inside the judgement-asset tree.
#
# Usage
#   powershell -NoProfile -File scripts\cleanup-finally-twin-check.ps1 -Target <script.ps1> `
#       -NeuterPattern '^\s*Remove-Item -LiteralPath \$sb .*$' -ProjectRoot <dir>
#
#   -Target         the script under test (it must accept the injection switch and print the sandbox
#                   path + a cleanup marker)
#   -NeuterPattern  comma-separated regexes; EVERY LINE matching ANY of them is commented out in the
#                   twin.  These are the cleanup actions.
#   -InjectArg      the switch/parameter that makes the target throw mid-run (default -InjectThrow)
#   -InjectValue    the value passed to it (default mid); pass '' to pass it as a bare switch
#   -SandboxRe      regex with the sandbox path (default 'sandbox=(?<p>[^\r\n]+)')
#   -CleanMarkerRe  regex proving the cleanup ran, printed by the target (default 'FINALLY\s+sandbox=.*removed=True')
#   -NormalMarkerRe regex proving the normal path succeeded (default 'FAILS=0')
#   -ExpectNeutered how many lines the twin must have disabled (default -1 = "at least one")
#
# exit 0 = P1+P2+P3 all hold; 1 = a reading failed; 2 = the twin could not be built faithfully.
param(
    [Parameter(Mandatory = $true)][string]$Target,
    [Parameter(Mandatory = $true)][string]$NeuterPattern,
    [string]$ProjectRoot = '',
    [string]$InjectArg = '-InjectThrow',
    [string]$InjectValue = 'mid',
    [string]$SandboxRe = 'sandbox=(?<p>[^\r\n]+)',
    [string]$CleanMarkerRe = 'FINALLY\s+sandbox=.*removed=True',
    [string]$NormalMarkerRe = 'FAILS=0',
    [int]$ExpectNeutered = -1
)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = (Get-Location).Path }
$root = [IO.Path]::GetFullPath($ProjectRoot)
$targetFull = if ([IO.Path]::IsPathRooted($Target)) { [IO.Path]::GetFullPath($Target) } else { [IO.Path]::GetFullPath((Join-Path $root $Target)) }
if (-not (Test-Path -LiteralPath $targetFull)) { Write-Output ('FAIL target not found: ' + $targetFull); exit 2 }

$fails = 0
function Ck($name, $got, $want) {
    $ok = ("$got" -eq "$want")
    if (-not $ok) { $script:fails++ }
    Write-Output ('  {0}  {1}  got={2} want={3}' -f ($(if ($ok) { 'PASS' } else { 'FAIL' }), $name, $got, $want))
}
function PathState([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return 'NO-PATH-PARSED' }
    return ([bool](Test-Path -LiteralPath $p))
}

function Invoke-Child([string]$script, [string[]]$extra) {
    $PSExe = 'powershell.exe'
    $cmd = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if ($null -ne $cmd) { $PSExe = $cmd.Source }
    $argv = New-Object System.Collections.Generic.List[string]
    foreach ($a in @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script)) { $argv.Add($a) }
    foreach ($a in $extra) { $argv.Add($a) }
    # TRAP (measured): with $ErrorActionPreference='Stop', merging a NATIVE program's stderr via
    # 2>&1 wraps each stderr line in a NativeCommandError => the HOST terminates as soon as the child
    # writes one.  So drop to Continue while capturing, then restore.
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = (& $PSExe @argv 2>&1 | Out-String)
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    $m = [regex]::Match($out, $SandboxRe)
    [pscustomobject]@{
        Exit    = $code
        Out     = $out
        Sandbox = $(if ($m.Success -and $m.Groups['p'].Success) { $m.Groups['p'].Value.Trim() } else { '' })
    }
}

# ---- 0. build the twin (cleanup actions commented out, everything else identical) ----
$patList = @($NeuterPattern.Split(',') | Where-Object { $_.Trim().Length -gt 0 } | ForEach-Object { $_.Trim() })
if ($patList.Count -eq 0) { Write-Output 'FAIL -NeuterPattern is empty'; exit 2 }
$twDir = Join-Path $root (Join-Path '.ai-tmp\test' 'cleanup-twin')
if (Test-Path -LiteralPath $twDir) { Remove-Item -LiteralPath $twDir -Recurse -Force }
$null = New-Item -ItemType Directory -Force -Path $twDir
$twin = Join-Path $twDir 'twin.ps1'
$srcLines = [IO.File]::ReadAllLines($targetFull)     # ReadAllLines strips the BOM for us
$twinLines = New-Object System.Collections.Generic.List[string]
$neutered = 0
foreach ($ln in $srcLines) {
    $hit = $false
    foreach ($pat in $patList) { if ($ln -match $pat) { $hit = $true; break } }
    if ($hit) { $twinLines.Add('# TWIN-DISABLED ' + $ln); $neutered++; continue }
    $twinLines.Add($ln)
}
if ($ExpectNeutered -ge 0) { Ck 'twin: disabled line count == -ExpectNeutered' $neutered $ExpectNeutered }
else { Ck 'twin: at least one cleanup line was disabled (otherwise the twin is not a twin)' ([bool]($neutered -ge 1)) 'True' }
# the twin must be the source modulo the marker -- otherwise it is a different script and P2 is void
$restored = @($twinLines | ForEach-Object { $_ -replace '^# TWIN-DISABLED ', '' })
Ck 'twin: equal to source after stripping the marker (case-sensitive, line by line)' ([bool]((($restored -join "`n") -ceq ($srcLines -join "`n")))) 'True'
Ck 'twin: still contains the finally keyword (the action was disabled, not the guard syntax)' ([bool](($twinLines -join "`n") -cmatch '\} finally \{')) 'True'
[IO.File]::WriteAllLines($twin, $twinLines, (New-Object Text.UTF8Encoding($true)))

$inject = @($InjectArg)
if (-not [string]::IsNullOrWhiteSpace($InjectValue)) { $inject += $InjectValue }
$sbLeft = @()
$rc = 0
try {
    Write-Output ''
    Write-Output '=== P2 negative control: twin (cleanup disabled) + injection => the sandbox MUST remain ==='
    $b = Invoke-Child $twin $inject
    Ck 'P2 the injection really fired (twin exit != 0)' ([bool]($b.Exit -ne 0)) 'True'
    Ck 'P2 a sandbox path was parsed (non-empty; an empty path makes Test-Path falsely report False)' ([bool]($b.Sandbox.Length -gt 0)) 'True'
    Ck 'P2 the sandbox is STILL THERE (False would mean P1 is tautological and this check is void)' (PathState $b.Sandbox) 'True'
    if ($b.Sandbox.Length -gt 0) { $sbLeft += $b.Sandbox }

    Write-Output ''
    Write-Output '=== P1 positive: the real script + the SAME injection => finally must clean the sandbox ==='
    $a = Invoke-Child $targetFull $inject
    Ck 'P1 the injection really fired (real exit != 0, error not swallowed)' ([bool]($a.Exit -ne 0)) 'True'
    Ck 'P1 the target reports the cleanup ran' ([bool]($a.Out -cmatch $CleanMarkerRe)) 'True'
    Ck 'P1 on-disk check: the sandbox no longer exists' (PathState $a.Sandbox) 'False'

    Write-Output ''
    Write-Output '=== P3 normal path: the real script with no injection => must still succeed ==='
    $c = Invoke-Child $targetFull @()
    Ck 'P3 exit code = 0' $c.Exit 0
    Ck 'P3 success marker printed' ([bool]($c.Out -cmatch $NormalMarkerRe)) 'True'
    Ck 'P3 on-disk check: the sandbox no longer exists' (PathState $c.Sandbox) 'False'
} finally {
    foreach ($s in $sbLeft) {
        if ($s.Length -gt 0 -and (Test-Path -LiteralPath $s)) { Remove-Item -LiteralPath $s -Recurse -Force -ErrorAction SilentlyContinue }
    }
    if (Test-Path -LiteralPath $twDir) { Remove-Item -LiteralPath $twDir -Recurse -Force -ErrorAction SilentlyContinue }
    Write-Output ('FINALLY-CHECK cleanup: twin dir still present? ' + (Test-Path -LiteralPath $twDir))
}
if ($fails -gt 0) { $rc = 1 }
Write-Output ''
Write-Output ('SELF-ASSERT(cleanup-finally-twin) fails=' + $fails)
exit $rc
