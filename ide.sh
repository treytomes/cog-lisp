#!/usr/bin/env bash
# ===========================================================================
#  cog-lisp : the development image, in Pharo's GUI (specs/34-morphic-ide.md
#  R-1 to R-4, R-37; the bash twin of ide.bat: keep the two in step)
#
#    ide.sh [FOLDER]          open the development image, on a project folder
#                             (COGLISP_IDE_PROJECT, else the current folder,
#                             if none is given)
#    ide.sh --repl            a new REPL window in the image
#    ide.sh --run FILE        run FILE in a new REPL window of the image
#    ide.sh --fresh [FOLDER]  build a new image (build-image.sh), set the old
#                             development image aside, and open the new one
#
#  The development image is pharo/ide/cog-lisp-ide.image, made from
#  pharo/cog-lisp.image the first time. It is yours: save it, and it keeps its
#  state (R-2); build-image and the suites never touch it. When it is running a
#  request goes to it as a file in pharo/ide/requests/, which it takes
#  (decision 13); when it is not, it is started and takes the request then. It
#  shows it is running by touching pharo/ide/heartbeat every two seconds.
# ===========================================================================
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# the cog-lisp folder, for *env* and require (specs/18-library-path.md R-4)
export COGLISP_HOME="$ROOT"
IDE="$ROOT/pharo/ide"
IMG="$IDE/cog-lisp-ide.image"
REQUESTS="$IDE/requests"

# a path as the image reads it: under Git Bash the VM is a Windows program
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi; }
# a string as a LISP string literal
lisp_string() { printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"; }

request=""
fresh=0
folder="${COGLISP_IDE_PROJECT:-$(pwd)}"
case "${1:-}" in
  --repl) request="(repl)" ;;
  --run)
    if [ $# -lt 2 ]; then echo "ide.sh: --run needs a file" >&2; exit 2; fi
    file="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
    if [ ! -f "$file" ]; then echo "ide.sh: no file $2" >&2; exit 2; fi
    request="(run $(lisp_string "$(native "$file")"))" ;;
  --fresh) fresh=1; [ $# -ge 2 ] && folder="$(cd "$2" && pwd)" ;;
  --help|-h) sed -n '3,19p' "${BASH_SOURCE[0]}" | sed 's/^#  \{0,1\}//'; exit 0 ;;
  "") ;;
  -*) echo "ide.sh: unknown option $1 (--repl, --run FILE, --fresh, --help)" >&2; exit 2 ;;
  *) folder="$(cd "$1" && pwd)" ;;
esac

if [ "$(uname -s)" = "Linux" ]; then GUI="$ROOT/pharo/pharo"; else GUI="$ROOT/pharo/Pharo.exe"; fi
if [ ! -x "$GUI" ] && [ ! -f "$GUI" ]; then
  echo "ide.sh: no Pharo VM at $GUI - run bootstrap-pharo.sh first" >&2
  exit 2
fi

# running: the heartbeat was touched in the last ten seconds
running() {
  [ -f "$IDE/heartbeat" ] || return 1
  local now then
  now="$(date +%s)"
  then="$(date -r "$IDE/heartbeat" +%s 2>/dev/null || echo 0)"
  [ $((now - then)) -lt 10 ]
}

if [ "$fresh" = 1 ]; then
  if running; then echo "ide.sh: close the development image first (it is running)" >&2; exit 1; fi
  "$ROOT/build-image.sh" || exit 1
  if [ -f "$IMG" ]; then
    stamp="$(date +%Y%m%d%H%M%S)"
    mv "$IMG" "$IDE/cog-lisp-ide.before-fresh-$stamp.image"
    mv "$IDE/cog-lisp-ide.changes" "$IDE/cog-lisp-ide.before-fresh-$stamp.changes" 2>/dev/null
    echo "ide.sh: the old development image is $IDE/cog-lisp-ide.before-fresh-$stamp.image"
  fi
fi

if [ ! -f "$IMG" ]; then
  if [ ! -f "$ROOT/pharo/cog-lisp.image" ]; then
    echo "ide.sh: no pharo/cog-lisp.image - run build-image.sh first" >&2
    exit 2
  fi
  mkdir -p "$IDE"
  cp "$ROOT/pharo/cog-lisp.image" "$IMG"
  cp "$ROOT/pharo/cog-lisp.changes" "$IDE/cog-lisp-ide.changes"
  cp "$ROOT"/pharo/*.sources "$IDE/" 2>/dev/null
  echo "ide.sh: made the development image $IMG"
fi

mkdir -p "$REQUESTS"
# the project folder first, then what was asked for: each request a file, taken in name order
put() { printf '%s\n' "$1" > "$REQUESTS/$(date +%s%N)-$$-$2.request"; }
if [ -z "$request" ] || ! running; then
  put "(project $(lisp_string "$(native "$folder")"))" 0
fi
[ -n "$request" ] && put "$request" 1

if running; then
  echo "ide.sh: the development image is running; it takes the request"
  exit 0
fi
# the GUI: --interactive, which the pinned (headless) VM does not add (spike 1)
# from its own folder: the GUI VM writes what a program prints to a file named stdout in its current folder
(cd "$IDE" && exec "$GUI" "$(native "$IMG")" --interactive --no-default-preferences >/dev/null 2>&1) &
disown 2>/dev/null || true
echo "ide.sh: starting the development image"
