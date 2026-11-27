# Claude Remote Manager - atualização automática pelo site CruzVerbenaGroup.
# Ao abrir a janela, pergunta ao site qual é a versão publicada. Se for mais nova que a deste PC,
# baixa o pacote, instala por cima desta pasta e abre o programa de novo.
# O login do site fica salvo por usuário do Windows (criptografado com DPAPI) em
# %USERPROFILE%\.claude-remote-manager\site-login.xml. Sem internet ou com o site fora do ar, segue sem atualizar.

$script:AtuApp      = 'claude-remote-manager'
$script:AtuRaiz     = Split-Path $PSScriptRoot -Parent
$script:AtuVersao   = Join-Path $PSScriptRoot 'versao.txt'
$script:AtuSiteJson = Join-Path $PSScriptRoot 'site.json'
$script:AtuLogin    = Join-Path (Join-Path $env:USERPROFILE '.claude-remote-manager') 'site-login.xml'

function Get-VersaoLocal {
    try { return [version]((Get-Content $script:AtuVersao -Raw).Trim()) } catch { return [version]'0.0.0' }
}

function Get-SiteUrl {
    try { return ((Get-Content $script:AtuSiteJson -Raw -Encoding UTF8 | ConvertFrom-Json).url).TrimEnd('/') } catch { return $null }
}

function Get-LoginSite([switch]$Pedir) {
    if (-not $Pedir -and (Test-Path $script:AtuLogin)) {
        try { return Import-Clixml $script:AtuLogin } catch { }
    }
    if (-not $Pedir) { return $null }
    $c = Get-Credential -Message 'Login do site CruzVerbenaGroup (para o programa se atualizar sozinho)'
    return $c
}

function Save-LoginSite($cred) {
    $dir = Split-Path $script:AtuLogin -Parent
    New-Item -ItemType Directory -Force $dir | Out-Null
    $cred | Export-Clixml $script:AtuLogin
}

function New-ClienteSite($cred) {
    $wc = New-Object Net.WebClient
    $par = $cred.UserName + ':' + $cred.GetNetworkCredential().Password
    $wc.Headers['Authorization'] = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($par))
    $wc.Headers['User-Agent'] = 'claude-remote-manager'
    $wc.Encoding = [Text.Encoding]::UTF8
    return $wc
}

# Devolve o objeto da versão publicada, $null se não deu para consultar.
function Get-VersaoSite([switch]$PodePedirLogin) {
    $url = Get-SiteUrl
    if (-not $url) { return $null }
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $cred = Get-LoginSite
    for ($tentativa = 0; $tentativa -lt 3; $tentativa++) {
        if (-not $cred) {
            if (-not $PodePedirLogin) { return $null }
            $cred = Get-LoginSite -Pedir
            if (-not $cred) { return $null }
        }
        try {
            $wc = New-ClienteSite $cred
            $txt = $wc.DownloadString("$url/api/versao/$($script:AtuApp)")
            $info = $txt | ConvertFrom-Json
            Save-LoginSite $cred
            $info | Add-Member -NotePropertyName Credencial -NotePropertyValue $cred -Force
            $info | Add-Member -NotePropertyName Site -NotePropertyValue $url -Force
            return $info
        } catch [Net.WebException] {
            $r = $_.Exception.Response
            if ($r -and [int]$r.StatusCode -eq 401) {
                if (Test-Path $script:AtuLogin) { Remove-Item $script:AtuLogin -Force -ErrorAction SilentlyContinue }
                $cred = $null
                continue
            }
            return $null
        } catch { return $null }
    }
    return $null
}

# Confere e, se houver versão nova, instala. Devolve $true quando atualizou (quem chamou deve reabrir o programa).
function Update-Programa([switch]$PodePedirLogin) {
    $info = Get-VersaoSite -PodePedirLogin:$PodePedirLogin
    if (-not $info -or -not $info.versao) { return $false }
    try { $nova = [version]$info.versao } catch { return $false }
    $atual = Get-VersaoLocal
    if ($nova -le $atual) { return $false }

    $tmp = Join-Path $env:TEMP ("crm-atualizacao-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force $tmp | Out-Null
    try {
        $zip = Join-Path $tmp 'pacote.zip'
        $wc = New-ClienteSite $info.Credencial
        $wc.DownloadFile($info.Site + $info.url, $zip)
        $dest = Join-Path $tmp 'pacote'
        Expand-Archive -Path $zip -DestinationPath $dest -Force
        # Confere que o pacote tem a cara do programa antes de copiar por cima.
        if (-not (Test-Path (Join-Path $dest 'app\Janela.ps1'))) { return $false }
        Copy-Item -Path (Join-Path $dest '*') -Destination $script:AtuRaiz -Recurse -Force
        return $true
    } catch {
        return $false
    } finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
