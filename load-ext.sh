#!/usr/bin/env bash
# (Re)install the VS Code extension (the bash twin of load-ext.bat). Rebuild it
# first with build-ext.sh; then reload the window.
#
# It installs the version build-ext wrote beside the .vsix
# (specs/28-versioning.md R-13). VS Code cannot replace an extension of the
# same version while it runs it: it retries a rename for minutes, then fails
# with EPERM, even after a restart, since the restarted window runs the
# extension again first. So an already installed version stops here.
cd "$(dirname "$0")" || exit 1
if [ ! -f vscode/cog-lisp.vsix ]; then
  echo "load-ext: no vscode/cog-lisp.vsix: build it with build-ext.sh" >&2
  exit 1
fi
VERSION="$(tr -d '\r\n' < vscode/cog-lisp.vsix.version 2>/dev/null)"
if [ -z "$VERSION" ]; then
  echo "load-ext: vscode/cog-lisp.vsix has no version beside it: rebuild it with build-ext.sh" >&2
  exit 1
fi

INSTALLED="$(code --list-extensions --show-versions 2>/dev/null | tr -d '\r' | grep -i '^cog-lisp\.cog-lisp@' | cut -d@ -f2)"
if [ "$INSTALLED" = "$VERSION" ]; then
  {
    echo "load-ext: cog-lisp $VERSION is already installed."
    echo "  VS Code cannot replace a version it is running. Rebuild with build-ext.sh,"
    echo "  which gives a new version; or uninstall cog-lisp, reload the window, and run"
    echo "  load-ext.sh again."
  } >&2
  exit 1
fi

if [ -n "$INSTALLED" ]; then
  echo "Installing cog-lisp $VERSION, replacing $INSTALLED"
else
  echo "Installing cog-lisp $VERSION"
fi
code --install-extension vscode/cog-lisp.vsix --force || exit 1
echo "Installed cog-lisp $VERSION: reload the VS Code window to use it."
