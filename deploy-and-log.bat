@echo off
setlocal enabledelayedexpansion

cd /d "D:\Gov-News-GitHub\gov-news-thailand"

set "logfile=deploy-log.txt"

(
    echo Timestamp: %date% %time%
    echo.
    echo Checking current location...
    cd
    echo.
    echo Git status before push:
    git status
    echo.
    echo ===================================
    echo Attempting git push to origin/master...
    echo ===================================
    echo.
    git push origin master

    if !ERRORLEVEL! EQU 0 (
        echo.
        echo SUCCESS! Git push completed on first attempt.
        goto :success
    ) else (
        echo.
        echo First push attempt failed with error code !ERRORLEVEL!
        echo Trying with git pull --rebase...
        echo.
        git pull --rebase origin master
        git push origin master

        if !ERRORLEVEL! EQU 0 (
            echo.
            echo SUCCESS! Git push completed after rebase.
            goto :success
        ) else (
            echo.
            echo Rebase/push attempt failed with error code !ERRORLEVEL!
            echo Attempting force push...
            echo.
            git push -f origin master

            if !ERRORLEVEL! EQU 0 (
                echo.
                echo SUCCESS! Force push completed.
                goto :success
            ) else (
                echo.
                echo FAILED! All push attempts failed with error code !ERRORLEVEL!
                goto :failure
            )
        )
    )

    :success
    echo.
    echo =================================
    echo DEPLOYMENT SUCCESSFUL
    echo =================================
    echo Timestamp: %date% %time%
    exit /b 0

    :failure
    echo.
    echo =================================
    echo DEPLOYMENT FAILED
    echo =================================
    echo Timestamp: %date% %time%
    exit /b 1

) > "!logfile!" 2>&1

echo Log saved to: %logfile%
type "%logfile%"
pause
