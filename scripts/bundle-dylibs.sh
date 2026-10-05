#!/bin/bash
# Makes a Wine install self-contained: copies every Homebrew library it needs (and their
# dependencies) into <engine>/lib and points all references at those copies, so the engine runs
# on Macs without Homebrew.
#
#   scripts/bundle-dylibs.sh <engine>
set -euo pipefail

ENGINE="${1:?usage: bundle-dylibs.sh <engine>}"
LIB="$ENGINE/lib"
BREW="$(brew --prefix)"
mkdir -p "$LIB"

is_external() { case "$1" in /usr/local/*|/opt/homebrew/*) return 0 ;; *) return 1 ;; esac; }
deps_of() { otool -L "$1" | tail -n +2 | awk '{print $1}'; }

# Libraries Wine opens by name at runtime (invisible to otool), plus everything linked directly.
queue=()
for name in libfreetype.6.dylib libgnutls.30.dylib libMoltenVK.dylib; do
  [ -e "$BREW/lib/$name" ] && queue+=("$BREW/lib/$name")
done
while IFS= read -r -d '' file; do
  for dep in $(deps_of "$file"); do is_external "$dep" && queue+=("$dep"); done
done < <(find "$ENGINE/bin" "$ENGINE/lib/wine" -type f \( -perm -u+x -o -name '*.so' \) -print0)

# Copy the transitive closure, named by the leaf name other files refer to.
copied=" "
while [ ${#queue[@]} -gt 0 ]; do
  path="${queue[0]}"; queue=("${queue[@]:1}")
  leaf="$(basename "$path")"
  case "$copied" in *" $leaf "*) continue ;; esac
  real="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$path")"
  [ -f "$real" ] || { echo "warning: $path not found" >&2; continue; }
  cp -f "$real" "$LIB/$leaf"
  chmod u+w "$LIB/$leaf"
  copied="$copied$leaf "
  for dep in $(deps_of "$real"); do is_external "$dep" && queue+=("$dep"); done
done
echo "Bundled:$copied"

# Rewrite references: bundled libraries find each other next to themselves; Wine's own binaries
# find them through the rpaths set at build time.
fix() {
  local file="$1" prefix="$2"
  for dep in $(deps_of "$file"); do
    is_external "$dep" && install_name_tool -change "$dep" "$prefix/$(basename "$dep")" "$file" 2>/dev/null
  done
  return 0
}
for leaf in $copied; do
  install_name_tool -id "@rpath/$leaf" "$LIB/$leaf"
  fix "$LIB/$leaf" "@loader_path"
done
while IFS= read -r -d '' file; do
  fix "$file" "@rpath"
done < <(find "$ENGINE/bin" "$ENGINE/lib/wine" -type f \( -perm -u+x -o -name '*.so' \) -print0)

# install_name_tool invalidates signatures; re-sign ad hoc.
find "$LIB" "$ENGINE/bin" "$ENGINE/lib/wine" -type f \( -name '*.dylib' -o -name '*.so' -o -perm -u+x \) -print0 |
  while IFS= read -r -d '' file; do
    file "$file" | grep -q Mach-O && codesign --force --sign - "$file" 2>/dev/null || true
  done

# Nothing may still point into Homebrew.
left=$(find "$ENGINE" -type f \( -name '*.dylib' -o -name '*.so' -o -perm -u+x \) -print0 |
  xargs -0 -n1 sh -c 'otool -L "$0" 2>/dev/null | tail -n +2 | grep -E "/usr/local/|/opt/homebrew/" | sed "s|^|$0: |"' || true)
if [ -n "$left" ]; then
  echo "$left" >&2
  echo "error: some files still use Homebrew libraries" >&2
  exit 1
fi
echo "All libraries bundled."
