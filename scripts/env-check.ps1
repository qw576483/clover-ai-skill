# ============================================================================
#  env-check.ps1 -- environment gate for any 3D project (run BEFORE the first Play,
#  and again before drawing any conclusion about frame rate / "the game is laggy").
#
#  One question: does this machine actually have a WORKING hardware 3D adapter?
#  Exit 0 = usable, 1 = software rendering / broken GPU (STOP: fix the machine first,
#  do NOT go looking for performance bugs in the code), 2 = could not decide.
#
#  Why this exists (2026-09-20, real incident):
#    A "the game is stuck at 1 fps" report took 6 Play sessions to trace. The machine
#    had a DISABLED discrete GPU (Code 22) and Unity was falling back to the CPU
#    software rasterizer (Microsoft Basic Render Driver, ~255ms/frame). The root cause
#    was visible in one command -- and the elapsed time was blamed on the project.
#    Seeing software rendering means every frame-time number on that machine is void.
#
#  This file must stay ASCII-only (Windows PowerShell 5.1 parses .ps1 as ANSI when the
#  file has no UTF-8 BOM). Do NOT match localized display names ("Basic Display
#  Adapter" is Chinese on zh-CN Windows) -- match PNPDeviceID prefixes and error codes,
#  which are language independent.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File tools\env-check.ps1
#    powershell -NoProfile -ExecutionPolicy Bypass -File tools\env-check.ps1 -Root <projectRoot>
# ============================================================================
param(
  [string]$Root = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = 'Continue'
$fail = 0
$unknown = 0

function Say([string]$level, [string]$name, [string]$msg) {
  Write-Output ("{0,-11} {1,-16} {2}" -f $level, $name, $msg)
}

# --- 1) physical GPUs (PNPDeviceID starts with PCI\) -------------------------
$vcs = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)
$pci = @($vcs | Where-Object { $_.PNPDeviceID -like 'PCI\*' })
$virt = @($vcs | Where-Object { $_.PNPDeviceID -notlike 'PCI\*' })

if ($pci.Count -eq 0) {
  $fail++
  Say 'FAIL' 'physical-gpu' 'no PCI display adapter reported by Win32_VideoController'
} else {
  foreach ($g in $pci) {
    $code = [int]$g.ConfigManagerErrorCode
    if ($code -eq 0) {
      Say 'PASS' 'physical-gpu' ($g.Name + '  (ConfigManagerErrorCode=0)')
    } else {
      $fail++
      $hint = switch ($code) {
        22 { 'CM_PROB_DISABLED -- the device is DISABLED (someone/something turned it off)' }
        43 { 'CM_PROB_FAILED_POST_START -- driver reported a problem; Windows stopped the device' }
        10 { 'CM_PROB_FAILED_START -- driver failed to start' }
        31 { 'CM_PROB_FAILED_LOAD -- driver failed to load' }
        28 { 'CM_PROB_FAILED_INSTALL -- no driver installed' }
        default { 'see CM_PROB_* for this code' }
      }
      Say 'FAIL' 'physical-gpu' ($g.Name + '  ConfigManagerErrorCode=' + $code + '  ' + $hint)
    }
  }
}

# --- 2) virtual / indirect display adapters (informational, not fatal) -------
foreach ($g in $virt) {
  Say 'INFO' 'virtual-display' ($g.Name + '  code=' + $g.ConfigManagerErrorCode)
}

# --- 3) what Unity itself ended up with (most direct evidence) --------------
$editorLog = Join-Path $Root 'client\Logs\Editor.log'
if (-not (Test-Path $editorLog)) {
  Say 'INFO' 'unity-renderer' ('no ' + $editorLog + ' yet -- re-run this after the first Play')
} else {
  $devLine = @(Select-String -Path $editorLog -Pattern 'Renderer:\s*(.+)$' -ErrorAction SilentlyContinue | Select-Object -First 1)
  if ($devLine.Count -eq 0) {
    $unknown++
    Say 'HUMAN-ONLY' 'unity-renderer' 'no "Renderer:" line found in Editor.log'
  } else {
    $dev = $devLine[0].Matches[0].Groups[1].Value.Trim()
    if ($dev -match 'Basic Render Driver|WARP|Basic Display') {
      $fail++
      Say 'FAIL' 'unity-renderer' ($dev + '  => SOFTWARE RENDERING; frame-time numbers on this machine are void')
    } else {
      Say 'PASS' 'unity-renderer' ('Unity is using: ' + $dev)
    }
  }
}

