#!/usr/bin/env bash
# ===========================================================================
#  cog-lisp : the console library on a real Unix terminal
#  (specs/29-console.md AC-4, AC-5). Runs terminal-check.lisp in a
#  pseudo-terminal from script(1), 100 by 30, with keys piped in, then prints its
#  checks and what it wrote to the terminal. Needs script (util-linux), so it
#  is not part of run-all.
#    tests/console/linux-check.sh
# ===========================================================================
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export CHECK_LOG="$(mktemp)"
OUT="$(mktemp)"
trap 'rm -f "$CHECK_LOG" "$OUT"' EXIT
ESC=$'\033'
# the keys: down, x, Ctrl+Left; Escape alone; Enter
(sleep 2; printf '%s' "${ESC}[Bx${ESC}[1;5D"; sleep 1; printf '%s' "$ESC"; sleep 1; printf '\r'; sleep 2) |
  TERM=xterm-256color COLORTERM= timeout 60 script -qfec \
    "stty cols 100 rows 30; '$ROOT/cog-lisp.sh' '$ROOT/tests/console/terminal-check.lisp'" /dev/null >"$OUT" 2>&1
cat "$CHECK_LOG"
echo "--- the terminal saw (escape codes as ^[):"
tr -d '\r' < "$OUT" | cat -v | head -5
grep -q '  FAIL  ' "$CHECK_LOG" && exit 1
grep -q 'RESULT:' "$CHECK_LOG" || exit 1
exit 0
