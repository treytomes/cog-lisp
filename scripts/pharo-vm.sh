#!/usr/bin/env bash
# ===========================================================================
#  cog-lisp : where the Pharo VM is, for the bash scripts (Phase 8.9).
#  Source this file; it sets COGLISP_PLATFORM (linux or windows) and, given
#  PHARO_DIR, defines pharo_vm, which prints the headless-capable VM to run:
#    Linux          pharo/pharo             (the launcher script in the VM zip)
#    Windows (Git Bash)  pharo/PharoConsole.exe  (writes to stdout, unlike Pharo.exe)
# ===========================================================================

case "$(uname -s)" in
  Linux*) COGLISP_PLATFORM=linux ;;
  MINGW*|MSYS*|CYGWIN*) COGLISP_PLATFORM=windows ;;
  *) COGLISP_PLATFORM=unsupported ;;
esac

pharo_vm() {
  local dir="$1"
  case "$COGLISP_PLATFORM" in
    linux) [ -x "$dir/pharo" ] && echo "$dir/pharo" ;;
    windows) [ -f "$dir/PharoConsole.exe" ] && echo "$dir/PharoConsole.exe" ;;
  esac
}
