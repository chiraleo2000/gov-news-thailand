@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

REM === Daily Gov-News Pages push (scheduled 18:00) ===
REM Task Scheduler often has a thin PATH / inherited proxy — fix that first.
set "PATH=C:\Program Files\Git\cmd;C:\Program Files\Git\bin;%LOCALAPPDATA%\Python\bin;%LOCALAPPDATA%\Programs\Python\Python312;%LOCALAPPDATA%\Programs\Python\Python311;%LOCALAPPDATA%\Programs\Python\Python310;%PATH%"
set "HTTP_PROXY="
set "HTTPS_PROXY="
set "http_proxy="
set "https_proxy="
set "ALL_PROXY="
set "all_proxy="
set "NO_PROXY=*"
set "no_proxy=*"
set "GIT_HTTP_LOW_SPEED_LIMIT=1000"
set "GIT_HTTP_LOW_SPEED_TIME=60"

set "REPO=%CD%"
set "PARENT=%~dp0.."
for %%I in ("%PARENT%") do set "PARENT=%%~fI"
set "LOGDIR=%PARENT%\Logs"
if not exist "%LOGDIR%" mkdir "%LOGDIR%" >nul 2>&1

for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set "TODAY=%%I"
set "LOG=%LOGDIR%\gov-push-%TODAY%.log"
set "DOCROOT=%PARENT%\Document"
set "RESULT=FAIL"

call :log "=== Gov-News Thailand PUSH ==="
call :log "Repo: %REPO%"
call :log "Time: %DATE% %TIME%"
call :pscheck "START" "Gov-News PUSH starting"

where git >nul 2>&1
if errorlevel 1 ( set "ERR=git not found on PATH" & goto :fail )

where python >nul 2>&1
if errorlevel 1 ( set "ERR=python not found on PATH" & goto :fail )

if not exist ".git" ( set "ERR=not a git repo: %REPO%" & goto :fail )

set "HELPER=%~dp0update-manifest.py"
if not exist "%HELPER%" ( set "ERR=missing update-manifest.py" & goto :fail )

echo.
echo [0/6] Remove .ps1 / .sh before push
call :cleanup_scripts
call :pscheck "CLEAN" "Removed leftover .ps1/.sh (if any)"

REM === TODAY ONLY — never republish an older date ===
set "TARGET=%TODAY%"
set "ENTRY=!TARGET!_news.json"
set "DOC_SRC=%DOCROOT%\!TARGET!_News\!ENTRY!"
set "DATA_SRC=%REPO%\data\!ENTRY!"
set "SRC="

call :find_today_source
if not defined SRC (
  call :log "Today source missing - waiting up to 10 minutes for !ENTRY!"
  call :wait_today_source 20 30
)
if not defined SRC (
  set "ERR=TODAY news missing: need Document\!TARGET!_News\!ENTRY! or data\!ENTRY! — refusing to push old news"
  goto :fail
)

REM Keep Document in sync when source was data/
if /I not "%SRC%"=="%DOC_SRC%" (
  if not exist "%DOCROOT%\!TARGET!_News" mkdir "%DOCROOT%\!TARGET!_News" >nul 2>&1
  copy /Y "%SRC%" "%DOC_SRC%" >nul
  call :log "Synced Document\!TARGET!_News\!ENTRY!"
)

set "DEST=%REPO%\data\!ENTRY!"
set "MANIFEST=%REPO%\data\manifest.json"

call :log "Target date: !TARGET! (TODAY ONLY)"
call :log "Source: %SRC%"
call :pscheck "SOURCE" "Using !ENTRY!"

echo.
echo [1/6] Copy + manifest
copy /Y "%SRC%" "%DEST%" >nul
if errorlevel 1 ( set "ERR=copy failed" & goto :fail )
for %%A in ("%DEST%") do call :log "Copied data\!ENTRY! (%%~zA bytes)"
python "%HELPER%" "%MANIFEST%" "!ENTRY!"
if errorlevel 1 ( set "ERR=manifest update failed" & goto :fail )
call :pscheck "COPY" "JSON + manifest updated"

echo.
echo [2/6] Clear .git locks
call :clear_locks
call :pscheck "LOCKS" "Cleared"

echo.
echo [3/6] git add data/ only
git add -- "data/!ENTRY!" "data/manifest.json"
if errorlevel 1 ( set "ERR=git add failed" & goto :fail )
REM never stage scripts
git reset HEAD -- "*.ps1" "*.sh" 2>nul
call :log "Staged files:"
for /f "delims=" %%F in ('git diff --cached --name-only') do call :log "  %%F"
call :pscheck "ADD" "Staged data files"

echo.
echo [4/6] git commit
git diff --cached --quiet
if errorlevel 1 (
  git commit -m "Add news !TARGET!"
  if errorlevel 1 ( set "ERR=git commit failed" & goto :fail )
  call :log "Committed Add news !TARGET!"
  call :pscheck "COMMIT" "Add news !TARGET!"
) else (
  call :log "Nothing new to commit"
  call :pscheck "COMMIT" "Nothing new"
)

echo.
echo [5/6] git push origin master
set "PUSHED=0"
git push origin master
if not errorlevel 1 set "PUSHED=1"

