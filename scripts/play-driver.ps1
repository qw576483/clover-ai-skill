# ============================================================================
#  play-driver.ps1 -- ONE driver for Play-mode probe scenes.
#
#  Merges the two shapes that used to live in two separate throwaway files:
#
#    * same-session (default): enter Play ONCE, then run several probe scenes
#      back to back inside that one session -- the cheap shape.
#    * fresh-session (-FreshSession): give EVERY scene its own fresh Play
#      session. Needed for scenes that end in a terminal state (result / game
#      over / boot): after those the FSM never comes back to the menu, the next
#      scene's dispatch silently lands in the wrong state and the frames come
#      out blank (a single colour) WITHOUT any error.
#
#  Three things this file exists to get right:
#    1) EVERY `unity` call carries --project-path (see Invoke-Unity). Editor
#       discovery is cwd-relative, so with more than one editor open the CLI
#       silently reports "no editor" -- and a bare `ready` may name a different
#       project than the one you think you are driving.
#    2) The "wait for the menu" step counts FRESH occurrences of the menu
#       marker, never "the file contains one somewhere": the old shape matched a
#       HISTORICAL line, returned instantly, and dispatched the next scene while
#       the boot flow was still in Boot.
#    3) Scene start / done are detected the same way: the COUNT of the scene's
#       own marker must increase after dispatch. Timeout is NEVER the completion
#       criterion -- it only ends the wait and reports ok=false.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File play-driver.ps1 `
#        -ProjectPath <project>/client -Scene walk,combat,result
#    powershell -NoProfile -ExecutionPolicy Bypass -File play-driver.ps1 `
#        -ProjectPath <project>/client -Scene result -FreshSession
#    powershell -NoProfile -ExecutionPolicy Bypass -File play-driver.ps1 `
#        -ProjectPath <project>/client -Scene walk -PreflightOnly
#
#  Exit codes:
#    0  every scene reached its done marker
#    1  the engine never came alive (no Play session to drive)
#    2  preflight failed (bad project path / no `unity` / unknown scene id)
#    3  the log could not be read (completion could not be judged)
#    4  one or more scenes were dispatched but did not finish
#
#  ASCII-only on purpose: Windows PowerShell 5.1 parses a BOM-less .ps1 as ANSI,
#  so CJK literals silently break -match. Non-ASCII markers are built from code
#  points (see the marker defaults below).
# ============================================================================
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string[]]$Scene,
    [string]$ProbeFile = 'tools\probes\probe.cs',
    [string]$EntryClass = 'Probe',
    [string]$EntryRegex = 'public static void ([A-Za-z0-9_]+)\(\)\s*=>\s*Start\("([A-Za-z0-9_\-]+)"',
    [string]$LogPath = '',
    [string]$MenuMarker = '',
    [string]$StartMarker = '',
    [string]$DoneMarker = '',
    [string]$AliveProbe = 'return CloverEngine.Game.IsRunning;',
    [int]$SceneTimeout = 240,
    [int]$PlayWaitSec = 60,
    [int]$MenuWaitSec = 60,
    [int]$StartWaitSec = 16,
    [switch]$FreshSession,
    [switch]$ReusePlay,
    [switch]$PreflightOnly
)
$ErrorActionPreference = 'Continue'
$exitCode = 0

