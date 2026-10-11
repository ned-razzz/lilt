@echo off
pwsh.exe -NoLogo -NoProfile -File "%~dp0codex-prompt-coach.ps1" %*
exit /b %ERRORLEVEL%