# --- 4) crash storms: the SAME exe dying over and over ------------------------
#     Why: on 2026-09-21 this machine wrote 8 SaveCheck.exe dumps in 24h (plus a
#     Unity.exe dump) while the project was being worked on. "It keeps crashing"
#     cannot be attributed to the project until the crash source is known -- same
#     spirit as the software-rendering gate above: prove the machine first.
#     Windows writes these dumps automatically (no extra tooling needed).
$dumpDir = Join-Path $env:LOCALAPPDATA 'CrashDumps'
if (-not (Test-Path $dumpDir)) {
  Say 'INFO' 'crash-dumps' ('no ' + $dumpDir + ' -- nothing to check')
} else {
  $cut   = (Get-Date).AddHours(-24)
  $dumps = @(Get-ChildItem $dumpDir -Filter *.dmp -File -ErrorAction SilentlyContinue |
             Where-Object { $_.CreationTime -gt $cut })
  if ($dumps.Count -eq 0) {
    Say 'PASS' 'crash-dumps' 'no new *.dmp in the last 24h'
  } else {
    $byName = @{}
    foreach ($d in $dumps) {
      # Normalise the exe label: Windows appends "(N)" and/or ".<pid>" when a dump name
      # repeats; without stripping them the SAME process is counted under several names
      # (measured: WindowsPackageManagerServer.exe showed up twice, each labelled "x4").
      # Strip repeatedly -- the suffixes can nest as "name.exe(1).1234.dmp".
      $n = $d.Name -replace '\.dmp$', ''
      while ($n -match '(\(\d+\)|\.\d+)$') { $n = $n -replace '(\(\d+\)|\.\d+)$', '' }
      if ($byName.ContainsKey($n)) { $byName[$n]++ } else { $byName[$n] = 1 }
    }
    $hot = @($byName.GetEnumerator() | Where-Object { $_.Value -ge 3 } | Sort-Object Value -Descending)
    foreach ($k in @($byName.GetEnumerator() | Sort-Object Value -Descending)) {
      Say 'INFO' 'crash-dump' ($k.Key + ' x' + $k.Value + ' in the last 24h')
    }
    if ($hot.Count -gt 0) {
      $fail++
      Say 'FAIL' 'crash-storm' ((@($hot | ForEach-Object { $_.Key + ' x' + $_.Value }) -join ', ') + '  => repeated crashes; identify the culprit process first, do NOT blame the project code')
    } else {
      Say 'PASS' 'crash-dumps' ('' + $dumps.Count + ' dump(s) in 24h, no single exe crashing 3+ times')
    }
  }
}

# --- 5) antivirus interference (informational only, never fails the gate) -----
#     Why: on this machine the 360-family tools are the usual cause of "the editor
#     is slow" / "the build fails for no reason" / "imported files vanish". Same
#     spirit as the gates above -- know the machine before blaming the code.
#     SecurityCenter2 is absent on Server SKUs => the try/catch keeps it quiet;
#     the process scan catches portable builds that register nothing.
$avReg = @()
try {
  $avReg = @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction SilentlyContinue |
             ForEach-Object { $_.displayName } | Where-Object { $_ })
} catch { $avReg = @() }
$avProc = @()
foreach ($p in @('360tray','360sd','360Safe','ZhuDongFangYu','QQPCTray','QQPCRTP','kxetray','avp','MsMpEng','HipsTray','HipsDaemon')) {
  if (@(Get-Process -Name $p -ErrorAction SilentlyContinue).Count -gt 0) { $avProc += $p }
}
if ($avReg.Count -eq 0 -and $avProc.Count -eq 0) {
  Say 'PASS' 'antivirus' 'no registered AV product and no known AV process'
} else {
  $bits = @()
  if ($avReg.Count -gt 0)  { $bits += 'registered: ' + ($avReg -join ', ') }
  if ($avProc.Count -gt 0) { $bits += 'running: ' + ($avProc -join ', ') }
  Say 'WARN' 'antivirus' (($bits -join ' | ') + '  -- if editing / building is slow or imported files vanish, pause real-time protection and retest')
}

# --- 6) verdict --------------------------------------------------------------
Write-Output ''
if ($fail -gt 0) {
  Write-Output ("ENV-FAIL ({0} problem(s)) -- fix the machine BEFORE judging 3D performance:" -f $fail)
  Write-Output '  1) Device Manager -> Display adapters -> right-click the GPU -> Enable device'
  Write-Output '  2) if it is disabled again after a reboot, look for remote-control / virtual-display'
  Write-Output '     software (its driver often disables the physical GPU) and stop it first'
  Write-Output '  3) reboot (a display adapter usually needs a full re-enumeration), then re-run this script'
  Write-Output '  4) if the code becomes 10/43 after the reboot, reinstall the GPU driver'
  Write-Output '  Reference: skill experience/perf-triage.md'
  exit 1
}
if ($unknown -gt 0) {
  Write-Output 'ENV-UNKNOWN -- could not confirm; run SystemInfo.graphicsDeviceName inside Play as well'
  exit 2
}
Write-Output 'ENV-OK -- a working hardware adapter was found; frame-time numbers may be trusted'
exit 0
