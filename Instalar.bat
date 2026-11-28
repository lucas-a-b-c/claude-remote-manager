@echo off
rem Claude Remote Manager - instalador. De dois cliques neste arquivo (depois de extrair o zip).
setlocal
if not exist "%~dp0app\Instalar.ps1" (
  echo.
  echo Extraia o zip primeiro: botao direito no zip, "Extrair tudo...".
  echo Depois abra o Instalar.bat de dentro da pasta extraida.
  echo.
  pause
  exit /b 1
)
net session >nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0app\Instalar.ps1"
if errorlevel 1 pause
