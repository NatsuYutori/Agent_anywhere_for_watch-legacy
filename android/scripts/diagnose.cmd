@echo off
rem Wrapper so the script runs without changing the machine's execution policy.
rem Usage: diagnose.cmd [-SettleSeconds 20]
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0diagnose.ps1" %*
exit /b %ERRORLEVEL%