if "!PUSHED!"=="0" (
  call :log "Push rejected - pull --rebase then retry"
  call :pscheck "RETRY" "pull --rebase"
  call :clear_locks
  git pull --rebase origin master
  if errorlevel 1 (
    call :log "rebase failed - abort and retry pull"
    git rebase --abort 2>nul
    git pull origin master
  )
  git push origin master
  if errorlevel 1 (
    call :log "second push failed - one more pull --rebase"
    call :clear_locks
    git pull --rebase origin master
    git push origin master
    if errorlevel 1 ( set "ERR=git push failed after retries" & goto :fail )
  )
)
call :log "Push OK"
call :pscheck "PUSH" "origin/master updated"

echo.
echo [6/6] Verify + print log
git fetch origin
if errorlevel 1 ( set "ERR=git fetch failed after push" & goto :fail )

for /f %%A in ('git rev-list --count origin/master..HEAD') do set "AHEAD=%%A"
call :log "AHEAD=!AHEAD!"
if not "!AHEAD!"=="0" ( set "ERR=still ahead by !AHEAD! commit(s) - PUSH FAIL" & goto :fail )

if not exist "%DEST%" ( set "ERR=data\!ENTRY! missing after push" & goto :fail )

REM Guard: never allow PASS if we somehow targeted a non-today date
if /I not "!TARGET!"=="%TODAY%" (
  set "ERR=refusing PASS - TARGET=!TARGET! is not TODAY=%TODAY%"
  goto :fail
)

for /f %%H in ('git rev-parse --short HEAD') do set "HEADSHORT=%%H"
call :log "OK data\!ENTRY! present"
call :log "HEAD=!HEADSHORT!"
call :log "RESULT=PASS"
call :log "SUCCESS - https://chiraleo2000.github.io/gov-news-thailand/"
set "RESULT=PASS"
call :print_summary
echo.
echo ===== PUSH PASS =====
echo SUCCESS - https://chiraleo2000.github.io/gov-news-thailand/
exit /b 0

:find_today_source
set "SRC="
if exist "%DOC_SRC%" (
  set "SRC=%DOC_SRC%"
  call :log "Found Document source: %DOC_SRC%"
  exit /b 0
)
if exist "%DATA_SRC%" (
  set "SRC=%DATA_SRC%"
  call :log "Found data/ source: %DATA_SRC%"
  exit /b 0
)
exit /b 1

:wait_today_source
REM %1 = attempts, %2 = seconds between attempts
set "TRIES=%~1"
set "DELAY=%~2"
if not defined TRIES set "TRIES=20"
if not defined DELAY set "DELAY=30"
for /L %%N in (1,1,!TRIES!) do (
  call :find_today_source
  if defined SRC exit /b 0
  call :log "Wait %%N/!TRIES! - still no !ENTRY! (sleep !DELAY!s)"
  powershell -NoProfile -Command "Start-Sleep -Seconds !DELAY!" >nul
)
exit /b 1

:clear_locks
del /f /q ".git\index.lock" 2>nul
del /f /q ".git\HEAD.lock" 2>nul
del /f /q ".git\config.lock" 2>nul
del /f /q ".git\refs\heads\master.lock" 2>nul
del /f /q ".git\shallow.lock" 2>nul
for /r ".git" %%F in (*.lock) do del /f /q "%%F" 2>nul
call :log "Locks cleared"
exit /b 0

:cleanup_scripts
REM Delete .ps1 / .sh in pages repo + parent project root (never commit them)
for %%P in ("%REPO%" "%PARENT%") do (
  if exist "%%~P" (
    for %%F in ("%%~P\*.ps1" "%%~P\*.sh") do (
      if exist "%%~F" (
        del /f /q "%%~F" >nul 2>&1
        call :log "Deleted script: %%~F"
      )
    )
  )
)
exit /b 0

:pscheck
REM Colored PowerShell status line + append to log
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$step='%~1'; $msg='%~2'; $c='Cyan'; if($step -eq 'PUSH' -or $step -eq 'PASS'){$c='Green'}; if($step -eq 'FAIL'){$c='Red'}; Write-Host ('[{0}] {1}' -f $step,$msg) -ForegroundColor $c"
>>"%LOG%" echo %DATE% %TIME% [%~1] %~2
exit /b 0

:log
echo %~1
>>"%LOG%" echo %DATE% %TIME% %~1
exit /b 0

:print_summary
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$log='%LOG%'; $repo='%REPO%'; $result='%RESULT%'; Write-Host ''; Write-Host '==== Gov-News Push Log (tail) ====' -ForegroundColor Cyan; if(Test-Path -LiteralPath $log){ Get-Content -LiteralPath $log -Tail 40 } else { Write-Host 'No log file' -ForegroundColor Yellow }; Write-Host ''; Set-Location -LiteralPath $repo; git fetch origin 2>$null | Out-Null; $ahead=0; try { $ahead=[int](git rev-list --count origin/master..HEAD 2>$null) } catch {}; $head=(git rev-parse --short HEAD); $orig=(git rev-parse --short origin/master 2>$null); Write-Host ('HEAD=' + $head + '  origin/master=' + $orig + '  AHEAD=' + $ahead); if($result -eq 'PASS' -and $ahead -eq 0){ Write-Host 'PUSH PASS' -ForegroundColor Green } else { Write-Host 'PUSH FAIL' -ForegroundColor Red }; Write-Host 'Live: https://chiraleo2000.github.io/gov-news-thailand/'; Write-Host ('Log: ' + $log)"
exit /b 0

:fail
call :log "ERROR: !ERR!"
call :log "RESULT=FAIL"
set "RESULT=FAIL"
call :pscheck "FAIL" "!ERR!"
call :print_summary
echo.
echo ===== PUSH FAIL =====
echo ERROR: !ERR!
echo See log: %LOG%
exit /b 1
