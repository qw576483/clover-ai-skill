# install-hooks.ps1 -- install the version-controlled hooks into .git/hooks/
#
# Why an installer: .git/hooks/ is NOT versioned, so a hook written directly there exists on
# exactly one machine and is lost on the next clone. Keeping the source under scripts/hooks/
# and copying it in makes the gate reproducible -- which is the difference between a gate and
# a habit.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install-hooks.ps1
#
# ASCII-only on purpose (PowerShell 5.1 parses a BOM-less .ps1 as ANSI => CJK in source breaks it).

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$src  = Join-Path $root 'scripts\hooks'
$dst  = Join-Path $root '.git\hooks'

if (-not (Test-Path (Join-Path $root '.git'))) {
    Write-Output ("FAIL  not a git repository: " + $root)
    exit 1
}
if (-not (Test-Path $src)) {
    Write-Output ("FAIL  hook source dir missing: " + $src)
    exit 1
}

foreach ($f in @(Get-ChildItem $src -File)) {
    $target = Join-Path $dst $f.Name
    Copy-Item $f.FullName $target -Force
    Write-Output ("OK    installed " + $f.Name + "  (" + $f.Length + " bytes)")
}

Write-Output ''
Write-Output 'Hooks are in place. They run on the next git commit in this repository.'
Write-Output 'NOTE: .git/hooks/ is not versioned -- run this installer again after a fresh clone.'
