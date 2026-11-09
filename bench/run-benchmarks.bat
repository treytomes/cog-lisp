@echo off
setlocal
rem ===========================================================================
rem  cog-lisp : run the benchmarks  (specs/phase-6-optimization.md section 6)
rem  Runs bench\bench.st against pharo\cog-lisp.image (which is not saved),
rem  prints the report, and writes bench\results.md. Run build-image.bat first.
rem  Exit code 0 when the benchmark checks (AC-15, AC-16) pass.
rem ===========================================================================

set "ROOT=%~dp0.."
set "VM=%ROOT%\pharo\PharoConsole.exe"
set "IMG=%ROOT%\pharo\cog-lisp.image"
if not exist "%IMG%" (
  echo run-benchmarks: no image at %IMG% - run build-image.bat first 1>&2
  exit /b 2
)
"%VM%" --headless "%IMG%" --no-default-preferences st "%ROOT%\bench\bench.st"
exit /b %ERRORLEVEL%
