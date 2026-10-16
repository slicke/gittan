<#
make.ps1 - the Makefile's targets for Windows, where there is no make.

Usage:
  .\make.ps1 [build|debug|rebuild|run|lexlib|test|clean|help] [lazbuild-args...]
  .\make.ps1 [lazbuild-args...]

 - Finds lazbuild as Trndi's make.ps1 does: LAZBUILD, then PATH, then
   C:\lazarus\lazbuild.exe and C:\fpcupdeluxe\lazarus\lazbuild.exe.
 - With no fpc on PATH (fpcupdeluxe puts none there), uses the fpc\bin\<cpu>-win64
   found beside lazbuild's directory, for the test target.
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
$DebugFlags = @('--opt=-g', '--opt=-gl')

$lazCandidates = @('C:\lazarus\lazbuild.exe', 'C:\fpcupdeluxe\lazarus\lazbuild.exe')

function Find-Lazbuild {
    if ($env:LAZBUILD -and (Test-Path $env:LAZBUILD)) { return $env:LAZBUILD }
    $cmd = Get-Command lazbuild -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Path }
    return $lazCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
$laz = Find-Lazbuild

# fpcupdeluxe keeps FPC beside its Lazarus, in fpc\bin\<cpu>-win64, and puts
# neither on PATH; lazbuild finds it through its lazarus.cfg, the test target
# calls fpc by name. PATH changes for this process only.
if ($laz -and -not (Get-Command fpc -ErrorAction SilentlyContinue)) {
    $fpcRoot = Join-Path (Split-Path -Parent (Split-Path -Parent $laz)) 'fpc\bin'
    $nativeCpu = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'aarch64' } else { 'x86_64' }
    $fpcBin = @(Join-Path $fpcRoot "$nativeCpu-win64") +
        @(Get-ChildItem $fpcRoot -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { $_.FullName }) |
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

function Invoke-Lazbuild([string[]]$Flags) {
    Need-Lazbuild
    Copy-Lexers
    Write-Host "Running: $laz $($Flags -join ' ') $Lpi" -ForegroundColor Cyan
    & $laz @Flags $Lpi
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$target = if ($MakeArgs.Count -ge 1) { $MakeArgs[0].ToLower() } else { 'build' }
$rest = if ($MakeArgs.Count -gt 1) { @($MakeArgs[1..($MakeArgs.Count - 1)]) } else { @() }

switch ($target) {
    'build' { Invoke-Lazbuild (@($LazFlags) + $rest); exit 0 }
    'debug' { Invoke-Lazbuild (@($LazFlags) + $DebugFlags + $rest); exit 0 }
    'rebuild' { Invoke-Lazbuild (@('--build-all') + $LazFlags + $rest); exit 0 }
    'run' {
        # Arguments after 'run' go to Gittan, not lazbuild.
        Invoke-Lazbuild $LazFlags
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
    'test' {
        if (-not (Get-Command fpc -ErrorAction SilentlyContinue)) {
            Write-Error 'fpc not found on PATH or beside lazbuild.'; exit 1
        }
        New-Item -ItemType Directory -Path 'tests\lib' -Force | Out-Null
        & fpc -Mobjfpc -Sh -O1 '-Fu.' '-FUtests\lib' '-FEtests' 'tests\gittantests.lpr'
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        & 'tests\gittantests.exe' --all --format=plain @rest
        exit $LASTEXITCODE
    }
    'clean' {
        foreach ($p in @('lib', $LexLib, 'tests\lib', 'Gittan.exe', 'tests\gittantests.exe')) {
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
