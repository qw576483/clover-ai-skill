# ============================================================================
#  compile-check.ps1 -- offline C# compile gate.
#
#  Compiles the project's OWN Unity assemblies with UNITY'S OWN bundled Roslyn
#  (csc.dll) plus the project's own .csproj reference list. No editor, no
#  batchmode, no test run, no rebuild of Library/ScriptAssemblies.
#
#  WHY THIS IS SHIPPED AS A SCRIPT (why it beats the `dotnet build -t:Rebuild`
#  recipe in reference/fast-compile-loop.md):
#    1. Toolchain = Unity's own csc + the project's own .csproj <HintPath> refs +
#       Library/ScriptAssemblies/*.dll + its own <DefineConstants>. `dotnet build`
#       uses whatever SDK is on PATH and whatever MSBuild resolves, so it drifts
#       from the editor's compile conditions (langversion / defines / SDK) and
#       goes green on code Unity will refuse, or red on code Unity accepts.
#    2. No MSBuild in the loop: the response file is built HERE and handed to csc
#       directly. That removes two measured fast-compile-loop.md pitfalls:
#         pit 1 -- MSBuild expands $(...) to EMPTY => zero sources compiled =>
#                  the only errors printed belong to third-party packages, which
#                  reads as "my code is clean". Here the source list comes from
#                  the csproj's own <Compile Include> items and a zero-source run
#                  is a hard FAIL, never a pass.
#         pit 2 -- `dotnet build` is incremental => a second run with no changes
#                  prints nothing => read as "zero errors". csc always compiles.
#    3. It REFUSES TO PASS when it cannot run: no Unity install => exit 2 with the
#       exact path it searched and what to install. (A gate that silently passes
#       when its toolchain is missing is pit 5: "the script does not report a
#       missing path, it reports other people's errors".)
#    4. Sources come from the .csproj, not from a hard-coded directory: Unity
#       writes one csproj per assembly, so `-Assembly auto` covers the Editor
#       assembly (Assets/**/Editor/** compiled with UNITY_EDITOR) as well. The
#       old recipe compiled Assets/Scripts only, which is exactly the blind spot
#       that let a CS0103 sit in an Editor script while every offline check
#       stayed green.
#    5. Every assembly that owns files inside <client>/Assets is compiled in ONE
#       invocation, so all compile errors show up in one pass.
#
#  KNOWN LIMITATION (read before trusting a PASS): the reference set is taken
#  from Library/ScriptAssemblies, i.e. Unity's LAST build. If you changed the
#  engine repo (or any local package with its own asmdef) and did not let Unity
#  rebuild, business code compiled against a stale engine DLL can PASS here and
#  still be red in the editor -- fast-compile-loop.md pit 4. Rebuild in the
#  editor first when the engine changed.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\compile-check.ps1 `
#        -Project <project root>                 # auto: every assembly owning Assets/**
#    powershell ... -Project <root> -Assembly <name|runtime|editor|auto>
#    powershell ... -Project <root> -Quiet 1     # print nothing on success
#
#  Exit codes: 0 = every selected assembly compiled; 1 = compile error, or an
#              assembly that could not be checked (zero sources, or a
#              <ProjectReference> whose built dll could not be located);
#              2 = environment / argument problem (no Unity, no csproj, bad path).
#
#  ASCII-only on purpose: Windows PowerShell 5.1 parses a BOM-less .ps1 as ANSI.
# ============================================================================
param(
    [string]$Project = '',
    [string]$Assembly = 'auto',
    [string]$LangVersion = '9.0',
    [string]$HubRoot = '',
    [string]$Quiet = '',
    [int]$MaxLogLines = 40
)
$ErrorActionPreference = 'Stop'

function Fail([object]$msg, [int]$code = 2) {
    # Callers write the message as a parenthesised concatenation with the exit code
    # after the closing paren, e.g.  Fail ('text' + $x + 'more', 2)  -- and PowerShell's
    # `,` binds LOOSER than `+`, so that call hands the 2-element ARRAY ('text...', 2)
    # to $msg and leaves $code at its default. Measured 2026-09-24: the code was glued
    # onto the message and the script exited 0 -- an environment failure reported as
    # success, which is the one thing this gate must never do. Both shapes are handled
    # here on purpose, so a wrong exit code can never be dropped silently again.
    if ($msg -is [array]) {
        $parts = @($msg)
        if ($parts.Count -ge 2) {
            $code = [int]$parts[$parts.Count - 1]
            $msg = [string]$parts[0]
        }
    }
    Write-Output ('FAIL compile-check: ' + [string]$msg)
    exit $code
}

