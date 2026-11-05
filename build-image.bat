@echo off
setlocal
rem ===========================================================================
rem  cog-lisp : build the cog-lisp image  (specs/phase-9-language.md 9.1;
rem  first specs/phase-5-repl-runner.md 4.1)
rem  Loads src\, lib\core.lisp and lib\compiler\ into the seed, an earlier cog-lisp
rem  image pinned in pharo.pins (pharo\seed.image), whose compiler compiles the new
rem  one, and saves the result as pharo\cog-lisp.image. The seed is never modified.
rem  Rerun after any change to src\, lib\core.lisp or lib\compiler\.
rem ===========================================================================

set "ROOT=%~dp0"
set "PHARO=%ROOT%pharo"
set "VM=%PHARO%\PharoConsole.exe"

set "SEED=%PHARO%\seed.image"
if not exist "%SEED%" goto :noseed
if not exist "%VM%" goto :noseed

if exist "%PHARO%\cog-lisp.image" del /q "%PHARO%\cog-lisp.image"
if exist "%PHARO%\cog-lisp.changes" del /q "%PHARO%\cog-lisp.changes"

echo === cog-lisp : building image ===
echo     from : %SEED%
"%VM%" --headless "%SEED%" st "%ROOT%build\build.st"
if errorlevel 1 goto :failed
if not exist "%PHARO%\cog-lisp.image" goto :failed

echo === OK : %PHARO%\cog-lisp.image ===
exit /b 0

:noseed
echo build-image: no seed image or VM under pharo\ - run bootstrap-pharo.bat first 1>&2
exit /b 1

:failed
echo build-image: build failed - see messages above 1>&2
exit /b 1
