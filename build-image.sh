#!/usr/bin/env bash
# ===========================================================================
#  cog-lisp : build the cog-lisp image  (bash equivalent of build-image.bat;
#  specs/phase-5-repl-runner.md 4.1)
#  Loads src/ and lib/core.lisp into the stock Pharo image and saves the result
#  as pharo/cog-lisp.image. The stock image is never modified. Rerun after any
#  change to src/ or lib/core.lisp.
# ===========================================================================
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHARO="$ROOT/pharo"
VM="$PHARO/PharoConsole.exe"

STOCK=""
for f in "$PHARO"/Pharo*.image; do
  [ -f "$f" ] && { STOCK="$f"; break; }
done
if [ -z "$STOCK" ] || [ ! -f "$VM" ]; then
  echo "build-image: no stock Pharo image or VM under pharo/ - run bootstrap-pharo.sh first" >&2
  exit 1
fi

rm -f "$PHARO/cog-lisp.image" "$PHARO/cog-lisp.changes"

echo "=== cog-lisp : building image ==="
echo "    from : $STOCK"
if ! "$VM" --headless "$STOCK" st "$ROOT/build/build.st" || [ ! -f "$PHARO/cog-lisp.image" ]; then
  echo "build-image: build failed - see messages above" >&2
  exit 1
fi

echo "=== OK : $PHARO/cog-lisp.image ==="
exit 0
