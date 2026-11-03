#!/usr/bin/env bash
# ===========================================================================
#  cog-lisp : Pharo bootstrap  (bash equivalent of bootstrap-pharo.bat)
#  Downloads the stable Pharo VM + image for 64-bit Windows, extracts them
#  into ./pharo/, and confirms the VM build and the image/system version.
#  Idempotent: cached zips are reused, so re-running is cheap.
#  Runs under Git Bash on Windows (cog-lisp's shell uses Win32 calls for stdin,
#  so Windows is the supported platform).
# ===========================================================================
set -u

# --- Which Pharo release to stand up (140 = Pharo 14, current stable). ------
PHARO_VERSION=140

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHARO_DIR="$ROOT/pharo"
DL_DIR="$PHARO_DIR/downloads"
VM_ZIP="$DL_DIR/pharo-vm.zip"
IMG_ZIP="$DL_DIR/pharo-image.zip"
VM_URL="https://files.pharo.org/get-files/$PHARO_VERSION/pharo-vm-Windows-x86_64-stable.zip"
IMG_URL="https://files.pharo.org/get-files/$PHARO_VERSION/pharoImage-x86_64.zip"

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
echo "=== cog-lisp : Pharo $PHARO_VERSION bootstrap ==="
echo "    target dir : $PHARO_DIR"
echo

mkdir -p "$DL_DIR" || fail

# --- Download the VM --------------------------------------------------------
if [ -f "$VM_ZIP" ]; then
  echo "[skip] VM zip already present"
else
  echo "[down] VM    $VM_URL"
  curl -L --fail --progress-bar -o "$VM_ZIP" "$VM_URL" || { rm -f "$VM_ZIP"; fail; }
fi

# --- Download the image -----------------------------------------------------
if [ -f "$IMG_ZIP" ]; then
  echo "[skip] image zip already present"
else
  echo "[down] image $IMG_URL"
  curl -L --fail --progress-bar -o "$IMG_ZIP" "$IMG_URL" || { rm -f "$IMG_ZIP"; fail; }
fi

# --- Extract ----------------------------------------------------------------
echo "[xtr ] VM    -> pharo/"
extract "$VM_ZIP" "$PHARO_DIR" || fail
echo "[xtr ] image -> pharo/"
extract "$IMG_ZIP" "$PHARO_DIR" || fail

# --- Locate the console VM exe (prefer PharoConsole.exe: it writes stdout) --
VM_EXE="$(find "$PHARO_DIR" -name PharoConsole.exe -print -quit)"
[ -n "$VM_EXE" ] || VM_EXE="$(find "$PHARO_DIR" -name Pharo.exe -print -quit)"
[ -n "$VM_EXE" ] || { echo "[err ] no Pharo VM executable found under pharo/"; fail; }

# --- Locate the stock image file (not a built cog-lisp image) ---------------
IMAGE="$(find "$PHARO_DIR" -name 'Pharo*.image' -print -quit)"
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
echo "Pharo $PHARO_VERSION is ready."
echo "Launch the GUI with:"
echo "    \"${VM_EXE%PharoConsole.exe}Pharo.exe\" \"$IMAGE\""
echo
exit 0
