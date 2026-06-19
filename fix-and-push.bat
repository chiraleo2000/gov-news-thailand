@echo off
setlocal enabledelayedexpansion

cd /d "D:\Gov-News-GitHub\gov-news-thailand"

echo.
echo Checking current git remote...
git remote -v

echo.
echo Switching remote back to HTTPS...
git remote set-url origin https://github.com/chiraleo2000/gov-news-thailand.git

echo.
echo Updated remote:
git remote -v

echo.
echo Attempting git push with HTTPS...
git push origin master

if !ERRORLEVEL! EQU 0 (
    echo.
    echo SUCCESS! Push completed.
    exit /b 0
) else (
    echo.
    echo Push failed. Trying with pull --rebase...
    git pull --rebase origin master
    git push origin master

    if !ERRORLEVEL! EQU 0 (
        echo SUCCESS after rebase!
        exit /b 0
    ) else (
        echo FAILED - All attempts unsuccessful
        exit /b 1
    )
)
