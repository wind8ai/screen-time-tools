@echo off
setlocal DisableDelayedExpansion
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -File "%~dp0shutdown-timer.ps1"
set "screenTimeExitCode=%ERRORLEVEL%"
if "%screenTimeExitCode%"=="0" exit /b 0
echo.
echo Unable to start the shutdown timer. Review the error above.
pause
exit /b %screenTimeExitCode%
