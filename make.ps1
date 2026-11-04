<#
make.ps1 - the Makefile's targets for Windows, where there is no make.

Usage:
  .\make.ps1 [build|debug|rebuild|run|lexlib|deps|ide|outdated|vendor-check|test|clean|help] [lazbuild-args...]
  .\make.ps1 [lazbuild-args...]

 - Finds lazbuild as Trndi's make.ps1 does: LAZBUILD, then PATH, then
   C:\lazarus\lazbuild.exe and C:\fpcupdeluxe\lazarus\lazbuild.exe.
 - With no fpc on PATH (neither installer puts it there), uses the one that
   came with lazbuild, for the test target: fpc\bin\<cpu>-win64 beside
   fpcupdeluxe's lazarus folder, or fpc\<version>\bin\<cpu>-win64 inside the
   Lazarus installer's folder.
 - Every build copies the lexers into lexlib\ first, as the Makefile does.
 - Arguments after a target go to lazbuild (to Gittan for run, to the test
   runner for test); unknown arguments are forwarded to lazbuild as they are.
#>

param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$MakeArgs
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$Lpi = 'Gittan.lpi'
$LexersSrc = 'vendor\CudaText-lexers'
$LexersOwn = 'lexers'
$LexLib = 'lexlib'
$LazFlags = @('--widgetset=win32')
# Gittan.lpi's Release mode (-O2, no debug info, smart linked, stripped) for
# build, rebuild and run, as CI ships it; its Default mode for debug.
$ReleaseFlags = @('--bm=Release')
$DebugFlags = @('--bm=Default', '--opt=-g', '--opt=-gl')

# Vendored packages, in dependency order, as VENDOR_PACKAGES in the Makefile
# and in .github/workflows/build.yml; a new package goes in all three.
$VendorPackages = @(
    'vendor\ATFlatControls\atflatcontrols\atflatcontrols_package.lpk',
    'vendor\EncConv\encconv\encconv_package.lpk',
    'vendor\BGRABitmap\bgrabitmap\bgrabitmappack.lpk',
    'vendor\ATSynEdit\atsynedit\atsynedit_package.lpk',
    'vendor\EControl\econtrol\econtrol_package.lpk',
    'vendor\ATSynEdit_Ex\atsynedit_ex\atsynedit_ex_package.lpk',
    'vendor\metadarkstyle\metadarkstyle.lpk',
    'vendor\lazink\lazink.lpk'
)

# Before every build Test-Vendor warns, as the Makefile's vendor-check does,
# when a submodule is not at the commit Gittan records and when a package the
# IDE is built with has moved since the last ide target, which writes their
# commits into $IdeStamp. 'outdated' fetches the remotes and lists what
# upstream has that the checkout lacks.
$IdeVendor = @('vendor/ATFlatControls', 'vendor/EncConv', 'vendor/BGRABitmap', 'vendor/ATSynEdit')
$IdeStamp = '.ide-vendor'

function Test-InGit {
    $ErrorActionPreference = 'Continue'  # git on stderr is no error here (Windows PowerShell 5.1)
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $false }
    & git rev-parse --git-dir *> $null
    return ($LASTEXITCODE -eq 0)
}

function Test-Vendor {
    $ErrorActionPreference = 'Continue'  # git on stderr is no error here (Windows PowerShell 5.1)
    if (-not (Test-InGit)) { return }
    foreach ($line in @(& git submodule status 2>$null)) {
        if ($line.Length -lt 2) { continue }
        $parts = $line.Substring(1).Trim().Split(' ')
        $sha = $parts[0]; $path = $parts[1]
        switch ($line[0]) {
            '-' { Write-Warning "$path is not checked out; run: git submodule update --init" }
            '+' {
                $rec = ((& git ls-files -s -- $path) -split ' ')[1]
                Write-Warning ("$path is at $($sha.Substring(0, 7)), Gittan records $($rec.Substring(0, 7)); " +
                    "run: git submodule update $path (or git add $path for a move you mean)")
            }
            'U' { Write-Warning "$path has a merge conflict" }
        }
    }
    if (Test-Path $IdeStamp) {
        $stamp = @(Get-Content $IdeStamp)
        $moved = @($IdeVendor | Where-Object { $stamp -notcontains "$(& git -C $_ rev-parse HEAD) $_" })
        if ($moved.Count -gt 0) {
            Write-Warning "the Lazarus IDE was built with older $($moved -join ' '); run: .\make.ps1 ide"
        }
    }
}

function Show-Outdated {
    $ErrorActionPreference = 'Continue'  # git on stderr is no error here (Windows PowerShell 5.1)
    foreach ($entry in @(& git config -f .gitmodules --get-regexp '\.path$')) {
        $d = ($entry -split ' ', 2)[1]
        & git -C $d fetch -q origin 2>$null
        if ($LASTEXITCODE -ne 0) { Write-Host "${d}: could not fetch origin"; continue }
        $up = & git -C $d symbolic-ref -q --short refs/remotes/origin/HEAD
        if (-not $up) {
            & git -C $d remote set-head origin -a *> $null
            $up = & git -C $d symbolic-ref -q --short refs/remotes/origin/HEAD
        }
        if (-not $up) { Write-Host "${d}: origin has no default branch"; continue }
        $n = [int](& git -C $d rev-list --count --no-merges "HEAD..$up")
        if ($n -eq 0) { Write-Host "${d}: up to date with $up"; continue }
        Write-Host "${d}: $n commit(s) behind $up"
        & git -C $d log --oneline --no-merges -10 "HEAD..$up" | ForEach-Object { Write-Host "    $_" }
    }
}

