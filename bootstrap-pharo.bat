@echo off
setlocal enabledelayedexpansion
rem ===========================================================================
rem  cog-lisp : Pharo bootstrap
rem  Downloads the stable Pharo VM + image for 64-bit Windows, extracts them
rem  into .\pharo\, and confirms the VM build and the image/system version.
rem  Idempotent: cached zips are reused, so re-running is cheap.
rem ===========================================================================

rem --- Which Pharo release to stand up (140 = Pharo 14, current stable). ------
set "PHARO_VERSION=140"

set "ROOT=%~dp0"
set "PHARO_DIR=%ROOT%pharo"
set "DL_DIR=%PHARO_DIR%\downloads"
set "VM_ZIP=%DL_DIR%\pharo-vm.zip"
set "IMG_ZIP=%DL_DIR%\pharo-image.zip"
set "VM_URL=https://files.pharo.org/get-files/%PHARO_VERSION%/pharo-vm-Windows-x86_64-stable.zip"
set "IMG_URL=https://files.pharo.org/get-files/%PHARO_VERSION%/pharoImage-x86_64.zip"

echo(
echo === cog-lisp : Pharo %PHARO_VERSION% bootstrap ===
echo     target dir : %PHARO_DIR%
echo(

if not exist "%DL_DIR%" mkdir "%DL_DIR%"

rem --- Download the VM --------------------------------------------------------
if exist "%VM_ZIP%" (
  echo [skip] VM zip already present
) else (
  echo [down] VM    %VM_URL%
  curl -L --fail --progress-bar -o "%VM_ZIP%" "%VM_URL%" || goto :fail
)

rem --- Download the image -----------------------------------------------------
if exist "%IMG_ZIP%" (
  echo [skip] image zip already present
) else (
  echo [down] image %IMG_URL%
  curl -L --fail --progress-bar -o "%IMG_ZIP%" "%IMG_URL%" || goto :fail
)

rem --- Extract (tar ships with Windows 10/11 and reads zip) -------------------
echo [xtr ] VM    -^> pharo\
tar -xf "%VM_ZIP%" -C "%PHARO_DIR%" || goto :fail
echo [xtr ] image -^> pharo\
tar -xf "%IMG_ZIP%" -C "%PHARO_DIR%" || goto :fail

rem --- Locate the console VM exe (prefer PharoConsole.exe: it writes stdout) --
set "VM_EXE="
for /r "%PHARO_DIR%" %%F in (PharoConsole.exe) do if not defined VM_EXE set "VM_EXE=%%F"
if not defined VM_EXE for /r "%PHARO_DIR%" %%F in (Pharo.exe) do if not defined VM_EXE set "VM_EXE=%%F"
if not defined VM_EXE ( echo [err ] no Pharo VM executable found under pharo\ & goto :fail )

rem --- Locate the image file --------------------------------------------------
set "IMAGE="
for /r "%PHARO_DIR%" %%F in (*.image) do if not defined IMAGE set "IMAGE=%%F"
if not defined IMAGE ( echo [err ] no .image file found under pharo\ & goto :fail )

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
echo Pharo %PHARO_VERSION% is ready.
echo Launch the GUI with:
echo     "%VM_EXE:PharoConsole.exe=Pharo.exe%" "%IMAGE%"
echo(
exit /b 0

:fail
echo(
echo [FAILED] bootstrap did not complete - see messages above.
exit /b 1