# ---- Unity's bundled Roslyn, discovered by SEARCH (never by a pinned path) ----
# <ProgramFiles>\Unity\Hub\Editor\<editor>\Editor\Data\DotNetSdk\sdk\<sdk>\Roslyn\bincore\csc.dll
# Newest editor first, then newest SDK inside it. Versions are compared by
# numeric field (a string sort puts 6000.10.* before 6000.6.*, which is wrong).
function Get-VersionSortKey([string]$name) {
    $m = [regex]::Match($name, '^(\d+)\.(\d+)\.(\d+)')
    if (-not $m.Success) { return '000000.000000.000000' }
    return ('{0:D6}.{1:D6}.{2:D6}' -f [int]$m.Groups[1].Value,
            [int]$m.Groups[2].Value, [int]$m.Groups[3].Value)
}

function Get-UnityToolchain([string]$hub) {
    if (-not (Test-Path -LiteralPath $hub)) { return $null }
    $editors = @(Get-ChildItem -LiteralPath $hub -Directory -ErrorAction SilentlyContinue |
        Sort-Object { Get-VersionSortKey $_.Name } -Descending)
    foreach ($e in $editors) {
        $sdkRoot = Join-Path $e.FullName 'Editor\Data\DotNetSdk\sdk'
        if (-not (Test-Path -LiteralPath $sdkRoot)) { continue }
        $sdks = @(Get-ChildItem -LiteralPath $sdkRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object { Get-VersionSortKey $_.Name } -Descending)
        foreach ($s in $sdks) {
            $cand = Join-Path $s.FullName 'Roslyn\bincore\csc.dll'
            if (Test-Path -LiteralPath $cand) {
                $rt = Join-Path $e.FullName 'Editor\Data\NetCoreRuntime\dotnet.exe'
                $runner = ''
                if (Test-Path -LiteralPath $rt) { $runner = $rt }
                return [pscustomobject]@{
                    Csc    = $cand
                    Runner = $runner
                    Editor = $e.Name
                    Sdk    = $s.Name
                }
            }
        }
    }
    return $null
}

# ---- reference resolution (ProjectReference + HintPath) ----------------------
# A Unity-generated csproj names its references in TWO shapes, and they are two
# halves of ONE list:
#   <Reference Include="X"><HintPath>...</HintPath></Reference>  -- precompiled dll
#   <ProjectReference Include="X.csproj" />                      -- asmdef-referenced
#     assembly (engine package, UGUI, test runners). These carry NO HintPath.
# Honoring only <HintPath> drops the whole asmdef-referenced half; if the dropped
# half is the engine, every engine type in the caller's code turns into CS0246
# "type not found" -- a FALSE RED aimed at code that is fine. The dll a
# ProjectReference produces is looked for in this order:
#   Library\ScriptAssemblies   (Unity's last editor build)
#   <client>\Temp\bin\Debug    (the <OutputPath> Unity writes into every csproj)
#   <refProjDir>\Temp\bin\Debug, \bin\Debug, \bin\Release, \bin
# If none of them has it the assembly is reported UNRESOLVED and FAILS without
# running csc: never silently dropped (measured on a project that
# gets all 6 engine references this way).
# The located dll is also DATED against the newest source of the project it is
# supposed to have been built from. A dll older than that source is a stale-dll
# reference (fast-compile-loop pit 4 / the KNOWN LIMITATION in the header), whose
# CS0246/CS0117/CS0122 are artifacts of the stale build, not code errors. That is
# reported as STALE-REF with BOTH timestamps so the red is self-explaining.
function Resolve-ReferenceDll([string]$projFileName, [string]$refProjDir, [string]$clientDir,
                              [string]$scriptAsmDir) {
    $asm = [IO.Path]::GetFileNameWithoutExtension($projFileName)
    $refProj = ''
    if (-not [string]::IsNullOrWhiteSpace($refProjDir)) {
        $cand = Join-Path $refProjDir $projFileName
        if (Test-Path -LiteralPath $cand) { $refProj = $cand }
    }
    if ($refProj -ne '') {
        $m = [regex]::Match([IO.File]::ReadAllText($refProj), '<AssemblyName>([^<]+)</AssemblyName>')
        if ($m.Success) { $asm = $m.Groups[1].Value.Trim() }
    }
    # Priority order, first hit wins: ScriptAssemblies (Unity's last build) before
    # the project-local output folders. De-duplicated case-insensitively while
    # KEEPING that order -- the referencing and referenced project usually share
    # the client folder, and a lookup directory printed twice reads as two tries.
    $dirs = @()
    $seenDir = @{}
    foreach ($d in @($scriptAsmDir,
                     (Join-Path $clientDir 'Temp\bin\Debug'),
                     (Join-Path $refProjDir 'Temp\bin\Debug'),
                     (Join-Path $refProjDir 'bin\Debug'),
                     (Join-Path $refProjDir 'bin\Release'),
                     (Join-Path $refProjDir 'bin'))) {
        if ([string]::IsNullOrWhiteSpace($d)) { continue }
        $k = $d.ToLower()
        if ($seenDir.ContainsKey($k)) { continue }
        $seenDir[$k] = $true
        $dirs += $d
    }
    foreach ($d in $dirs) {
        $p = Join-Path $d ($asm + '.dll')
        if (Test-Path -LiteralPath $p) {
            return [pscustomobject]@{ Dll = $p; Asm = $asm; Proj = $refProj; Dirs = $dirs }
        }
    }
    return [pscustomobject]@{ Dll = ''; Asm = $asm; Proj = $refProj; Dirs = $dirs }
}

