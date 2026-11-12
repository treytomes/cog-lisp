#!/usr/bin/env bash
# ===========================================================================
#  cog-lisp : the MCP server for coding agents  (bash equivalent of
#  mcp-server.bat; specs/35-mcp-server.md R-19)
#    ./mcp-server.sh [folder]
#  Serves the Model Context Protocol on standard input and output, with the
#  folder (optional) as the workspace whose definitions the tools know. Runs
#  lib/mcp.lisp on a private copy of the image, so that a host keeping the
#  server running never holds pharo/cog-lisp.image (build-image would fail),
#  and removes the copy when the server ends. Standard output is the protocol:
#  nothing here writes to it. Set COGLISP_IMAGE to serve another image.
#  Runs on Linux and under Git Bash on Windows.
# ===========================================================================
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${COGLISP_IMAGE:-$ROOT/pharo/cog-lisp.image}"
if [ ! -f "$SRC" ]; then
  echo "cog-lisp mcp: no image at $SRC: run build-image.sh first" >&2
  exit 1
fi
TMPBASE="${TMPDIR:-/tmp}"

# copies a killed server left behind. Only a folder this launcher made is
# touched (it names the launcher that made it, in owner.pid), and only one
# whose launcher has gone is removed.
for d in "$TMPBASE"/cog-lisp-mcp-image-*; do
  [ -d "$d" ] && [ -f "$d/owner.pid" ] || continue
  owner="$(cat "$d/owner.pid" 2>/dev/null || true)"
  if [ -n "$owner" ] && kill -0 "$owner" 2>/dev/null; then continue; fi
  rm -rf "$d"
done

DIR="$(mktemp -d "$TMPBASE/cog-lisp-mcp-image-XXXXXX")" || { echo "cog-lisp mcp: cannot make a folder in $TMPBASE" >&2; exit 1; }
echo $$ > "$DIR/owner.pid"
cleanup() { rm -rf "$DIR"; }
if ! cp "$SRC" "$DIR/cog-lisp.image" 2>/dev/null; then
  echo "cog-lisp mcp: cannot copy $SRC" >&2
  cleanup
  exit 1
fi
[ -f "${SRC%.image}.changes" ] && cp "${SRC%.image}.changes" "$DIR/cog-lisp.changes" 2>/dev/null

IMAGE="$DIR/cog-lisp.image"
FOLDER=()
if [ $# -gt 0 ] && [ -n "$1" ]; then
  FOLDER=("$(cd "$1" 2>/dev/null && pwd || echo "$1")")
fi
# under Git Bash the VM is a Windows program: give it Windows paths
if command -v cygpath >/dev/null 2>&1; then
  IMAGE="$(cygpath -w "$IMAGE")"
  [ ${#FOLDER[@]} -gt 0 ] && FOLDER=("$(cygpath -w "${FOLDER[0]}")")
fi

# the server runs as a child, so a host's SIGTERM reaches it and the copy is
# still removed; its standard input is the launcher's (a background job's
# would otherwise be /dev/null)
COGLISP_IMAGE="$IMAGE" "$ROOT/cog-lisp.sh" "$ROOT/lib/mcp.lisp" ${FOLDER[@]+"${FOLDER[@]}"} <&0 &
SERVER=$!
trap 'kill "$SERVER" 2>/dev/null' TERM INT HUP
wait "$SERVER"
RC=$?
# wait answers early when a signal arrives: wait again for the server itself
if kill -0 "$SERVER" 2>/dev/null; then wait "$SERVER"; RC=$?; fi
cleanup
exit $RC
