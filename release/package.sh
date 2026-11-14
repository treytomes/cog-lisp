#!/usr/bin/env bash
# ===========================================================================
#  cog-lisp : package a release  (specs/14-phase-8.9-ci-cd.md section 4.2)
#    release/package.sh VERSION
#  Run on Linux, after bootstrap-pharo.sh and build-image.sh. Writes to dist/:
#    cog-lisp-VERSION-linux-x86_64.tar.gz    the Linux VM, image, launcher, lib, examples
#    cog-lisp-VERSION-windows-x86_64.zip     the same with the Windows VM
#  The image is the same file in both: a Spur image runs on any platform's VM.
#  Both VMs come from their pinned archives (pharo.pins), checked against their
#  SHA-256: the Linux one as bootstrap-pharo.sh left it in pharo/downloads/, the
#  Windows one downloaded there if missing. Each bundle carries only the VM files
#  listed below, and the license of everything it ships, in licenses/.
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

LINUX_VM_ZIP="pharo/downloads/pharo-vm-linux.zip"
if [ ! -f "$LINUX_VM_ZIP" ] || [ "$(sha256sum "$LINUX_VM_ZIP" | cut -d' ' -f1)" != "$VM_LINUX_SHA256" ]; then
  echo "package: $LINUX_VM_ZIP is missing or does not match its pin - run bootstrap-pharo.sh" >&2
  exit 1
fi

rm -rf "$STAGE"
mkdir -p "$STAGE" "$DIST"

# --- The VM files a bundle ships ---------------------------------------------
# Only these: the VM itself and its plugins (pharo-vm, MIT), libffi (MIT) and, on
# Windows, winpthreads (MIT and BSD), each with its license in licenses/ (see
# release/THIRD-PARTY-NOTICES.md). The rest of the VM archive is third-party
# libraries cog-lisp does not use (graphics, git, ssh, OpenSSL, compression,
# iconv, SDL, the JPEG plugin's libjpeg, a test library); every suite passes
# without them. A list of what to keep, not of what to drop, so a new VM build
# cannot slip a library (and a license) into a bundle unnoticed: a file missing
# from the archive, or one the archive has that is in neither list, stops the
# packaging until this list is updated.
VM_PLUGINS="B2DPlugin BitBltPlugin DSAPrims FileAttributesPlugin FilePlugin
  FloatArrayPlugin JPEGReaderPlugin LargeIntegers LocalePlugin MiscPrimitivePlugin
  NewFilePlugin SocketPlugin SqueakSSL SurfacePlugin UUIDPlugin"
LINUX_KEEP="pharo bin/pharo lib/pharo lib/pharo.signatures lib/libPharoVMCore.so
  lib/libffi.so lib/libtty.so lib/libUnixOSProcessPlugin.so
  $(for p in $VM_PLUGINS; do printf 'lib/lib%s.so ' "$p"; done)"
LINUX_DROP='^lib/lib(git2|ssh2|ssl|crypto|cairo|pixman-1|freetype|fontconfig|harfbuzz|png16|expat|bz2|SDL2-2\.0)\.so|^lib/lib(TestLibrary|JPEGReadWriter2Plugin)\.so$'
WINDOWS_KEEP="PharoConsole.exe PharoConsole.exe.manifest PharoVMCore.dll
  pharo.signatures ffi.dll libwinpthread-1.dll
  $(for p in $VM_PLUGINS; do printf '%s.dll ' "$p"; done)"
WINDOWS_DROP='^(Pharo\.exe|Pharo\.exe\.manifest|.*\.dll\.a|lib(git2|ssh2|ssl|crypto|cairo|pixman|freetype|fontconfig|harfbuzz|png16|expat|bz2|gcc_s_seh)-.*\.dll|libpng16\.dll|zlib1\.dll|iconv\.dll|SDL[23]\.dll|TestLibrary\.dll|JPEGReadWriter2Plugin\.dll)$'