# Newest write time among a csproj's own <Compile Include> files (the source it
# claims to be built from). $null when the csproj is not on disk (package project
# that Unity did not generate a local csproj for), which disables staleness dating
# for that reference -- an unknown, never a pass.
function Get-NewestSourceTime([string]$projPath) {
    if ([string]::IsNullOrWhiteSpace($projPath)) { return $null }
    if (-not (Test-Path -LiteralPath $projPath)) { return $null }
    $dir = Split-Path -Parent $projPath
    $newest = $null
    foreach ($m in [regex]::Matches([IO.File]::ReadAllText($projPath), '<Compile\s+Include="([^"]+)"')) {
        $s = $m.Groups[1].Value
        if (-not [IO.Path]::IsPathRooted($s)) { $s = Join-Path $dir $s }
        if (-not (Test-Path -LiteralPath $s)) { continue }
        $w = (Get-Item -LiteralPath $s).LastWriteTime
        if (($newest -eq $null) -or ($w -gt $newest)) { $newest = $w }
    }
    return $newest
}

# ---- 1) locate the project and its Unity folder -----------------------------
if ([string]::IsNullOrWhiteSpace($Project)) { $Project = (Get-Location).Path }
if (-not (Test-Path -LiteralPath $Project)) {
    Fail ('-Project not found -> ' + $Project + ' ; pass -Project <project root containing client/>', 2)
}
$Project = (Resolve-Path -LiteralPath $Project).Path
$client = ''
if (Test-Path -LiteralPath (Join-Path $Project 'client\Assets')) {
    $client = Join-Path $Project 'client'
} elseif (Test-Path -LiteralPath (Join-Path $Project 'Assets')) {
    $client = $Project
} else {
    Fail ('no Unity project under ' + $Project + ' ; expected <root>\client\Assets or <root>\Assets', 2)
}
$assets = Join-Path $client 'Assets'
# WHY NOT INSIDE THE PROJECT (slice sink4, 2026-09-24): the rsp/log files below are pure
# build by-products, and the project's tmp-budget gate (template item 27 / SKILL 3.5) counts
# every file under <project>\.ai-tmp.  Writing them there leaked 2 files per assembly on
# EVERY run (measured: compile-<asm>.rsp + .log per assembly), which eats the file
# budget of a resource this script does not own -- and a leaked cache is exactly what that
# gate reports as "build cache inside .ai-tmp".  The system temp dir is the right place for
# build by-products; evidence the caller wants to KEEP must be copied out explicitly.
$tmp = Join-Path $env:TEMP 'clover-compile-check'
if (-not (Test-Path -LiteralPath $tmp)) { New-Item -ItemType Directory -Path $tmp -Force | Out-Null }

