@echo off
rem Atalho do assistente: libera a execucao do PowerShell so para este script.
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0aluno.ps1" %*
set "RC=%ERRORLEVEL%"
if "%~1"=="" pause
exit /b %RC%
