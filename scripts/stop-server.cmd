@echo off
setlocal
cd /d "%~dp0.."
call npm run stop
echo.
pause
exit /b %ERRORLEVEL%
