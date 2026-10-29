@echo off
rem Wrapper so the build works without changing the machine's execution policy.
rem Usage: build-and-install.cmd [-Variant Release] [-SkipInstall]
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-and-install.ps1" %*
exit /b %ERRORLEVEL%
