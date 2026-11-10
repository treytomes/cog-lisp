@echo off
setlocal
rem ===========================================================================
rem  cog-lisp : the console library on a real Windows console
rem  (specs/29-console.md AC-4, AC-5). Starts windows-check.st in a fresh
rem  classic console window (conhost), which closes when it is done, and prints
rem  its log. Needs a desktop, so it is not part of run-all.
rem    tests\console\windows-check.bat
rem ===========================================================================

set "ROOT=%~dp0..\.."
set "LOG=%TEMP%\cog-lisp-console-check.log"
if exist "%LOG%" del /q "%LOG%"
start "cog-lisp console check" /wait %SystemRoot%\System32\conhost.exe "%ROOT%\pharo\PharoConsole.exe" --headless "%ROOT%\pharo\cog-lisp.image" --no-default-preferences st "%~dp0windows-check.st"
if not exist "%LOG%" (
  echo windows-check: the check wrote no log 1>&2
  exit /b 1
)
type "%LOG%"
findstr /c:"  FAIL  " /c:"  ERROR  " "%LOG%" >nul && exit /b 1
exit /b 0
