#!/usr/bin/env bash
# Build the VS Code extension as vscode/cog-lisp.vsix (the bash twin of
# build-ext.bat). Installs the extension's npm packages from package-lock.json
# if they are missing, then packages it. Install the result with load-ext.sh,
# then reload the VS Code window.
#
# The .vsix carries this build's version (specs/28-versioning.md R-10), from
# scripts/version.sh: package.json and package-lock.json hold it only while
# packaging, and are put back byte for byte afterwards, even when packaging
# fails; the committed files keep the placeholder 0.0.0. The version is also
# written beside the .vsix, as cog-lisp.vsix.version, for load-ext.sh.
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT/vscode"
if [ ! -d node_modules/@vscode/vsce ]; then
  echo "Installing the extension's npm packages..."
  npm ci
fi

VERSION="$("$ROOT/scripts/version.sh")"
SAVED="$(mktemp -d)"
cp package.json package-lock.json "$SAVED/"
restore() {
  cp -f "$SAVED/package.json" "$SAVED/package-lock.json" .
  rm -rf "$SAVED"
}
trap restore EXIT

npm version "$VERSION" --no-git-tag-version --allow-same-version >/dev/null
rm -f cog-lisp.vsix.version
npm run package
echo "$VERSION" > cog-lisp.vsix.version
echo "Built vscode/cog-lisp.vsix, version $VERSION; install it with load-ext.sh"
