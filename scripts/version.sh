#!/usr/bin/env bash
# ===========================================================================
#  cog-lisp : print the version of a build  (specs/28-versioning.md R-1 to R-7;
#  the bash twin of scripts/version.bat, which must give the same answers)
#
#  COGLISP_VERSION, when set, is the version (a release sets it from its tag).
#  Otherwise git gives it:
#    at a release's tag, nothing uncommitted   0.4.0
#    anywhere else                             0.4.1-dev.4.20261110153000
#      (the next patch, the commits since the tag, the build's time in UTC)
#    with uncommitted changes                  ... .dirty
#    without git, or without a tag             0.0.0-dev.0.20261110153000
#  COGLISP_BUILD_TIME (14 digits, UTC) gives the time, so one build can stamp
#  several things with one version. Only the version goes to stdout.
# ===========================================================================
set -u

if [ -n "${COGLISP_VERSION:-}" ]; then
  echo "$COGLISP_VERSION"
  exit 0
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIME="${COGLISP_BUILD_TIME:-$(date -u +%Y%m%d%H%M%S)}"

fallback() {
  echo "version: $1; the version is 0.0.0-dev.0.$TIME" >&2
  echo "0.0.0-dev.0.$TIME$DIRTY"
  exit 0
}

DIRTY=""
if ! git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  fallback "not a git repository"
fi
# tracked files only: a stray untracked file does not make a build unreproducible
if [ -n "$(git -C "$ROOT" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
  DIRTY=".dirty"
fi

TAG="$(git -C "$ROOT" describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null)" || fallback "no release tag"
COMMITS="$(git -C "$ROOT" rev-list --count "$TAG..HEAD")"
RELEASE="${TAG#v}"
if [ "$COMMITS" = "0" ] && [ -z "$DIRTY" ]; then
  echo "$RELEASE"
  exit 0
fi

# 0.4.0 -> 0.4.1-dev.N.TIME; a pre-release tag 0.5.0-rc1 -> 0.5.0-rc1.dev.N.TIME,
# which still sorts after the tag and before 0.5.0
case "$RELEASE" in
  *-*) BASE="$RELEASE.dev" ;;
  *)   IFS=. read -r MAJOR MINOR PATCH <<< "$RELEASE"
       BASE="$MAJOR.$MINOR.$((PATCH + 1))-dev" ;;
esac
echo "$BASE.$COMMITS.$TIME$DIRTY"
