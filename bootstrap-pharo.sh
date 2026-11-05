#!/usr/bin/env bash
# ===========================================================================
#  cog-lisp : Pharo bootstrap  (bash equivalent of bootstrap-pharo.bat)
#  Downloads the pinned 64-bit Pharo VM for this platform (Linux, or Windows
#  under Git Bash) and the pinned Pharo image (pharo.pins), checks each against
#  its SHA-256, extracts them into ./pharo/, and confirms the VM build and the
#  image/system version.
#  Idempotent: a cached zip that matches its pin is reused; one that does not
#  (an older pin) is downloaded again.
# ===========================================================================
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHARO_DIR="$ROOT/pharo"
DL_DIR="$PHARO_DIR/downloads"
. "$ROOT/scripts/pharo-vm.sh"
# the pins: IMAGE_URL, IMAGE_SHA256, VM_LINUX_URL, VM_LINUX_SHA256, VM_WINDOWS_...
. "$ROOT/pharo.pins"
case "$COGLISP_PLATFORM" in
  linux)   VM_ZIP="$DL_DIR/pharo-vm-linux.zip"; VM_URL="$VM_LINUX_URL"; VM_SHA256="$VM_LINUX_SHA256" ;;
  windows) VM_ZIP="$DL_DIR/pharo-vm-windows.zip"; VM_URL="$VM_WINDOWS_URL"; VM_SHA256="$VM_WINDOWS_SHA256" ;;
  *) echo "bootstrap-pharo: unsupported platform $(uname -s) (Linux and Windows are)" >&2; exit 1 ;;
esac
IMG_ZIP="$DL_DIR/pharo-image.zip"

fail() {
  echo
  echo "[FAILED] bootstrap did not complete - see messages above."
  exit 1
}

# Extract a zip into a directory with whatever this machine has: unzip, the
# Windows bsdtar (reads zip; Git Bash's own GNU tar does not), or Python.
extract() {
  local zip="$1" dest="$2"
  if command -v unzip >/dev/null 2>&1; then
    unzip -o -q "$zip" -d "$dest"
  elif [ -x /c/Windows/System32/tar.exe ]; then
    /c/Windows/System32/tar.exe -xf "$(cygpath -w "$zip")" -C "$(cygpath -w "$dest")"
  elif command -v python >/dev/null 2>&1; then
    python -I -m zipfile -e "$zip" "$dest"
  else
    echo "[err ] no unzip, tar.exe or python to extract $zip"
    return 1
  fi
}

echo
echo "=== cog-lisp : Pharo bootstrap (pinned in pharo.pins) ==="
echo "    target dir : $PHARO_DIR"
echo

mkdir -p "$DL_DIR" || fail

# Reuse a file that matches its pin; otherwise download it and check it.
fetch() {   # $1 URL, $2 SHA-256, $3 file
  local url="$1" want="$2" file="$3" got
  if [ -f "$file" ]; then
    got="$(sha256sum "$file" | cut -d' ' -f1)"
    if [ "$got" = "$want" ]; then
      echo "[skip] $(basename "$file") matches its pin"
      return 0
    fi
    echo "[redo] $(basename "$file") does not match its pin: downloading it again"
    rm -f "$file"
  fi
  echo "[down] $url"
  curl -L --fail --progress-bar -o "$file" "$url" || { rm -f "$file"; return 1; }
  got="$(sha256sum "$file" | cut -d' ' -f1)"
  if [ "$got" != "$want" ]; then
    echo "[err ] $(basename "$file"): SHA-256 $got, pinned $want"
    rm -f "$file"
    return 1
  fi
  echo "[ok  ] $(basename "$file") matches its pin"
}

fetch "$VM_URL" "$VM_SHA256" "$VM_ZIP" || fail
fetch "$IMAGE_URL" "$IMAGE_SHA256" "$IMG_ZIP" || fail

# --- Extract ----------------------------------------------------------------
# the Windows VM zip marks its files read-only, so a second extraction could not
# replace them: make what is there writable first
chmod -R u+w "$PHARO_DIR" 2>/dev/null
echo "[xtr ] VM    -> pharo/"
extract "$VM_ZIP" "$PHARO_DIR" || fail
echo "[xtr ] image -> pharo/"
extract "$IMG_ZIP" "$PHARO_DIR" || fail

# --- Locate the VM to run headless (Linux: the pharo launcher; Windows:
#     PharoConsole.exe, which writes stdout) ---------------------------------
VM_EXE="$(pharo_vm "$PHARO_DIR")"
[ -n "$VM_EXE" ] || { echo "[err ] no Pharo VM executable found under pharo/"; fail; }

# --- Locate the stock image file (not a built cog-lisp image) ---------------
IMAGE="$(find "$PHARO_DIR" -maxdepth 1 -name 'Pharo*.image' -print -quit)"
[ -n "$IMAGE" ] || { echo "[err ] no .image file found under pharo/"; fail; }

echo
echo "[ok  ] VM exe : $VM_EXE"
echo "[ok  ] image  : $IMAGE"

# --- Confirm the VM build ---------------------------------------------------
echo
echo "=== VM version ============================================================="
"$VM_EXE" --version || { echo "[err ] VM failed to report its version"; fail; }

# --- Confirm the image / system version (headless eval, then quit) ----------
echo
echo "=== Image / system version ================================================="
"$VM_EXE" --headless "$IMAGE" eval "SystemVersion current printString" \
  || { echo "[err ] image failed to evaluate SystemVersion"; fail; }

echo
echo "=== OK ====================================================================="
echo "Pharo is ready."
if [ "$COGLISP_PLATFORM" = windows ]; then
  echo "Launch the GUI with:"
  echo "    \"${VM_EXE%PharoConsole.exe}Pharo.exe\" \"$IMAGE\""
fi
echo
exit 0
