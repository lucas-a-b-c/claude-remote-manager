@echo off
rem Claude Remote Manager: abre o programa (use este arquivo só na primeira vez).
rem Ele gera o "Claude Remote Manager.exe" na pasta de cima; depois disso, abra pelo .exe.
setlocal
set "APP=%~dp0Janela.ps1"
net session >nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File "%APP%"
