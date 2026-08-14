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

# Exclude every MSYS2/toolchain directory. Those directories contain many
# of the same FFmpeg/ncurses DLLs as the published pack and previously made
# CI green even though a normal installed application failed with 0x7e.
$env:PATH = @($rakuDir, $system32, $env:SystemRoot) -join ';'
Remove-Item Env:NOTCURSES_NATIVE_LIB_DIR -ErrorAction SilentlyContinue

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
