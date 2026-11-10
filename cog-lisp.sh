#!/usr/bin/env bash
# ===========================================================================
#  cog-lisp : run a program or start the REPL  (bash equivalent of
#  cog-lisp.bat; specs/04-phase-5-repl-runner.md)
#    ./cog-lisp.sh                 start the REPL
#    ./cog-lisp.sh program.lisp [arg ...]   run a program, then exit
#  Exit code: 0 on success, 1 on an uncaught LISP error, or the code given to
#  (exit n). Set COGLISP_IMAGE to use an image other than pharo/cog-lisp.image.
#  Runs on Linux and under Git Bash on Windows. In mintty (the Git Bash
#  window), stdin is not a Windows console, so for an interactive REPL use a
#  console terminal (Windows Terminal, VS Code) or prefix with winpty; piped
#  input works everywhere.
# ===========================================================================
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# the cog-lisp folder, for *env* and require (specs/18-library-path.md R-4)
export COGLISP_HOME="$ROOT"
. "$ROOT/scripts/pharo-vm.sh"
VM="$(pharo_vm "$ROOT/pharo")"
IMG="${COGLISP_IMAGE:-$ROOT/pharo/cog-lisp.image}"

# The image stops a program whose heap passes 2 GB (COGLISP_MAX_MEMORY_MB);
# the VM cap is a backstop in case that watchdog cannot run. At the cap the VM
# aborts and hangs, so keep it well above the watchdog limit.
CAP="--maxOldSpaceSize=8589934592"

if [ -z "$VM" ]; then
  echo "cog-lisp: no Pharo VM under $ROOT/pharo - run bootstrap-pharo.sh first" >&2
  exit 2
fi
if [ ! -f "$IMG" ]; then
  echo "cog-lisp: no image at $IMG" >&2
  echo "cog-lisp: run build-image.sh first" >&2
  exit 2
fi

if [ $# -eq 0 ]; then
  "$VM" --headless "$CAP" "$IMG" --no-default-preferences lisp repl
  exit $?
fi

# The full path of the program, as the runner reports it in error locations.
case "$1" in
  /*|[A-Za-z]:*) PROG="$1" ;;
  *) PROG="$(pwd)/$1" ;;
esac
command -v cygpath >/dev/null 2>&1 && PROG="$(cygpath -w "$PROG")"
shift
# Each argument goes with a leading : that the shell removes, so the VM's
# command-line parser never takes a program's --flag for one of its own.
ARGS=()
for a in "$@"; do ARGS+=(":$a"); done
"$VM" --headless "$CAP" "$IMG" --no-default-preferences lisp run "$PROG" ${ARGS[@]+"${ARGS[@]}"}
exit $?
