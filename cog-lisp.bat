@echo off
setlocal
rem ===========================================================================
rem  cog-lisp : run a program or start the REPL  (specs/phase-5-repl-runner.md)
rem    cog-lisp.bat                 start the REPL
rem    cog-lisp.bat program.lisp    run a program, then exit
rem  Exit code: 0 on success, 1 on an uncaught LISP error, or the code given to
rem  (exit n). Set COGLISP_IMAGE to use an image other than pharo\cog-lisp.image.
rem ===========================================================================

set "ROOT=%~dp0"
set "VM=%ROOT%pharo\PharoConsole.exe"
if defined COGLISP_IMAGE (set "IMG=%COGLISP_IMAGE%") else (set "IMG=%ROOT%pharo\cog-lisp.image")

if not exist "%IMG%" goto :noimage

if "%~1"=="" goto :repl
"%VM%" --headless "%IMG%" lisp run "%~f1"
exit /b %ERRORLEVEL%

:repl
"%VM%" --headless "%IMG%" lisp repl
exit /b %ERRORLEVEL%

:noimage
echo cog-lisp: no image at %IMG% 1>&2
echo cog-lisp: run build-image.bat first 1>&2
exit /b 2
