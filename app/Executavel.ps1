# Claude Remote Manager - gera e usa o "Claude Remote Manager.exe".
# O .exe já vem pronto no zip do site (e é trocado pelas atualizações). Só se ele faltar, é compilado
# aqui mesmo no PC com o csc.exe do .NET Framework que vem no Windows.

$script:ExeRaiz    = Split-Path $PSScriptRoot -Parent
$script:ExeArquivo = Join-Path $script:ExeRaiz 'Claude Remote Manager.exe'
$script:ExeFonte   = Join-Path $PSScriptRoot 'Lancador.cs'
$script:ExeMarca   = Join-Path (Join-Path $env:USERPROFILE '.claude-remote-manager') 'lancador.sha'

function Get-Csc {
    foreach ($d in @("$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319", "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319")) {
        $c = Join-Path $d 'csc.exe'
        if (Test-Path $c) { return $c }
    }
    return $null
}

function Get-HashFonte {
    $arqs = @($script:ExeFonte, (Join-Path $PSScriptRoot 'lancador.manifest'), (Join-Path $PSScriptRoot 'icone.ico'))
    $txt = ($arqs | ForEach-Object { if (Test-Path $_) { (Get-FileHash $_ -Algorithm SHA256).Hash } else { '-' } }) -join ','
    return $txt
}

# Compila o .exe só se ele não existe. Devolve $true se o .exe está pronto.
function Update-Executavel {
    if (Test-Path $script:ExeArquivo) { return $true }
    if (-not (Test-Path $script:ExeFonte)) { return $false }
    $hash = Get-HashFonte
    $csc = Get-Csc
    if (-not $csc) { return (Test-Path $script:ExeArquivo) }
    $sma = [PSObject].Assembly.Location
    $tmp = Join-Path $env:TEMP ("crm-exe-" + [guid]::NewGuid().ToString('N') + '.exe')
    $a = @('/nologo', '/target:winexe', '/optimize+', "/out:$tmp", "/r:$sma", '/r:System.Windows.Forms.dll', '/r:System.Core.dll')
    $ico = Join-Path $PSScriptRoot 'icone.ico'
    $man = Join-Path $PSScriptRoot 'lancador.manifest'
    if (Test-Path $ico) { $a += "/win32icon:$ico" }
    if (Test-Path $man) { $a += "/win32manifest:$man" }
    $a += $script:ExeFonte
    $saida = & $csc @a 2>&1
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tmp)) {
        $script:ExeErro = ($saida | Out-String).Trim()
        return (Test-Path $script:ExeArquivo)
    }
    # O .exe antigo pode estar fechando agora (depois de Atualizar agora): tenta por alguns segundos.
    for ($i = 0; $i -lt 20; $i++) {
        try { Copy-Item $tmp $script:ExeArquivo -Force -ErrorAction Stop; break } catch { Start-Sleep -Milliseconds 500 }
    }
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path $script:ExeArquivo)) { return $false }
    New-Item -ItemType Directory -Force (Split-Path $script:ExeMarca -Parent) | Out-Null
    [IO.File]::WriteAllText($script:ExeMarca, $hash)
    return $true
}

# Quando a janela foi aberta pelo PowerShell (o .bat ou uma atualização), passa para o .exe.
# Devolve $true se abriu o .exe (quem chamou deve sair).
function Switch-ParaExecutavel {
    if ($env:CRM_EXE) { return $false }
    try {
        if (-not (Update-Executavel)) { return $false }
        # Se o .exe falhou depois de gerado, segue pelo PowerShell até ele ser refeito.
        $falha = Join-Path (Split-Path $script:ExeMarca -Parent) 'exe-falhou.txt'
        if ((Test-Path $falha) -and (Get-Item $falha).LastWriteTime -gt (Get-Item $script:ExeArquivo).LastWriteTime) {
            $script:ExeErro = 'o .exe deu erro na última vez (veja ' + $falha + ').'
            return $false
        }
        Start-Process -FilePath $script:ExeArquivo | Out-Null
        return $true
    } catch { return $false }
}
