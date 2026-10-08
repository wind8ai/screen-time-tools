@echo off
setlocal DisableDelayedExpansion
set "screenTimePowerShell=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "screenTimeLog=%TEMP%\screen-time-tools-shutdown-startup-%RANDOM%-%RANDOM%.log"
"%screenTimePowerShell%" -NoLogo -NoProfile -STA -WindowStyle Hidden -File "%~dp0src\shutdown-timer.ps1" >"%screenTimeLog%" 2>&1
set "screenTimeExitCode=%ERRORLEVEL%"
if "%screenTimeExitCode%"=="0" (
    del /q "%screenTimeLog%" >nul 2>&1
    exit /b 0
)
"%screenTimePowerShell%" -NoLogo -NoProfile -WindowStyle Normal -Command "exit 0" >nul 2>&1
echo.
echo Unable to start the shutdown timer.
if exist "%screenTimeLog%" type "%screenTimeLog%"
echo.
echo Diagnostic log: "%screenTimeLog%"
pause
exit /b %screenTimeExitCode%
