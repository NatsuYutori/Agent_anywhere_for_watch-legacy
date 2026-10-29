@echo off
rem Wrapper so the script runs without changing the machine's execution policy.
rem Usage: screenshot.cmd [-SettleSeconds 10]
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0screenshot.ps1" %*
exit /b %ERRORLEVEL%
