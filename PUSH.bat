@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo === Gov-News Thailand PUSH ===
echo Repo: %CD%
echo Time: %DATE% %TIME%

for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set "TODAY=%%I"
set "SRC=%~dp0..\Document\%TODAY%_News\%TODAY%_news.json"
set "DEST=%CD%\data\%TODAY%_news.json"
set "MANIFEST=%CD%\data\manifest.json"

echo.
echo [0/5] Today: %TODAY%
if exist "%SRC%" (
  echo Copy: %SRC%
  copy /Y "%SRC%" "%DEST%" >nul
  if errorlevel 1 (
    echo ERROR: copy failed
    exit /b 1
  )
  echo Copied to data\%TODAY%_news.json
  python "%~dp0update-manifest.py" "%MANIFEST%" "%TODAY%_news.json"
  if errorlevel 1 (
    echo ERROR: manifest update failed
    exit /b 1
  )
) else (
  echo WARNING: source not found: %SRC%
  echo Will push whatever is already in data\
)

echo.
echo [1/5] Remove .git lock files...
del /f /q ".git\index.lock" 2>nul
del /f /q ".git\HEAD.lock" 2>nul
del /f /q ".git\config.lock" 2>nul
del /f /q ".git\refs\heads\master.lock" 2>nul
del /f /q ".git\shallow.lock" 2>nul
for /r ".git" %%F in (*.lock) do del /f /q "%%F" 2>nul

echo.
echo [2/5] git add data/...
git add -- "data/%TODAY%_news.json" "data/manifest.json"
git add -- "data/"
if errorlevel 1 (
  echo ERROR: git add failed
  exit /b 1
)

echo.
echo [3/5] git commit...
git diff --cached --quiet
if errorlevel 1 (
  git commit -m "Add news %TODAY%"
  if errorlevel 1 (
    echo ERROR: git commit failed
    exit /b 1
  )
) else (
  echo Nothing new to commit.
)

echo.
echo [4/5] git push origin master...
git push origin master
if errorlevel 1 (
  echo Push rejected - pull --rebase then retry...
  git pull --rebase origin master
  git push origin master
  if errorlevel 1 (
    echo ERROR: git push failed
    exit /b 1
  )
)

echo.
echo [5/5] Verify...
git fetch origin
git status -sb
git log --oneline -3
if not exist "data\%TODAY%_news.json" (
  echo ERROR: data\%TODAY%_news.json missing
  exit /b 1
)
echo OK: data\%TODAY%_news.json present
echo.
echo SUCCESS - https://chiraleo2000.github.io/gov-news-thailand/
exit /b 0