# ---- argument resolution ---------------------------------------------------
if (-not (Test-Path $ProjectPath)) {
    Write-Output ('PREFLIGHT FAIL: project path not found -> ' + $ProjectPath)
    exit 2
}
$ProjectPath = (Resolve-Path $ProjectPath).Path
$ProbePath = $ProbeFile
if (-not [System.IO.Path]::IsPathRooted($ProbePath)) { $ProbePath = Join-Path $ProjectPath $ProbeFile }
if ([string]::IsNullOrWhiteSpace($LogPath)) {
    $LogPath = Join-Path $ProjectPath ('Logs\' + (Get-Date -Format 'yyyy-MM-dd') + '.log')
} elseif (-not [System.IO.Path]::IsPathRooted($LogPath)) {
    $LogPath = Join-Path $ProjectPath $LogPath
}
# Marker defaults are the clover app-flow / probe conventions; override them
# with -MenuMarker / -StartMarker / -DoneMarker when a project writes others.
if ([string]::IsNullOrWhiteSpace($MenuMarker)) { $MenuMarker = ([char]0x2192) + ' Menu' }   # "-> Menu"
if ([string]::IsNullOrWhiteSpace($StartMarker)) { $StartMarker = 'scene start:' }
if ([string]::IsNullOrWhiteSpace($DoneMarker)) { $DoneMarker = 'scene end:' }
if ($FreshSession) { $ReusePlay = $false }

# ---- helpers --------------------------------------------------------------
function Invoke-Unity([string[]]$UnityArgs) {
    # Single funnel: EVERY unity call gets --project-path. Do not call `unity`
    # anywhere else in this file.
    $all = @($UnityArgs) + @('--project-path', $ProjectPath)
    return (& unity @all 2>&1 | Out-String)
}
function Get-PlayMode {
    $j = Invoke-Unity @('command', 'editor_status', '--format', 'json', '--no-banner')
    if ($j -match 'playMode[^a-zA-Z]+([a-zA-Z]+)') { return $Matches[1] }
    if ($j -match '"status"\s*:\s*"([a-zA-Z]+)"') { return $Matches[1] }
    return 'unknown'
}
function Get-EngineAlive {
    $j = Invoke-Unity @('command', 'eval', '--code', $AliveProbe, '--format', 'json', '--no-banner')
    return ($j -match '"result"\s*:\s*true')
}
function LogText {
    if (-not (Test-Path $LogPath)) { return '' }
    try {
        $fs = New-Object System.IO.FileStream($LogPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
        $t = $sr.ReadToEnd(); $sr.Close(); $fs.Close()
        return $t
    } catch {
        Write-Output ('WARN log read failed: ' + $_.Exception.Message)
        return ''
    }
}
function Get-MarkerCount([string]$Marker) {
    $t = LogText
    if ([string]::IsNullOrEmpty($t)) { return 0 }
    return @([regex]::Matches($t, [regex]::Escape($Marker))).Count
}
function Wait-MarkerIncrease([string]$Marker, [int]$Before, [int]$TimeoutSec) {
    # Completion is judged ONLY by the marker the program under test wrote.
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        Start-Sleep -Seconds 2
        if ((Get-MarkerCount $Marker) -gt $Before) { return $true }
    }
    return $false
}
function Stop-Play {
    if ((Get-PlayMode) -eq 'playing') {
        [void](Invoke-Unity @('command', 'editor_stop', '--no-banner'))
        for ($i = 0; $i -lt 30; $i++) {
            Start-Sleep -Seconds 1
            if ((Get-PlayMode) -ne 'playing') { return }
        }
    }
}
function Start-FreshPlay {
    Stop-Play
    [void](Invoke-Unity @('command', 'editor_play', '--no-banner'))
    for ($i = 0; $i -lt [int]($PlayWaitSec / 2); $i++) {
        Start-Sleep -Seconds 2
        if ((Get-PlayMode) -eq 'playing') { break }
    }
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Seconds 2
        if (Get-EngineAlive) { return $true }
    }
    return $false
}

# ---- PREFLIGHT (seconds): everything checkable BEFORE the minute-long runs --
if (-not (Get-Command unity -ErrorAction SilentlyContinue)) {
    Write-Output 'PREFLIGHT FAIL: the `unity` CLI is not on PATH (install it, or run this from a shell that has it)'
    exit 2
}
if (-not (Test-Path $ProbePath)) {
    Write-Output ('PREFLIGHT FAIL: probe file not found -> ' + $ProbePath)
    exit 2
}
$probeText = [System.IO.File]::ReadAllText($ProbePath, [System.Text.Encoding]::UTF8)
$entryOf = @{}
foreach ($m in [regex]::Matches($probeText, $EntryRegex)) {
    # groups: 1 = C# method name, 2 = declared scene id
    $entryOf[$m.Groups[2].Value.ToLower()] = $m.Groups[1].Value
}
$scenes = @($Scene | ForEach-Object { $_ -split ',' } | Where-Object { $_ -ne '' })
if ($scenes.Count -eq 0) {
    Write-Output 'PREFLIGHT FAIL: no scene id given'
    exit 2
}
if ($entryOf.Count -eq 0) {
    Write-Output ('PREFLIGHT FAIL: no scene declared in ' + $ProbePath + ' (does -EntryRegex match its entries?)')
    exit 2
}
$unknown = @($scenes | Where-Object { -not $entryOf.ContainsKey($_.ToLower()) })
if ($unknown.Count -gt 0) {
    Write-Output ('PREFLIGHT FAIL: not declared in ' + $ProbeFile + ' -> ' + ($unknown -join ','))
    exit 2
}
if ((LogText) -eq '') {
    Write-Output ('PREFLIGHT FAIL: cannot read the game log -> ' + $LogPath)
    exit 3
}
$mode = 'same-session'
if ($FreshSession) { $mode = 'fresh-session' } elseif ($ReusePlay) { $mode = 'reuse-play' }
Write-Output ('PREFLIGHT OK: scenes=' + ($scenes -join ',') + ' project=' + $ProjectPath + ' probe=' + $ProbeFile + ' mode=' + $mode)
if ($PreflightOnly) {
    Write-Output 'PREFLIGHT_ONLY=1'
    exit 0
}

