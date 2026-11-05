@echo off
setlocal enabledelayedexpansion
rem ===========================================================================
rem  cog-lisp : Phase 5 runner acceptance suite  (specs/phase-5-repl-runner.md)
rem  Drives the real entry points: build-image.bat and cog-lisp.bat.
rem    tests\runner\NAME.lisp    run as a program
rem    tests\runner\NAME.stdin   piped into the REPL
rem  with optional NAME.expected (exact stdout), NAME.exitcode (default 0) and
rem  NAME.stderr (a substring stderr must contain). examples\*.lisp are run the
rem  same way against examples\*.expected. Prints PASS/FAIL and RESULT: n/n.
rem ===========================================================================

pushd "%~dp0.."
set "CL=%CD%\cog-lisp.bat"
set "TMPD=%TEMP%\coglisp-runner"
if exist "%TMPD%" rd /s /q "%TMPD%"
mkdir "%TMPD%"
set PASS=0
set TOTAL=0

echo == cog-lisp Phase 5 : runner ==

rem --- AC-1 / AC-2: build ------------------------------------------------------
rem  the image is built from the seed (Phase 9 step 9.1), which the build never saves
set "STOCK=%CD%\pharo\seed.image"
for %%F in ("!STOCK!") do set "BEFORE=%%~tF %%~zF"
rem  call by full path: the current directory may not be on the command search path
call "%CD%\build-image.bat" >"%TMPD%\build.log" 2>&1
set RC=!ERRORLEVEL!
for %%F in ("!STOCK!") do set "AFTER=%%~tF %%~zF"
set OK=0
if "!RC!"=="0" if exist "pharo\cog-lisp.image" set OK=1
call :check "AC-1 build-image.bat creates pharo\cog-lisp.image" !OK!
set OK=0
if "!BEFORE!"=="!AFTER!" set OK=1
call :check "AC-1 the seed image unchanged" !OK!

rem --- runner and REPL fixtures, then the examples --------------------------------
for %%F in (tests\runner\*.lisp) do call :runcase "%%~fF" prog
for %%F in (tests\runner\*.stdin) do call :runcase "%%~fF" repl
for %%F in (examples\*.lisp) do call :runcase "%%~fF" prog
rem  multi-file example programs: examples\NAME\main.lisp
for %%F in (examples\*\main.lisp) do call :runcase "%%~fF" prog

rem --- REPL input that arrives late, as at an interactive prompt ---------------------
rem  Pharo's stdin never blocks, so the REPL must wait for input rather than treat
rem  "nothing yet" as end of input. ping gives a delay of about two seconds.
(ping -n 3 127.0.0.1 >nul & type "tests\runner\delayed\late.stdin") | "%CL%" >"%TMPD%\late.out" 2>"%TMPD%\late.err"
set OK=0
fc /b "tests\runner\delayed\late.expected" "%TMPD%\late.out" >nul 2>&1 && set OK=1
call :check "REPL waits for input that arrives late" !OK!

rem --- AC-13 / AC-21: persistence across save-image and a new process -------------
copy /y "pharo\cog-lisp.image" "pharo\cog-lisp-test.image" >nul
copy /y "pharo\cog-lisp.changes" "pharo\cog-lisp-test.changes" >nul
set "COGLISP_IMAGE=%CD%\pharo\cog-lisp-test.image"
call "%CL%" <"tests\runner\persist\session1.stdin" >"%TMPD%\session1.out" 2>"%TMPD%\session1.err"
set RC1=!ERRORLEVEL!
call "%CL%" "tests\runner\persist\session2.lisp" >"%TMPD%\session2.out" 2>"%TMPD%\session2.err"
set RC2=!ERRORLEVEL!
set "COGLISP_IMAGE="
set OK=0
if "!RC1!"=="0" if "!RC2!"=="0" set OK=1
call :check "AC-13 session 1 saves, session 2 runs: exit codes !RC1! !RC2!" !OK!
set OK=0
fc /b "tests\runner\persist\session2.expected" "%TMPD%\session2.out" >nul 2>&1 && set OK=1
call :check "AC-13/AC-21 saved definition and its source survive a new process" !OK!
call "%CL%" "tests\runner\persist\session2.lisp" >"%TMPD%\session2-orig.out" 2>&1
rem  take the exit code at once: run from a .cmd file (as CI does), SET resets ERRORLEVEL
set RC=!ERRORLEVEL!
set OK=0
if not "!RC!"=="0" set OK=1
call :check "AC-13 the unsaved build image does not have the definition" !OK!
del /q "pharo\cog-lisp-test.image" "pharo\cog-lisp-test.changes" >nul 2>&1

echo.
echo == RESULT: !PASS!/!TOTAL! checks passed ==
popd
if "!PASS!"=="!TOTAL!" (exit /b 0) else (exit /b 1)

rem ---------------------------------------------------------------------------
:runcase
rem  %1 = full path of a .lisp or .stdin fixture, %2 = prog or repl
set "BASE=%~dpn1"
set "NAME=%~n1"
rem  a program may have NAME.args (one line of arguments) and NAME.input (its stdin)
set "ARGS="
if exist "%BASE%.args" set /p ARGS=<"%BASE%.args"
if "%~2"=="repl" (
  call "%CL%" <"%~1" >"%TMPD%\%NAME%.out" 2>"%TMPD%\%NAME%.err"
) else if exist "%BASE%.input" (
  call "%CL%" "%~1" !ARGS! <"%BASE%.input" >"%TMPD%\%NAME%.out" 2>"%TMPD%\%NAME%.err"
) else (
  call "%CL%" "%~1" !ARGS! >"%TMPD%\%NAME%.out" 2>"%TMPD%\%NAME%.err"
)
set RC=!ERRORLEVEL!
set WANT=0
if exist "%BASE%.exitcode" set /p WANT=<"%BASE%.exitcode"
set OK=0
if "!RC!"=="!WANT!" set OK=1
call :check "%NAME%: exit code !RC!, want !WANT!" !OK!
if exist "%BASE%.expected" (
  set OK=0
  fc /b "%BASE%.expected" "%TMPD%\%NAME%.out" >nul 2>&1 && set OK=1
  call :check "%NAME%: stdout matches %NAME%.expected" !OK!
)
if exist "%BASE%.stderr" (
  set /p NEEDLE=<"%BASE%.stderr"
  set OK=0
  findstr /L /C:"!NEEDLE!" "%TMPD%\%NAME%.err" >nul 2>&1 && set OK=1
  call :check "%NAME%: stderr contains the expected text" !OK!
)
exit /b 0

:check
rem  %1 = label, %2 = 1 for pass
set /a TOTAL+=1
if "%~2"=="1" (
  set /a PASS+=1
  echo   PASS  %~1
) else (
  echo   FAIL  %~1
)
exit /b 0
