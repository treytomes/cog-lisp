@echo off
setlocal
rem ===========================================================================
rem  cog-lisp : build the VS Code extension as vscode\cog-lisp.vsix
rem  Installs the extension's npm packages from package-lock.json when they do
rem  not match it, then packages it. Install the result with load-ext.bat, then
rem  reload the VS Code window. The bash twin is build-ext.sh.
rem
rem  The .vsix carries this build's version (specs/28-versioning.md R-10), from
rem  scripts\version.bat: package.json and package-lock.json hold it only while
rem  packaging, and are put back byte for byte afterwards, even when packaging
rem  fails; the committed files keep the placeholder 0.0.0. The version is also
rem  written beside the .vsix, as cog-lisp.vsix.version, for load-ext.bat.
rem ===========================================================================

set "ROOT=%~dp0"
cd /d "%ROOT%vscode" || exit /b 1

rem npm ci when node_modules\ does not match package-lock.json (specs/31-vsix-bundle.md R-8)
node scripts\deps.js
set RC=%ERRORLEVEL%
if not "%RC%"=="0" exit /b %RC%

set "VERSION="
for /f "delims=" %%v in ('call "%ROOT%scripts\version.bat"') do set "VERSION=%%v"
if not defined VERSION (echo build-ext: no version from scripts\version.bat & exit /b 1)
set "SAVED=%TEMP%\cog-lisp-ext-%RANDOM%%RANDOM%"
mkdir "%SAVED%" || exit /b 1
copy /y /b package.json "%SAVED%\package.json" >nul
copy /y /b package-lock.json "%SAVED%\package-lock.json" >nul
if exist cog-lisp.vsix.version del /q cog-lisp.vsix.version

call npm version "%VERSION%" --no-git-tag-version --allow-same-version >nul
set RC=%ERRORLEVEL%
if "%RC%"=="0" call npm run package
if "%RC%"=="0" set RC=%ERRORLEVEL%

rem  put the committed files back, whatever happened
copy /y /b "%SAVED%\package.json" package.json >nul
copy /y /b "%SAVED%\package-lock.json" package-lock.json >nul
rmdir /s /q "%SAVED%"

if not "%RC%"=="0" (echo packaging failed & exit /b %RC%)
>cog-lisp.vsix.version echo %VERSION%
echo Built vscode\cog-lisp.vsix, version %VERSION%; install it with load-ext.bat
exit /b 0
