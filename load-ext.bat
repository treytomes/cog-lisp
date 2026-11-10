@echo off
setlocal
rem ===========================================================================
rem  cog-lisp : (re)install the VS Code extension. Rebuild it first with
rem  build-ext.bat; then reload the window. The bash twin is load-ext.sh.
rem
rem  It installs the version build-ext wrote beside the .vsix
rem  (specs/28-versioning.md R-13). VS Code cannot replace an extension of the
rem  same version while it runs it: it retries a rename for minutes, then fails
rem  with EPERM, even after a restart, since the restarted window runs the
rem  extension again first. So an already installed version stops here.
rem ===========================================================================

cd /d "%~dp0" || exit /b 1
if not exist vscode\cog-lisp.vsix goto :novsix
set "VERSION="
if exist vscode\cog-lisp.vsix.version set /p VERSION=<vscode\cog-lisp.vsix.version
if not defined VERSION goto :noversion

set "INSTALLED="
for /f "tokens=2 delims=@" %%v in ('call code --list-extensions --show-versions 2^>nul ^| findstr /b /i /c:"cog-lisp.cog-lisp@"') do set "INSTALLED=%%v"
if /i "%INSTALLED%"=="%VERSION%" goto :same

if defined INSTALLED (echo Installing cog-lisp %VERSION%, replacing %INSTALLED%) else (echo Installing cog-lisp %VERSION%)
call code --install-extension vscode\cog-lisp.vsix --force
if errorlevel 1 exit /b 1
echo Installed cog-lisp %VERSION%: reload the VS Code window to use it.
exit /b 0

:same
echo load-ext: cog-lisp %VERSION% is already installed. 1>&2
echo   VS Code cannot replace a version it is running. Rebuild with build-ext.bat, 1>&2
echo   which gives a new version; or uninstall cog-lisp, reload the window, and run 1>&2
echo   load-ext.bat again. 1>&2
exit /b 1

:novsix
echo load-ext: no vscode\cog-lisp.vsix: build it with build-ext.bat 1>&2
exit /b 1

:noversion
echo load-ext: vscode\cog-lisp.vsix has no version beside it: rebuild it with build-ext.bat 1>&2
exit /b 1