# copy_vm FROM TO KEEP DROP: copy the KEEP files; fail on anything unlisted
copy_vm() {
  local from="$1" to="$2" keep="$3" drop="$4" f bad=0
  for f in $keep; do
    if [ -f "$from/$f" ]; then
      mkdir -p "$to/$(dirname "$f")"
      cp -p "$from/$f" "$to/$f"
    else
      echo "package: the VM has no $f (update the lists in release/package.sh)" >&2; bad=1
    fi
  done
  while IFS= read -r f; do
    case " $(echo $keep) " in *" $f "*) continue ;; esac
    echo "$f" | grep -Eq "$drop" && continue
    echo "package: the VM has $f, in neither list (check its license, then list it in release/package.sh)" >&2; bad=1
  done < <(cd "$from" && find . -type f | sed 's|^\./||' | sort)
  [ "$bad" = 0 ]
}

# what every bundle has: the image, the LISP library, the examples, the notes
common() {   # $1 the bundle's folder
  local d="$1"
  mkdir -p "$d/pharo" "$d/scripts" "$d/licenses" "$d/tools"
  cp pharo/cog-lisp.image pharo/cog-lisp.changes "$SOURCES" "$d/pharo/"
  cp -r lib examples docs "$d/"
  cp LICENSE release/INSTALL.md release/THIRD-PARTY-NOTICES.md README.md PROJECT-PLAN.md "$d/"
  cp release/licenses/Pharo-LICENSE.txt release/licenses/pharo-vm-LICENSE.txt \
     release/licenses/Apache-2.0.txt release/licenses/OFL-1.1.txt \
     release/licenses/libffi-LICENSE.txt "$d/licenses/"
  cp cog-lisp.sh mcp-server.sh "$d/"
  cp scripts/pharo-vm.sh "$d/scripts/"
  # the console driver the skill's console.md teaches (specs/36-console-driver.md R-6)
  cp tools/console_driver.py "$d/tools/"
  chmod +x "$d/cog-lisp.sh" "$d/mcp-server.sh"
  # the agent skill, a project skill wherever the bundle is opened (Phase 10 step 10.7)
  skill "$d/.agents/skills/cog-lisp"
}

# the agent skill, stamped with the version: $1 the folder to put it in. Bionic
# ignores front matter fields it does not know; the agent sees which release.
skill() {
  mkdir -p "$1"
  cp .agents/skills/cog-lisp/SKILL.md .agents/skills/cog-lisp/reference.md .agents/skills/cog-lisp/mcp.md \
     .agents/skills/cog-lisp/console.md "$1/"
  awk -v v="$VERSION" '{ print } /^name: / && !done { print "version: " v; done = 1 }' \
    .agents/skills/cog-lisp/SKILL.md > "$1/SKILL.md"
  grep -q "^version: $VERSION\$" "$1/SKILL.md"
}

# --- Linux -------------------------------------------------------------------
L="$STAGE/linux/$NAME"
common "$L"
LINUX_VM="$STAGE/linux-vm"
mkdir -p "$LINUX_VM"
unzip -q -o "$LINUX_VM_ZIP" -d "$LINUX_VM"
copy_vm "$LINUX_VM" "$L/pharo" "$LINUX_KEEP" "$LINUX_DROP"
tar -czf "$DIST/$NAME-linux-x86_64.tar.gz" -C "$STAGE/linux" "$NAME"
echo "[ok  ] $DIST/$NAME-linux-x86_64.tar.gz"

# --- Windows -----------------------------------------------------------------
W="$STAGE/windows/$NAME"
common "$W"
cp release/licenses/winpthreads-COPYING.txt "$W/licenses/"
cp cog-lisp.bat mcp-server.bat "$W/"
WINDOWS_VM="$STAGE/windows-vm"
mkdir -p "$WINDOWS_VM"
unzip -q -o "$WIN_VM_ZIP" -d "$WINDOWS_VM"
copy_vm "$WINDOWS_VM" "$W/pharo" "$WINDOWS_KEEP" "$WINDOWS_DROP"
(cd "$STAGE/windows" && zip -q -r "$DIST/$NAME-windows-x86_64.zip" "$NAME")
echo "[ok  ] $DIST/$NAME-windows-x86_64.zip"

# --- the agent skill on its own ----------------------------------------------
skill "$STAGE/skill/cog-lisp"
(cd "$STAGE/skill" && zip -q -r "$DIST/cog-lisp-skill-$VERSION.zip" cog-lisp)
echo "[ok  ] $DIST/cog-lisp-skill-$VERSION.zip"
