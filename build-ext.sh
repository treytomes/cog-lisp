#!/usr/bin/env bash
# Build the VS Code extension as vscode/cog-lisp.vsix (the bash twin of
# build-ext.bat). Installs the extension's npm packages from package-lock.json
# if they are missing, then packages it. Install the result with load-ext.sh,
# then reload the VS Code window.
set -e
cd "$(dirname "$0")/vscode"
if [ ! -d node_modules/@vscode/vsce ]; then
  echo "Installing the extension's npm packages..."
  npm ci
fi
npm run package
echo "Built vscode/cog-lisp.vsix; install it with load-ext.sh"
