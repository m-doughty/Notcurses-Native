param(
    [ValidateSet('prebuilt', 'source')]
    [string]$Mode = 'prebuilt'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$raku = $env:NOTCURSES_TEST_RAKU
if ([string]::IsNullOrWhiteSpace($raku)) {
    $raku = (Get-Command raku.exe -ErrorAction Stop).Path
}
if (-not (Test-Path -LiteralPath $raku -PathType Leaf)) {
    throw "native Raku executable does not exist: $raku"
}
$rakuDir = Split-Path -Parent $raku
$system32 = [Environment]::GetFolderPath([Environment+SpecialFolder]::System)
Remove-Item Env:NOTCURSES_NATIVE_LIB_DIR -ErrorAction SilentlyContinue

# Fail before changing PATH or loading a DLL when the workflow label disagrees
# with the durable provenance marker in the actual BINARY_TAG-keyed stage.
$stagedModeOutput = @(& $raku -Ilib -e 'use Notcurses::Native :INTERNAL; print _windows-staged-load-mode()')
$stagedModeExit = $LASTEXITCODE
$stagedMode = [string]($stagedModeOutput | Select-Object -Last 1)
if ($stagedModeExit -ne 0 -or [string]::IsNullOrWhiteSpace($stagedMode)) {
    throw 'could not determine the staged Notcurses loader mode'
}
$stagedMode = $stagedMode.Trim()
if ($stagedMode -ne $Mode) {
    throw "requested loader mode '$Mode' does not match staged mode '$stagedMode'"
}

# A prebuilt archive must be sibling-closed, so exclude every MSYS2/toolchain
# directory that could mask a missing bundled DLL. A source build deliberately
# retains ordinary MSYS2 dependencies. The MSYS2 build step records its real
# Windows runtime directory because a later pwsh step does not inherit the
# shell's $MINGW_PREFIX/bin path.
if ($Mode -eq 'prebuilt') {
    Remove-Item Env:NOTCURSES_TEST_MSYS2_BIN -ErrorAction SilentlyContinue
    $env:PATH = @($rakuDir, $system32, $env:SystemRoot) -join ';'
} else {
    $msys2Bin = $env:NOTCURSES_TEST_MSYS2_BIN
    if ([string]::IsNullOrWhiteSpace($msys2Bin)) {
        throw 'source mode requires NOTCURSES_TEST_MSYS2_BIN'
    }
    if (-not (Test-Path -LiteralPath $msys2Bin -PathType Container)) {
        throw "source-mode MSYS2 runtime directory does not exist: $msys2Bin"
    }
    $env:PATH = @($msys2Bin, $env:PATH) -join ';'
}

function Invoke-RakuChecked {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    & $raku @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "raku failed with exit ${LASTEXITCODE}: $($Arguments -join ' ')"
    }
}

# Default BINARY_TAG-keyed staged-directory path.
Invoke-RakuChecked @('-Ilib', 't/18-full-library-load.rakutest')

# Resolve the same pack, then prove the explicit override takes the identical
# dependency-search path even when the default data root cannot be used.
$fullLibraryOutput = @(& $raku -Ilib -e 'use Notcurses::Native; print nc-lib()')
$fullLibrary = [string]($fullLibraryOutput | Select-Object -Last 1)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($fullLibrary)) {
    throw 'could not resolve the installed full notcurses library'
}
$fullLibrary = $fullLibrary.Trim()
if (-not (Test-Path -LiteralPath $fullLibrary -PathType Leaf)) {
    throw "resolved full notcurses library does not exist: $fullLibrary"
}

$env:NOTCURSES_NATIVE_LIB_DIR = Split-Path -Parent $fullLibrary
$env:NOTCURSES_NATIVE_DATA_DIR = Join-Path $env:RUNNER_TEMP 'notcurses-missing-data-root'
Invoke-RakuChecked @('-Ilib', 't/18-full-library-load.rakutest')
