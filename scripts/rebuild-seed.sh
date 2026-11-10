#!/usr/bin/env bash
# ===========================================================================
#  cog-lisp : rebuild the seed from its source  (specs/15-phase-9-language.md 9.1)
#    scripts/rebuild-seed.sh [TAG]
#  The way back if a seed is lost (a release deleted, a download gone): build
#  the seed's own source, at its tag (SEED_TAG in pharo.pins unless TAG is
#  given), the way it was built, and install the result as pharo/seed.image and
#  pharo/seed.changes. If that tag's own pharo.pins names a seed, that seed is
#  rebuilt first, the same way, all the way back to a tag built from the pinned
#  stock Pharo image. Runs on Linux and in Git Bash on Windows; needs the tags
#  (git fetch --tags). Pharo downloads already in pharo/downloads are reused
#  when they match a tag's pins.
#
#  A rebuilt seed is not byte-identical to the released one (images never are),
#  but it is built from the same source by the same steps; the build from it, and
#  every suite, are the check (CI runs this path).
# ===========================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SEED_TAG=""
# shellcheck disable=SC1091
. "$ROOT/pharo.pins"
TAG="${1:-$SEED_TAG}"
[ -n "$TAG" ] || { echo "rebuild-seed: no TAG given and no SEED_TAG in pharo.pins" >&2; exit 2; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/cog-lisp-seed.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# build_tag TAG DIR: DIR/pharo/cog-lisp.image built from TAG's source
build_tag() {
  local tag="$1" dir="$2" inner
  echo "=== rebuild-seed: $tag ==="
  git -C "$ROOT" rev-parse -q --verify "refs/tags/$tag" >/dev/null \
    || { echo "rebuild-seed: no tag $tag here (git fetch --tags)" >&2; return 1; }
  mkdir -p "$dir/pharo/downloads"
  git -C "$ROOT" archive "$tag" | tar -x -C "$dir"
  # reuse what is already downloaded; a bootstrap fetches again what does not match its pins
  cp "$ROOT"/pharo/downloads/*.zip "$ROOT"/pharo/downloads/*.tar.gz "$dir/pharo/downloads/" 2>/dev/null || true
  inner="$(sed -n 's/^SEED_TAG=//p' "$dir/pharo.pins" | tr -d '\r')"
  if [ -n "$inner" ]; then
    build_tag "$inner" "$dir.seed" || return 1
    (cd "$dir" && COGLISP_SKIP_SEED=1 ./bootstrap-pharo.sh >"$dir.bootstrap.log" 2>&1) \
      || { tail -20 "$dir.bootstrap.log"; return 1; }
    cp "$dir.seed/pharo/cog-lisp.image" "$dir/pharo/seed.image"
    cp "$dir.seed/pharo/cog-lisp.changes" "$dir/pharo/seed.changes"
  else
    echo "    $tag is built from the stock Pharo image"
    (cd "$dir" && ./bootstrap-pharo.sh >"$dir.bootstrap.log" 2>&1) \
      || { tail -20 "$dir.bootstrap.log"; return 1; }
  fi
  (cd "$dir" && ./build-image.sh >"$dir.build.log" 2>&1) || { tail -20 "$dir.build.log"; return 1; }
  [ -f "$dir/pharo/cog-lisp.image" ] || { echo "rebuild-seed: $tag built no image" >&2; return 1; }
  echo "    built $tag"
}

build_tag "$TAG" "$WORK/tree"
mkdir -p "$ROOT/pharo"
cp "$WORK/tree/pharo/cog-lisp.image" "$ROOT/pharo/seed.image"
cp "$WORK/tree/pharo/cog-lisp.changes" "$ROOT/pharo/seed.changes"
echo "=== OK: pharo/seed.image rebuilt from $TAG's source ==="
