@echo off
pwsh.exe -NoLogo -NoProfile -File "%~dp0lilt.ps1" %*
exit /b %ERRORLEVEL%
