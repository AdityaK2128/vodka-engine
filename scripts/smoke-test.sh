#!/bin/bash
# Quick checks that a built engine works: it starts, creates a Windows environment, finds its
# bundled fonts/TLS libraries, and exposes what Apple's D3DMetal needs from winemac.drv.
#
#   scripts/smoke-test.sh <engine>
set -uo pipefail

ENGINE="$(cd "${1:?usage: smoke-test.sh <engine>}" && pwd)"
WINE="$ENGINE/bin/wine"
failed=0
pass() { echo "  ✓ $1"; }
fail() { echo "  ✗ $1"; failed=1; }
# macOS has no `timeout`.
limit() { local seconds="$1"; shift; perl -e 'alarm shift; exec @ARGV' "$seconds" "$@"; }

echo "Engine: $ENGINE"
if version="$("$WINE" --version 2>&1)"; then pass "starts: $version"; else fail "starts: $version"; fi
if [ -n "$(ls "$ENGINE/share/wine/mono" 2>/dev/null)" ] && [ -n "$(ls "$ENGINE/share/wine/gecko" 2>/dev/null)" ]; then
  pass "Mono and Gecko bundled"; else fail "Mono and Gecko bundled"; fi
if [ -f "$ENGINE/lib/wine/x86_64-windows/kernel32.dll" ] && [ -f "$ENGINE/lib/wine/i386-windows/kernel32.dll" ]; then
  pass "32-bit and 64-bit Windows DLLs"; else fail "32-bit and 64-bit Windows DLLs"; fi

echo "winemac.drv exports used by D3DMetal:"
nm -gU "$ENGINE/lib/wine/x86_64-unix/winemac.so" 2>/dev/null | grep -i macdrv_ | head -20
if nm -gU "$ENGINE/lib/wine/x86_64-unix/winemac.so" 2>/dev/null | grep -q macdrv_functions; then
  pass "macdrv_functions exported"; else fail "macdrv_functions exported"; fi

export WINEPREFIX="$(mktemp -d)/prefix"
export WINEDEBUG="err+all,fixme-all"
log="$(mktemp)"
echo "Creating a Windows environment in $WINEPREFIX"
limit 600 "$WINE" wineboot --init >"$log" 2>&1
limit 120 "$ENGINE/bin/wineserver" -w
if [ -f "$WINEPREFIX/system.reg" ]; then pass "wineboot created the registry"; else fail "wineboot created the registry"; fi
if limit 120 "$WINE" cmd /c ver 2>>"$log" | grep -q Windows; then pass "cmd.exe runs"; else fail "cmd.exe runs"; fi
if grep -q -i "cannot find the FreeType" "$log"; then fail "FreeType found"; else pass "FreeType found"; fi
if grep -q -i -E "libgnutls.*(not found|failed)" "$log"; then fail "GnuTLS found"; else pass "GnuTLS found"; fi
if grep -q -i -E "(libvulkan|libMoltenVK).*(not found|failed)" "$log"; then fail "MoltenVK found"; else pass "MoltenVK found"; fi
"$ENGINE/bin/wineserver" -k 2>/dev/null
echo "--- Wine messages (first 60 lines) ---"
head -n 60 "$log"
exit $failed
