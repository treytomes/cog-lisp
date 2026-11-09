#!/usr/bin/env bash
# ===========================================================================
#  cog-lisp : build the cog-lisp image  (bash equivalent of build-image.bat;
#  specs/phase-9-language.md 9.1; first specs/phase-5-repl-runner.md 4.1)
#  Loads src/, lib/core.lisp and lib/compiler/ into the seed, an earlier cog-lisp
#  image pinned in pharo.pins (pharo/seed.image), whose compiler compiles the new
#  one, and saves the result as pharo/cog-lisp.image. The seed is never modified.
#  Rerun after any change to src/, lib/core.lisp or lib/compiler/.
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

rm -f "$PHARO/cog-lisp.image" "$PHARO/cog-lisp.changes"

echo "=== cog-lisp : building image ==="
echo "    from : $SEED"
if ! "$VM" --headless "$SEED" --no-default-preferences st "$ROOT/build/build.st" || [ ! -f "$PHARO/cog-lisp.image" ]; then
  echo "build-image: build failed - see messages above" >&2
  exit 1
fi

echo "=== OK : $PHARO/cog-lisp.image ==="
exit 0
