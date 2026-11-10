#!/usr/bin/env bash
# ===========================================================================
#  cog-lisp : run every acceptance suite  (bash equivalent of tests\run-all.bat;
#  specs/07-phase-7.5-review-and-tooling.md AC-5, Phase 8.9)
#    tests/run-all.sh
#  Builds pharo/cog-lisp.image from the seed (build-image.sh), runs each
#  tests/phase-*.st in a fresh copy of it (pharo/suite.image: suites file in
#  their harness, which writes to the image's changes file), then the runner
#  suite (which builds the image again), then the LISP unit tests
#  tests/lisp/*.lisp, and prints each suite's RESULT and a total. Exit code 0
#  only if every suite passed. Suite outputs stay in $COGLISP_TEST_OUTPUT
#  (default: a temporary folder) for reading a failure. Benchmarks are separate.
# ===========================================================================
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2
. "$ROOT/scripts/pharo-vm.sh"
VM="$(pharo_vm "$ROOT/pharo")"
if [ ! -f pharo/seed.image ] || [ -z "$VM" ]; then
  echo "run-all: no seed image or VM in pharo/ -- run bootstrap-pharo.sh first" >&2
  exit 2
fi
TMPD="${COGLISP_TEST_OUTPUT:-${TMPDIR:-/tmp}/coglisp-run-all}"
rm -rf "$TMPD"
mkdir -p "$TMPD"

PASS=0
TOTAL=0
FAILED=0
echo "== cog-lisp : all suites =="

# A suite passes when it exits 0 and prints "RESULT: n/n".
tally() {   # $1 suite name, $2 its output, $3 its exit code
  local line n m
  line="$(grep -a 'RESULT:' "$2" | tail -n 1)"
  if [ -z "$line" ]; then
    echo "  FAIL  $1  (no RESULT line, exit $3) -- see $2"
    FAILED=$((FAILED + 1))
    return
  fi
  n="$(echo "$line" | sed -E 's/.*RESULT: ([0-9]+)\/([0-9]+).*/\1/')"
  m="$(echo "$line" | sed -E 's/.*RESULT: ([0-9]+)\/([0-9]+).*/\2/')"
  PASS=$((PASS + n))
  TOTAL=$((TOTAL + m))
  if [ "$3" = 0 ] && [ "$n" = "$m" ]; then
    echo "  PASS  $1  $n/$m"
  else
    echo "  FAIL  $1  $n/$m, exit $3 -- see $2"
    grep -a '  FAIL  ' "$2"
    FAILED=$((FAILED + 1))
  fi
}

if ! "$ROOT/build-image.sh" >"$TMPD/build-image.out" 2>&1; then
  echo "  FAIL  build-image  -- see $TMPD/build-image.out"
  tail -n 5 "$TMPD/build-image.out"
  echo
  echo "== THE IMAGE DID NOT BUILD: no suite was run =="
  exit 1
fi
echo "  ok    build-image (from the seed)"

# the version of a build (specs/28-versioning.md AC-1): scripts/version.sh
"$ROOT/tests/versioning.sh" </dev/null >"$TMPD/versioning.out" 2>&1
tally versioning "$TMPD/versioning.out" $?

for t in tests/phase-*.st; do
  name="$(basename "$t" .st)"
  cp -f pharo/cog-lisp.image pharo/suite.image && cp -f pharo/cog-lisp.changes pharo/suite.changes
  "$VM" --headless "$ROOT/pharo/suite.image" --no-default-preferences st "$ROOT/$t" </dev/null >"$TMPD/$name.out" 2>&1
  tally "$name" "$TMPD/$name.out" $?
done
rm -f pharo/suite.image pharo/suite.changes

"$ROOT/tests/phase-5-runner.sh" >"$TMPD/phase-5-runner.out" 2>&1
tally phase-5-runner "$TMPD/phase-5-runner.out" $?

# unit tests written in cog-lisp (lib/test.lisp; Phase 7.9), on the image the runner built
for t in tests/lisp/*.lisp; do
  name="$(basename "$t" .lisp)"
  "$ROOT/cog-lisp.sh" "$ROOT/$t" </dev/null >"$TMPD/lisp-$name.out" 2>&1
  tally "lisp/$name" "$TMPD/lisp-$name.out" $?
done

echo
if [ "$FAILED" = 0 ]; then
  echo "== ALL SUITES PASSED: $PASS/$TOTAL checks =="
  exit 0
fi
echo "== $FAILED SUITE(S) FAILED: $PASS/$TOTAL checks passed =="
exit 1
