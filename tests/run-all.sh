#!/usr/bin/env bash
# ===========================================================================
#  cog-lisp : run every acceptance suite  (bash equivalent of tests\run-all.bat;
#  specs/phase-7.5-review-and-tooling.md AC-5, Phase 8.9)
#    tests/run-all.sh
#  Runs each tests/phase-*.st in a fresh stock image, then the runner suite
#  (which rebuilds pharo/cog-lisp.image), then the LISP unit tests
#  tests/lisp/*.lisp, and prints each suite's RESULT and a total. Exit code 0
#  only if every suite passed. Suite outputs stay in $COGLISP_TEST_OUTPUT
#  (default: a temporary folder) for reading a failure. Benchmarks are separate.
# ===========================================================================
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2
. "$ROOT/scripts/pharo-vm.sh"
VM="$(pharo_vm "$ROOT/pharo")"
STOCK=""
for f in pharo/Pharo*.image; do [ -f "$f" ] && { STOCK="$ROOT/$f"; break; }; done
if [ -z "$STOCK" ] || [ -z "$VM" ]; then
  echo "run-all: no stock image or VM in pharo/ -- run bootstrap-pharo.sh first" >&2
  exit 2
fi
TMPD="${COGLISP_TEST_OUTPUT:-${TMPDIR:-/tmp}/coglisp-run-all}"
rm -rf "$TMPD"
mkdir -p "$TMPD"

PASS=0
TOTAL=0
FAILED=0
# the reader and compiler in use (Phase 8 step 8.5): LISP unless COGLISP_COMPILER=smalltalk
if [ "$(echo "${COGLISP_COMPILER:-}" | tr '[:upper:]' '[:lower:]')" = smalltalk ]; then
  echo "== cog-lisp : all suites, on the Smalltalk reader and compiler (COGLISP_COMPILER=smalltalk) =="
else
  echo "== cog-lisp : all suites, on the LISP reader and compiler =="
fi

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

for t in tests/phase-*.st; do
  name="$(basename "$t" .st)"
  "$VM" --headless "$STOCK" st "$ROOT/$t" </dev/null >"$TMPD/$name.out" 2>&1
  tally "$name" "$TMPD/$name.out" $?
done

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
