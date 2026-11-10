@echo off
setlocal EnableDelayedExpansion
rem ===========================================================================
rem  cog-lisp : scripts\version.bat, in a throwaway git repository
rem  (specs/28-versioning.md AC-1). The same cases and answers as
rem  tests/versioning.sh, which checks scripts/version.sh, so the twins agree.
rem  run-all.bat runs this.
rem ===========================================================================

set "ROOT=%~dp0.."
set "REPO=%TEMP%\coglisp-version-%RANDOM%%RANDOM%"
set "COGLISP_VERSION="
set "COGLISP_BUILD_TIME="
set "GIT_AUTHOR_NAME=t"
set "GIT_AUTHOR_EMAIL=t@t"
set "GIT_COMMITTER_NAME=t"
set "GIT_COMMITTER_EMAIL=t@t"
set "T=20261110153000"
set PASS=0
set TOTAL=0

echo == cog-lisp : scripts\version.bat (specs/28-versioning.md) ==
mkdir "%REPO%\scripts"
copy /y "%ROOT%\scripts\version.bat" "%REPO%\scripts\version.bat" >nul

call :version
call :check "not a git repository" "0.0.0-dev.0.%T%"
set "ERR="
for /f "delims=" %%e in ('cmd /d /c "set COGLISP_BUILD_TIME=%T%&& "%REPO%\scripts\version.bat"" 2^>^&1 1^>nul') do set "ERR=%%e"
set "GOT=!ERR!"
call :check "not a git repository: it says so on stderr" "version: not a git repository; the version is 0.0.0-dev.0.%T%"

git -C "%REPO%" init -q
git -C "%REPO%" config core.autocrlf false
>"%REPO%\.gitignore" echo scripts/
git -C "%REPO%" add .gitignore
call :commit one
call :version
call :check "no release tag" "0.0.0-dev.0.%T%"

git -C "%REPO%" tag v0.4.0
call :version
call :check "at a release's tag" "0.4.0"
>"%REPO%\untracked.txt" echo stray
call :version
call :check "an untracked file is not a change" "0.4.0"
>>"%REPO%\file.txt" echo changed
call :version
call :check "at the tag, with an uncommitted change" "0.4.1-dev.0.%T%.dirty"
git -C "%REPO%" checkout -q -- file.txt

call :commit two
call :commit three
call :version
call :check "two commits after the tag" "0.4.1-dev.2.%T%"
>>"%REPO%\file.txt" echo changed
call :version
call :check "after the tag, with an uncommitted change" "0.4.1-dev.2.%T%.dirty"
git -C "%REPO%" checkout -q -- file.txt

git -C "%REPO%" tag v0.5.0-rc1
call :commit four
call :version
call :check "after a pre-release tag" "0.5.0-rc1.dev.1.%T%"
git -C "%REPO%" tag v0.9.10
call :commit five
call :version
call :check "a patch number of two digits" "0.9.11-dev.1.%T%"

set "GOT="
for /f "delims=" %%v in ('cmd /d /c "set COGLISP_VERSION=1.2.3&& "%REPO%\scripts\version.bat""') do set "GOT=%%v"
call :check "COGLISP_VERSION wins" "1.2.3"
set "GOT="
for /f "delims=" %%v in ('"%REPO%\scripts\version.bat" 2^>nul') do set "GOT=%%v"
set "OK=0"
echo !GOT!| findstr /r /x "0\.9\.11-dev\.1\.[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]" >nul && set "OK=1"
set "GOT=!OK!"
call :check "the time is 14 digits, by default now" "1"

rmdir /s /q "%REPO%"
echo.
echo == RESULT: !PASS!/!TOTAL! checks passed ==
if "!PASS!"=="!TOTAL!" exit /b 0
exit /b 1

rem  GOT := what version.bat prints, at the fixed time
:version
set "GOT="
for /f "delims=" %%v in ('cmd /d /c "set COGLISP_BUILD_TIME=%T%&& "%REPO%\scripts\version.bat"" 2^>nul') do set "GOT=%%v"
exit /b 0

rem  %1 what, %2 the answer wanted; GOT holds the answer given
:check
set /a TOTAL+=1
if "!GOT!"=="%~2" (
  set /a PASS+=1
  echo   PASS  %~1
) else (
  echo   FAIL  %~1  got=!GOT!  want=%~2
)
exit /b 0

:commit
>>"%REPO%\file.txt" echo %1
git -C "%REPO%" add file.txt
git -C "%REPO%" commit -q -m %1
exit /b 0
