# Claude Remote Manager - instala num PC novo (chamado pelo Instalar.bat, já como administrador).
# Copia a pasta app para "%LOCALAPPDATA%\Programs\Claude Remote Manager", gera o .exe, cria os atalhos
# na área de trabalho e no menu Iniciar e abre o programa. Pode rodar de novo sem problema.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
$destino = Join-Path $env:LOCALAPPDATA 'Programs\Claude Remote Manager'
$origem = $PSScriptRoot
try {
    Write-Host "Instalando o Claude Remote Manager em $destino ..."
    # Fecha o programa se estiver aberto (os Remote Control não são afetados).
    Get-Process -Name 'Claude Remote Manager' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
    $app = Join-Path $destino 'app'
    New-Item -ItemType Directory -Force $app | Out-Null
    if ((Resolve-Path $origem).Path.TrimEnd('\') -ne (Resolve-Path $app).Path.TrimEnd('\')) {
        Copy-Item -Path (Join-Path $origem '*') -Destination $app -Recurse -Force
    }
    Get-ChildItem $destino -Recurse -File | Unblock-File -ErrorAction SilentlyContinue

    # Gera o .exe.
    . (Join-Path $app 'Executavel.ps1')
    $ErrorActionPreference = 'Continue'
    $exeOk = Update-Executavel
    $ErrorActionPreference = 'Stop'
    $exe = Join-Path $destino 'Claude Remote Manager.exe'
    $alvo = if ($exeOk -and (Test-Path $exe)) { $exe } else { Join-Path $app 'Abrir.bat' }

    # Atalhos.
    $shell = New-Object -ComObject WScript.Shell
    foreach ($pasta in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs'))) {
        if (-not $pasta) { continue }
        $lnk = $shell.CreateShortcut((Join-Path $pasta 'Claude Remote Manager.lnk'))
        $lnk.TargetPath = $alvo
        $lnk.WorkingDirectory = $destino
        if (Test-Path (Join-Path $app 'icone.ico')) { $lnk.IconLocation = (Join-Path $app 'icone.ico') }
        $lnk.Save()
    }

    Start-Process -FilePath $alvo -WorkingDirectory $destino | Out-Null
    $aviso = if ($alvo -eq $exe) { '' } else { "`r`n`r`nNão consegui gerar o .exe ($script:ExeErro); o atalho abre pelo PowerShell." }
    [void][Windows.Forms.MessageBox]::Show("Pronto! O Claude Remote Manager foi instalado e já está abrindo.`r`n`r`nAtalho na área de trabalho e no menu Iniciar. Pode apagar o zip e a pasta extraída.$aviso", 'Claude Remote Manager', 'OK', 'Information')
    exit 0
} catch {
    [void][Windows.Forms.MessageBox]::Show("Não consegui instalar: $($_.Exception.Message)", 'Claude Remote Manager', 'OK', 'Error')
    exit 1
}
