@echo off
setlocal enabledelayedexpansion
rem ===========================================================================
rem  cog-lisp : run every acceptance suite  (specs/phase-7.5-review-and-tooling.md AC-5)
rem    tests\run-all.bat
rem  Runs each tests\phase-*.st in a fresh stock image, then the runner suite
rem  (which rebuilds pharo\cog-lisp.image), then the LISP unit tests tests\lisp\*.lisp, and prints each suite's RESULT and a
rem  total. Exit code 0 only if every suite passed. Benchmarks are separate:
rem  bench\run-benchmarks.bat.
rem ===========================================================================

pushd "%~dp0.."
set "VM=%CD%\pharo\PharoConsole.exe"
set "STOCK="
for %%F in ("pharo\Pharo*.image") do if not defined STOCK set "STOCK=%%~fF"
if not defined STOCK (
  echo run-all: no stock image in pharo\ -- run bootstrap-pharo.bat first 1>&2
  popd & exit /b 2
)
set "TMPD=%TEMP%\coglisp-run-all"
if exist "%TMPD%" rd /s /q "%TMPD%"
mkdir "%TMPD%"

set PASS=0
set TOTAL=0
set FAILED=0
echo == cog-lisp : all suites ==

for %%T in (tests\phase-*.st) do call :suite "%%~fT" "%%~nT"
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
rem  %1 = full path of a suite, %2 = its name
"%VM%" --headless "%STOCK%" st "%~1" >"%TMPD%\%~2.out" 2>&1
set RC=!ERRORLEVEL!
call :tally "%~2" "%TMPD%\%~2.out" !RC!
exit /b 0

:runner
call "%CD%\tests\phase-5-runner.bat" >"%TMPD%\phase-5-runner.out" 2>&1
set RC=!ERRORLEVEL!
call :tally "phase-5-runner" "%TMPD%\phase-5-runner.out" !RC!
exit /b 0

:lisptest
call "%CD%\cog-lisp.bat" "%~1" >"%TMPD%\lisp-%~2.out" 2>&1
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
