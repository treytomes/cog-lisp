@echo off
setlocal
rem ===========================================================================
rem  cog-lisp : build the VS Code extension as vscode\cog-lisp.vsix
rem  Installs the extension's npm packages from package-lock.json if they are
rem  missing, then packages it. Install the result with load-ext.bat, then
rem  reload the VS Code window. The bash twin is build-ext.sh.
rem ===========================================================================

cd /d "%~dp0vscode" || exit /b 1

if exist node_modules\@vscode\vsce goto :package
echo Installing the extension's npm packages...
call npm ci
set RC=%ERRORLEVEL%
if not "%RC%"=="0" (echo npm ci failed & exit /b %RC%)

:package
call npm run package
set RC=%ERRORLEVEL%
if not "%RC%"=="0" (echo packaging failed & exit /b %RC%)
echo Built vscode\cog-lisp.vsix; install it with load-ext.bat
exit /b 0
