#!/usr/bin/env bash
# ===========================================================================
#  cog-lisp : run the benchmarks  (bash equivalent of bench\run-benchmarks.bat;
#  specs/phase-6-optimization.md section 6, Phase 8.9)
#  Runs bench/bench.st against pharo/cog-lisp.image (which is not saved), prints
#  the report, and writes bench/results.md. Run build-image.sh first.
#  Exit code 0 when the benchmark checks pass.
# ===========================================================================
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/scripts/pharo-vm.sh"
VM="$(pharo_vm "$ROOT/pharo")"
IMG="$ROOT/pharo/cog-lisp.image"
if [ -z "$VM" ] || [ ! -f "$IMG" ]; then
  echo "run-benchmarks: no VM or image in pharo/ - run bootstrap-pharo.sh and build-image.sh first" >&2
  exit 2
fi
"$VM" --headless "$IMG" --no-default-preferences st "$ROOT/bench/bench.st" </dev/null
