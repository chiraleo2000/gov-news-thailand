@echo off
cd /d "D:\Gov-News-GitHub\gov-news-thailand"

echo Checking git status...
git status

echo.
echo Attempting git push to origin/master...
git push origin master

if %ERRORLEVEL% EQU 0 (
    echo.
    echo SUCCESS! Push completed.
    pause
    exit /b 0
) else (
    echo.
    echo First push failed. Trying with rebase...
    git pull --rebase origin master
    git push origin master

    if %ERRORLEVEL% EQU 0 (
        echo.
        echo SUCCESS! Push completed with rebase.
        pause
        exit /b 0
    ) else (
        echo.
        echo Attempting force push...
        git push -f origin master

        if %ERRORLEVEL% EQU 0 (
            echo.
            echo SUCCESS! Force push completed.
            pause
            exit /b 0
        ) else (
            echo.
            echo FAILED! All push attempts failed.
            pause
            exit /b 1
        )
    )
)
