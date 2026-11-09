#!/usr/bin/env bash
# (Re)install the VS Code extension (the bash twin of load-ext.bat).
# Rebuild it first with build-ext.sh; then reload the window.
cd "$(dirname "$0")" && code --install-extension vscode/cog-lisp.vsix --force
