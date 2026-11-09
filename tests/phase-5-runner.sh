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

# --- Starting anywhere (specs/startup-anywhere.md AC-2, AC-3) ------------------
# Two runs at once on one image: hold.lisp keeps it for six seconds, and
# beside.lisp starts on it after three; then a REPL holds it while a program runs.
"$CL" tests/runner/together/hold.lisp </dev/null >"$TMPD/hold.out" 2>"$TMPD/hold.err" &
HOLD=$!
sleep 3
"$CL" tests/runner/together/beside.lisp </dev/null >"$TMPD/beside.out" 2>"$TMPD/beside.err"
RC=$?
wait $HOLD
RCH=$?
OK=0; [ "$RC" = 0 ] && [ "$(same tests/runner/together/beside.expected "$TMPD/beside.out")" = 1 ] && OK=1
check "two runs at once on one image: the second runs beside the first (exit $RC)" $OK
OK=0; [ "$RCH" = 0 ] && [ "$(same tests/runner/together/hold.expected "$TMPD/hold.out")" = 1 ] && OK=1
check "... and the first finishes undisturbed (exit $RCH)" $OK
(printf '(display (+ 40 2))\n'; sleep 6; printf '(display "still here")\n') | "$CL" >"$TMPD/holder-repl.out" 2>&1 &
HOLD=$!
sleep 3
"$CL" tests/runner/together/beside.lisp </dev/null >"$TMPD/beside2.out" 2>"$TMPD/beside2.err"
RC=$?
wait $HOLD
OK=0; [ "$RC" = 0 ] && [ "$(same tests/runner/together/beside.expected "$TMPD/beside2.out")" = 1 ] && grep -q "still here" "$TMPD/holder-repl.out" && OK=1
check "a program runs while a REPL holds the image, and the REPL still answers" $OK
# A run writes nothing to the current folder (no cog-lisp.changes, pharo-local or
# PharoDebug.log); on Linux, a read-only one works too.
CWD="$TMPD/cwd-check"; rm -rf "$CWD"; mkdir -p "$CWD"
(cd "$CWD" && "$CL" "$ROOT/examples/hello.lisp" </dev/null >"$TMPD/cwd.out" 2>"$TMPD/cwd.err")
OK=0; [ -z "$(ls -A "$CWD")" ] && [ "$(same examples/hello.expected "$TMPD/cwd.out")" = 1 ] && OK=1
check "a run writes nothing to the current folder" $OK
# require finds cog-lisp's own libraries from a program in another folder
# (specs/library-path.md AC-1)
cp tests/runner/elsewhere/uses-libs.lisp "$CWD/"
(cd "$CWD" && "$CL" uses-libs.lisp </dev/null >"$TMPD/uses-libs.out" 2>"$TMPD/uses-libs.err")
check "require finds cog-lisp's libraries from a program in another folder" \
  "$(same tests/runner/elsewhere/uses-libs.expected "$TMPD/uses-libs.out")"
rm -f "$CWD/uses-libs.lisp"
if [ "$(uname -s)" = Linux ] && [ "$(id -u)" != 0 ]; then
  chmod 555 "$CWD"
  (cd "$CWD" && "$CL" "$ROOT/examples/hello.lisp" </dev/null >"$TMPD/cwd-ro.out" 2>"$TMPD/cwd-ro.err")
  chmod 755 "$CWD"
  check "a run from a read-only folder works" "$(same examples/hello.expected "$TMPD/cwd-ro.out")"
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