$lazCandidates = @('C:\lazarus\lazbuild.exe', 'C:\fpcupdeluxe\lazarus\lazbuild.exe')

function Find-Lazbuild {
    if ($env:LAZBUILD -and (Test-Path $env:LAZBUILD)) { return $env:LAZBUILD }
    $cmd = Get-Command lazbuild -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Path }
    return $lazCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
$laz = Find-Lazbuild

# fpcupdeluxe keeps FPC beside its Lazarus, in fpc\bin\<cpu>-win64, and the
# Lazarus installer inside it, in fpc\<version>\bin\<cpu>-win64; neither
# puts it on PATH. lazbuild finds it through its lazarus.cfg, the test target
# calls fpc by name. The native CPU's first, the newest version first. PATH
# changes for this process only.
if ($laz -and -not (Get-Command fpc -ErrorAction SilentlyContinue)) {
    $lazDir = Split-Path -Parent $laz
    $nativeCpu = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'aarch64' } else { 'x86_64' }
    $binRoots = @(Join-Path (Split-Path -Parent $lazDir) 'fpc\bin') +
        @(Get-ChildItem (Join-Path $lazDir 'fpc') -Directory -ErrorAction SilentlyContinue |
            Sort-Object { try { [version]$_.Name } catch { [version]'0.0' } } -Descending |
            ForEach-Object { Join-Path $_.FullName 'bin' })
    $fpcBin = $binRoots | ForEach-Object {
            $root = $_
            @(Join-Path $root "$nativeCpu-win64") +
                @(Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
                    ForEach-Object { $_.FullName })
        } |
        Where-Object { Test-Path (Join-Path $_ 'fpc.exe') } | Select-Object -First 1
    if ($fpcBin) { $env:PATH = "$fpcBin;$env:PATH" }
}

function Need-Lazbuild {
    if (-not $laz) { Write-Error 'lazbuild not found. Install Lazarus or set LAZBUILD.'; exit 1 }
}

# vendor\CudaText-lexers keeps each lexer in a folder of its own; Gittan loads
# *.lcf from one flat folder beside the executable.
function Copy-Lexers {
    if (-not (Test-Path (Join-Path $LexersSrc 'Pascal'))) {
        Write-Error "$LexersSrc is empty; run: git submodule update --init"
        exit 1
    }
    if (Test-Path $LexLib) { Remove-Item $LexLib -Recurse -Force }
    New-Item -ItemType Directory -Path $LexLib | Out-Null
    foreach ($dir in @($LexersSrc, $LexersOwn)) {
        Get-ChildItem $dir -Directory | ForEach-Object {
            Get-ChildItem $_.FullName -File |
                Where-Object { $_.Extension -in '.lcf', '.cuda-lexmap' } |
                Copy-Item -Destination $LexLib
        }
    }
    $count = @(Get-ChildItem $LexLib -Filter *.lcf).Count
    Write-Host "Copied $count lexers to $LexLib\"
}

# The extension engine (gittan.ext.quickjs) links quickjs-ng and its ABI
# shim, prebuilt in externals\quickjs\prebuilt\<cpu>-win64. Windows finds a
# DLL beside the executable, so they are copied next to Gittan.exe after a
# build and next to the test binary before the tests run. The CPU is the
# executable's own, read from its PE header: lazbuild's compiler may not be
# the native CPU's, and a DLL of another CPU stops the program before it
# starts (0xC000007B).
function Get-QjsDir([string]$Cpu) {
    Join-Path $PSScriptRoot "externals\quickjs\prebuilt\$Cpu-win64"
}

function Get-ExeCpu([string]$Exe) {
    $bytes = [System.IO.File]::ReadAllBytes($Exe)
    $pe = [BitConverter]::ToInt32($bytes, 0x3c)
    switch ([BitConverter]::ToUInt16($bytes, $pe + 4)) {
        0xAA64 { 'aarch64' }
        0x8664 { 'x86_64' }
        default { $null }
    }
}

function Copy-QuickJSLibs {
    param([string]$Exe = (Join-Path $PSScriptRoot 'Gittan.exe'))
    $cpu = Get-ExeCpu $Exe
    $dir = Get-QjsDir $cpu
    if (-not $cpu -or -not (Test-Path $dir)) {
        Write-Warning "No QuickJS libraries for $Exe ($cpu); the extensions will not start."
        return
    }
    foreach ($name in @('libqjs.dll', 'tqshim.dll')) {
        Copy-Item (Join-Path $dir $name) (Split-Path -Parent $Exe) -Force
    }
}