# ---- acquire a Play session ------------------------------------------------
$ok = $false
if ($ReusePlay) {
    # Re-dispatch into the Play session that is ALREADY running: no new Play
    # entry (reuse the session before opening another one).
    $ok = Get-EngineAlive
    Write-Output ('REUSE_PLAY=' + $ok + ' playMode=' + (Get-PlayMode))
} else {
    Write-Output ('---- fresh Play session (' + $mode + ') ----')
    $ok = Start-FreshPlay
    Write-Output ('ENGINE_ALIVE=' + $ok + ' playMode=' + (Get-PlayMode))
}
if (-not $ok) {
    Write-Output 'ABORT: engine never came alive'
    exit 1
}

# ---- run the scenes --------------------------------------------------------
$failed = @()
foreach ($s in $scenes) {
    if ($FreshSession) {
        if (-not (Start-FreshPlay)) {
            Write-Output ('FRESH_PLAY_FAILED ' + $s)
            $failed += $s
            continue
        }
    }
    # wait for a FRESH menu marker (count must increase)
    $menuBefore = Get-MarkerCount $MenuMarker
    $w = 0
    while ($w -lt $MenuWaitSec) {
        if ((Get-MarkerCount $MenuMarker) -gt $menuBefore) { break }
        Start-Sleep -Seconds 1; $w++
    }
    if ($w -ge $MenuWaitSec) { Write-Output ('MENU_WAIT_TIMEOUT ' + $s) }
    Write-Output ('---- scene: ' + $s + ' (fresh menu marker after ' + $w + ' s) ----')

    $logOff    = (LogText).Length
    $startBefore = Get-MarkerCount ($StartMarker + $s)
    $doneBefore  = Get-MarkerCount ($DoneMarker + $s)
    $entry    = $EntryClass + '.' + $entryOf[$s.ToLower()]
    $resp     = Invoke-Unity @('command', 'run_script', '--file', $ProbeFile, '--entry', $entry, '--no-banner')
    if ($resp -match 'Entry Point Not Found') {
        Write-Output ('DISPATCH_FAILED ' + $s + ' : entry not found')
        $failed += $s
        continue
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $started = Wait-MarkerIncrease ($StartMarker + $s) $startBefore $StartWaitSec
    if (-not $started) {
        Write-Output ('DISPATCH_FAILED ' + $s + ' : no start marker within ' + $StartWaitSec + 's')
        # Never slice with a length computed elsewhere: a stale/other length
        # throws and swallows the run_script error that actually matters.
        $flat = ($resp -replace "\s+", ' ')
        $n = [Math]::Min(400, $flat.Length)
        Write-Output ('  raw: [' + $flat.Length + '] ' + $flat.Substring(0, $n))
        $failed += $s
        continue
    }

    $done = Wait-MarkerIncrease ($DoneMarker + $s) $doneBefore $SceneTimeout
    Write-Output ('SCENE_DONE=' + $s + ' ok=' + $done + ' sec=' + [int]$sw.Elapsed.TotalSeconds)
    $t = LogText
    $tail = ''
    if ($t.Length -gt $logOff) { $tail = $t.Substring($logOff) }
    $errs = @(($tail -split "`n") | Where-Object { $_ -match '\[Error\]' })
    Write-Output ('SCENE_ERRORS=' + $s + ' ' + $errs.Count)
    foreach ($e in $errs) { Write-Output ('   ' + $e.Trim()) }
    if (-not $done) { $failed += $s }
}

Write-Output 'ALL_SCENES_DISPATCHED'
if ($failed.Count -gt 0) {
    Write-Output ('SCENES_FAILED=' + ($failed -join ','))
    $exitCode = 4
}
exit $exitCode
