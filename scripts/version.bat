@echo off
setlocal EnableDelayedExpansion
rem ===========================================================================
rem  cog-lisp : print the version of a build  (specs/28-versioning.md R-1 to R-7;
rem  the twin of scripts/version.sh, which must give the same answers)
rem
rem  COGLISP_VERSION, when set, is the version (a release sets it from its tag).
rem  Otherwise git gives it:
rem    at a release's tag, nothing uncommitted   0.4.0
rem    anywhere else                             0.4.1-dev.4.20261110153000
rem      (the next patch, the commits since the tag, the build's time in UTC)
rem    with uncommitted changes                  ... .dirty
rem    without git, or without a tag             0.0.0-dev.0.20261110153000
rem  COGLISP_BUILD_TIME (14 digits, UTC) gives the time, so one build can stamp
rem  several things with one version. Only the version goes to stdout. (STAMP,
rem  not TIME: cmd's TIME is the clock.)
rem ===========================================================================

if defined COGLISP_VERSION (
  echo(!COGLISP_VERSION!
  exit /b 0
)

set "ROOT=%~dp0.."
set "STAMP=%COGLISP_BUILD_TIME%"
if not defined STAMP (
  for /f %%t in ('powershell -NoProfile -Command "(Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss')"') do set "STAMP=%%t"
)

set "DIRTY="
git -C "%ROOT%" rev-parse --git-dir >nul 2>&1
if errorlevel 1 (
  set "WHY=not a git repository"
  goto :fallback
)
rem  tracked files only: a stray untracked file does not make a build unreproducible
for /f "delims=" %%l in ('git -C "%ROOT%" status --porcelain --untracked-files^=no 2^>nul') do set "DIRTY=.dirty"

set "TAG="
for /f "delims=" %%t in ('git -C "%ROOT%" describe --tags --abbrev^=0 --match "v[0-9]*" 2^>nul') do set "TAG=%%t"
if not defined TAG (
  set "WHY=no release tag"
  goto :fallback
)
for /f %%n in ('git -C "%ROOT%" rev-list --count !TAG!..HEAD') do set "COMMITS=%%n"
set "RELEASE=!TAG:~1!"
if "!COMMITS!"=="0" if not defined DIRTY (
  echo(!RELEASE!
  exit /b 0
)

rem  0.4.0 -> 0.4.1-dev.N.TIME; a pre-release tag 0.5.0-rc1 -> 0.5.0-rc1.dev.N.TIME,
rem  which still sorts after the tag and before 0.5.0
if not "!RELEASE:-=!"=="!RELEASE!" (
  set "BASE=!RELEASE!.dev"
) else (
  for /f "tokens=1-3 delims=." %%a in ("!RELEASE!") do (
    set "MAJOR=%%a"
    set "MINOR=%%b"
    set /a PATCH=%%c+1
  )
  set "BASE=!MAJOR!.!MINOR!.!PATCH!-dev"
)
echo(!BASE!.!COMMITS!.!STAMP!!DIRTY!
exit /b 0

:fallback
1>&2 echo version: !WHY!; the version is 0.0.0-dev.0.!STAMP!
echo(0.0.0-dev.0.!STAMP!!DIRTY!
exit /b 0
