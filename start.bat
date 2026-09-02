@echo off
setlocal
cd /d "%~dp0"
title Minecraft Companion Bot

where node >nul 2>nul
if errorlevel 1 goto :no_node

node "scripts\launch.js"
goto :done

:no_node
echo.
echo   Node.js is not installed - the bot needs it to run.
echo.
where winget >nul 2>nul
if errorlevel 1 goto :manual_node

choice /c YN /m "  Install Node.js now (recommended)"
if errorlevel 2 goto :manual_node

echo.
echo   Installing Node.js LTS...
winget install -e --id OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements
echo.
echo   Node.js is installed. Close this window and double-click start.bat again.
goto :done

:manual_node
echo   Download the LTS installer from https://nodejs.org, install it,
echo   then double-click start.bat again.
start "" https://nodejs.org/en/download
goto :done

:done
echo.
pause
