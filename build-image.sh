#!/usr/bin/env bash
# ===========================================================================
#  cog-lisp : build the cog-lisp image  (bash equivalent of build-image.bat;
#  specs/15-phase-9-language.md 9.1; first specs/04-phase-5-repl-runner.md 4.1)
#  Loads src/, lib/core.lisp and lib/compiler/ into the seed, an earlier cog-lisp
#  image pinned in pharo.pins (pharo/seed.image), whose compiler compiles the new
#  one, and saves the result as pharo/cog-lisp-new.image; only then does it take the
#  place of pharo/cog-lisp.image, so a failed build leaves the old image as it was.
#  A cog-lisp.changes that a running cog-lisp holds cannot be replaced (on Windows,
#  under Git Bash): the build then says so, and keeps both. The seed is never
#  modified. Rerun after any change to src/, lib/core.lisp or lib/compiler/.
# ===========================================================================
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHARO="$ROOT/pharo"
. "$ROOT/scripts/pharo-vm.sh"
VM="$(pharo_vm "$PHARO")"

SEED="$PHARO/seed.image"
if [ ! -f "$SEED" ] || [ -z "$VM" ]; then
  echo "build-image: no seed image or VM under pharo/ - run bootstrap-pharo.sh first" >&2
  exit 1
fi

rm -f "$PHARO/cog-lisp-new.image" "$PHARO/cog-lisp-new.changes"

# The build's version (specs/28-versioning.md R-9), for *env* and
# (image-build-info): COGLISP_VERSION when set (a release), else from git.
COGLISP_BUILD_TIME="${COGLISP_BUILD_TIME:-$(date -u +%Y%m%d%H%M%S)}"
export COGLISP_BUILD_TIME
COGLISP_VERSION="$("$ROOT/scripts/version.sh")"
export COGLISP_VERSION
COGLISP_COMMIT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
export COGLISP_COMMIT

echo "=== cog-lisp : building image ==="
echo "    from    : $SEED"
echo "    version : $COGLISP_VERSION"
if ! "$VM" --headless "$SEED" --no-default-preferences st "$ROOT/build/build.st" || [ ! -f "$PHARO/cog-lisp-new.image" ]; then
  echo "build-image: build failed - see messages above" >&2
  exit 1
fi

# The new image takes the old one's place. The old files move aside first: on
# Windows a file a running cog-lisp holds cannot move, and then nothing is replaced.
in_use() {
  echo "build-image: the new image is built, but pharo/cog-lisp.image cannot be replaced:" >&2
  echo "  a cog-lisp running on it (a REPL, or a program) holds its files. Nothing was" >&2
  echo "  replaced; the new image is pharo/cog-lisp-new.image. Close that cog-lisp and" >&2
  echo "  run build-image.sh again." >&2
  exit 1
}
if [ -f "$PHARO/cog-lisp.changes" ]; then
  mv -f "$PHARO/cog-lisp.changes" "$PHARO/cog-lisp.changes.old" 2>/dev/null || in_use
fi
if [ -f "$PHARO/cog-lisp.image" ]; then
  if ! mv -f "$PHARO/cog-lisp.image" "$PHARO/cog-lisp.image.old" 2>/dev/null; then
    mv -f "$PHARO/cog-lisp.changes.old" "$PHARO/cog-lisp.changes" 2>/dev/null
    in_use
  fi
fi
mv -f "$PHARO/cog-lisp-new.image" "$PHARO/cog-lisp.image"
mv -f "$PHARO/cog-lisp-new.changes" "$PHARO/cog-lisp.changes"
rm -f "$PHARO/cog-lisp.image.old" "$PHARO/cog-lisp.changes.old"

echo "=== OK : $PHARO/cog-lisp.image ==="
exit 0
