@echo off
setlocal
rem ===========================================================================
rem  cog-lisp : build the cog-lisp image  (specs/phase-9-language.md 9.1;
rem  first specs/phase-5-repl-runner.md 4.1)
rem  Loads src\, lib\core.lisp and lib\compiler\ into the seed, an earlier cog-lisp
rem  image pinned in pharo.pins (pharo\seed.image), whose compiler compiles the new
rem  one, and saves the result as pharo\cog-lisp-new.image; only then does it take the
rem  place of pharo\cog-lisp.image, so a failed build leaves the old image as it was.
rem  A cog-lisp.changes that a running cog-lisp holds cannot be replaced: the build
rem  then says so, and keeps both. The seed is never modified.
rem  Rerun after any change to src\, lib\core.lisp or lib\compiler\.
rem ===========================================================================

set "ROOT=%~dp0"
set "PHARO=%ROOT%pharo"
set "VM=%PHARO%\PharoConsole.exe"

set "SEED=%PHARO%\seed.image"
if not exist "%SEED%" goto :noseed
if not exist "%VM%" goto :noseed

if exist "%PHARO%\cog-lisp-new.image" del /q "%PHARO%\cog-lisp-new.image"
if exist "%PHARO%\cog-lisp-new.changes" del /q "%PHARO%\cog-lisp-new.changes"

echo === cog-lisp : building image ===
echo     from : %SEED%
"%VM%" --headless "%SEED%" --no-default-preferences st "%ROOT%build\build.st"
if errorlevel 1 goto :failed
if not exist "%PHARO%\cog-lisp-new.image" goto :failed

rem  The new image takes the old one's place. The old files move aside first: a
rem  file a running cog-lisp holds cannot move, and then nothing is replaced.
if not exist "%PHARO%\cog-lisp.changes" goto :oldimage
move /y "%PHARO%\cog-lisp.changes" "%PHARO%\cog-lisp.changes.old" >nul 2>&1
if errorlevel 1 goto :inuse
:oldimage
if not exist "%PHARO%\cog-lisp.image" goto :place
move /y "%PHARO%\cog-lisp.image" "%PHARO%\cog-lisp.image.old" >nul 2>&1
if errorlevel 1 goto :inuserestore
:place
move /y "%PHARO%\cog-lisp-new.image" "%PHARO%\cog-lisp.image" >nul
move /y "%PHARO%\cog-lisp-new.changes" "%PHARO%\cog-lisp.changes" >nul
if exist "%PHARO%\cog-lisp.image.old" del /q "%PHARO%\cog-lisp.image.old"
if exist "%PHARO%\cog-lisp.changes.old" del /q "%PHARO%\cog-lisp.changes.old"

echo === OK : %PHARO%\cog-lisp.image ===
exit /b 0

:inuserestore
move /y "%PHARO%\cog-lisp.changes.old" "%PHARO%\cog-lisp.changes" >nul 2>&1
:inuse
echo build-image: the new image is built, but pharo\cog-lisp.image cannot be replaced: 1>&2
echo   a cog-lisp running on it (a REPL, or a program) holds its files. Nothing was 1>&2
echo   replaced; the new image is pharo\cog-lisp-new.image. Close that cog-lisp and 1>&2
echo   run build-image.bat again. 1>&2
exit /b 1

:noseed
echo build-image: no seed image or VM under pharo\ - run bootstrap-pharo.bat first 1>&2
exit /b 1

:failed
echo build-image: build failed - see messages above 1>&2
exit /b 1
