#!/usr/bin/env bash
# ===========================================================================
#  cog-lisp : run a program or start the REPL  (bash equivalent of
#  cog-lisp.bat; specs/phase-5-repl-runner.md)
#    ./cog-lisp.sh                 start the REPL
#    ./cog-lisp.sh program.lisp    run a program, then exit
#  Exit code: 0 on success, 1 on an uncaught LISP error, or the code given to
#  (exit n). Set COGLISP_IMAGE to use an image other than pharo/cog-lisp.image.
#  In mintty (the Git Bash window), stdin is not a Windows console, so for an
#  interactive REPL use a console terminal (Windows Terminal, VS Code) or
#  prefix with winpty; piped input works everywhere.
# ===========================================================================
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM="$ROOT/pharo/PharoConsole.exe"
IMG="${COGLISP_IMAGE:-$ROOT/pharo/cog-lisp.image}"

# The image stops a program whose heap passes 2 GB (COGLISP_MAX_MEMORY_MB);
# the VM cap is a backstop in case that watchdog cannot run. At the cap the VM
# aborts and hangs, so keep it well above the watchdog limit.
CAP="--maxOldSpaceSize=8589934592"

if [ ! -f "$IMG" ]; then
  echo "cog-lisp: no image at $IMG" >&2
  echo "cog-lisp: run build-image.sh first" >&2
  exit 2
fi

if [ $# -eq 0 ]; then
  "$VM" --headless "$CAP" "$IMG" lisp repl
  exit $?
fi

# The full path of the program, as the runner reports it in error locations.
case "$1" in
  /*|[A-Za-z]:*) PROG="$1" ;;
  *) PROG="$(pwd)/$1" ;;
esac
command -v cygpath >/dev/null 2>&1 && PROG="$(cygpath -w "$PROG")"
"$VM" --headless "$CAP" "$IMG" lisp run "$PROG"
exit $?
