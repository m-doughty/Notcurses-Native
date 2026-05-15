#!/usr/bin/env bash
# Single source of truth for "is this DLL a Windows system DLL?"
# Sourced by both bundle-dll/action.yml's process_deps (the
# ldd walk + the objdump backstop) and its audit step.
#
# Function: is_system_dll <name> [path]
#   Returns 0 (success/true) if <name> is a DLL that ships with
#   every supported Windows version and must NOT be bundled.
#   <path> is an optional second arg used as a belt-and-braces
#   check — anything under C:\Windows is a system DLL regardless
#   of the name pattern. Callers that don't have a path (e.g.
#   the objdump-based walk, since PE import tables list names
#   only) can omit it; the name-based check is comprehensive
#   enough to stand alone.

# Long-standing Windows system DLLs. Maintained as a flat array
# (one entry per line for diff-friendliness). Lowercased; the
# function lowercases the input before comparison.
_WIN_SYS_DLLS=(
  # Kernel + CRT + low-level runtime.
  kernel32.dll kernelbase.dll ntdll.dll
  msvcrt.dll ucrtbase.dll msvcp_win.dll
  profapi.dll cryptbase.dll cryptsp.dll
  rpcrt4.dll combase.dll sechost.dll
  # User / shell / window manager.
  user32.dll advapi32.dll shell32.dll shlwapi.dll
  shcore.dll comctl32.dll comdlg32.dll
  uxtheme.dll dwmapi.dll imm32.dll
  userenv.dll version.dll
  # GDI + text rendering + Direct3D.
  gdi32.dll gdi32full.dll gdiplus.dll msimg32.dll
  usp10.dll d3d11.dll d3d9.dll dxgi.dll d2d1.dll
  dwrite.dll opengl32.dll dxva2.dll
  # COM / OLE / props.
  ole32.dll oleaut32.dll propsys.dll normaliz.dll
  # Security + crypto. bcryptprimitives is the crypto-primitives
  # backend that bcrypt forwards into on Win 10+.
  crypt32.dll secur32.dll bcrypt.dll bcryptprimitives.dll
  ncrypt.dll wldap32.dll
  # Networking.
  ws2_32.dll wsock32.dll iphlpapi.dll wininet.dll
  winhttp.dll urlmon.dll dnsapi.dll mpr.dll netapi32.dll
  # Power / config / install / diagnostics.
  setupapi.dll cfgmgr32.dll powrprof.dll
  cabinet.dll wtsapi32.dll winspool.drv
  psapi.dll dbghelp.dll mscoree.dll
  # Multimedia.
  winmm.dll avrt.dll avicap32.dll
  mfplat.dll mfreadwrite.dll mf.dll evr.dll
)

is_system_dll() {
  local name="$1"
  local path="${2:-}"

  # `tr`-based lowercasing for portability — bash 4+'s `${name,,}`
  # works on MSYS2 bash 5.x where this runs in CI, but the same
  # script is occasionally sourced for local diagnostics on macOS
  # where bash 3.2 doesn't support `${,,}`.
  local name_lc
  name_lc=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')

  # Windows API Set forwarders — always present in System32 on
  # Win 10+. Match by prefix.
  case "$name_lc" in
    api-ms-*|ext-ms-*|ms-win-*) return 0 ;;
  esac

  # Versioned runtime DLLs (different suffixes per VS toolchain
  # version): vcruntime140.dll, vcruntime140_1.dll, etc.
  # d3dcompiler_43.dll / _47.dll.
  case "$name_lc" in
    vcruntime*.dll|d3dcompiler_*.dll) return 0 ;;
  esac

  # Exact name match against the curated whitelist. Linear scan
  # is fine — ~60 entries × a few hundred DLLs per build = ~10k
  # comparisons, milliseconds total.
  local entry
  for entry in "${_WIN_SYS_DLLS[@]}"; do
    if [[ "$name_lc" == "$entry" ]]; then
      return 0
    fi
  done

  # Belt-and-braces: anything under C:\Windows is a system DLL
  # regardless of name. ldd's name reports occasionally lie on
  # CLANGARM64 (xtajit64 quirks); a path-based fallback protects
  # us from miscategorizing those entries.
  local path_lc
  path_lc=$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')
  case "$path_lc" in
    /c/windows/*|c:/windows/*|c:\\windows\\*) return 0 ;;
  esac

  return 1
}
