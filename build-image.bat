@echo off
setlocal
rem ===========================================================================
rem  cog-lisp : build the cog-lisp image  (specs/phase-5-repl-runner.md 4.1)
rem  Loads src\, lib\core.lisp and lib\compiler\ into the stock Pharo image and
rem  saves the result as pharo\cog-lisp.image. The stock image is never modified.
rem  Rerun after any change to src\, lib\core.lisp or lib\compiler\.
rem ===========================================================================

set "ROOT=%~dp0"
set "PHARO=%ROOT%pharo"
set "VM=%PHARO%\PharoConsole.exe"

set "STOCK="
for %%F in ("%PHARO%\Pharo*.image") do if not defined STOCK set "STOCK=%%F"
if not defined STOCK goto :nostock
if not exist "%VM%" goto :nostock

if exist "%PHARO%\cog-lisp.image" del /q "%PHARO%\cog-lisp.image"
if exist "%PHARO%\cog-lisp.changes" del /q "%PHARO%\cog-lisp.changes"

echo === cog-lisp : building image ===
echo     from : %STOCK%
"%VM%" --headless "%STOCK%" st "%ROOT%build\build.st"
if errorlevel 1 goto :failed
if not exist "%PHARO%\cog-lisp.image" goto :failed

echo === OK : %PHARO%\cog-lisp.image ===
exit /b 0

:nostock
echo build-image: no stock Pharo image or VM under pharo\ - run bootstrap-pharo.bat first 1>&2
exit /b 1

:failed
echo build-image: build failed - see messages above 1>&2
exit /b 1
