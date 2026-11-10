#!/usr/bin/env bash
# ===========================================================================
#  cog-lisp : scripts/version.sh, in a throwaway git repository
#  (specs/28-versioning.md AC-1). tests/versioning.bat checks scripts/version.bat
#  against the same cases and answers, so the twins agree. run-all.sh runs this.
# ===========================================================================
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$(mktemp -d)"
trap 'rm -rf "$REPO"' EXIT
unset COGLISP_VERSION COGLISP_BUILD_TIME
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
T=20261110153000

PASS=0
TOTAL=0
check() {   # $1 what, $2 actual, $3 expected
  TOTAL=$((TOTAL + 1))
  if [ "$2" = "$3" ]; then
    PASS=$((PASS + 1))
    echo "  PASS  $1"
  else
    echo "  FAIL  $1  got=$2  want=$3"
  fi
}
version() { COGLISP_BUILD_TIME=$T bash "$REPO/scripts/version.sh" 2>/dev/null; }
commit() { echo "$1" >> "$REPO/file.txt"; git -C "$REPO" add file.txt; git -C "$REPO" commit -q -m "$1"; }

echo "== cog-lisp : scripts/version.sh (specs/28-versioning.md) =="
mkdir -p "$REPO/scripts"
cp "$ROOT/scripts/version.sh" "$REPO/scripts/version.sh"

check "not a git repository" "$(version)" "0.0.0-dev.0.$T"
check "not a git repository: it says so on stderr" \
  "$(COGLISP_BUILD_TIME=$T bash "$REPO/scripts/version.sh" 2>&1 >/dev/null)" \
  "version: not a git repository; the version is 0.0.0-dev.0.$T"

git -C "$REPO" init -q
git -C "$REPO" config core.autocrlf false        # no line-ending warnings
echo "scripts/" > "$REPO/.gitignore"           # the script itself is not part of the history
git -C "$REPO" add .gitignore
commit one
check "no release tag" "$(version)" "0.0.0-dev.0.$T"

git -C "$REPO" tag v0.4.0
check "at a release's tag" "$(version)" "0.4.0"
echo stray > "$REPO/untracked.txt"
check "an untracked file is not a change" "$(version)" "0.4.0"
echo changed >> "$REPO/file.txt"
check "at the tag, with an uncommitted change" "$(version)" "0.4.1-dev.0.$T.dirty"
git -C "$REPO" checkout -q -- file.txt

commit two
commit three
check "two commits after the tag" "$(version)" "0.4.1-dev.2.$T"
echo changed >> "$REPO/file.txt"
check "after the tag, with an uncommitted change" "$(version)" "0.4.1-dev.2.$T.dirty"
git -C "$REPO" checkout -q -- file.txt

git -C "$REPO" tag v0.5.0-rc1
commit four
check "after a pre-release tag" "$(version)" "0.5.0-rc1.dev.1.$T"
git -C "$REPO" tag v0.9.10
commit five
check "a patch number of two digits" "$(version)" "0.9.11-dev.1.$T"

check "COGLISP_VERSION wins" "$(COGLISP_VERSION=1.2.3 bash "$REPO/scripts/version.sh")" "1.2.3"
now="$(bash "$REPO/scripts/version.sh")"
check "the time is 14 digits, by default now" \
  "$(echo "$now" | grep -cE '^0\.9\.11-dev\.1\.[0-9]{14}$')" "1"

echo
echo "== RESULT: $PASS/$TOTAL checks passed =="
[ "$PASS" = "$TOTAL" ]
