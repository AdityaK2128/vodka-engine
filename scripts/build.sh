#!/bin/bash
# Builds CrossOver's open-source Wine for macOS (x86_64, new WoW64) into a self-contained folder
# that Vodka can install as an engine, then packages it into dist/.
#
#   scripts/build.sh [crossover-version]        # default 26.3.0
#
# Needs (Homebrew, x86_64): bison mingw-w64 freetype gnutls molten-vk pkgconf
# Environment: WORK (scratch folder, default ./work), JOBS (parallel jobs).
set -euo pipefail

CX_VERSION="${1:-26.3.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${WORK:-$ROOT/work}"
DIST="$ROOT/dist"
OUT="$WORK/wine"                      # the engine: bin/ lib/ share/
JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"
BREW="$(brew --prefix)"
SOURCE_URL="https://media.codeweavers.com/pub/crossover/source/crossover-sources-$CX_VERSION.tar.gz"

[ "$(uname -m)" = x86_64 ] || { echo "Build on an Intel Mac or under Rosetta (arch -x86_64)." >&2; exit 1; }
mkdir -p "$WORK" "$DIST"
cd "$WORK"

step() { echo; echo "==> $*"; }

# 1. Source -------------------------------------------------------------------------------------
step "Fetching CrossOver $CX_VERSION source"
if [ ! -f "crossover-sources-$CX_VERSION.tar.gz" ]; then
  curl -fL --retry 3 -o "crossover-sources-$CX_VERSION.tar.gz" "$SOURCE_URL"
fi
if [ ! -d src/sources/wine ]; then
  mkdir -p src
  tar -xzf "crossover-sources-$CX_VERSION.tar.gz" -C src sources/wine
fi
WINE_SRC="$WORK/src/sources/wine"
WINE_VERSION="$(sed -e 's/Wine version //' "$WINE_SRC/VERSION")"
echo "Wine $WINE_VERSION"

# 2. Configure ----------------------------------------------------------------------------------
step "Configuring"
export PATH="$BREW/opt/bison/bin:$BREW/opt/mingw-w64/bin:$BREW/bin:$PATH"
export PKG_CONFIG_PATH="$BREW/opt/freetype/lib/pkgconfig:$BREW/opt/gnutls/lib/pkgconfig:$BREW/lib/pkgconfig"
export MACOSX_DEPLOYMENT_TARGET=11.0
export CPPFLAGS="-I$BREW/include"
# Wine dlopens freetype, gnutls and MoltenVK by file name; these rpaths make it find the copies
# bundled in <engine>/lib (from bin/ and from lib/wine/x86_64-unix/).
export LDFLAGS="-L$BREW/lib -Wl,-rpath,@loader_path/../lib -Wl,-rpath,@loader_path/../../"
# Keep winemac.drv's Metal helpers visible to dlsym: Apple's D3DMetal looks them up at runtime.
export CFLAGS="-O2 -fvisibility=default"
export CROSSCFLAGS="-O2"
if command -v ccache >/dev/null; then export CC="ccache clang" CXX="ccache clang++"; fi

mkdir -p build
cd build
if [ ! -f Makefile ]; then
  "$WINE_SRC/configure" \
    --prefix="$OUT" \
    --enable-archs=i386,x86_64 \
    --disable-tests \
    --without-x \
    --without-gstreamer \
    --without-sdl \
    --with-freetype \
    --with-gnutls \
    --with-vulkan \
    || { tail -n 80 config.log; exit 1; }
fi
for feature in freetype gnutls vulkan; do
  grep -q "SONAME_LIB$(echo $feature | tr a-z A-Z)" include/config.h && echo "  $feature: yes" || echo "  $feature: NOT FOUND"
done
grep -E "SONAME_LIB(FREETYPE|GNUTLS|VULKAN|MOLTENVK)" include/config.h || true

# 3. Build --------------------------------------------------------------------------------------
step "Building with $JOBS jobs"
make -j"$JOBS"
rm -rf "$OUT"
make install-lib >/dev/null
cd "$WORK"

# 4. Make it self-contained ---------------------------------------------------------------------
step "Bundling libraries"
"$ROOT/scripts/bundle-dylibs.sh" "$OUT"

step "Adding Wine Mono and Gecko"
MONO="$(sed -n 's/.*WINE_MONO_VERSION "\(.*\)".*/\1/p' "$WINE_SRC/dlls/mscoree/mscoree_private.h")"
GECKO="$(sed -n 's/.*define GECKO_VERSION "\(.*\)".*/\1/p' "$WINE_SRC/dlls/appwiz.cpl/addons.c")"
mkdir -p "$OUT/share/wine/mono" "$OUT/share/wine/gecko"
curl -fL --retry 3 "https://dl.winehq.org/wine/wine-mono/$MONO/wine-mono-$MONO-x86.tar.xz" | tar -xJ -C "$OUT/share/wine/mono"
for arch in x86 x86_64; do
  curl -fL --retry 3 "https://dl.winehq.org/wine/wine-gecko/$GECKO/wine-gecko-$GECKO-$arch.tar.xz" | tar -xJ -C "$OUT/share/wine/gecko"
done
echo "Mono $MONO, Gecko $GECKO"

# Tools that expect the older name find the new-WoW64 loader too.
[ -e "$OUT/bin/wine64" ] || ln -s wine "$OUT/bin/wine64"

# 5. Package ------------------------------------------------------------------------------------
step "Packaging"
NAME="vodka-wine-cx$CX_VERSION-x86_64"
cat > "$OUT/vodka-engine.json" <<EOF
{
  "name": "Wine $WINE_VERSION (CrossOver $CX_VERSION source)",
  "wineVersion": "$WINE_VERSION",
  "crossoverVersion": "$CX_VERSION",
  "source": "$SOURCE_URL",
  "mono": "$MONO",
  "gecko": "$GECKO",
  "built": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
tar -C "$WORK" -cJf "$DIST/$NAME.tar.xz" wine
( cd "$DIST" && shasum -a 256 "$NAME.tar.xz" > "$NAME.tar.xz.sha256" )
ls -la "$DIST"
echo "Built $DIST/$NAME.tar.xz"