# ---- 2) toolchain -----------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($HubRoot)) { $HubRoot = Join-Path $env:ProgramFiles 'Unity\Hub\Editor' }
$tool = Get-UnityToolchain $HubRoot
if ($tool -eq $null) {
    Fail ("cannot find Unity's bundled csc.dll. Searched '" + (Join-Path $HubRoot '<editor version>') +
          "\Editor\Data\DotNetSdk\sdk\<sdk version>\Roslyn\bincore\csc.dll' for every installed editor/SDK " +
          'and found none. Install Unity through Unity Hub (the bundled DotNetSdk ships with it), then re-run ' +
          'this script -- or pass -HubRoot <path to the Unity Hub Editor folder>.', 2)
}
$dotnetExe = $tool.Runner
if ($dotnetExe -eq '') {
    $cmd = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($cmd -eq $null) {
        Fail ('Unity ' + $tool.Editor + " does not ship Editor\Data\NetCoreRuntime\dotnet.exe and 'dotnet' is not " +
              'on PATH, so csc.dll cannot be started. Install the .NET runtime or repair the Unity installation.', 2)
    }
    $dotnetExe = $cmd.Source
}

# ---- 3) references come from Unity's own build products ---------------------
$scriptAsmDir = Join-Path $client 'Library\ScriptAssemblies'
if (-not (Test-Path -LiteralPath $scriptAsmDir)) {
    Fail ('missing ' + $scriptAsmDir + ' -- the project has never been compiled by the editor. Open the project in ' +
          'Unity (via Unity Hub) once so Library/ScriptAssemblies exists, then re-run.', 2)
}