function Invoke-Lazbuild([string[]]$Flags) {
    Need-Lazbuild
    Test-Vendor
    Copy-Lexers
    Write-Host "Running: $laz $($Flags -join ' ') $Lpi" -ForegroundColor Cyan
    & $laz @Flags $Lpi
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$target = if ($MakeArgs.Count -ge 1) { $MakeArgs[0].ToLower() } else { 'build' }
$rest = if ($MakeArgs.Count -gt 1) { @($MakeArgs[1..($MakeArgs.Count - 1)]) } else { @() }

switch ($target) {
    'build' { Invoke-Lazbuild (@($LazFlags) + $ReleaseFlags + $rest); Copy-QuickJSLibs; exit 0 }
    'debug' { Invoke-Lazbuild (@($LazFlags) + $DebugFlags + $rest); Copy-QuickJSLibs; exit 0 }
    'rebuild' { Invoke-Lazbuild (@('--build-all') + $LazFlags + $ReleaseFlags + $rest); Copy-QuickJSLibs; exit 0 }
    'run' {
        # Arguments after 'run' go to Gittan, not lazbuild.
        Invoke-Lazbuild (@($LazFlags) + $ReleaseFlags)
        Copy-QuickJSLibs
        $startArgs = @{ FilePath = (Join-Path $PSScriptRoot 'Gittan.exe'); WorkingDirectory = $PSScriptRoot }
        if ($rest.Count -gt 0) {
            $startArgs.ArgumentList = @($rest | ForEach-Object {
                if ($_ -eq '' -or $_ -match '\s') { '"' + $_ + '"' } else { $_ }
            })
        }
        Start-Process @startArgs
        exit 0
    }
    'lexlib' { Copy-Lexers; exit 0 }
    'deps' {
        Need-Lazbuild
        foreach ($lpk in $VendorPackages) {
            if (-not (Test-Path $lpk)) {
                Write-Error "$lpk is missing; run: git submodule update --init"
                exit 1
            }
            & $laz --add-package-link $lpk
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
            & $laz @LazFlags @rest $lpk
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        }
        exit 0
    }
    'ide' {
        # The IDE's own build profile, its widgetset too. The arguments go
        # first: built with FPC 3.3.1, lazbuild takes one after an empty
        # --build-ide= for a short option and stops.
        Need-Lazbuild
        & $laz @rest --build-ide=
        $rc = $LASTEXITCODE
        if ($rc -eq 0 -and (Test-InGit)) {
            $IdeVendor | ForEach-Object { "$(& git -C $_ rev-parse HEAD) $_" } | Set-Content $IdeStamp
        }
        exit $rc
    }
    'vendor-check' { Test-Vendor; exit 0 }
    'outdated' { Show-Outdated; exit 0 }
    'test' {
        if (-not (Get-Command fpc -ErrorAction SilentlyContinue)) {
            Write-Error 'fpc not found on PATH or beside lazbuild.'; exit 1
        }
        New-Item -ItemType Directory -Path 'tests\lib' -Force | Out-Null
        $qjsDir = Get-QjsDir ((& fpc -iTP) | Out-String).Trim()
        & fpc -Mobjfpc -Sh -O1 '-Fusrc\core' '-Fusrc\proj' '-Fuvendor\toml-fp\src' '-FUtests\lib' '-FEtests' "-Fl$qjsDir" 'tests\gittantests.lpr'
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        Copy-QuickJSLibs (Join-Path $PSScriptRoot 'tests\gittantests.exe')
        & 'tests\gittantests.exe' --all --format=plain @rest
        exit $LASTEXITCODE
    }
    'clean' {
        foreach ($p in @('lib', $LexLib, 'tests\lib', 'Gittan.exe', 'tests\gittantests.exe',
                'libqjs.dll', 'tqshim.dll', 'tests\libqjs.dll', 'tests\tqshim.dll')) {
            if (Test-Path $p) { Remove-Item $p -Recurse -Force }
        }
        exit 0
    }
    'help' {
        Write-Host 'Targets:'
        Write-Host '  build     Build Gittan.lpi (default)'
        Write-Host '  debug     Build with debug info'
        Write-Host '  rebuild   Build with every unit recompiled'
        Write-Host "  run       Build, then start Gittan (arguments after 'run' go to Gittan)"
        Write-Host '  deps      Register the vendored packages with lazbuild and compile them'
        Write-Host '  ide       Rebuild the Lazarus IDE (after ATSynEdit, ATFlatControls, EncConv or BGRABitmap moves)'
        Write-Host "  outdated  Fetch the vendored packages' remotes and list the commits upstream is ahead"
        Write-Host '  test      Build and run the unit tests in tests\'
        Write-Host "  lexlib    Copy the lexers from $LexersSrc and $LexersOwn into $LexLib\ (part of every build)"
        Write-Host "  clean     Remove lib\, $LexLib\, the test build and the binary"
        Write-Host "Current: LAZBUILD=$laz"
        exit 0
    }
    default {
        Need-Lazbuild
        Write-Host "Forwarding to lazbuild: $laz $MakeArgs" -ForegroundColor Cyan
        & $laz @MakeArgs
        exit $LASTEXITCODE
    }
}
