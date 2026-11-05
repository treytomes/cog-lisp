@echo off
setlocal enabledelayedexpansion
rem ===========================================================================
rem  cog-lisp : run every acceptance suite  (specs/phase-7.5-review-and-tooling.md AC-5)
rem    tests\run-all.bat
rem  Builds pharo\cog-lisp.image from the seed (build-image.bat), runs each
rem  tests\phase-*.st in a fresh copy of it (pharo\suite.image: suites file in
rem  their harness, which writes to the image's changes file), then the runner
rem  suite (which builds the image again), then the LISP unit tests
rem  tests\lisp\*.lisp, and prints each suite's RESULT and a total. Exit code 0
rem  only if every suite passed. Benchmarks are separate: bench\run-benchmarks.bat.
rem ===========================================================================

pushd "%~dp0.."
set "VM=%CD%\pharo\PharoConsole.exe"
if not exist "pharo\seed.image" (
  echo run-all: no seed image in pharo\ -- run bootstrap-pharo.bat first 1>&2
  popd & exit /b 2
)
set "TMPD=%TEMP%\coglisp-run-all"
if exist "%TMPD%" rd /s /q "%TMPD%"
mkdir "%TMPD%"
rem  every suite and test reads stdin from an empty file, so (read) sees the end of
rem  input whatever stdin run-all itself has (an open pipe would block it; NUL is
rem  a character device, which LispStdin takes for a console)
type nul >"%TMPD%\empty-input.txt"

set PASS=0
set TOTAL=0
set FAILED=0
echo == cog-lisp : all suites ==

call "%CD%\build-image.bat" >"%TMPD%\build-image.out" 2>&1
set RC=!ERRORLEVEL!
if not "!RC!"=="0" (
  echo   FAIL  build-image  -- see %TMPD%\build-image.out
  echo.
  echo == THE IMAGE DID NOT BUILD: no suite was run ==
  popd & exit /b 1
)
echo   ok    build-image ^(from the seed^)

for %%T in (tests\phase-*.st) do call :suite "%%~fT" "%%~nT"
if exist "pharo\suite.image" del /q "pharo\suite.image" "pharo\suite.changes"
call :runner
rem  unit tests written in cog-lisp (lib/test.lisp; Phase 7.9), on the image the runner built
for %%T in (tests\lisp\*.lisp) do call :lisptest "%%~fT" "%%~nT"

echo.
if "!FAILED!"=="0" (
  echo == ALL SUITES PASSED: !PASS!/!TOTAL! checks ==
  popd & exit /b 0
)
echo == !FAILED! SUITE^(S^) FAILED: !PASS!/!TOTAL! checks passed ==
popd & exit /b 1

rem ---------------------------------------------------------------------------
:suite
rem  %1 = full path of a suite, %2 = its name; each runs on a fresh copy of the built image
copy /y "pharo\cog-lisp.image" "pharo\suite.image" >nul
copy /y "pharo\cog-lisp.changes" "pharo\suite.changes" >nul
"%VM%" --headless "%CD%\pharo\suite.image" st "%~1" <"%TMPD%\empty-input.txt" >"%TMPD%\%~2.out" 2>&1
set RC=!ERRORLEVEL!
call :tally "%~2" "%TMPD%\%~2.out" !RC!
exit /b 0

:runner
call "%CD%\tests\phase-5-runner.bat" >"%TMPD%\phase-5-runner.out" 2>&1
set RC=!ERRORLEVEL!
call :tally "phase-5-runner" "%TMPD%\phase-5-runner.out" !RC!
exit /b 0

:lisptest
call "%CD%\cog-lisp.bat" "%~1" <"%TMPD%\empty-input.txt" >"%TMPD%\lisp-%~2.out" 2>&1
set RC=!ERRORLEVEL!
call :tally "lisp/%~2" "%TMPD%\lisp-%~2.out" !RC!
exit /b 0

:tally
rem  %1 = suite name, %2 = its output, %3 = its exit code.
rem  A suite passes when it exits 0 and prints "RESULT: n/n".
set "LINE="
for /f "delims=" %%L in ('findstr /C:"RESULT:" "%~2"') do set "LINE=%%L"
set "N=" & set "M="
if defined LINE for /f "tokens=2 delims=:" %%R in ("!LINE!") do (
  for /f "tokens=1,2 delims=/ " %%a in ("%%R") do (set "N=%%a" & set "M=%%b")
)
if not defined N (
  echo   FAIL  %~1  ^(no RESULT line, exit %~3^) -- see %~2
  set /a FAILED+=1
  exit /b 0
)
set /a PASS+=N
set /a TOTAL+=M
if "%~3"=="0" if "!N!"=="!M!" (
  echo   PASS  %~1  !N!/!M!
  exit /b 0
)
echo   FAIL  %~1  !N!/!M!, exit %~3 -- see %~2
findstr /C:"  FAIL  " "%~2"
set /a FAILED+=1
exit /b 0
