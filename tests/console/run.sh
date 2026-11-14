#!/usr/bin/env bash
# ===========================================================================
#  cog-lisp : the console scenarios (specs/36-console-driver.md R-7)
#  (the bash twin of run.bat)
#
#  Each NAME.txt here is a step script for tools/console_driver.py, run against
#  ./cog-lisp.sh NAME.lisp when there is a NAME.lisp, else against the REPL, in
#  a real terminal (a pty). Needs Python with ptyprocess and pyte (PYTHON, else
#  python3). Every scenario runs; the exit code is 1 if any failed.
# ===========================================================================
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PY="${PYTHON:-python3}"
RC=0
for scenario in "$ROOT"/tests/console/*.txt; do
	name="${scenario%.txt}"
	program=()
	[ -f "$name.lisp" ] && program=("$name.lisp")
	echo "==> tests/console/$(basename "$scenario")"
	"$PY" "$ROOT/tools/console_driver.py" --cwd "$ROOT" "$scenario" -- "$ROOT/cog-lisp.sh" ${program[@]+"${program[@]}"} </dev/null || RC=1
done
exit $RC
