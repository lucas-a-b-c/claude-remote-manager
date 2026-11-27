@echo off
rem Claude Remote Manager: abre a janela que cria, confere, conserta, loga e testa os Remote Control deste PC.
rem   sem argumentos       -> abre a janela
rem   /consertar           -> sem janela: cria os sugeridos que faltam e confere/conserta todos (abre login se precisar)
rem   /consertar-sem-login -> igual, mas nunca abre login (para rodar por uma sessao remota)
setlocal
set "APP=%~dp0app\Janela.ps1"

net session >nul 2>&1
if errorlevel 1 (
  echo Pedindo permissao de administrador...
  if "%~1"=="" (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  ) else (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%~1' -Verb RunAs"
  )
  exit /b
)

if /i "%~1"=="/consertar" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%APP%" -ConsertarTudo
  pause
  exit /b
)
if /i "%~1"=="/consertar-sem-login" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%APP%" -ConsertarTudo -SemLogin
  exit /b
)

start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File "%APP%"
