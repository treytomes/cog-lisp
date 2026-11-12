@echo off
setlocal EnableDelayedExpansion
rem ===========================================================================
rem  cog-lisp : the MCP server for coding agents  (specs/35-mcp-server.md R-19)
rem    mcp-server.bat [folder]
rem  Serves the Model Context Protocol on standard input and output, with the
rem  folder (optional) as the workspace whose definitions the tools know. Runs
rem  lib\mcp.lisp on a private copy of the image, so that a host keeping the
rem  server running never holds pharo\cog-lisp.image (build-image would fail),
rem  and removes the copy when the server ends. Hosts run it as
rem    cmd.exe /d /c C:\path\to\cog-lisp\mcp-server.bat C:\path\to\project
rem  Standard output is the protocol: nothing here writes to it.
rem  Set COGLISP_IMAGE to serve an image other than pharo\cog-lisp.image.
rem ===========================================================================

set "ROOT=%~dp0"
if defined COGLISP_IMAGE (set "SRC=%COGLISP_IMAGE%") else (set "SRC=%ROOT%pharo\cog-lisp.image")
if not exist "%SRC%" (
  echo cog-lisp mcp: no image at %SRC%: run build-image.bat first 1>&2
  exit /b 1
)
set "SRCCHANGES=%SRC:~0,-6%.changes"

rem  copies a killed server left behind. Only a folder this launcher made is
rem  touched (it holds the marker file), and only one no VM holds: such a
rem  folder can be renamed. A renamed one (-old) is removed whatever is left.
for /d %%D in ("%TEMP%\cog-lisp-mcp-image-*") do (
  if exist "%%D\cog-lisp-mcp.copy" (
    ren "%%D" "%%~nxD-old" >nul 2>nul && rd /s /q "%%D-old" >nul 2>nul
  )
)
for /d %%D in ("%TEMP%\cog-lisp-mcp-image-*-old") do rd /s /q "%%D" >nul 2>nul

:newdir
set "DIR=%TEMP%\cog-lisp-mcp-image-%RANDOM%%RANDOM%"
if exist "%DIR%" goto :newdir
mkdir "%DIR%" >nul 2>nul || (
  echo cog-lisp mcp: cannot make %DIR% 1>&2
  exit /b 1
)
type nul > "%DIR%\cog-lisp-mcp.copy"
copy /y "%SRC%" "%DIR%\cog-lisp.image" >nul 2>nul || (
  echo cog-lisp mcp: cannot copy %SRC% 1>&2
  rd /s /q "%DIR%" >nul 2>nul
  exit /b 1
)
if exist "%SRCCHANGES%" copy /y "%SRCCHANGES%" "%DIR%\cog-lisp.changes" >nul 2>nul

set "COGLISP_IMAGE=%DIR%\cog-lisp.image"
if "%~1"=="" (
  call "%ROOT%cog-lisp.bat" "%ROOT%lib\mcp.lisp"
) else (
  call "%ROOT%cog-lisp.bat" "%ROOT%lib\mcp.lisp" "%~f1"
)
set RC=!ERRORLEVEL!

rd /s /q "%DIR%" >nul 2>nul
exit /b %RC%