# ---- 4) pick the assembly (or assemblies) to compile ------------------------
# A "project assembly" is a csproj that owns at least one <Compile Include> file
# physically inside <client>\Assets. Unity also writes csprojs for package and
# engine assemblies (their sources live under Library/PackageCache, Packages\ or a
# sibling repo), and compiling those is not what this gate is for.
$csprojs = @(Get-ChildItem -LiteralPath $client -Filter *.csproj -File -ErrorAction SilentlyContinue)
if ($csprojs.Count -eq 0) {
    Fail ('no .csproj under ' + $client + ' -- in Unity, Edit > Preferences > External Tools > "Generate all ' +
          '.csproj files", let it regenerate, then re-run.', 2)
}
$owners = @()
foreach ($cp in $csprojs) {
    $txt = [IO.File]::ReadAllText($cp.FullName)
    $incs = @([regex]::Matches($txt, '<Compile\s+Include="([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
    $inside = 0
    foreach ($i in $incs) {
        $full = $i
        if (-not [IO.Path]::IsPathRooted($full)) { $full = Join-Path $cp.DirectoryName $i }
        if ($full.StartsWith($assets, [StringComparison]::OrdinalIgnoreCase)) { $inside++ }
    }
    $owners += [pscustomobject]@{ File = $cp; Text = $txt; Inside = $inside }
}
$selected = @()
if ([string]::IsNullOrWhiteSpace($Assembly) -or ($Assembly.Trim().ToLower() -eq 'auto')) {
    $selected = @($owners | Where-Object { $_.Inside -gt 0 })
    if ($selected.Count -eq 0) {
        Fail ('no .csproj owns any file under ' + $assets + ' -- nothing to compile. Pass -Assembly <name> ' +
              'explicitly (available: ' + (($owners | ForEach-Object { $_.File.BaseName }) -join ', ') + ').', 2)
    }
} else {
    $want = $Assembly.Trim()
    $alias = @{ 'runtime' = 'Assembly-CSharp'; 'editor' = 'Assembly-CSharp-Editor' }
    if ($alias.ContainsKey($want.ToLower())) { $want = $alias[$want.ToLower()] }
    $selected = @($owners | Where-Object { $_.File.BaseName -ieq $want })
    if ($selected.Count -eq 0) {
        Fail ('no csproj named ' + $want + ' under ' + $client + ' -- available: ' +
              (($owners | ForEach-Object { $_.File.BaseName }) -join ', '), 2)
    }
}

# ---- 5) compile, one csc invocation per assembly ---------------------------
$failed = @()
$staleSeen = $false
foreach ($o in $selected) {
    $base = $o.File.BaseName

    $refs = @()
    $taken = @{}
    $unresolved = @()
    $stale = @()
    $missing = @()

    # (a) <ProjectReference> -> the dll that referenced project builds.
    foreach ($m in [regex]::Matches($o.Text, '<ProjectReference\s+Include="([^"]+)"')) {
        $pr = $m.Groups[1].Value.Trim()
        $r = Resolve-ReferenceDll $pr $o.File.DirectoryName $client $scriptAsmDir
        if ($r.Dll -eq '') {
            $unresolved += ($pr + '  ->  looked for ' + $r.Asm + '.dll in: ' + ($r.Dirs -join ' | '))
            continue
        }
        $refs += $r.Dll
        $taken[$r.Asm.ToLower()] = $true
        $newest = Get-NewestSourceTime $r.Proj
        if ($newest -ne $null) {
            $dllTime = (Get-Item -LiteralPath $r.Dll).LastWriteTime
            if ($newest -gt $dllTime) {
                $stale += ($r.Asm + ': dll ' + $dllTime.ToString('yyyy-MM-dd HH:mm:ss') +
                           '  <  source ' + $newest.ToString('yyyy-MM-dd HH:mm:ss') +
                           '  (' + $r.Proj + ')')
            }
        }
    }

    # (b) <Reference><HintPath> -> a precompiled dll that must exist on disk.
    foreach ($m in [regex]::Matches($o.Text, '<HintPath>([^<]+)</HintPath>')) {
        $r = $m.Groups[1].Value.Trim()
        if (-not [IO.Path]::IsPathRooted($r)) { $r = Join-Path $o.File.DirectoryName $r }
        if (Test-Path -LiteralPath $r) {
            $refs += $r
            $taken[[IO.Path]::GetFileNameWithoutExtension($r).ToLower()] = $true
        } else {
            $missing += $r
        }
    }

    # (c) Unity's build products, for package assemblies referenced in neither of
    # the two shapes above -- minus this assembly's own output (referencing it
    # would duplicate every type) and minus everything already resolved in (a)/(b):
    # two paths for one assembly identity is CS1703, not a bigger reference set.
    $own = $base + '.dll'
    $refs += @(Get-ChildItem -LiteralPath $scriptAsmDir -Filter *.dll |
        Where-Object { $_.Name -ne $own } |
        Where-Object { -not $taken.ContainsKey([IO.Path]::GetFileNameWithoutExtension($_.Name).ToLower()) } |
        ForEach-Object { $_.FullName })
    $refs = @($refs | Sort-Object -Unique)

    if ($unresolved.Count -gt 0) {
        $failed += $base
        Write-Output ('FAIL  ' + $base + '  unresolved ProjectReference(s)=' + $unresolved.Count +
                      '  -- csc was NOT run: compiling without them would come out as CS0246 "type not found" ' +
                      'in this project''s own code, i.e. a false red. Let Unity rebuild Library\ScriptAssemblies ' +
                      '(or build the missing project) and re-run.')
        foreach ($u in $unresolved) { Write-Output ('      UNRESOLVED  ' + $u) }
        continue
    }

    $dm = [regex]::Match($o.Text, '<DefineConstants>([^<]+)</DefineConstants>')
    $defs = ''
    if ($dm.Success) { $defs = $dm.Groups[1].Value.Trim() }

    # sources = the csproj's OWN list (this is what makes the count trustworthy)
    $sources = @()
    foreach ($m in [regex]::Matches($o.Text, '<Compile\s+Include="([^"]+)"')) {
        $s = $m.Groups[1].Value
        if (-not [IO.Path]::IsPathRooted($s)) { $s = Join-Path $o.File.DirectoryName $s }
        if (Test-Path -LiteralPath $s) { $sources += $s }
    }
    $sources = @($sources | Sort-Object -Unique)

    $rsp = Join-Path $tmp ('compile-' + $base + '.rsp')
    $log = Join-Path $tmp ('compile-' + $base + '.log')
    $out = Join-Path $tmp ($base + '.Check.dll')

    if ($sources.Count -eq 0) {
        $failed += $base
        Write-Output ('FAIL  ' + $base + '  sources=0  -- the csproj lists no existing source file; a gate that ' +
                      'compiles nothing must not report success')
        continue
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('-target:library')
    $lines.Add('-nologo')
    $lines.Add('-nullable:disable')
    $lines.Add('-warn:4')
    $lines.Add('-langversion:' + $LangVersion)
    $lines.Add('-out:"' + $out + '"')
    # Only when the csproj HAS defines: a bare '-define:' makes csc fail with
    # CS2006 ("option -define: requires <text>"), i.e. an assembly reported as a
    # compile error over a shape the csproj is allowed to have. Real Unity csprojs
    # always carry DefineConstants, but a hand-written / trimmed csproj does not.
    if ($defs -ne '') { $lines.Add('-define:' + $defs) }
    foreach ($r in $refs) { $lines.Add('-r:"' + $r + '"') }
    foreach ($s in $sources) { $lines.Add('"' + $s + '"') }
    [IO.File]::WriteAllLines($rsp, $lines.ToArray(), (New-Object System.Text.UTF8Encoding($false)))

    $raw = & $dotnetExe exec $tool.Csc ('@' + $rsp) 2>&1
    $code = $LASTEXITCODE
    $text = ($raw | Out-String)
    [IO.File]::WriteAllText($log, $text, (New-Object System.Text.UTF8Encoding($false)))

    if ($code -eq 0) {
        if ($Quiet -eq '') {
            Write-Output ('PASS  ' + $base + '  sources=' + $sources.Count + ' refs=' + $refs.Count +
                          '  log=' + $log)
        }
    } else {
        $failed += $base
        Write-Output ('FAIL  ' + $base + '  sources=' + $sources.Count + ' refs=' + $refs.Count +
                      '  csc_exit=' + $code + '  log=' + $log)
        $errs = @($raw | Where-Object { $_ -match 'error [A-Z]{2}\d+' })
        if ($errs.Count -eq 0) { $errs = @($raw) }
        $show = $errs.Count
        if (($MaxLogLines -gt 0) -and ($show -gt $MaxLogLines)) { $show = $MaxLogLines }
        for ($i = 0; $i -lt $show; $i++) { Write-Output ('      ' + ([string]$errs[$i]).Trim()) }
        if ($show -lt $errs.Count) {
            Write-Output ('      ... and ' + ($errs.Count - $show) + ' more line(s); full log = ' + $log)
        }
    }

    # Reference diagnosis, printed AFTER the status line so the verdict stays the
    # first thing a caller reads. Silence on success is the -Quiet contract; a
    # failing assembly always gets these lines because they can be the whole story.
    if (($Quiet -eq '') -or ($code -ne 0)) {
        foreach ($s in $stale) { Write-Output ('      STALE-REF  ' + $s) }
        if ($stale.Count -gt 0) {
            $staleSeen = $true
            Write-Output ('      ... STALE-REF means the dll is OLDER than the source of the project it should ' +
                          'have been built from, so errors naming engine/package types can be stale-dll ' +
                          'artifacts (fast-compile-loop pit 4), not defects in this project''s code.')
        }
        foreach ($x in $missing) { Write-Output ('      UNRESOLVED-HINTPATH  ' + $x) }
    }
}

# ---- 6) summary -------------------------------------------------------------
if ($staleSeen -and (($Quiet -eq '') -or ($failed.Count -gt 0))) {
    Write-Output ('HINT  at least one referenced assembly is STALE (see STALE-REF above): rebuild in the editor, ' +
                  'then re-run this gate before chasing the compile errors.')
}
if ($failed.Count -gt 0) {
    Write-Output ('===== compile-check: FAIL (' + $failed.Count + ' of ' + $selected.Count +
                  ' assembly/assemblies: ' + ($failed -join ', ') + ') =====')
    exit 1
}
# -Quiet: nothing at all on success (the caller reads the exit code). Failures
# always print -- silence about a failure would be the worst of both worlds.
if ($Quiet -eq '') {
    Write-Output ('csc=' + $tool.Csc)
    Write-Output ('runner=' + $dotnetExe)
    Write-Output ('client=' + $client)
    Write-Output ('===== compile-check: PASS (' + $selected.Count + ' assembly/assemblies, editor=' +
                  $tool.Editor + ', sdk=' + $tool.Sdk + ') =====')
}
exit 0
