@echo off
setlocal EnableDelayedExpansion
rem ===========================================================================
rem  cog-lisp : the console scenarios (specs/36-console-driver.md R-7)
rem  (the twin of run.sh)
rem
rem  Each NAME.txt here is a step script for tools\console_driver.py, run against
rem  cog-lisp.bat NAME.lisp when there is a NAME.lisp, else against the REPL, in
rem  a real console (ConPTY). Needs Python with pywinpty and pyte (PYTHON, else
rem  python). Every scenario runs; the exit code is 1 if any failed.
rem ===========================================================================

for %%r in ("%~dp0..\..") do set "ROOT=%%~fr"
if not defined PYTHON set "PYTHON=python"
set RC=0
for %%s in ("%ROOT%\tests\console\*.txt") do (
  echo ==^> tests\console\%%~nxs
  set "PROGRAM="
  if exist "%%~dpns.lisp" set "PROGRAM=%%~dpns.lisp"
  "%PYTHON%" "%ROOT%\tools\console_driver.py" --cwd "%ROOT%" "%%~fs" -- cmd.exe /c "%ROOT%\cog-lisp.bat" !PROGRAM! < nul
  if errorlevel 1 set RC=1
)
exit /b %RC%
