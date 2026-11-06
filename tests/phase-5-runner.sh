#!/usr/bin/env bash
# ===========================================================================
#  cog-lisp : Phase 5 runner acceptance suite  (bash equivalent of
#  tests\phase-5-runner.bat; specs/phase-5-repl-runner.md, Phase 8.9)
#  Drives the real entry points: build-image.sh and cog-lisp.sh.
#    tests/runner/NAME.lisp    run as a program
#    tests/runner/NAME.stdin   piped into the REPL
#  with optional NAME.expected (exact stdout), NAME.exitcode (default 0) and
#  NAME.stderr (a substring stderr must contain). examples/*.lisp are run the
#  same way against examples/*.expected. Prints PASS/FAIL and RESULT: n/n.
# ===========================================================================
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2
CL="$ROOT/cog-lisp.sh"
TMPD="${TMPDIR:-/tmp}/coglisp-runner"
rm -rf "$TMPD"
mkdir -p "$TMPD"
PASS=0
TOTAL=0

check() {   # $1 label, $2 1 for pass
  TOTAL=$((TOTAL + 1))
  if [ "$2" = 1 ]; then
    PASS=$((PASS + 1))
    echo "  PASS  $1"
  else
    echo "  FAIL  $1"
  fi
}

same() { cmp -s "$1" "$2" && echo 1 || echo 0; }

echo "== cog-lisp Phase 5 : runner =="

# --- AC-1 / AC-2: build ------------------------------------------------------
# the image is built from the seed (Phase 9 step 9.1), which the build never saves
STOCK="pharo/seed.image"
BEFORE="$(stat -c '%Y %s' "$STOCK" 2>/dev/null)"
"$ROOT/build-image.sh" >"$TMPD/build.log" 2>&1
RC=$?
AFTER="$(stat -c '%Y %s' "$STOCK" 2>/dev/null)"
OK=0; [ "$RC" = 0 ] && [ -f pharo/cog-lisp.image ] && OK=1
check "AC-1 build-image.sh creates pharo/cog-lisp.image" $OK
OK=0; [ "$BEFORE" = "$AFTER" ] && OK=1
check "AC-1 the seed image unchanged" $OK

# --- one fixture: a program or REPL input ------------------------------------
runcase() {   # $1 path of a .lisp or .stdin fixture, $2 prog or repl
  local file="$1" mode="$2"
  local base="${file%.*}" name
  name="$(basename "$base")"
  local args=()
  # a program may have NAME.args (one line of arguments) and NAME.input (its stdin)
  [ -f "$base.args" ] && read -r -a args < "$base.args"
  if [ "$mode" = repl ]; then
    "$CL" <"$file" >"$TMPD/$name.out" 2>"$TMPD/$name.err"
  elif [ -f "$base.input" ]; then
    "$CL" "$file" ${args[@]+"${args[@]}"} <"$base.input" >"$TMPD/$name.out" 2>"$TMPD/$name.err"
  else
    "$CL" "$file" ${args[@]+"${args[@]}"} </dev/null >"$TMPD/$name.out" 2>"$TMPD/$name.err"
  fi
  local rc=$? want=0
  [ -f "$base.exitcode" ] && want="$(tr -d '\r\n' < "$base.exitcode")"
  local ok=0; [ "$rc" = "$want" ] && ok=1
  check "$name: exit code $rc, want $want" $ok
  if [ -f "$base.expected" ]; then
    check "$name: stdout matches $name.expected" "$(same "$base.expected" "$TMPD/$name.out")"
  fi
  if [ -f "$base.stderr" ]; then
    local needle
    needle="$(head -n 1 "$base.stderr" | tr -d '\r\n')"
    ok=0; grep -qF -- "$needle" "$TMPD/$name.err" && ok=1
    check "$name: stderr contains the expected text" $ok
  fi
}

for f in tests/runner/*.lisp; do runcase "$ROOT/$f" prog; done
for f in tests/runner/*.stdin; do runcase "$ROOT/$f" repl; done
for f in examples/*.lisp; do runcase "$ROOT/$f" prog; done
# multi-file example programs: examples/NAME/main.lisp
for f in examples/*/main.lisp; do runcase "$ROOT/$f" prog; done
# the agent skill's examples (Phase 10 step 10.7), shown in SKILL.md with their output
for f in docs/skill/examples/*.lisp; do runcase "$ROOT/$f" prog; done

# --- REPL input that arrives late, as at an interactive prompt ---------------
(sleep 2; cat tests/runner/delayed/late.stdin) | "$CL" >"$TMPD/late.out" 2>"$TMPD/late.err"
check "REPL waits for input that arrives late" "$(same tests/runner/delayed/late.expected "$TMPD/late.out")"

# --- Linux: the REPL at a terminal (Phase 8.9 AC-3) ----------------------------
# script(1) gives the REPL a pseudo-terminal. Lines are typed a second apart, as
# a person would; the terminal echoes them (and ends lines with CR LF, removed
# here). An error opens the break loop, (abort) leaves it, Ctrl+D ends input.
if [ "$(uname -s)" = Linux ] && command -v script >/dev/null 2>&1; then
  (sleep 3; printf '(+ 1 2)\n'; sleep 1; printf '(display "\316\273 caf\303\251")\n'; sleep 1
   printf '(car 5)\n'; sleep 1; printf '(abort)\n'; sleep 1; printf '\004') \
    | script -qfec "$CL" /dev/null 2>&1 | tr -d '\r' | grep -v '^exit=' >"$TMPD/terminal.out"
  check "REPL at a terminal: echo, UTF-8, break loop, Ctrl+D" \
    "$(same tests/runner/terminal/session.expected "$TMPD/terminal.out")"
fi

# --- AC-13 / AC-21: persistence across save-image and a new process ----------
cp pharo/cog-lisp.image pharo/cog-lisp-test.image
cp pharo/cog-lisp.changes pharo/cog-lisp-test.changes
export COGLISP_IMAGE="$ROOT/pharo/cog-lisp-test.image"
"$CL" <tests/runner/persist/session1.stdin >"$TMPD/session1.out" 2>"$TMPD/session1.err"
RC1=$?
"$CL" tests/runner/persist/session2.lisp </dev/null >"$TMPD/session2.out" 2>"$TMPD/session2.err"
RC2=$?
unset COGLISP_IMAGE
OK=0; [ "$RC1" = 0 ] && [ "$RC2" = 0 ] && OK=1
check "AC-13 session 1 saves, session 2 runs: exit codes $RC1 $RC2" $OK
check "AC-13/AC-21 saved definition and its source survive a new process" \
  "$(same tests/runner/persist/session2.expected "$TMPD/session2.out")"
"$CL" tests/runner/persist/session2.lisp </dev/null >"$TMPD/session2-orig.out" 2>&1
RC=$?
OK=0; [ "$RC" != 0 ] && OK=1
check "AC-13 the unsaved build image does not have the definition" $OK
rm -f pharo/cog-lisp-test.image pharo/cog-lisp-test.changes

echo
echo "== RESULT: $PASS/$TOTAL checks passed =="
[ "$PASS" = "$TOTAL" ]
