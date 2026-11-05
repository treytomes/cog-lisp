@echo off
setlocal enabledelayedexpansion
rem ===========================================================================
rem  cog-lisp : Pharo bootstrap
rem  Downloads the pinned Pharo VM + image for 64-bit Windows (pharo.pins),
rem  checks each against its SHA-256, extracts them into .\pharo\, and confirms
rem  the VM build and the image/system version.
rem  Idempotent: a cached zip that matches its pin is reused; one that does not
rem  (an older pin) is downloaded again.
rem ===========================================================================

set "ROOT=%~dp0"
set "PHARO_DIR=%ROOT%pharo"
set "DL_DIR=%PHARO_DIR%\downloads"

rem  the pins: IMAGE_URL, IMAGE_SHA256, VM_WINDOWS_URL, VM_WINDOWS_SHA256, ...
for /f "usebackq eol=# tokens=1* delims==" %%A in ("%ROOT%pharo.pins") do set "%%A=%%B"
if not defined VM_WINDOWS_URL ( echo [err ] no pins read from pharo.pins & goto :fail )

echo(
echo === cog-lisp : Pharo bootstrap (pinned in pharo.pins) ===
echo     target dir : %PHARO_DIR%
echo(

if not exist "%DL_DIR%" mkdir "%DL_DIR%"

rem  variable NAMES, not values: a URL holds %2B, which CALL would expand again
call :fetch VM_WINDOWS_URL VM_WINDOWS_SHA256 "%DL_DIR%\pharo-vm-windows.zip" || goto :fail
call :fetch IMAGE_URL IMAGE_SHA256 "%DL_DIR%\pharo-image.zip" || goto :fail

rem --- Extract (tar ships with Windows 10/11 and reads zip; named in full, since
rem     a Git Bash PATH puts GNU tar first, which reads C:\ as a remote host) ---
rem  the VM zip marks its files read-only, so a second extraction could not
rem  replace them: clear that first
attrib -r "%PHARO_DIR%\*" /s >nul 2>&1
echo [xtr ] VM    -^> pharo\
"%SystemRoot%\System32\tar.exe" -xf "%DL_DIR%\pharo-vm-windows.zip" -C "%PHARO_DIR%" || goto :fail
echo [xtr ] image -^> pharo\
"%SystemRoot%\System32\tar.exe" -xf "%DL_DIR%\pharo-image.zip" -C "%PHARO_DIR%" || goto :fail

rem --- Locate the console VM exe (prefer PharoConsole.exe: it writes stdout) --
set "VM_EXE="
if exist "%PHARO_DIR%\PharoConsole.exe" set "VM_EXE=%PHARO_DIR%\PharoConsole.exe"
if not defined VM_EXE ( echo [err ] no PharoConsole.exe under pharo\ & goto :fail )

rem --- Locate the stock image (not a built cog-lisp image) ---------------------
set "IMAGE="
for %%F in ("%PHARO_DIR%\Pharo*.image") do if not defined IMAGE set "IMAGE=%%~fF"
if not defined IMAGE ( echo [err ] no Pharo*.image found under pharo\ & goto :fail )

echo(
echo [ok  ] VM exe : %VM_EXE%
echo [ok  ] image  : %IMAGE%

rem --- Confirm the VM build ---------------------------------------------------
echo(
echo === VM version =============================================================
"%VM_EXE%" --version
if errorlevel 1 ( echo [err ] VM failed to report its version & goto :fail )

rem --- Confirm the image / system version (headless eval, then quit) ----------
rem  --headless: without it the VM opens a window, and on a CI runner it never returns
echo(
echo === Image / system version =================================================
"%VM_EXE%" --headless "%IMAGE%" eval "SystemVersion current printString"
if errorlevel 1 ( echo [err ] image failed to evaluate SystemVersion & goto :fail )

echo(
echo === OK =====================================================================
echo Pharo is ready.
echo Launch the GUI with:
echo     "%VM_EXE:PharoConsole.exe=Pharo.exe%" "%IMAGE%"
echo(
exit /b 0

:fail
echo(
echo [FAILED] bootstrap did not complete - see messages above.
exit /b 1

rem ---------------------------------------------------------------------------
:fetch
rem  %1 = name of the URL variable, %2 = name of the SHA-256 variable, %3 = the file.
rem  Reuse the file if it matches its pin; otherwise download it and check it.
set "URL=!%~1!"
set "WANT=!%~2!"
set "FILE=%~3"
if exist "!FILE!" (
  call :sha256 "!FILE!"
  if /i "!GOT!"=="!WANT!" (
    echo [skip] %~nx3 matches its pin
    exit /b 0
  )
  echo [redo] %~nx3 does not match its pin: downloading it again
  del /q "!FILE!"
)
echo [down] !URL!
curl -L --fail --progress-bar -o "!FILE!" "!URL!" || exit /b 1
call :sha256 "!FILE!"
if /i not "!GOT!"=="!WANT!" (
  echo [err ] %~nx3: SHA-256 !GOT!, pinned !WANT!
  del /q "!FILE!"
  exit /b 1
)
echo [ok  ] %~nx3 matches its pin
exit /b 0

:sha256
rem  %1 = a file; sets GOT to its SHA-256, lower case
set "GOT="
for /f "usebackq delims=" %%H in (`powershell -NoProfile -Command "(Get-FileHash -Algorithm SHA256 -LiteralPath '%~1').Hash.ToLower()"`) do set "GOT=%%H"
exit /b 0
