@echo off
setlocal enabledelayedexpansion

cd /d "D:\Gov-News-GitHub\gov-news-thailand"

echo.
echo Setting up git credential storage...
git config --global credential.helper wincred

echo.
echo Checking current remote...
git remote -v

echo.
echo Current git status:
git status

echo.
echo Attempting to push (will prompt for credentials if needed)...
echo.
echo When prompted, enter:
echo Username: chiraleo2000
echo Password: (your GitHub password or Personal Access Token)
echo.

git push -u origin master

if !ERRORLEVEL! EQU 0 (
    echo.
    echo ============================================
    echo SUCCESS! Git push completed.
    echo ============================================
    pause
    exit /b 0
) else (
    echo.
    echo Push failed. Trying with rebase...
    git pull --rebase origin master
    git push -u origin master

    if !ERRORLEVEL! EQU 0 (
        echo.
        echo SUCCESS after rebase!
        pause
        exit /b 0
    ) else (
        echo.
        echo FAILED - Push unsuccessful
        echo Error code: !ERRORLEVEL!
        pause
        exit /b 1
    )
)
