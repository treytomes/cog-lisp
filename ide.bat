@echo off
setlocal EnableDelayedExpansion
rem ===========================================================================
rem  cog-lisp : the development image, in Pharo's GUI (specs/34-morphic-ide.md
rem  R-1 to R-4, R-37; the cmd twin of ide.sh: keep the two in step)
rem
rem    ide.bat [FOLDER]          open the development image, on a project folder
rem                              (COGLISP_IDE_PROJECT, else the current folder,
rem                              if none is given)
rem    ide.bat --repl            a new REPL window in the image
rem    ide.bat --run FILE        run FILE in a new REPL window of the image
rem    ide.bat --fresh [FOLDER]  build a new image (build-image.bat), set the old
rem                              development image aside, and open the new one
rem
rem  The development image is pharo\ide\cog-lisp-ide.image, made from
rem  pharo\cog-lisp.image the first time. It is yours: save it, and it keeps its
rem  state (R-2); build-image and the suites never touch it. When it is running a
rem  request goes to it as a file in pharo\ide\requests\, which it takes
rem  (decision 13); when it is not, it is started and takes the request then. It
rem  shows it is running by touching pharo\ide\heartbeat every two seconds.
rem ===========================================================================

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
rem the cog-lisp folder, for *env* and require (specs/18-library-path.md R-4)
set "COGLISP_HOME=%ROOT%"
set "IDE=%ROOT%\pharo\ide"
set "IMG=%IDE%\cog-lisp-ide.image"
set "REQUESTS=%IDE%\requests"
set "GUI=%ROOT%\pharo\Pharo.exe"

set "REQUEST="
set "FRESH=0"
set "FOLDER=%CD%"
if defined COGLISP_IDE_PROJECT set "FOLDER=%COGLISP_IDE_PROJECT%"
if "%~1"=="--repl" set "REQUEST=(repl)"
if "%~1"=="--run" (
  if "%~2"=="" ( echo ide.bat: --run needs a file 1>&2 & exit /b 2 )
  if not exist "%~f2" ( echo ide.bat: no file %~2 1>&2 & exit /b 2 )
  set "RUNFILE=%~f2"
  set "RUNFILE=!RUNFILE:\=/!"
  set "REQUEST=(run "!RUNFILE!")"
)
if "%~1"=="--fresh" (
  set "FRESH=1"
  if not "%~2"=="" set "FOLDER=%~f2"
)
if "%~1"=="--help" ( for /f "tokens=1* delims= " %%a in ('findstr /b /c:"rem  " "%~f0"') do echo.%%b
  exit /b 0 )
set "FIRST=%~1"
rem (delayed expansion: %FIRST:~0,1% of an undefined FIRST garbles the line)
if defined FIRST if not "!FIRST!"=="--repl" if not "!FIRST!"=="--run" if not "!FIRST!"=="--fresh" if not "!FIRST!"=="--help" (
  if "!FIRST:~0,1!"=="-" ( echo ide.bat: unknown option !FIRST! ^(--repl, --run FILE, --fresh, --help^) 1>&2 & exit /b 2 )
  set "FOLDER=%~f1"
)

if not exist "%GUI%" ( echo ide.bat: no Pharo VM at %GUI% - run bootstrap-pharo.bat first 1>&2 & exit /b 2 )

call :running
set "RUNNING=!ERRORLEVEL!"
rem nothing asked of a running image: a new REPL window there, to show it heard
if not defined REQUEST if "!RUNNING!"=="0" if "%FRESH%"=="0" set "REQUEST=(repl)"

if "%FRESH%"=="1" (
  if "!RUNNING!"=="0" ( echo ide.bat: close the development image first ^(it is running, or closed in the last ten seconds^) 1>&2 & exit /b 1 )
  call "%ROOT%\build-image.bat"
  set "RC=!ERRORLEVEL!"
  if not "!RC!"=="0" exit /b 1
  if exist "%IMG%" (
    for /f %%t in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMddHHmmss"') do set "STAMP=%%t"
    move /y "%IMG%" "%IDE%\cog-lisp-ide.before-fresh-!STAMP!.image" >nul
    if exist "%IDE%\cog-lisp-ide.changes" move /y "%IDE%\cog-lisp-ide.changes" "%IDE%\cog-lisp-ide.before-fresh-!STAMP!.changes" >nul
    echo ide.bat: the old development image is %IDE%\cog-lisp-ide.before-fresh-!STAMP!.image
  )
)

if not exist "%IMG%" (
  if not exist "%ROOT%\pharo\cog-lisp.image" ( echo ide.bat: no pharo\cog-lisp.image - run build-image.bat first 1>&2 & exit /b 2 )
  if not exist "%IDE%" mkdir "%IDE%"
  copy /y "%ROOT%\pharo\cog-lisp.image" "%IMG%" >nul
  copy /y "%ROOT%\pharo\cog-lisp.changes" "%IDE%\cog-lisp-ide.changes" >nul
  copy /y "%ROOT%\pharo\*.sources" "%IDE%\" >nul 2>nul
  echo ide.bat: made the development image %IMG%
)

if not exist "%REQUESTS%" mkdir "%REQUESTS%"
set "FOLDERFWD=%FOLDER:\=/%"
for /f %%t in ('powershell -NoProfile -Command "[DateTime]::UtcNow.Ticks"') do set "TICKS=%%t"
set "SEND_PROJECT=0"
if not defined REQUEST set "SEND_PROJECT=1"
if not "!RUNNING!"=="0" set "SEND_PROJECT=1"
if "!SEND_PROJECT!"=="1" > "%REQUESTS%\!TICKS!-0.request" echo (project "!FOLDERFWD!")
if defined REQUEST > "%REQUESTS%\!TICKS!-1.request" echo !REQUEST!

if "!RUNNING!"=="0" (
  echo ide.bat: the development image is running; it takes the request
  exit /b 0
)
rem the GUI: --interactive, which the pinned (headless) VM does not add (spike 1)
rem from its own folder: the GUI VM writes what a program prints to a file named stdout in its current folder
start "" /D "%IDE%" "%GUI%" "%IMG%" --interactive --no-default-preferences
echo ide.bat: starting the development image
exit /b 0

rem 0 when the heartbeat was touched in the last ten seconds, else 1
:running
if not exist "%IDE%\heartbeat" exit /b 1
powershell -NoProfile -Command "if (((Get-Date) - (Get-Item '%IDE%\heartbeat').LastWriteTime).TotalSeconds -lt 10) { exit 0 } else { exit 1 }"
exit /b !ERRORLEVEL!
