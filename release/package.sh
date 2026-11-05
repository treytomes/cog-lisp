#!/usr/bin/env bash
# ===========================================================================
#  cog-lisp : package a release  (specs/phase-8.9-ci-cd.md section 4.2)
#    release/package.sh VERSION
#  Run on Linux, after bootstrap-pharo.sh and build-image.sh. Writes to dist/:
#    cog-lisp-VERSION-linux-x86_64.tar.gz    the Linux VM, image, launcher, lib, examples
#    cog-lisp-VERSION-windows-x86_64.zip     the same with the Windows VM
#  The image is the same file in both: a Spur image runs on any platform's VM.
#  The Windows VM is the one pinned in pharo.pins, downloaded (and kept in
#  pharo/downloads/) if missing, and checked against its SHA-256.
# ===========================================================================
set -euo pipefail

VERSION="${1:?usage: release/package.sh VERSION}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
. "$ROOT/pharo.pins"
WIN_VM_ZIP="pharo/downloads/pharo-vm-windows.zip"
DIST="$ROOT/dist"
STAGE="$DIST/stage"
NAME="cog-lisp-$VERSION"

[ -f pharo/cog-lisp.image ] || { echo "package: no pharo/cog-lisp.image - run build-image.sh first" >&2; exit 1; }
[ -x pharo/pharo ] || { echo "package: no Linux VM in pharo/ - run bootstrap-pharo.sh on Linux first" >&2; exit 1; }
SOURCES="$(ls pharo/Pharo*.sources | head -n 1)"

if [ ! -f "$WIN_VM_ZIP" ] || [ "$(sha256sum "$WIN_VM_ZIP" | cut -d' ' -f1)" != "$VM_WINDOWS_SHA256" ]; then
  echo "[down] Windows VM (pinned)"
  curl -L --fail --silent --show-error -o "$WIN_VM_ZIP" "$VM_WINDOWS_URL"
fi
if [ "$(sha256sum "$WIN_VM_ZIP" | cut -d' ' -f1)" != "$VM_WINDOWS_SHA256" ]; then
  echo "package: the Windows VM does not match its pin in pharo.pins" >&2
  exit 1
fi

rm -rf "$STAGE"
mkdir -p "$STAGE" "$DIST"

# what every bundle has: the image, the LISP library, the examples, the notes
common() {   # $1 the bundle's folder
  local d="$1"
  mkdir -p "$d/pharo" "$d/scripts"
  cp pharo/cog-lisp.image pharo/cog-lisp.changes "$SOURCES" "$d/pharo/"
  cp -r lib examples "$d/"
  cp LICENSE release/INSTALL.md release/THIRD-PARTY-NOTICES.md README.md "$d/"
  cp cog-lisp.sh "$d/"
  cp scripts/pharo-vm.sh "$d/scripts/"
  chmod +x "$d/cog-lisp.sh"
}

# --- Linux -------------------------------------------------------------------
L="$STAGE/linux/$NAME"
common "$L"
cp -r pharo/pharo pharo/bin pharo/lib "$L/pharo/"
tar -czf "$DIST/$NAME-linux-x86_64.tar.gz" -C "$STAGE/linux" "$NAME"
echo "[ok  ] $DIST/$NAME-linux-x86_64.tar.gz"

# --- Windows -----------------------------------------------------------------
W="$STAGE/windows/$NAME"
common "$W"
cp cog-lisp.bat "$W/"
unzip -q -o "$WIN_VM_ZIP" -d "$W/pharo"
(cd "$STAGE/windows" && zip -q -r "$DIST/$NAME-windows-x86_64.zip" "$NAME")
echo "[ok  ] $DIST/$NAME-windows-x86_64.zip"
