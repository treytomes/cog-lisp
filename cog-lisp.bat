@echo off
setlocal
rem ===========================================================================
rem  cog-lisp : run a program or start the REPL  (specs/phase-5-repl-runner.md)
rem    cog-lisp.bat                 start the REPL
rem    cog-lisp.bat program.lisp [arg ...]   run a program, then exit
rem  Exit code: 0 on success, 1 on an uncaught LISP error, or the code given to
rem  (exit n). Set COGLISP_IMAGE to use an image other than pharo\cog-lisp.image.
rem ===========================================================================

set "ROOT=%~dp0"
rem  the cog-lisp folder, for *env* and require (specs/library-path.md R-4)
set "COGLISP_HOME=%~dp0"
set "VM=%ROOT%pharo\PharoConsole.exe"
if defined COGLISP_IMAGE (set "IMG=%COGLISP_IMAGE%") else (set "IMG=%ROOT%pharo\cog-lisp.image")

rem  The image stops a program whose heap passes 2 GB (COGLISP_MAX_MEMORY_MB);
rem  the VM cap is a backstop in case that watchdog cannot run. At the cap the VM
rem  aborts and hangs, so keep it well above the watchdog limit.
set "CAP=--maxOldSpaceSize=8589934592"

if not exist "%IMG%" goto :noimage

if "%~1"=="" goto :repl
rem  the program, then any arguments for it: (command-line) answers them all.
rem  Each argument goes with a leading : that the shell removes, so the VM's
rem  command-line parser never takes a program's --flag for one of its own.
set "PROG=%~f1"
set "ARGS="
:collect
shift
if "%~1"=="" goto :run
set ARGS=%ARGS% ":%~1"
goto :collect
:run
"%VM%" --headless %CAP% "%IMG%" --no-default-preferences lisp run "%PROG%"%ARGS%
exit /b %ERRORLEVEL%

:repl
"%VM%" --headless %CAP% "%IMG%" --no-default-preferences lisp repl
exit /b %ERRORLEVEL%

:noimage
echo cog-lisp: no image at %IMG% 1>&2
echo cog-lisp: run build-image.bat first 1>&2
exit /b 2
